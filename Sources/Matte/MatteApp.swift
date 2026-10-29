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
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add images…") { model.chooseImages() }.keyboardShortcut("o")
            }
            // Re-provide the clipboard items so Select All can mean "all images" outside text fields.
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { _ = NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }.keyboardShortcut("x")
                Button("Copy") { _ = NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }.keyboardShortcut("c")
                Button("Paste") { _ = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }.keyboardShortcut("v")
                Button("Select All") { model.selectAllCommand() }.keyboardShortcut("a")
            }
            CommandMenu("Images") {
                Button("Select all images") { model.selectAllImages() }.disabled(model.images.isEmpty)
                Button("Deselect") { model.deselectAll() }.keyboardShortcut(.escape, modifiers: []).disabled(model.selection.isEmpty)
                Divider()
                Button("Remove selected") { model.removeSelected() }.keyboardShortcut(.delete, modifiers: .command).disabled(model.selection.isEmpty)
                Divider()
                Button("Formats") { model.mainTab = .formats }.keyboardShortcut("1")
                Button("Simulate") { model.mainTab = .simulate }.keyboardShortcut("2")
                Divider()
                Button(model.exportLabel) { model.requestExport() }.keyboardShortcut("e").disabled(model.exportBlocker != nil || model.isExporting)
            }
        }

        Settings {
            SettingsView(model: model)
                .preferredColorScheme(.dark)
        }
    }
}

/// Weak handle on the main window, set by `WindowConfigurator`.
@MainActor
enum MainWindow {
    static weak var window: NSWindow?
}

/// Configures the hosting window: transparent full-size title bar over a black shell.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguringView { ConfiguringView(frame: .zero) }
    func updateNSView(_ nsView: ConfiguringView, context: Context) {}

    final class ConfiguringView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            MainWindow.window = window
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = .black
            window.isOpaque = true
        }
    }
}

@MainActor
enum DevHooks {
    nonisolated static func parseSize(_ text: String) -> CGSize? {
        let parts = text.lowercased().split(separator: "x").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return CGSize(width: parts[0], height: parts[1])
    }

    static func resizeMainWindow(to size: CGSize) {
        guard let window = MainWindow.window else { return }
        window.setContentSize(NSSize(width: size.width, height: size.height))
        window.center()
    }

    /// Writes a PNG of the main window (or the Settings window when `preferSettings`) via cacheDisplay, then quits.
    static func snapshot(to path: String, preferSettings: Bool) {
        let visible = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) && $0.contentView != nil }
        let main = MainWindow.window.flatMap { window in visible.contains(window) ? window : nil }
        let settings = visible.first { $0 !== main }
        let target = preferSettings ? (settings ?? main) : (main ?? NSApp.keyWindow ?? visible.first)
        guard let window = target, let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            FileHandle.standardError.write(Data("MATTE_SNAPSHOT: no visible window\n".utf8))
            exit(2)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        do {
            guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write(Data("MATTE_SNAPSHOT: \(error.localizedDescription)\n".utf8))
        }
        NSApp.terminate(nil)
    }
}
