import CoreGraphics
import Foundation
import ImageIO

/// File types the export engine can write. HEIC and WebP depend on the system encoders; check `isAvailable`.
public enum ExportFileType: String, Codable, Sendable, CaseIterable, Hashable {
    case png, jpeg, heic, webp

    public init(_ legacy: ExportType) { self = legacy == .png ? .png : .jpeg }

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        case .webp: "webp"
        }
    }

    public var typeIdentifier: String {
        switch self {
        case .png: "public.png"
        case .jpeg: "public.jpeg"
        case .heic: "public.heic"
        case .webp: "org.webmproject.webp"
        }
    }

    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .webp: "WebP"
        }
    }

    /// Whether `quality` (and size capping by quality) applies.
    public var isLossy: Bool { self != .png }

    /// Whether this Mac's ImageIO can write the type. Unavailable types fall back to PNG with a warning.
    public var isAvailable: Bool {
        self == .png || self == .jpeg || Self.writableTypeIdentifiers.contains(typeIdentifier)
    }

    public static var availableCases: [ExportFileType] { allCases.filter { $0.isAvailable } }

    private static let writableTypeIdentifiers: Set<String> = {
        guard let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] else { return [] }
        return Set(identifiers)
    }()
}

public struct PixelSize: Codable, Sendable, Hashable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) { self.width = width; self.height = height }

    public var cgSize: CGSize { CGSize(width: width, height: height) }
    public var description: String { "\(width)x\(height)" }
}

/// Output scale relative to a format's nominal pixel size.
public enum ExportScale: Codable, Sendable, Hashable {
    case x1
    case x2
    /// Caps the long edge at this many pixels, keeping the ratio. Never upscales.
    case maxLongEdge(Int)

    public func pixelSize(width: Int, height: Int) -> PixelSize {
        switch self {
        case .x1:
            return PixelSize(width: width, height: height)
        case .x2:
            return PixelSize(width: width * 2, height: height * 2)
        case .maxLongEdge(let limit):
            let longEdge = max(width, height)
            guard limit > 0, longEdge > limit else { return PixelSize(width: width, height: height) }
            let factor = Double(limit) / Double(longEdge)
            return PixelSize(width: max(1, Int((Double(width) * factor).rounded())), height: max(1, Int((Double(height) * factor).rounded())))
        }
    }

    public func pixelSize(for format: MatteFormat) -> PixelSize { pixelSize(width: format.width, height: format.height) }

    /// Parses `1x`, `2x` or `max:N`.
    public init?(argument: String) {
        let text = argument.trimmingCharacters(in: .whitespaces).lowercased()
        switch text {
        case "1x", "x1", "1": self = .x1
        case "2x", "x2", "2": self = .x2
        default:
            guard text.hasPrefix("max:"), let limit = Int(text.dropFirst(4)), limit > 0 else { return nil }
            self = .maxLongEdge(limit)
        }
    }

    public var argument: String {
        switch self {
        case .x1: "1x"
        case .x2: "2x"
        case .maxLongEdge(let limit): "max:\(limit)"
        }
    }

    public var label: String {
        switch self {
        case .x1: "1×"
        case .x2: "2×"
        case .maxLongEdge(let limit): "Max \(limit) px"
        }
    }
}

public enum ExportColorSpace: String, Codable, Sendable, CaseIterable, Hashable {
    case sRGB = "srgb"
    case displayP3 = "p3"

    public var cgColorSpaceName: CFString { self == .sRGB ? CGColorSpace.sRGB : CGColorSpace.displayP3 }
    public var displayName: String { self == .sRGB ? "sRGB" : "Display P3" }
}

/// Per-format render overrides; nil fields keep the global `RenderOptions` value.
public struct FormatOverride: Codable, Sendable, Hashable {
    public var padding: Double?
    public var mode: RenderMode?

    public init(padding: Double? = nil, mode: RenderMode? = nil) { self.padding = padding; self.mode = mode }

    public var isEmpty: Bool { padding == nil && mode == nil }

    public func applied(to base: RenderOptions) -> RenderOptions {
        var options = base
        if let padding { options.padding = min(0.3, max(0, padding)) }
        if let mode { options.mode = mode }
        return options
    }
}

extension Platform {
    /// Upload limit worth staying under for still images (decimal bytes).
    public var recommendedMaxFileSizeBytes: Int {
        switch self {
        case .x: 5_000_000
        case .instagram: 8_000_000
        }
    }
}

extension MatteFormat {
    public var recommendedMaxFileSizeBytes: Int? { platform.recommendedMaxFileSizeBytes }
}

