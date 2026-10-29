import AppKit
import MatteCore
import SwiftUI

/// v0.1's colour row (swatches + eyedropper, hex field + colour well, auto-match), plus recent colours.
/// The well opens NSColorPanel through `ColorPanelBridge`, which throttles live updates; previews render off-main.
struct ColorControls: View {
    @ObservedObject var model: AppModel
    @State private var hexDraft = ""
    @State private var hexInvalid = false
    @FocusState private var hexFocused: Bool

    private var currentHex: String { model.colorHex.uppercased() }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Colour").sectionLabel()
            HStack(spacing: 8) {
                ForEach(ColorPreset.all) { preset in swatch(preset.hex, help: "\(preset.name) \(preset.hex)") }
                Spacer(); Button { model.sampleColor() } label: { Image(systemName: "eyedropper") }.buttonStyle(IconButtonStyle(isActive: model.isSampling)).help("Pick a colour from the screen")
            }
            if !model.recentColors.isEmpty {
                HStack(spacing: 8) { ForEach(model.recentColors, id: \.self) { hex in swatch(hex, help: "Recent \(hex)") } }
            }
            HStack {
                TextField("#RRGGBB", text: $hexDraft).textFieldStyle(.plain).font(.system(size: 12, design: .monospaced)).focused($hexFocused).onSubmit(commitHex)
                    .padding(8).background(Theme.control, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(hexInvalid ? Tone.danger.dot : .clear, lineWidth: 1))
                Button { model.colorPanelOpen.toggle() } label: {
                    Capsule().fill(swiftUIColor(model.autoMatch ? (model.focusedImage?.edgeColor ?? model.frameColor) : model.frameColor)).frame(width: 44, height: 24)
                        .overlay(Capsule().stroke(model.colorPanelOpen ? Theme.brand : Theme.line, lineWidth: model.colorPanelOpen ? 2 : 1))
                }.buttonStyle(.plain).help("Custom colour…")
            }
            if hexInvalid { Text("Use #RRGGBB, for example #F4F1EA").font(.system(size: 11)).foregroundStyle(Tone.danger.text) }
            Toggle("Auto-match edges", isOn: $model.autoMatch).toggleStyle(.switch).controlSize(.mini).foregroundStyle(Theme.secondary)
        }
        .background(
            ColorPanelBridge(
                isOpen: $model.colorPanelOpen,
                hex: model.colorHex,
                onChange: { hex in model.applyColor(hex, remember: false) },
                onClose: { hex in model.rememberRecent(hex) }
            )
            .frame(width: 0, height: 0)
        )
        .onAppear { hexDraft = model.colorHex }
        .onChange(of: model.colorHex) { _, newValue in
            if !hexFocused { hexDraft = newValue }
            hexInvalid = false
        }
        .onChange(of: hexFocused) { _, focused in
            if !focused { hexDraft = model.colorHex; hexInvalid = false }
        }
    }

    private func swatch(_ hex: String, help: String) -> some View {
        Button { model.applyColor(hex, remember: false) } label: {
            Circle().fill(swiftUIColor(FrameColor(hex: hex) ?? .white)).frame(width: 25, height: 25)
                .overlay(Circle().stroke(!model.autoMatch && currentHex == hex ? Theme.brand : Theme.line, lineWidth: 2))
        }.buttonStyle(.plain).help(help)
    }

    private func commitHex() {
        guard let color = FrameColor.parseHex6(hexDraft) else {
            hexInvalid = true
            return
        }
        hexInvalid = false
        hexDraft = color.hex
        model.applyColor(color.hex, remember: true)
    }
}

/// Drives NSColorPanel.shared: sets this coordinator as target/action while open, throttles continuous updates,
/// and reports when the panel closes.
struct ColorPanelBridge: NSViewRepresentable {
    @Binding var isOpen: Bool
    let hex: String
    let onChange: (String) -> Void
    let onClose: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        coordinator.onClose = onClose
        let binding = $isOpen
        coordinator.markClosed = { binding.wrappedValue = false }
        if isOpen && !coordinator.isOpen {
            coordinator.open(hex: hex)
        } else if !isOpen && coordinator.isOpen {
            coordinator.close()
        } else if isOpen {
            coordinator.sync(hex: hex)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onChange: ((String) -> Void)?
        var onClose: ((String) -> Void)?
        var markClosed: (() -> Void)?
        private(set) var isOpen = false
        private var lastHex = ""
        private var pendingHex: String?
        private var flushScheduled = false
        private var isSyncing = false

        func open(hex: String) {
            let panel = NSColorPanel.shared
            panel.showsAlpha = false
            panel.isContinuous = true
            isSyncing = true
            setPanelColor(hex)
            isSyncing = false
            lastHex = hex
            panel.setTarget(self)
            panel.setAction(#selector(colorChanged(_:)))
            NotificationCenter.default.addObserver(self, selector: #selector(panelWillClose(_:)), name: NSWindow.willCloseNotification, object: panel)
            isOpen = true
            panel.orderFront(nil)
        }

        /// Keeps the panel in step when the colour changes elsewhere (a preset, the hex field) while it is open.
        func sync(hex: String) {
            guard hex != lastHex, pendingHex == nil else { return }
            lastHex = hex
            isSyncing = true
            setPanelColor(hex)
            isSyncing = false
        }

        /// Closes without posting back to the binding (used when the binding itself turned false, or the view went away).
        /// Callbacks are deferred because this runs inside a SwiftUI view update.
        func close() {
            guard isOpen else { return }
            let pending = pendingHex
            pendingHex = nil
            if let pending { lastHex = pending }
            let finalHex = lastHex
            detach()
            NSColorPanel.shared.orderOut(nil)
            Task { @MainActor [weak self] in
                if let pending { self?.onChange?(pending) }
                self?.onClose?(finalHex)
            }
        }

        @objc func colorChanged(_ sender: NSColorPanel) {
            guard !isSyncing, isOpen, let rgb = sender.color.usingColorSpace(.sRGB) else { return }
            pendingHex = FrameColor(red: Double(rgb.redComponent), green: Double(rgb.greenComponent), blue: Double(rgb.blueComponent)).hex
            guard !flushScheduled else { return }
            flushScheduled = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(50))
                self?.flush()
            }
        }

        @objc func panelWillClose(_ notification: Notification) {
            guard isOpen else { return }
            flush()
            detach()
            onClose?(lastHex)
            markClosed?()
        }

        private func flush() {
            flushScheduled = false
            guard let hex = pendingHex else { return }
            pendingHex = nil
            lastHex = hex
            onChange?(hex)
        }

        private func detach() {
            isOpen = false
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: NSColorPanel.shared)
            NSColorPanel.shared.setTarget(nil)
            NSColorPanel.shared.setAction(nil)
        }

        private func setPanelColor(_ hex: String) {
            guard let color = FrameColor(hex: hex) else { return }
            NSColorPanel.shared.color = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        }
    }
}
