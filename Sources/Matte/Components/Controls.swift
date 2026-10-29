import SwiftUI

// MARK: - Buttons

enum ButtonKind {
    /// Inverted white, black text: the main action.
    case primary
    /// #ffffff12 plus hairline.
    case secondary
    /// No background until hovered.
    case ghost
}

struct MatteButtonStyle: ButtonStyle {
    var kind: ButtonKind = .secondary
    var height: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        MatteButtonBody(configuration: configuration, kind: kind, height: height)
    }
}

private struct MatteButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: ButtonKind
    let height: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var background: Color {
        guard isEnabled else { return kind == .ghost ? .clear : Theme.cardSubtle }
        switch kind {
        case .primary: return Color.white.opacity(configuration.isPressed ? 0.75 : hovering ? 0.8 : 0.95)
        case .secondary: return configuration.isPressed ? Theme.componentActive : hovering ? Theme.componentHover : Theme.component
        case .ghost: return configuration.isPressed ? Theme.componentActive : hovering ? Theme.componentHover : .clear
        }
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.fgDisabled }
        switch kind {
        case .primary: return .black
        case .secondary: return Theme.fg1
        case .ghost: return hovering ? Theme.fg1 : Theme.fg2
        }
    }

    var body: some View {
        configuration.label
            .font(Theme.font(height <= 24 ? 12 : 13, .medium))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, height <= 24 ? 8 : 10)
            .frame(height: height)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .hairline(6, color: kind == .secondary && isEnabled ? Theme.line : .clear)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.motion, value: hovering)
            .animation(.timingCurve(0, 0, 0.2, 1, duration: 0.2), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

/// Square icon-only button (transparent until hovered).
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, size: size, isActive: isActive)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: CGFloat
    let isActive: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: size <= 20 ? 10 : 13, weight: .medium))
            .foregroundStyle(!isEnabled ? Theme.fgDisabled : isActive ? Theme.brandText : hovering ? Theme.fg1 : Theme.fg2)
            .frame(width: size, height: size)
            .background(isActive ? Theme.brandSubtle : configuration.isPressed ? Theme.componentActive : hovering ? Theme.componentHover : .clear,
                        in: RoundedRectangle(cornerRadius: size <= 20 ? 4 : 6, style: .continuous))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.motion, value: hovering)
            .animation(Theme.motion, value: isActive)
            .onHover { hovering = $0 }
    }
}

/// Brand-coloured text link.
struct TextLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(13, .medium))
            .foregroundStyle(configuration.isPressed ? Theme.fg1 : Theme.brandText)
            .contentShape(Rectangle())
    }
}

// MARK: - Segmented control

/// Interfere segmented tabs: neutral track, sliding neutral indicator with a hairline.
struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var fillWidth = false
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                SegmentItem(
                    label: options[index].label,
                    isSelected: options[index].value == selection,
                    fillWidth: fillWidth,
                    namespace: namespace
                ) {
                    let value = options[index].value
                    withAnimation(Theme.slide) { selection = value }
                }
            }
        }
        .padding(2)
        .background(Theme.component, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct SegmentItem: View {
    let label: String
    let isSelected: Bool
    let fillWidth: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.font(13, .medium))
                .lineLimit(1)
                .foregroundStyle(isSelected || hovering ? Theme.fg1 : Theme.fg2)
                .padding(.horizontal, 10)
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .frame(height: 24)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.11))
                            .hairline(5, color: Theme.lineStrong.opacity(0.6))
                            .matchedGeometryEffect(id: "indicator", in: namespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.motion, value: hovering)
        .onHover { hovering = $0 }
    }
}

// MARK: - Switch

/// 16px pill switch, brand when on.
struct MatteSwitch: View {
    let title: String
    @Binding var isOn: Bool
    var subtitle: String? = nil
    @State private var hovering = false

    var body: some View {
        Button {
            withAnimation(Theme.motion) { isOn.toggle() }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.font(13, .medium)).foregroundStyle(hovering ? Theme.fg1 : Theme.fg2)
                    if let subtitle { Text(subtitle).font(Theme.font(11)).foregroundStyle(Theme.fg3).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 8)
                SwitchPill(isOn: isOn, hovering: hovering)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.motion, value: hovering)
        .onHover { hovering = $0 }
    }
}

struct SwitchPill: View {
    let isOn: Bool
    var hovering = false

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Theme.brand : (hovering ? Theme.componentActive : Theme.component))
            Circle().fill(Color.white).frame(width: 12, height: 12).padding(2).shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
        }
        .frame(width: 28, height: 16)
        .overlay(Capsule().strokeBorder(isOn ? Color.clear : Theme.line, lineWidth: 0.5))
        .animation(Theme.motion, value: isOn)
    }
}