/// Everything about how a rendered format is encoded, sized, named and placed on disk.
public struct ExportOptions: Codable, Sendable, Hashable {
    public static let defaultFilenamePattern = "{name}__{format}_{w}x{h}"
    public static let defaultQuality = 0.92
    /// Lowest quality the size cap search will go to.
    public static let minimumCapQuality = 0.4

    public var fileType: ExportFileType
    /// 0...1, used by JPEG, HEIC and WebP.
    public var quality: Double
    public var scale: ExportScale
    /// Tokens: {name} {format} {w} {h} {ratio} {date} {index}. Empty means the default.
    public var filenamePattern: String
    /// Keyed by `MatteFormat.id`.
    public var overrides: [String: FormatOverride]
    public var colorSpace: ExportColorSpace
    /// When false, EXIF/TIFF/IPTC from the source are copied (never GPS), with orientation reset to 1.
    public var stripMetadata: Bool
    /// Explicit cap in bytes. Lossy types lower quality (down to 0.4) to fit; PNG warns, or falls back to JPEG if `allowLossyFallback`.
    public var maxFileSizeBytes: Int?
    /// When `maxFileSizeBytes` is nil, use the format's platform cap (X 5 MB, Instagram 8 MB).
    public var usePlatformSizeCaps: Bool
    public var allowLossyFallback: Bool
    /// False appends -2, -3… instead of replacing files already on disk.
    public var overwriteExisting: Bool
    public var outputDirectory: URL?

    public init(fileType: ExportFileType = .png, quality: Double = ExportOptions.defaultQuality, scale: ExportScale = .x1, filenamePattern: String = ExportOptions.defaultFilenamePattern, overrides: [String: FormatOverride] = [:], colorSpace: ExportColorSpace = .sRGB, stripMetadata: Bool = true, maxFileSizeBytes: Int? = nil, usePlatformSizeCaps: Bool = false, allowLossyFallback: Bool = false, overwriteExisting: Bool = false, outputDirectory: URL? = nil) {
        self.fileType = fileType
        self.quality = min(1, max(0, quality))
        self.scale = scale
        self.filenamePattern = filenamePattern
        self.overrides = overrides
        self.colorSpace = colorSpace
        self.stripMetadata = stripMetadata
        self.maxFileSizeBytes = maxFileSizeBytes
        self.usePlatformSizeCaps = usePlatformSizeCaps
        self.allowLossyFallback = allowLossyFallback
        self.overwriteExisting = overwriteExisting
        self.outputDirectory = outputDirectory
    }

    private enum CodingKeys: String, CodingKey {
        case fileType, quality, scale, filenamePattern, overrides, colorSpace, stripMetadata, maxFileSizeBytes, usePlatformSizeCaps, allowLossyFallback, overwriteExisting, outputDirectory
    }

    /// Tolerates missing keys so persisted settings survive new fields.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ExportOptions()
        fileType = try container.decodeIfPresent(ExportFileType.self, forKey: .fileType) ?? defaults.fileType
        quality = min(1, max(0, try container.decodeIfPresent(Double.self, forKey: .quality) ?? defaults.quality))
        scale = try container.decodeIfPresent(ExportScale.self, forKey: .scale) ?? defaults.scale
        filenamePattern = try container.decodeIfPresent(String.self, forKey: .filenamePattern) ?? defaults.filenamePattern
        overrides = try container.decodeIfPresent([String: FormatOverride].self, forKey: .overrides) ?? defaults.overrides
        colorSpace = try container.decodeIfPresent(ExportColorSpace.self, forKey: .colorSpace) ?? defaults.colorSpace
        stripMetadata = try container.decodeIfPresent(Bool.self, forKey: .stripMetadata) ?? defaults.stripMetadata
        maxFileSizeBytes = try container.decodeIfPresent(Int.self, forKey: .maxFileSizeBytes)
        usePlatformSizeCaps = try container.decodeIfPresent(Bool.self, forKey: .usePlatformSizeCaps) ?? defaults.usePlatformSizeCaps
        allowLossyFallback = try container.decodeIfPresent(Bool.self, forKey: .allowLossyFallback) ?? defaults.allowLossyFallback
        overwriteExisting = try container.decodeIfPresent(Bool.self, forKey: .overwriteExisting) ?? defaults.overwriteExisting
        outputDirectory = try container.decodeIfPresent(URL.self, forKey: .outputDirectory)
    }

    public static let `default` = ExportOptions()

    /// Old app settings (`ExportType` + JPEG quality) expressed as export options.
    public init(legacyType: ExportType, quality: Double, outputDirectory: URL?) {
        self.init(fileType: ExportFileType(legacyType), quality: quality, overwriteExisting: true, outputDirectory: outputDirectory)
    }

    /// The type actually written: the requested one, or PNG when the system cannot encode it.
    public var resolvedFileType: ExportFileType { fileType.isAvailable ? fileType : .png }

    public func pixelSize(for format: MatteFormat) -> PixelSize { scale.pixelSize(for: format) }

    public func renderOptions(_ base: RenderOptions, for format: MatteFormat) -> RenderOptions {
        overrides[format.id]?.applied(to: base) ?? base
    }

    public func effectiveMaxFileSize(for format: MatteFormat) -> Int? {
        if let maxFileSizeBytes, maxFileSizeBytes > 0 { return maxFileSizeBytes }
        return usePlatformSizeCaps ? format.recommendedMaxFileSizeBytes : nil
    }
}

