import CoreText
import SwiftUI

/// Interfere design tokens (reference/INTERFERE-DESIGN.md), dark theme.
enum Theme {
    static let shell = Color.black
    static let panel = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let modal = Color(red: 0.137, green: 0.137, blue: 0.137)
    static let cardSubtle = Color.white.opacity(0.035)
    static let cardStrong = Color.white.opacity(0.07)
    static let component = Color.white.opacity(0.07)
    static let componentHover = Color.white.opacity(0.106)
    static let componentActive = Color.white.opacity(0.133)
    static let sunken = Color.black.opacity(0.4)
    static let line = Color.white.opacity(0.07)
    static let lineStrong = Color.white.opacity(0.173)

    static let fg1 = Color.white.opacity(0.93)
    static let fg2 = Color.white.opacity(0.686)
    static let fg3 = Color.white.opacity(0.392)
    static let fgDisabled = Color.white.opacity(0.333)

    static let brand = Color(red: 0, green: 0.565, blue: 1)
    static let brandSubtle = Color(red: 0, green: 0.467, blue: 1).opacity(0.227)
    static let brandText = Color(red: 0.439, green: 0.722, blue: 1)

    static let positive = Color(red: 0.188, green: 0.643, blue: 0.424)
    static let positiveSubtle = Color(red: 0.133, green: 1, blue: 0.6).opacity(0.118)
    static let positiveText = Color(red: 0.275, green: 0.996, blue: 0.647).opacity(0.83)
    static let warning = Color(red: 0.969, green: 0.42, blue: 0.082)
    static let warningSubtle = Color(red: 0.984, green: 0.416, blue: 0).opacity(0.145)
    static let warningText = Color(red: 1, green: 0.627, blue: 0.341)
    static let danger = Color(red: 0.898, green: 0.302, blue: 0.18)
    static let dangerSubtle = Color(red: 1, green: 0.208, blue: 0.137).opacity(0.17)
    static let dangerText = Color(red: 1, green: 0.592, blue: 0.49)

    /// 150ms cubic-bezier(0, 0, .2, 1): colour, background and border changes.
    static var motion: Animation { .timingCurve(0, 0, 0.2, 1, duration: 0.15) }
    /// 200ms ease-in-out: sliding indicators.
    static var slide: Animation { .easeInOut(duration: 0.2) }

    /// "Inter Variable" when the bundled font registered, else nil (system font).
    static let fontFamily: String? = {
        let families = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        if families.contains("Inter Variable") { return "Inter Variable" }
        if families.contains("Inter") { return "Inter" }
        return nil
    }()

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let fontFamily { return Font.custom(fontFamily, size: size).weight(weight) }
        return Font.system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// 0.5px inset hairline, the design system's replacement for borders.
    func hairline(_ radius: CGFloat, color: Color = Theme.line) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(color, lineWidth: 0.5).allowsHitTesting(false))
    }

    func card(_ radius: CGFloat = 12, fill: Color = Theme.cardSubtle) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous)).hairline(radius)
    }

    func sectionLabel() -> some View { font(Theme.font(13, .medium)).foregroundStyle(Theme.fg3) }
    func monoCaption() -> some View { font(Theme.mono(11)).foregroundStyle(Theme.fg3) }
}

extension String {
    /// Abbreviates the home folder to ~.
    var abbreviatingHome: String {
        let home = NSHomeDirectory()
        return hasPrefix(home) ? "~" + String(dropFirst(home.count)) : self
    }
}
