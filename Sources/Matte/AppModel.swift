import AppKit
import MatteCore
import SwiftUI

enum MainTab: String, CaseIterable {
    case formats, simulate
}

enum SimKind: String, CaseIterable {
    case xPost, igCarousel, igGrid
}

enum SimSource: String, CaseIterable {
    case original, export
}

struct ColorPreset: Identifiable, Sendable {
    let name: String
    let hex: String
    var id: String { hex }

    static let all: [ColorPreset] = [
        ColorPreset(name: "White", hex: "#FFFFFF"),
        ColorPreset(name: "Off-white", hex: "#F4F1EA"),
        ColorPreset(name: "Black", hex: "#000000"),
        ColorPreset(name: "Paper grey", hex: "#E9E9E9"),
        ColorPreset(name: "Ink", hex: "#111111"),
    ]
}

/// Selected images × checked formats, frozen when the user presses Export.
struct ExportPlan: Identifiable, Sendable {
    let id = UUID()
    let images: [SourceImage]
    let formats: [MatteFormat]
    let render: RenderOptions
    /// Encoding, scale, naming and per-format overrides. `outputDirectory` is unused: each file goes to `directory(for:)`.
    var export: ExportOptions
    let root: URL
    /// Fixed for the batch so {date} and the overwrite check agree with what is written.
    let date: Date
    /// Planned files (via `MatteRenderer.plannedURL`) already on disk.
    let existing: [URL]

    var total: Int { images.count * formats.count }
    /// A single file (1 image × 1 format) goes straight into `root`; multi-file exports get one subfolder per image.
    var usesSubfolders: Bool { total > 1 }

    func directory(for image: SourceImage) -> URL {
        ExportPlan.directory(for: image, root: root, usesSubfolders: usesSubfolders)
    }

    static func directory(for image: SourceImage, root: URL, usesSubfolders: Bool) -> URL {
        guard usesSubfolders else { return root }
        return root.appendingPathComponent(image.url.deletingPathExtension().lastPathComponent, isDirectory: true)
    }
}

struct ExportOutcome: Sendable {
    var written = 0
    var failures: [String] = []
    var warnings: [String] = []
    var cancelled = false
    var lastFolder: URL?
    var lastFile: URL?
}

/// Result of writing one file in a background task.
private struct FileResult: Sendable {
    var file: URL?
    var failure: String?
    var warnings: [String] = []
}

/// Max file size control: no cap, the format's platform cap, or `maxFileSizeBytes`.
enum SizeCapChoice: String, CaseIterable, Hashable {
    case off, platform, custom
}

/// Scale control: `ExportScale` without the associated value, so it can drive a segmented picker.
enum ScaleChoice: String, CaseIterable, Hashable {
    case x1, x2, max
}

@MainActor
final class AppModel: ObservableObject {
    // MARK: Images and selection
    @Published private(set) var images: [SourceImage] = []
    /// Selected image ids. `selectionOrder` holds the same ids in the order they were selected (used by the simulator).
    @Published private(set) var selection: Set<UUID> = []
    @Published private(set) var selectionOrder: [UUID] = []
    /// The inspected image: the last one clicked (falls back to the first image).
    @Published var focusedImageID: UUID?
    @Published private(set) var loadingCount = 0
    private var anchorID: UUID?

    // MARK: Formats
    /// Checked formats. Empty by default; the user's last choice persists under "checkedFormats".
    @Published private(set) var checked: Set<String> = []
    @Published var selectedFormatID = "x-carousel-45"
    @Published var mainTab: MainTab = .formats
    @Published var platformFilter = "All"

    // MARK: Frame
    @Published var mode: RenderMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    @Published var padding: Double { didSet { defaults.set(padding, forKey: "padding") } }
    @Published var alwaysPad: Bool { didSet { defaults.set(alwaysPad, forKey: "alwaysPad") } }
    @Published var colorHex: String { didSet { defaults.set(colorHex, forKey: "color") } }
    @Published var autoMatch: Bool { didSet { defaults.set(autoMatch, forKey: "autoMatch") } }
    @Published private(set) var recentColors: [String] { didSet { defaults.set(recentColors, forKey: "recentColors") } }
    @Published var colorPanelOpen = false
    @Published private(set) var isSampling = false
    private var sampler: NSColorSampler?

