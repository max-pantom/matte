import AppKit
import MatteCore
import SwiftUI

struct ColorControls: View {
    @ObservedObject var model: AppModel
    @State private var hexDraft = ""
    @State private var hexInvalid = false
    @FocusState private var hexFocused: Bool

    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 8), count: 7)

    private var currentHex: String { model.colorHex.uppercased() }
    private var isKnownColor: Bool {
        ColorPreset.all.contains { $0.hex == currentHex } || model.recentColors.contains(currentHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Colour").sectionLabel()
                Spacer()
                Text(model.autoMatch ? "Auto · \(model.focusedImage?.edgeColor.hex ?? "edges")" : currentHex)
                    .monoCaption()
                    .contentTransition(.opacity)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                if model.autoMatch {
                    Swatch(color: model.focusedImage?.edgeColor ?? .white, name: "Matched from image edges", isSelected: true, badge: "A") {}
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                ForEach(ColorPreset.all) { preset in
                    Swatch(color: FrameColor(hex: preset.hex) ?? .white, name: "\(preset.name) \(preset.hex)",
                           isSelected: !model.autoMatch && currentHex == preset.hex, isDimmed: model.autoMatch) {
                        withAnimation(Theme.motion) { model.applyColor(preset.hex, remember: false) }
                    }
                }
                CustomSwatch(isActive: model.colorPanelOpen || (!model.autoMatch && !isKnownColor), isDimmed: model.autoMatch) {
                    model.colorPanelOpen.toggle()
                }
            }

            if !model.recentColors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent").font(Theme.font(11)).foregroundStyle(Theme.fg3)
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(model.recentColors, id: \.self) { hex in
                            Swatch(color: FrameColor(hex: hex) ?? .white, name: hex,
                                   isSelected: !model.autoMatch && currentHex == hex, isDimmed: model.autoMatch) {
                                withAnimation(Theme.motion) { model.applyColor(hex, remember: false) }
                            }
                        }
                    }
                }
                .transition(.opacity)
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(swiftUIColor(FrameColor.parseHex6(hexDraft) ?? model.frameColor))
                        .frame(width: 14, height: 14)
                        .hairline(3, color: Theme.lineStrong)
                    TextField("#RRGGBB", text: $hexDraft)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.fg1)
                        .focused($hexFocused)
                        .onSubmit(commitHex)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(Theme.component, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(hexInvalid ? Theme.danger : hexFocused ? Theme.brand : Theme.line, lineWidth: hexInvalid || hexFocused ? 1 : 0.5)
                )
                .animation(.easeOut(duration: 0.075), value: hexFocused)

                Button { model.sampleColor() } label: { Image(systemName: "eyedropper") }
                    .buttonStyle(IconButtonStyle(size: 32, isActive: model.isSampling))
                    .help("Pick a colour from the screen")
            }
            if hexInvalid {
                Text("Use #RRGGBB, for example #F4F1EA").font(Theme.font(11)).foregroundStyle(Theme.dangerText)
                    .transition(.opacity)
            }

            MatteSwitch(title: "Match edges", isOn: $model.autoMatch,
                        subtitle: model.autoMatch ? "Uses the most common colour along each image's edges." : nil)
        }
        .animation(Theme.motion, value: model.autoMatch)
        .animation(Theme.motion, value: model.recentColors)
        .animation(Theme.motion, value: hexInvalid)
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

    private func commitHex() {
        guard let color = FrameColor.parseHex6(hexDraft) else {
            hexInvalid = true
            return
        }
        hexInvalid = false
        hexDraft = color.hex
        withAnimation(Theme.motion) { model.applyColor(color.hex, remember: true) }
    }
}

func swiftUIColor(_ color: FrameColor) -> Color {
    Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
}

struct Swatch: View {
    let color: FrameColor
    let name: String
    let isSelected: Bool
    var isDimmed = false
    var badge: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(swiftUIColor(color))
                Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(color.luminance > 0.6 ? Color.black.opacity(0.75) : Color.white)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else if let badge {
                    Text(badge).font(Theme.font(9, .semibold)).foregroundStyle(color.luminance > 0.6 ? Color.black.opacity(0.6) : Color.white.opacity(0.8))
                }
            }
            .frame(width: 20, height: 20)
            .padding(3)
            .overlay(Circle().strokeBorder(isSelected ? Theme.brand : hovering ? Theme.lineStrong : Color.clear, lineWidth: isSelected ? 2 : 1))
            .frame(width: 26, height: 26)
            .scaleEffect(hovering && !isSelected ? 1.06 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isDimmed ? 0.3 : 1)
        .help(name)
        .onHover { hovering = $0 }
        .animation(Theme.motion, value: isSelected)
        .animation(Theme.motion, value: hovering)
        .animation(Theme.motion, value: isDimmed)
    }
}

/// Rainbow swatch that opens the system colour panel.
struct CustomSwatch: View {
    let isActive: Bool
    var isDimmed = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                Circle().fill(Color.black.opacity(0.25)).padding(5)
                Image(systemName: "plus").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.white)
            }
            .frame(width: 20, height: 20)
            .padding(3)
            .overlay(Circle().strokeBorder(isActive ? Theme.brand : hovering ? Theme.lineStrong : Color.clear, lineWidth: isActive ? 2 : 1))
            .frame(width: 26, height: 26)
            .scaleEffect(hovering ? 1.06 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isDimmed ? 0.3 : 1)
        .help("Custom… (system colour panel)")
        .onHover { hovering = $0 }
        .animation(Theme.motion, value: isActive)
        .animation(Theme.motion, value: hovering)
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
