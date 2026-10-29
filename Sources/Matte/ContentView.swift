import AppKit
import MatteCore
import SwiftUI
import UniformTypeIdentifiers

enum Theme {
    static let shell = Color.black
    static let panel = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let card = Color.white.opacity(0.035)
    static let control = Color.white.opacity(0.07)
    static let line = Color.white.opacity(0.07)
    static let primary = Color.white.opacity(0.93)
    static let secondary = Color.white.opacity(0.69)
    static let tertiary = Color.white.opacity(0.39)
    static let brand = Color(red: 0, green: 0.565, blue: 1)
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var dropTarget = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 4) {
                Sidebar(model: model).frame(width: 256)
                MainPanel(model: model)
                Inspector(model: model).frame(width: 300)
            }
            .padding(4)
            .background(Theme.shell)
            .onDrop(of: [UTType.fileURL], isTargeted: $dropTarget) { providers in
                let target = model
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { @Sendable url, _ in
                        guard let url else { return }
                        Task { @MainActor in target.add(urls: [url]) }
                    }
                }
                return true
            }
            if dropTarget {
                RoundedRectangle(cornerRadius: 16).stroke(Theme.brand, lineWidth: 2).background(Theme.brand.opacity(0.08)).padding(8).allowsHitTesting(false)
            }
            if let toast = model.toast {
                HStack(spacing: 12) {
                    Text(toast).foregroundStyle(Theme.primary).lineLimit(2)
                    if model.lastExportFolder != nil { Button("Reveal") { model.revealLastExport() }.buttonStyle(LinkButtonStyle()) }
                    Button { model.toast = nil } label: { Image(systemName: "xmark") }.buttonStyle(IconButtonStyle())
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.leading, 16).padding(.trailing, 8).frame(minHeight: 44).frame(maxWidth: 460)
                .background(Color(red: 0.14, green: 0.14, blue: 0.14), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 8).padding(20)
            }
        }
        .font(.system(size: 13))
        .background(WindowConfigurator())
        .sheet(item: $model.pendingExport) { plan in
            ExportConfirmSheet(plan: plan, cancel: { model.pendingExport = nil }, confirm: { replace in model.confirmExport(replace: replace) })
        }
        .onAppear {
            if model.launchOpensSettings {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    openSettings()
                }
            }
        }
    }
}

private struct MainPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.focusedImage?.name ?? "Add an image to begin").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.primary).lineLimit(1).truncationMode(.middle)
                    if let image = model.focusedImage { Text(image.dimensions).monoCaption() }
                }
                Spacer()
                ExportControls(model: model)
            }.padding(.horizontal, 24).frame(height: 72).overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
            HStack(spacing: 18) {
                ForEach(["All", "X", "Instagram"], id: \.self) { tab in
                    TabButton(title: tab, isActive: model.mainTab == .formats && model.platformFilter == tab) { model.platformFilter = tab; model.mainTab = .formats }
                }
                Rectangle().fill(Theme.line).frame(width: 0.5, height: 14)
                TabButton(title: "Simulate", isActive: model.mainTab == .simulate) { model.mainTab = .simulate }
                Spacer()
                if model.mainTab == .formats {
                    let visible = model.visibleFormats
                    let allChecked = visible.allSatisfy { model.isChecked($0) }
                    Button(allChecked ? "Uncheck all" : "Check all") { model.setChecked(visible, !allChecked) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    Text("\(model.checked.count) checked").monoCaption()
                } else {
                    Text(model.selection.isEmpty ? "No images selected" : "\(model.selection.count) in selection order").monoCaption()
                }
            }.padding(.horizontal, 24)
            switch model.mainTab {
            case .formats: FormatsGrid(model: model)
            case .simulate: SimulatorView(model: model)
            }
        }.background(Theme.panel, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 0.5))
    }
}

private struct TabButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void
    var body: some View {
        Button(title, action: action).buttonStyle(.plain).foregroundStyle(isActive ? Theme.primary : Theme.secondary).padding(.vertical, 12).overlay(alignment: .bottom) { if isActive { Rectangle().fill(Theme.primary).frame(height: 1) } }
    }
}

/// "Export N × M = K files", a quiet hint while it is disabled, or progress with Cancel while exporting.
/// The export folder (set in Settings) is shown underneath; clicking it chooses another.
private struct ExportControls: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 10) {
                if let progress = model.exportProgress {
                    ProgressView(value: progress).controlSize(.small).frame(width: 140)
                    Text(model.exportStatus).monoCaption()
                    Button("Cancel") { model.cancelExport() }.buttonStyle(SecondaryButtonStyle())
                } else {
                    if let blocker = model.exportBlocker { Text(blocker).font(.system(size: 11)).foregroundStyle(Tone.warning.text.opacity(0.8)).lineLimit(1) }
                    Button(model.exportLabel) { model.requestExport() }.buttonStyle(PrimaryButtonStyle()).disabled(model.exportBlocker != nil)
                }
            }
            Button { model.chooseOutputFolder() } label: {
                Text("→ \(model.outputFolder.path.abbreviatingHome)").monoCaption().lineLimit(1).truncationMode(.middle).frame(maxWidth: 280, alignment: .trailing)
            }.buttonStyle(.plain).disabled(model.isExporting).help("Export folder (also in Settings). Click to change.")
        }
    }
}