    // MARK: Export
    /// The single source of truth for file type, quality, scale, naming, colour space, metadata, size cap and per-format overrides
    /// (inspector and Settings both edit it). Stored as JSON under "exportOptions"; the folder lives in `outputFolder`.
    @Published var exportOptions: ExportOptions { didSet { saveExportOptions() } }
    @Published var exportOptionsExpanded: Bool { didSet { defaults.set(exportOptionsExpanded, forKey: "exportOptionsExpanded") } }
    @Published var outputFolder: URL { didSet { defaults.set(outputFolder.path, forKey: "outputFolder") } }
    @Published var pendingExport: ExportPlan?
    @Published private(set) var exportProgress: Double?
    @Published private(set) var exportStatus = ""
    @Published var toast: String?
    @Published var lastExportFolder: URL?
    private var exportTask: Task<Void, Never>?

    // MARK: Watched folder
    @Published var watchedFolder: URL? { didSet { defaults.set(watchedFolder?.path, forKey: "watchedFolder") } }
    @Published var watching: Bool { didSet { defaults.set(watching, forKey: "watching"); updateWatcher() } }
    @Published private(set) var watchedExportCount = 0
    @Published private(set) var watchMessage: String?
    private var watcher: FolderWatcher?
    private var knownWatchedFiles = Set<URL>()

    // MARK: Simulator
    @Published var simKind: SimKind = .xPost
    @Published var simSource: SimSource = .original
    @Published var simXFormatID = "x-carousel-45"
    @Published var simIGFormatID = "ig-feed-45"

    // MARK: Launch hooks
    let launchOpensSettings: Bool
    private var pendingSelectSpec: String?

    private let defaults = UserDefaults.standard

    init() {
        mode = RenderMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .fit
        padding = defaults.object(forKey: "padding") == nil ? 0.06 : defaults.double(forKey: "padding")
        alwaysPad = defaults.bool(forKey: "alwaysPad")
        colorHex = FrameColor.parseHex6(defaults.string(forKey: "color") ?? "")?.hex ?? "#F4F1EA"
        autoMatch = defaults.bool(forKey: "autoMatch")
        recentColors = Array((defaults.stringArray(forKey: "recentColors") ?? []).prefix(6))
        exportOptions = AppModel.loadExportOptions(from: UserDefaults.standard)
        exportOptionsExpanded = defaults.bool(forKey: "exportOptionsExpanded")
        outputFolder = URL(fileURLWithPath: defaults.string(forKey: "outputFolder") ?? NSString(string: "~/Desktop/Matte Exports").expandingTildeInPath)
        watchedFolder = defaults.string(forKey: "watchedFolder").map { URL(fileURLWithPath: $0) }
        watching = defaults.bool(forKey: "watching")
        let known = Set(MatteFormat.all.map(\.id))
        checked = Set(defaults.stringArray(forKey: "checkedFormats") ?? []).intersection(known)

        let env = ProcessInfo.processInfo.environment
        launchOpensSettings = env["MATTE_SETTINGS"] == "1"
        if env["MATTE_EXPORTOPTIONS"] == "1" { exportOptionsExpanded = true }
        updateWatcher()
        applyLaunchEnvironment(env)
    }

    // MARK: Derived state

