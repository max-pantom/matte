import CoreGraphics
import Foundation

public enum RenderMode: String, Codable, Sendable, CaseIterable {
    case fit
    case fill
}

public enum Verdict: String, Codable, Sendable {
    case perfect
    case needsFrame
    case needsCrop
}

public struct FitAnalysis: Sendable {
    public let verdict: Verdict
    public let label: String
    public let cropLoss: Double
    public let scaleFactor: Double
    public let isUpscaled: Bool
}

public struct FrameColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = min(1, max(0, red)); self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue)); self.alpha = min(1, max(0, alpha))
    }

    public static let white = FrameColor(red: 1, green: 1, blue: 1)
    public static let black = FrameColor(red: 0, green: 0, blue: 0)

    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        if text.count == 6 {
            self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
        } else {
            self.init(red: Double((value >> 24) & 255) / 255, green: Double((value >> 16) & 255) / 255, blue: Double((value >> 8) & 255) / 255, alpha: Double(value & 255) / 255)
        }
    }

    public var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    /// Strict #RRGGBB (or RRGGBB) parser for user-typed values.
    public static func parseHex6(_ text: String) -> FrameColor? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, value.allSatisfy(\.isHexDigit) else { return nil }
        return FrameColor(hex: value)
    }

    /// Relative luminance (sRGB approximation), used to pick a legible checkmark colour.
    public var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
}

public struct RenderOptions: Sendable {
    public var mode: RenderMode
    public var padding: Double
    public var alwaysPadPerfect: Bool
    public var color: FrameColor
    public var autoMatch: Bool
    public var focalPoint: CGPoint
    public var cornerRadius: Double

    public init(mode: RenderMode = .fit, padding: Double = 0.06, alwaysPadPerfect: Bool = false, color: FrameColor = .white, autoMatch: Bool = false, focalPoint: CGPoint = CGPoint(x: 0.5, y: 0.5), cornerRadius: Double = 0) {
        self.mode = mode; self.padding = min(0.3, max(0, padding)); self.alwaysPadPerfect = alwaysPadPerfect
        self.color = color; self.autoMatch = autoMatch; self.focalPoint = focalPoint; self.cornerRadius = cornerRadius
    }

    /// Stable string identifying every option that affects rendered pixels, for preview caches.
    public var cacheKey: String {
        "\(mode.rawValue)|\(Int((padding * 1000).rounded()))|\(alwaysPadPerfect)|\(color.hex)|\(autoMatch)|\(Int((focalPoint.x * 1000).rounded())),\(Int((focalPoint.y * 1000).rounded()))|\(cornerRadius)"
    }
}

public enum Fit {
    public static func analyze(imageSize: CGSize, format: MatteFormat, mode: RenderMode = .fit) -> FitAnalysis {
        let imageRatio = imageSize.width / imageSize.height
        let relativeDifference = abs(imageRatio - format.aspectRatio) / format.aspectRatio
        let fitScale = min(Double(format.width) / imageSize.width, Double(format.height) / imageSize.height)
        let fillScale = max(Double(format.width) / imageSize.width, Double(format.height) / imageSize.height)
        let visibleArea = (Double(format.width) / fillScale) * (Double(format.height) / fillScale)
        let cropLoss = max(0, 1 - visibleArea / (imageSize.width * imageSize.height))
        let upscaled = fillScale > 1.0001
        if relativeDifference <= 0.01 {
            return FitAnalysis(verdict: .perfect, label: upscaled ? "Perfect as is · upscaled" : "Perfect as is", cropLoss: cropLoss, scaleFactor: fitScale, isUpscaled: upscaled)
        }
        if mode == .fill {
            return FitAnalysis(verdict: .needsCrop, label: "Needs a crop (loses \(Int((cropLoss * 100).rounded()))%)", cropLoss: cropLoss, scaleFactor: fillScale, isUpscaled: upscaled)
        }
        return FitAnalysis(verdict: .needsFrame, label: cropLoss <= 0.15 ? "Needs a frame (or a light crop)" : "Needs a frame", cropLoss: cropLoss, scaleFactor: fitScale, isUpscaled: fitScale > 1.0001)
    }

    public static func displayRatio(width: Int, height: Int) -> String {
        let divisor = gcd(width, height)
        return "\(width / divisor):\(height / divisor)"
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }
}