private struct ExportConfirmSheet: View {
    let plan: ExportPlan
    let cancel: () -> Void
    /// true replaces existing files, false keeps both (new files get -2, -3…).
    let confirm: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export \(plan.total) file\(plan.total == 1 ? "" : "s")?").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.primary)
            Text("\(plan.images.count) image\(plan.images.count == 1 ? "" : "s") × \(plan.formats.count) format\(plan.formats.count == 1 ? "" : "s") as \(plan.export.resolvedFileType.displayName)\(plan.usesSubfolders ? ", one folder per image," : ", saved directly") into")
                .foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Text(plan.root.path.abbreviatingHome).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.tertiary).lineLimit(2).truncationMode(.middle)
            if !plan.existing.isEmpty {
                Text("\(plan.existing.count) file\(plan.existing.count == 1 ? " already exists" : "s already exist") and will be replaced").foregroundStyle(Tone.warning.text)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(plan.existing.prefix(5), id: \.self) { url in Text(url.pathComponents.suffix(2).joined(separator: "/")).monoCaption().lineLimit(1).truncationMode(.middle) }
                    if plan.existing.count > 5 { Text("and \(plan.existing.count - 5) more").monoCaption() }
                }
            }
            if plan.total > 40 {
                Text("Large batch: it runs in the background and you can cancel it at any time.").font(.system(size: 11)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                if !plan.existing.isEmpty { Button("Keep both") { confirm(false) }.buttonStyle(SecondaryButtonStyle()) }
                Button(plan.existing.isEmpty ? "Export \(plan.total) files" : "Replace and export") { confirm(true) }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }.padding(.top, 4)
        }
        .font(.system(size: 13))
        .padding(20)
        .frame(width: 420)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Shared styles

/// v0.1 badge palettes: fit verdicts, warnings and watched-folder status.
enum Tone {
    case neutral, positive, warning, danger

    var dot: Color {
        switch self {
        case .neutral: Theme.tertiary
        case .positive: Color(red: 0.188, green: 0.643, blue: 0.424)
        case .warning: Color(red: 0.969, green: 0.42, blue: 0.082)
        case .danger: Color(red: 0.898, green: 0.302, blue: 0.18)
        }
    }
    var fill: Color {
        switch self {
        case .neutral: Theme.control
        case .positive: Color(red: 0.133, green: 1, blue: 0.6).opacity(0.12)
        case .warning: Color(red: 0.984, green: 0.416, blue: 0).opacity(0.15)
        case .danger: Color(red: 1, green: 0.208, blue: 0.137).opacity(0.17)
        }
    }
    var text: Color {
        switch self {
        case .neutral: Theme.secondary
        case .positive: Color(red: 0.275, green: 0.996, blue: 0.647).opacity(0.83)
        case .warning: Color(red: 1, green: 0.627, blue: 0.341)
        case .danger: Color(red: 1, green: 0.592, blue: 0.49)
        }
    }
}

struct Pill: View {
    let text: String
    let tone: Tone
    var body: some View { HStack(spacing: 5) { Circle().fill(tone.dot).frame(width: 6, height: 6); Text(text).lineLimit(1) }.font(.system(size: 11)).foregroundStyle(tone.text).padding(.horizontal, 6).frame(height: 20).background(tone.fill, in: RoundedRectangle(cornerRadius: 4)) }
}

private struct DimWhenDisabled: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View { content.opacity(isEnabled ? 1 : 0.4) }
}

struct PrimaryButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .medium)).lineLimit(1).foregroundStyle(.black).padding(.horizontal, 10).frame(height: 28).background(Color.white.opacity(configuration.isPressed ? 0.8 : 0.95), in: RoundedRectangle(cornerRadius: 6)).scaleEffect(configuration.isPressed ? 0.98 : 1).modifier(DimWhenDisabled()) } }
struct SecondaryButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .medium)).lineLimit(1).foregroundStyle(Theme.primary).padding(.horizontal, 10).frame(height: 28).background(configuration.isPressed ? Color.white.opacity(0.13) : Theme.control, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 0.5)).modifier(DimWhenDisabled()) } }
struct IconButtonStyle: ButtonStyle { var isActive = false; func makeBody(configuration: Configuration) -> some View { configuration.label.foregroundStyle(isActive ? Theme.primary : Theme.secondary).frame(width: 28, height: 28).background(configuration.isPressed || isActive ? Theme.control : .clear, in: RoundedRectangle(cornerRadius: 6)).contentShape(Rectangle()) } }
struct LinkButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(configuration.isPressed ? Color.white : Theme.brand).modifier(DimWhenDisabled()) } }

extension View {
    func sectionLabel() -> some View { self.font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.tertiary) }
    func monoCaption() -> some View { self.font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.tertiary) }
}

func swiftUIColor(_ color: FrameColor) -> Color {
    Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
}

extension String {
    /// Abbreviates the home folder to ~.
    var abbreviatingHome: String {
        let home = NSHomeDirectory()
        return hasPrefix(home) ? "~" + String(dropFirst(home.count)) : self
    }
}