/// Filename pattern expansion and sanitising.
public enum FilenamePattern {
    public static let tokens = ["{name}", "{format}", "{w}", "{h}", "{ratio}", "{date}", "{index}"]

    /// Expands tokens and sanitises the result. Returns a base name without extension.
    /// {format} is the format id, {ratio} e.g. `16-9`, {date} `yyyy-MM-dd` (local), {index} the 1-based source position.
    public static func expand(_ pattern: String, name: String, format: MatteFormat, pixelSize: PixelSize, date: Date = Date(), index: Int = 1) -> String {
        let template = pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ExportOptions.defaultFilenamePattern : pattern
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        let dateText = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let values: [(String, String)] = [
            ("{name}", name),
            ("{format}", format.id),
            ("{w}", String(pixelSize.width)),
            ("{h}", String(pixelSize.height)),
            ("{ratio}", format.ratioLabel.replacingOccurrences(of: ":", with: "-")),
            ("{date}", dateText),
            ("{index}", String(index)),
        ]
        var result = template
        for (token, value) in values { result = result.replacingOccurrences(of: token, with: value) }
        return sanitize(result)
    }

    /// Replaces path separators, `:` and other characters that are unsafe in filenames with `-`, trims, drops leading dots and caps the length.
    public static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        let dash = Unicode.Scalar(UInt8(ascii: "-"))
        var scalars = String.UnicodeScalarView()
        for scalar in name.unicodeScalars { scalars.append(illegal.contains(scalar) ? dash : scalar) }
        var result = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix(".") { result.removeFirst() }
        while result.utf8.count > 200 { result.removeLast() }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "image" : result
    }

    /// `base.ext`, or `base-2.ext`, `base-3.ext`… when that name is on disk (unless `overwriteExisting`) or in `avoiding` (file names, case-insensitive).
    public static func uniqueURL(directory: URL, baseName: String, fileExtension: String, overwriteExisting: Bool, avoiding: Set<String> = []) -> (url: URL, renamed: Bool) {
        let reserved = Set(avoiding.map { $0.lowercased() })
        func taken(_ fileName: String) -> Bool {
            if reserved.contains(fileName.lowercased()) { return true }
            return !overwriteExisting && FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path)
        }
        var fileName = "\(baseName).\(fileExtension)"
        var suffix = 2
        while taken(fileName) {
            fileName = "\(baseName)-\(suffix).\(fileExtension)"
            suffix += 1
        }
        return (directory.appendingPathComponent(fileName), suffix > 2)
    }
}

/// Decimal byte sizes (1 KB = 1,000 bytes, 1 MB = 1,000,000 bytes), matching Finder.
public enum ByteSize {
    /// Parses `5MB`, `500KB`, `1.5 mb`, `200000`, `200000B`.
    public static func parse(_ text: String) -> Int? {
        var value = text.trimmingCharacters(in: .whitespaces).uppercased()
        var multiplier = 1.0
        for (suffix, factor) in [("MB", 1_000_000.0), ("KB", 1_000.0), ("M", 1_000_000.0), ("K", 1_000.0), ("B", 1.0)] where value.hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            multiplier = factor
            break
        }
        guard let number = Double(value), number > 0, number.isFinite else { return nil }
        let bytes = (number * multiplier).rounded(.down)
        return bytes >= 1 && bytes < Double(Int.max) ? Int(bytes) : nil
    }

    public static func format(_ bytes: Int) -> String {
        if bytes < 1_000 { return "\(bytes) B" }
        if bytes < 1_000_000 { return String(format: "%.1f KB", Double(bytes) / 1_000) }
        return String(format: "%.2f MB", Double(bytes) / 1_000_000)
    }
}