    var focusedImage: SourceImage? { images.first { $0.id == focusedImageID } ?? images.first }
    var selectedFormat: MatteFormat { MatteFormat.format(id: selectedFormatID) ?? MatteFormat.all[0] }
    /// Selected images in the order the user selected them.
    var selectedImagesInSelectionOrder: [SourceImage] {
        let byID = Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0) })
        return selectionOrder.compactMap { byID[$0] }
    }
    var selectedImagesInListOrder: [SourceImage] { images.filter { selection.contains($0.id) } }
    var checkedFormats: [MatteFormat] { MatteFormat.all.filter { checked.contains($0.id) } }
    var visibleFormats: [MatteFormat] { MatteFormat.all.filter { platformFilter == "All" || $0.platform.rawValue == platformFilter } }
    var frameColor: FrameColor { FrameColor(hex: colorHex) ?? .white }
    var renderOptions: RenderOptions { RenderOptions(mode: mode, padding: padding, alwaysPadPerfect: alwaysPad, color: frameColor, autoMatch: autoMatch) }
    /// Frame options with the format's export override (padding, fit/fill) applied, so previews match exports.
    func renderOptions(for format: MatteFormat) -> RenderOptions { exportOptions.renderOptions(renderOptions, for: format) }
    var isExporting: Bool { exportProgress != nil }

    var exportCount: Int { selection.count * checked.count }
    var exportLabel: String {
        let total = exportCount
        return "Export \(selection.count) × \(checked.count) = \(total) file\(total == 1 ? "" : "s")"
    }
    /// What is missing before export can run, if anything.
    var exportBlocker: String? {
        if images.isEmpty || selection.isEmpty { return "Select at least one image" }
        if checked.isEmpty { return "Pick at least one format" }
        return nil
    }

    // MARK: Images

    func add(urls: [URL]) {
        var expanded: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                expanded.append(contentsOf: children.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
            } else {
                expanded.append(url)
            }
        }
        var seen = Set(images.map(\.url))
        var candidates: [URL] = []
        for url in expanded where ImageLoader.supportedExtensions.contains(url.pathExtension.lowercased()) && !seen.contains(url) {
            seen.insert(url)
            candidates.append(url)
        }
        guard !candidates.isEmpty else { return }
        let batch = candidates
        loadingCount += batch.count
        Task { [weak self] in
            let loaded = await ImageLoader.loadAll(batch)
            self?.finishAdding(loaded, requested: batch.count)
        }
    }

    private func finishAdding(_ loaded: [SourceImage], requested: Int) {
        loadingCount = max(0, loadingCount - requested)
        let existing = Set(images.map(\.url))
        let fresh = loaded.filter { !existing.contains($0.url) }
        images.append(contentsOf: fresh)
        if focusedImageID == nil { focusedImageID = images.first?.id }
        if loaded.count < requested { toast = "\(requested - loaded.count) file\(requested - loaded.count == 1 ? "" : "s") could not be read" }
        if loadingCount == 0, let spec = pendingSelectSpec {
            pendingSelectSpec = nil
            applySelectSpec(spec)
        }
    }

    func chooseImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP]
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    func remove(_ id: UUID) {
        images.removeAll { $0.id == id }
        setSelection(selectionOrder.filter { $0 != id })
        if focusedImageID == id { focusedImageID = images.first?.id }
        if anchorID == id { anchorID = nil }
    }

    func removeSelected() {
        let doomed = selection
        guard !doomed.isEmpty else { return }
        images.removeAll { doomed.contains($0.id) }
        setSelection([])
        if let focused = focusedImageID, doomed.contains(focused) { focusedImageID = images.first?.id }
        anchorID = nil
    }

    func reveal(_ image: SourceImage) { NSWorkspace.shared.activateFileViewerSelecting([image.url]) }

    // MARK: Selection

    /// Click = select one, Cmd-click = toggle, Shift-click = range from the last clicked image. The clicked image becomes the inspected one.
    func click(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift), let anchor = anchorID,
           let from = images.firstIndex(where: { $0.id == anchor }), let to = images.firstIndex(where: { $0.id == id }) {
            let range = images[min(from, to)...max(from, to)].map(\.id)
            var order = modifiers.contains(.command) ? selectionOrder : []
            for item in range where !order.contains(item) { order.append(item) }
            setSelection(order)
        } else if modifiers.contains(.command) {
            if selection.contains(id) { setSelection(selectionOrder.filter { $0 != id }) } else { setSelection(selectionOrder + [id]) }
            anchorID = id
        } else {
            setSelection([id])
            anchorID = id
        }
        focusedImageID = id
    }

    func selectAllImages() {
        var order = selectionOrder.filter { id in images.contains { $0.id == id } }
        for image in images where !order.contains(image.id) { order.append(image.id) }
        setSelection(order)
    }

    func deselectAll() { setSelection([]) }

    /// Edit › Select All: text fields keep their own behaviour, everywhere else selects every image.
    func selectAllCommand() {
        if NSApp.keyWindow?.firstResponder is NSText {
            _ = NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        } else {
            selectAllImages()
        }
    }

    private func setSelection(_ ids: [UUID]) {
        selectionOrder = ids
        selection = Set(ids)
    }

    private func applySelectSpec(_ spec: String) {
        if spec.lowercased() == "all" {
            selectAllImages()
        } else {
            let indices = spec.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            setSelection(indices.filter { images.indices.contains($0) }.map { images[$0].id })
        }
        if let last = selectionOrder.last { focusedImageID = last; anchorID = last }
    }

    // MARK: Formats

    func isChecked(_ format: MatteFormat) -> Bool { checked.contains(format.id) }

    func toggle(_ format: MatteFormat) {
        if checked.contains(format.id) { checked.remove(format.id) } else { checked.insert(format.id) }
        if format.previewKind.isPostImage {
            if format.platform == .x { simXFormatID = format.id } else { simIGFormatID = format.id }
        }
        saveChecked()
    }

    func setChecked(_ formats: [MatteFormat], _ isOn: Bool) {
        let ids = formats.map(\.id)
        if isOn { checked.formUnion(ids) } else { checked.subtract(ids) }
        saveChecked()
    }

    private func saveChecked() { defaults.set(checked.sorted(), forKey: "checkedFormats") }

    // MARK: Colour

    func applyColor(_ hex: String, remember: Bool) {
        guard let color = FrameColor.parseHex6(hex) else { return }
        if autoMatch { autoMatch = false }
        if colorHex != color.hex { colorHex = color.hex }
        if remember { rememberRecent(color.hex) }
    }

    func rememberRecent(_ hex: String) {
        guard let color = FrameColor.parseHex6(hex) else { return }
        let value = color.hex
        guard !ColorPreset.all.contains(where: { $0.hex == value }) else { return }
        var list = recentColors.filter { $0 != value }
        list.insert(value, at: 0)
        recentColors = Array(list.prefix(6))
    }

    /// System eyedropper. The sampler is retained while active; cancel (nil) leaves the colour untouched.
    func sampleColor() {
        guard sampler == nil else { return }
        let sampler = NSColorSampler()
        self.sampler = sampler
        isSampling = true
        // AppModel lives for the whole app, so a strong capture is fine; the handler hops to the main actor itself.
        sampler.show { @Sendable color in
            var hex: String?
            if let rgb = color?.usingColorSpace(.sRGB) {
                hex = FrameColor(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent)).hex
            }
            let result = hex
            Task { @MainActor in self.finishSampling(result) }
        }
    }

    private func finishSampling(_ hex: String?) {
        sampler = nil
        isSampling = false
        if let hex { applyColor(hex, remember: true) }
    }

    // MARK: Export options

    private static func loadExportOptions(from defaults: UserDefaults) -> ExportOptions {
        if let data = defaults.data(forKey: "exportOptions"), let options = try? JSONDecoder().decode(ExportOptions.self, from: data) { return options }
        // Migrate the v0.1 PNG/JPEG + quality settings.
        let legacyType = ExportType(rawValue: defaults.string(forKey: "exportType") ?? "") ?? .png
        let quality = defaults.object(forKey: "jpegQuality") == nil ? ExportOptions.defaultQuality : defaults.double(forKey: "jpegQuality")
        return ExportOptions(fileType: ExportFileType(legacyType), quality: quality)
    }

    private func saveExportOptions() {
        var stored = exportOptions
        stored.outputDirectory = nil
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: "exportOptions") }
    }

    var sizeCapChoice: SizeCapChoice {
        get {
            if let bytes = exportOptions.maxFileSizeBytes, bytes > 0 { return .custom }
            return exportOptions.usePlatformSizeCaps ? .platform : .off
        }
        set {
            switch newValue {
            case .off: exportOptions.maxFileSizeBytes = nil; exportOptions.usePlatformSizeCaps = false
            case .platform: exportOptions.maxFileSizeBytes = nil; exportOptions.usePlatformSizeCaps = true
            case .custom: if sizeCapChoice != .custom { exportOptions.maxFileSizeBytes = 5_000_000 }
            }
        }
    }

    var scaleChoice: ScaleChoice {
        get {
            switch exportOptions.scale {
            case .x1: .x1
            case .x2: .x2
            case .maxLongEdge: .max
            }
        }
        set {
            switch newValue {
            case .x1: exportOptions.scale = .x1
            case .x2: exportOptions.scale = .x2
            case .max: if scaleChoice != .max { exportOptions.scale = .maxLongEdge(lastMaxLongEdge) }
            }
        }
    }

    /// Long-edge limit for `.maxLongEdge`; remembered while another scale is chosen.
    var maxLongEdge: Int {
        get {
            if case .maxLongEdge(let limit) = exportOptions.scale { return limit }
            return lastMaxLongEdge
        }
        set {
            let limit = min(20_000, max(16, newValue))
            lastMaxLongEdge = limit
            exportOptions.scale = .maxLongEdge(limit)
        }
    }
    private var lastMaxLongEdge = 2048

    /// Custom cap in decimal megabytes (1 MB = 1,000,000 bytes, as in `ByteSize`).
    var customMaxSizeMB: Double {
        get { Double(exportOptions.maxFileSizeBytes ?? 5_000_000) / 1_000_000 }
        set { if newValue.isFinite, newValue > 0 { exportOptions.maxFileSizeBytes = max(1_000, Int((newValue * 1_000_000).rounded())) } }
    }

    /// Fit/fill override for the inspected format; nil follows the Frame setting.
    var inspectedModeOverride: RenderMode? {
        get { formatOverride(for: selectedFormat).mode }
        set { var value = formatOverride(for: selectedFormat); value.mode = newValue; setOverride(value, for: selectedFormat) }
    }

    var inspectedHasPaddingOverride: Bool {
        get { formatOverride(for: selectedFormat).padding != nil }
        set { var value = formatOverride(for: selectedFormat); value.padding = newValue ? padding : nil; setOverride(value, for: selectedFormat) }
    }

    /// Padding for the inspected format: its override, else the Frame padding.
    var inspectedPadding: Double {
        get { formatOverride(for: selectedFormat).padding ?? padding }
        set { var value = formatOverride(for: selectedFormat); value.padding = min(0.3, max(0, newValue)); setOverride(value, for: selectedFormat) }
    }

    func formatOverride(for format: MatteFormat) -> FormatOverride { exportOptions.overrides[format.id] ?? FormatOverride() }

    func setOverride(_ value: FormatOverride, for format: MatteFormat) {
        exportOptions.overrides[format.id] = value.isEmpty ? nil : value
    }

    func resetOverride(for format: MatteFormat) { exportOptions.overrides[format.id] = nil }

    /// Short summary for the collapsed section header, e.g. `JPEG 92 · 2× · P3`.
    var exportOptionsSummary: String {
        let options = exportOptions
        var parts = [options.resolvedFileType.displayName + (options.resolvedFileType.isLossy ? " \(Int((options.quality * 100).rounded()))" : "")]
        parts.append(options.scale.label)
        if options.colorSpace == .displayP3 { parts.append("P3") }
        if !options.overrides.isEmpty { parts.append("\(options.overrides.count) override\(options.overrides.count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    // MARK: Export

    func requestExport() {
        guard exportBlocker == nil, !isExporting else { return }
        let plan = makePlan(images: selectedImagesInListOrder, formats: checkedFormats, root: outputFolder)
        if !plan.existing.isEmpty || plan.total > 40 {
            pendingExport = plan
        } else {
            startExport(plan)
        }
    }

    /// `replace` overwrites files already on disk; otherwise new files get -2, -3… suffixes.
    func confirmExport(replace: Bool = true) {
        guard var plan = pendingExport else { return }
        pendingExport = nil
        plan.export.overwriteExisting = replace
        startExport(plan)
    }

    func cancelExport() { exportTask?.cancel() }

    private func makePlan(images: [SourceImage], formats: [MatteFormat], root: URL) -> ExportPlan {
        var options = exportOptions
        options.outputDirectory = nil
        options.overwriteExisting = true
        let date = Date()
        var existing: [URL] = []
        let usesSubfolders = images.count * formats.count > 1
        for (offset, image) in images.enumerated() {
            let directory = ExportPlan.directory(for: image, root: root, usesSubfolders: usesSubfolders)
            for format in formats {
                guard let url = MatteRenderer.plannedURL(sourceURL: image.url, format: format, options: options, outputDirectory: directory, index: offset + 1, date: date) else { continue }
                if FileManager.default.fileExists(atPath: url.path), !existing.contains(url) { existing.append(url) }
            }
        }
        return ExportPlan(images: images, formats: formats, render: renderOptions, export: options, root: root, date: date, existing: existing)
    }

    private func startExport(_ plan: ExportPlan) {
        exportTask?.cancel()
        exportProgress = 0
        exportStatus = "0 of \(plan.total)"
        toast = nil
        exportTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await self.perform(plan) { done in
                self.exportProgress = Double(done) / Double(max(1, plan.total))
                self.exportStatus = "\(done) of \(plan.total)"
            }
            self.exportProgress = nil
            self.exportStatus = ""
            self.exportTask = nil
            // Reveal selects the file for a single-file export, the image's subfolder for one image, else the export root.
            if let folder = outcome.lastFolder {
                if !plan.usesSubfolders {
                    self.lastExportFolder = outcome.lastFile ?? folder
                } else {
                    self.lastExportFolder = plan.images.count > 1 ? plan.root : folder
                }
            }
            var message = outcome.cancelled ? "Cancelled after \(outcome.written) file\(outcome.written == 1 ? "" : "s")" : "Exported \(outcome.written) file\(outcome.written == 1 ? "" : "s")"
            if let first = outcome.failures.first { message += " · \(outcome.failures.count) failed: \(first)" }
            if let first = outcome.warnings.first { message += " · \(outcome.warnings.count) warning\(outcome.warnings.count == 1 ? "" : "s"): \(first)" }
            self.toast = message
        }
    }

    /// Renders and writes every image × format pair through `MatteRenderer.export`. Decoding and encoding run in detached tasks;
    /// only bookkeeping touches the main actor. Names used in each folder are passed as `avoiding` so patterns without {format}
    /// (or two sources with the same name) never overwrite a file written earlier in the batch.
    private func perform(_ plan: ExportPlan, progress: (Int) -> Void) async -> ExportOutcome {
        var outcome = ExportOutcome()
        var done = 0
        var usedNames: [URL: Set<String>] = [:]
        for (offset, image) in plan.images.enumerated() {
            if Task.isCancelled { outcome.cancelled = true; break }
            let sourceURL = image.url
            let decoded = await Task.detached(priority: .userInitiated) { () -> SendableImage? in
                (try? MatteRenderer.loadImage(at: sourceURL)).map { SendableImage(cgImage: $0) }
            }.value
            guard let full = decoded else {
                outcome.failures.append("Could not read \(image.name)")
                done += plan.formats.count
                progress(done)
                continue
            }
            let render = plan.render.resolved(for: image)
            let options = plan.export
            let directory = plan.directory(for: image)
            let index = offset + 1, date = plan.date
            for format in plan.formats {
                if Task.isCancelled { outcome.cancelled = true; break }
                let avoiding = usedNames[directory] ?? []
                let result = await Task.detached(priority: .userInitiated) { () -> FileResult in
                    do {
                        let written = try MatteRenderer.export(image: full.cgImage, format: format, options: options, renderOptions: render, sourceURL: sourceURL, outputDirectory: directory, index: index, date: date, avoiding: avoiding)
                        return FileResult(file: written.url, failure: nil, warnings: written.warnings.map { "\(written.url.lastPathComponent): \($0.description)" })
                    } catch {
                        return FileResult(file: nil, failure: error.localizedDescription)
                    }
                }.value
                outcome.warnings += result.warnings
                if let failure = result.failure {
                    outcome.failures.append(failure)
                } else if let file = result.file {
                    outcome.written += 1
                    outcome.lastFolder = directory
                    outcome.lastFile = file
                    usedNames[directory, default: []].insert(file.lastPathComponent)
                }
                done += 1
                progress(done)
            }
            if outcome.cancelled { break }
        }
        return outcome
    }

    func revealLastExport() { if let folder = lastExportFolder { NSWorkspace.shared.activateFileViewerSelecting([folder]) } }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = outputFolder
        if panel.runModal() == .OK, let url = panel.url { outputFolder = url }
    }

    // MARK: Watched folder

    func chooseWatchedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            watchedFolder = url
            updateWatcher()
        }
    }

    var watchStatus: (text: String, tone: Tone) {
        guard let folder = watchedFolder else { return ("No folder chosen", .neutral) }
        guard watching else { return ("Off", .neutral) }
        guard watcher != nil else { return ("Cannot watch \(folder.lastPathComponent)", .danger) }
        if checked.isEmpty { return ("Watching, but no formats are checked", .warning) }
        return ("Watching \(folder.lastPathComponent)", .positive)
    }

    private func updateWatcher() {
        watcher = nil
        guard watching, let folder = watchedFolder else { return }
        knownWatchedFiles = Set((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
        watcher = FolderWatcher(url: folder) { [weak self] in self?.scanWatchedFolder() }
    }

    private func scanWatchedFolder() {
        guard let folder = watchedFolder else { return }
        let current = Set((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
        let newFiles = current.subtracting(knownWatchedFiles).filter {
            $0.lastPathComponent != "Matte" && ImageLoader.supportedExtensions.contains($0.pathExtension.lowercased())
        }
        knownWatchedFiles = current
        guard !newFiles.isEmpty else { return }
        let files = Array(newFiles)
        Task { [weak self] in
            // Wait for the file size to settle before reading.
            try? await Task.sleep(for: .milliseconds(600))
            let before = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            try? await Task.sleep(for: .milliseconds(600))
            let after = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            guard before == after else { return }
            let loaded = await ImageLoader.loadAll(files)
            await self?.exportWatched(loaded, root: folder.appendingPathComponent("Matte", isDirectory: true))
        }
    }

    private func exportWatched(_ loaded: [SourceImage], root: URL) async {
        guard !loaded.isEmpty else { return }
        let formats = checkedFormats
        guard !formats.isEmpty else {
            watchMessage = "Skipped \(loaded.count) new image\(loaded.count == 1 ? "" : "s"): no formats checked"
            return
        }
        let plan = makePlan(images: loaded, formats: formats, root: root)
        let outcome = await perform(plan) { _ in }
        watchedExportCount += loaded.count
        watchMessage = "Last run: \(outcome.written) file\(outcome.written == 1 ? "" : "s") from \(loaded.map(\.name).joined(separator: ", "))"
    }

    // MARK: Launch environment (dev/docs hooks)

    /// MATTE_OPEN=a.png:b.png preload · MATTE_SELECT=all|0,2 · MATTE_FORMATS=id,id · MATTE_FORMAT=id (inspected format) ·
    /// MATTE_TAB=formats|simulate · MATTE_COLORPANEL=1 · MATTE_SETTINGS=1 (see ContentView) · MATTE_EXPORTOPTIONS=1 (expanded, set in init) ·
    /// MATTE_SNAPSHOT=out.png (+ MATTE_SNAPSHOT_SIZE=1280x820) writes the window after 3s and quits.
    private func applyLaunchEnvironment(_ env: [String: String]) {
        if let formats = env["MATTE_FORMATS"] {
            let known = Set(MatteFormat.all.map(\.id))
            checked = formats == "all" ? known : Set(formats.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }).intersection(known)
        }
        if let format = env["MATTE_FORMAT"], MatteFormat.format(id: format) != nil { selectedFormatID = format }
        if let tab = env["MATTE_TAB"].flatMap({ MainTab(rawValue: $0.lowercased()) }) { mainTab = tab }
        if env["MATTE_COLORPANEL"] == "1" {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                self?.colorPanelOpen = true
            }
        }
        if let open = env["MATTE_OPEN"] {
            pendingSelectSpec = env["MATTE_SELECT"]
            add(urls: open.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
        }
        if let shot = env["MATTE_SNAPSHOT"] {
            let size = env["MATTE_SNAPSHOT_SIZE"].flatMap { DevHooks.parseSize($0) }
            let settings = launchOpensSettings
            Task { @MainActor in
                if let size {
                    try? await Task.sleep(for: .milliseconds(900))
                    DevHooks.resizeMainWindow(to: size)
                    try? await Task.sleep(for: .milliseconds(2100))
                } else {
                    try? await Task.sleep(for: .seconds(3))
                }
                DevHooks.snapshot(to: shot, preferSettings: settings)
            }
        }
    }
}

final class FolderWatcher: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject
    private let descriptor: Int32
    init?(url: URL, handler: @escaping @MainActor @Sendable () -> Void) {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .extend], queue: .main)
        source.setEventHandler { Task { @MainActor in handler() } }
        source.setCancelHandler { [descriptor] in close(descriptor) }
        source.resume()
    }
    deinit { source.cancel() }
}
