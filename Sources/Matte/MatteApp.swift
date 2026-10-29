import AppKit
import CoreText
import MatteCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct MatteApp: App {
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        if let fontURL = Bundle.main.url(forResource: "InterVariable", withExtension: "woff2") ?? Bundle.module.url(forResource: "InterVariable", withExtension: "woff2", subdirectory: "Resources") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1100, minHeight: 720)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands { CommandGroup(replacing: .newItem) { Button("Add images…") { model.chooseImages() }.keyboardShortcut("o") } }
    }
}

struct SourceImage: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let image: CGImage
    var name: String { url.lastPathComponent }
    var dimensions: String { "\(image.width)×\(image.height) · \(Fit.displayRatio(width: image.width, height: image.height))" }
    static func == (lhs: SourceImage, rhs: SourceImage) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var images: [SourceImage] = []
    @Published var selectedImageID: UUID?
    @Published var selectedFormatID = MatteFormat.all[0].id
    @Published var platformFilter = "All"
    @Published var checked = Set(MatteFormat.all.map(\.id))
    @Published var mode: RenderMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    @Published var padding: Double { didSet { defaults.set(padding, forKey: "padding") } }
    @Published var alwaysPad: Bool { didSet { defaults.set(alwaysPad, forKey: "alwaysPad") } }
    @Published var colorHex: String { didSet { defaults.set(colorHex, forKey: "color") } }
    @Published var autoMatch: Bool { didSet { defaults.set(autoMatch, forKey: "autoMatch") } }
    @Published var exportType: ExportType { didSet { defaults.set(exportType.rawValue, forKey: "exportType") } }
    @Published var outputFolder: URL { didSet { defaults.set(outputFolder.path, forKey: "outputFolder") } }
    @Published var watchedFolder: URL? { didSet { defaults.set(watchedFolder?.path, forKey: "watchedFolder") } }
    @Published var watching: Bool { didSet { defaults.set(watching, forKey: "watching"); updateWatcher() } }
    @Published var watchedExportCount = 0
    @Published var toast: String?
    @Published var lastExportFolder: URL?

    private let defaults = UserDefaults.standard
    private var watcher: FolderWatcher?
    private var knownWatchedFiles = Set<URL>()

    init() {
        let modeValue = defaults.string(forKey: "mode") ?? RenderMode.fit.rawValue
        mode = RenderMode(rawValue: modeValue) ?? .fit
        padding = defaults.object(forKey: "padding") == nil ? 0.06 : defaults.double(forKey: "padding")
        alwaysPad = defaults.bool(forKey: "alwaysPad")
        colorHex = defaults.string(forKey: "color") ?? "#F4F1EA"
        autoMatch = defaults.bool(forKey: "autoMatch")
        exportType = ExportType(rawValue: defaults.string(forKey: "exportType") ?? "png") ?? .png
        outputFolder = URL(fileURLWithPath: defaults.string(forKey: "outputFolder") ?? NSString(string: "~/Desktop/Matte Exports").expandingTildeInPath)
        watchedFolder = defaults.string(forKey: "watchedFolder").map { URL(fileURLWithPath: $0) }
        watching = defaults.bool(forKey: "watching")
        if let saved = defaults.stringArray(forKey: "checkedFormats") { checked = Set(saved) }
        updateWatcher()
        // Dev/docs hooks: MATTE_OPEN=a.png:b.png preloads images; MATTE_SNAPSHOT=out.png saves the window and quits.
        let env = ProcessInfo.processInfo.environment
        if let open = env["MATTE_OPEN"] { add(urls: open.split(separator: ":").map { URL(fileURLWithPath: String($0)) }) }
        if let fmt = env["MATTE_FORMAT"] { selectedFormatID = fmt }
        if let shot = env["MATTE_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard let window = NSApp.windows.first(where: { $0.isVisible }), let view = window.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: shot))
                NSApp.terminate(nil)
            }
        }
    }

    var selectedImage: SourceImage? { images.first { $0.id == selectedImageID } }
    var selectedFormat: MatteFormat { MatteFormat.all.first { $0.id == selectedFormatID } ?? MatteFormat.all[0] }
    var visibleFormats: [MatteFormat] { MatteFormat.all.filter { platformFilter == "All" || $0.platform.rawValue == platformFilter } }
    var renderOptions: RenderOptions { RenderOptions(mode: mode, padding: padding, alwaysPadPerfect: alwaysPad, color: FrameColor(hex: colorHex) ?? .white, autoMatch: autoMatch) }

    func add(urls: [URL]) {
        let extensions = Set(["png", "jpg", "jpeg", "heic", "tiff", "tif", "webp"])
        for url in urls where extensions.contains(url.pathExtension.lowercased()) && !images.contains(where: { $0.url == url }) {
            if let image = try? MatteRenderer.loadImage(at: url) { images.append(SourceImage(url: url, image: image)) }
        }
        if selectedImageID == nil { selectedImageID = images.first?.id }
    }

    func chooseImages() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP]
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    func remove(_ image: SourceImage) {
        images.removeAll { $0.id == image.id }
        if selectedImageID == image.id { selectedImageID = images.first?.id }
    }

    func toggle(_ format: MatteFormat) {
        if checked.contains(format.id) { checked.remove(format.id) } else { checked.insert(format.id) }
        defaults.set(Array(checked), forKey: "checkedFormats")
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { outputFolder = url }
    }

    func chooseWatchedFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { watchedFolder = url; updateWatcher() }
    }

    func sampleColor() {
        NSColorSampler().show { [weak self] color in
            guard let color = color?.usingColorSpace(.sRGB) else { return }
            let hex = FrameColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent).hex
            Task { @MainActor in self?.colorHex = hex; self?.autoMatch = false }
        }
    }

    func exportSelected() { if let image = selectedImage { export([image]) } }
    func exportAll() { export(images) }

    func export(_ sourceImages: [SourceImage], root: URL? = nil) {
        guard !sourceImages.isEmpty else { return }
        do {
            var count = 0
            for source in sourceImages {
                let directory = (root ?? outputFolder).appendingPathComponent(source.url.deletingPathExtension().lastPathComponent, isDirectory: true)
                for format in MatteFormat.all where checked.contains(format.id) {
                    _ = try MatteRenderer.export(image: source.image, sourceURL: source.url, format: format, options: renderOptions, type: exportType, outputDirectory: directory)
                    count += 1
                }
                lastExportFolder = directory
            }
            toast = "Exported \(count) file\(count == 1 ? "" : "s")"
        } catch { toast = error.localizedDescription }
    }

    func reveal() { if let folder = lastExportFolder { NSWorkspace.shared.activateFileViewerSelecting([folder]) } }

    private func updateWatcher() {
        watcher = nil
        guard watching, let folder = watchedFolder else { return }
        knownWatchedFiles = Set((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
        watcher = FolderWatcher(url: folder) { [weak self] in self?.scanWatchedFolder() }
    }

    private func scanWatchedFolder() {
        guard let folder = watchedFolder else { return }
        let current = Set((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? [])
        let newFiles = current.subtracting(knownWatchedFiles).filter { $0.lastPathComponent != "Matte" }
        knownWatchedFiles = current
        guard !newFiles.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            let before = newFiles.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            try? await Task.sleep(for: .milliseconds(600))
            let after = newFiles.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            guard before == after else { return }
            let loaded = newFiles.compactMap { url -> SourceImage? in guard let image = try? MatteRenderer.loadImage(at: url) else { return nil }; return SourceImage(url: url, image: image) }
            export(loaded, root: folder.appendingPathComponent("Matte", isDirectory: true)); watchedExportCount += loaded.count
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