// MARK: - Slider

/// Thin track slider with a white thumb; snaps to `step`.
struct MatteSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    @State private var hovering = false
    @State private var dragging = false

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? min(1, max(0, (value - range.lowerBound) / span)) : 0
    }

    var body: some View {
        GeometryReader { proxy in
            let thumb: CGFloat = 14
            let usable = max(1, proxy.size.width - thumb)
            let x = CGFloat(fraction) * usable
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.component).frame(height: 4)
                Capsule().fill(dragging || hovering ? Theme.fg1 : Theme.fg2).frame(width: x + thumb / 2, height: 4)
                Circle()
                    .fill(Color.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .scaleEffect(dragging ? 1.15 : hovering ? 1.07 : 1)
                    .offset(x: x)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !dragging { dragging = true }
                        let t = min(1, max(0, Double((gesture.location.x - thumb / 2) / usable)))
                        var newValue = range.lowerBound + t * (range.upperBound - range.lowerBound)
                        if step > 0 { newValue = (newValue / step).rounded() * step }
                        newValue = min(range.upperBound, max(range.lowerBound, newValue))
                        if abs(newValue - value) > step / 10 { value = newValue }
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(height: 20)
        .onHover { hovering = $0 }
        .animation(Theme.motion, value: hovering)
        .animation(Theme.motion, value: dragging)
    }
}

// MARK: - Checkbox, badge, progress

struct Checkbox: View {
    let isOn: Bool
    var isMixed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isOn || isMixed ? Theme.brand : Theme.component)
            .frame(width: 16, height: 16)
            .overlay(
                Image(systemName: isMixed && !isOn ? "minus" : "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white)
                    .opacity(isOn || isMixed ? 1 : 0)
                    .scaleEffect(isOn || isMixed ? 1 : 0.6)
            )
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(isOn || isMixed ? Color.clear : Theme.lineStrong, lineWidth: 0.5))
            .animation(Theme.motion, value: isOn)
    }
}

enum BadgeKind {
    case neutral, brand, positive, warning, danger

    var colors: (dot: Color, background: Color, text: Color) {
        switch self {
        case .neutral: return (dot: Theme.fg3, background: Theme.component, text: Theme.fg2)
        case .brand: return (dot: Theme.brand, background: Theme.brandSubtle, text: Theme.brandText)
        case .positive: return (dot: Theme.positive, background: Theme.positiveSubtle, text: Theme.positiveText)
        case .warning: return (dot: Theme.warning, background: Theme.warningSubtle, text: Theme.warningText)
        case .danger: return (dot: Theme.danger, background: Theme.dangerSubtle, text: Theme.dangerText)
        }
    }
}

struct Badge: View {
    let text: String
    var kind: BadgeKind = .neutral
    var icon: String? = nil
    var showsDot = true

    var body: some View {
        let colors = kind.colors
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(colors.dot)
            } else if showsDot {
                Circle().fill(colors.dot).frame(width: 6, height: 6)
            }
            Text(text).lineLimit(1)
        }
        .font(Theme.font(12))
        .foregroundStyle(colors.text)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(colors.background, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.component)
                Capsule().fill(Theme.fg1).frame(width: max(4, proxy.size.width * CGFloat(min(1, max(0, value)))))
            }
        }
        .frame(height: 4)
        .animation(Theme.motion, value: value)
    }
}

/// Dashed drop target; turns brand when a drag hovers the window.
struct DropZone: View {
    let title: String
    let subtitle: String
    var minHeight: CGFloat = 140
    var iconSize: CGFloat = 26
    var isTargeted = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: iconSize, weight: .light))
                    .foregroundStyle(isTargeted ? Theme.brandText : hovering ? Theme.fg2 : Theme.fg3)
                Text(title).font(Theme.font(minHeight > 200 ? 15 : 13, .medium)).foregroundStyle(Theme.fg1)
                Text(subtitle).font(Theme.font(12)).foregroundStyle(Theme.fg3)
            }
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(isTargeted ? Theme.brandSubtle : hovering ? Theme.cardStrong : Theme.cardSubtle, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isTargeted ? Theme.brand : hovering ? Theme.lineStrong : Theme.line, style: StrokeStyle(lineWidth: isTargeted ? 1 : 0.5, dash: isTargeted ? [] : [5, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.motion, value: hovering)
        .animation(Theme.motion, value: isTargeted)
        .onHover { hovering = $0 }
    }
}
