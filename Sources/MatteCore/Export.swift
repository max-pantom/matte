import CoreGraphics
import Foundation
import ImageIO

public enum ExportWarning: Sendable, Hashable, CustomStringConvertible {
    /// The requested type cannot be encoded on this Mac; `used` was written instead.
    case typeUnavailable(requested: ExportFileType, used: ExportFileType)
    /// Quality was lowered to meet the size cap.
    case qualityReduced(from: Double, to: Double, cap: Int)
    /// The written file is still larger than the cap.
    case overSizeCap(bytes: Int, cap: Int)
    /// A lossless file was over the cap and was written as `to` instead.
    case lossyFallback(from: ExportFileType, to: ExportFileType)
    /// The natural file name was taken; `to` was used.
    case renamed(from: String, to: String)
    /// Metadata was requested but the source could not be read (or no source URL was given).
    case metadataUnavailable

    public var description: String {
        switch self {
        case .typeUnavailable(let requested, let used): "\(requested.displayName) is not supported on this Mac; wrote \(used.displayName)"
        case .qualityReduced(let from, let to, let cap): "quality lowered from \(Int((from * 100).rounded())) to \(Int((to * 100).rounded())) to fit \(ByteSize.format(cap))"
        case .overSizeCap(let bytes, let cap): "\(ByteSize.format(bytes)) is over the \(ByteSize.format(cap)) cap"
        case .lossyFallback(let from, let to): "\(from.displayName) was over the size cap; wrote \(to.displayName)"
        case .renamed(let from, let to): "\(from) exists; wrote \(to)"
        case .metadataUnavailable: "source metadata unavailable; wrote without it"
        }
    }
}

public struct ExportResult: Sendable {
    public let url: URL
    public let pixelSize: PixelSize
    public let bytes: Int
    /// The type actually written (may differ from the requested one after a fallback).
    public let fileType: ExportFileType
    /// Encoder quality used, nil for PNG.
    public let quality: Double?
    public let warnings: [ExportWarning]
}

extension MatteRenderer {
    /// Renders `format`, encodes it per `options`, writes it and verifies its pixel size.
    /// - Parameters:
    ///   - renderOptions: framing options; `options.overrides[format.id]` is applied on top.
    ///   - sourceURL: supplies {name} and, when `stripMetadata` is false, the metadata to copy.
    ///   - outputDirectory: overrides `options.outputDirectory`; falls back to the source's folder. Created if missing.
    ///   - index: value of {index} (1-based position of the source in the batch).
    ///   - avoiding: file names already used in this batch, so patterns without {format} don't clobber each other.
    @discardableResult
    public static func export(image: CGImage, format: MatteFormat, options: ExportOptions, renderOptions: RenderOptions = RenderOptions(), sourceURL: URL? = nil, outputDirectory: URL? = nil, index: Int = 1, date: Date = Date(), avoiding: Set<String> = []) throws -> ExportResult {
        try performExport(image: image, format: format, options: options, renderOptions: renderOptions, sourceURL: sourceURL, outputDirectory: outputDirectory, index: index, date: date, avoiding: avoiding, fixedURL: nil)
    }

    /// The URL `export` would write before collision handling or size-cap fallbacks, for overwrite checks. Nil without any directory.
    public static func plannedURL(sourceURL: URL?, format: MatteFormat, options: ExportOptions, outputDirectory: URL? = nil, index: Int = 1, date: Date = Date()) -> URL? {
        guard let directory = outputDirectory ?? options.outputDirectory ?? sourceURL?.deletingLastPathComponent() else { return nil }
        let baseName = FilenamePattern.expand(options.filenamePattern, name: sourceName(sourceURL), format: format, pixelSize: options.pixelSize(for: format), date: date, index: index)
        return directory.appendingPathComponent("\(baseName).\(options.resolvedFileType.fileExtension)")
    }

    static func performExport(image: CGImage, format: MatteFormat, options: ExportOptions, renderOptions: RenderOptions, sourceURL: URL?, outputDirectory: URL?, index: Int, date: Date, avoiding: Set<String>, fixedURL: URL?) throws -> ExportResult {
        guard let directory = fixedURL?.deletingLastPathComponent() ?? outputDirectory ?? options.outputDirectory ?? sourceURL?.deletingLastPathComponent() else { throw MatteError.noOutputDirectory }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var warnings: [ExportWarning] = []

        var fileType = options.fileType
        if !fileType.isAvailable {
            warnings.append(.typeUnavailable(requested: fileType, used: .png))
            fileType = .png
        }

        let size = options.pixelSize(for: format)
        let rendered = try render(image: image, format: format, options: options.renderOptions(renderOptions, for: format), pixelSize: size, colorSpace: options.colorSpace)

        var metadata: [CFString: Any] = [:]
        if !options.stripMetadata {
            if let sourceURL, let copied = copyableMetadata(from: sourceURL) { metadata = copied } else { warnings.append(.metadataUnavailable) }
        }

        let quality = min(1, max(0, options.quality))
        let cap = options.effectiveMaxFileSize(for: format)
        var encoded = try encodeFitting(rendered, as: fileType, quality: quality, cap: cap, metadata: metadata)
        warnings += encoded.warnings
        if let cap, encoded.data.count > cap, !fileType.isLossy, options.allowLossyFallback {
            let fallback = try encodeFitting(rendered, as: .jpeg, quality: quality, cap: cap, metadata: metadata)
            warnings.append(.lossyFallback(from: fileType, to: .jpeg))
            warnings += fallback.warnings
            encoded = fallback
        }
        if let cap, encoded.data.count > cap { warnings.append(.overSizeCap(bytes: encoded.data.count, cap: cap)) }

        let url: URL
        if let fixedURL, encoded.type.fileExtension == fixedURL.pathExtension {
            url = fixedURL
        } else {
            let baseName = fixedURL?.deletingPathExtension().lastPathComponent
                ?? FilenamePattern.expand(options.filenamePattern, name: sourceName(sourceURL), format: format, pixelSize: size, date: date, index: index)
            let unique = FilenamePattern.uniqueURL(directory: directory, baseName: baseName, fileExtension: encoded.type.fileExtension, overwriteExisting: options.overwriteExisting || fixedURL != nil, avoiding: avoiding)
            if unique.renamed { warnings.append(.renamed(from: "\(baseName).\(encoded.type.fileExtension)", to: unique.url.lastPathComponent)) }
            url = unique.url
        }

        do { try encoded.data.write(to: url, options: .atomic) } catch { throw MatteError.cannotWrite(url) }
        let actual = try imageSize(at: url)
        guard Int(actual.width) == size.width, Int(actual.height) == size.height else { throw MatteError.verificationFailed(url, expected: size.cgSize, actual: actual) }
        return ExportResult(url: url, pixelSize: size, bytes: encoded.data.count, fileType: encoded.type, quality: encoded.type.isLossy ? encoded.quality : nil, warnings: warnings)
    }

    private static func sourceName(_ sourceURL: URL?) -> String {
        sourceURL?.deletingPathExtension().lastPathComponent ?? "image"
    }

    private struct Encoded {
        var data: Data
        var type: ExportFileType
        var quality: Double
        var warnings: [ExportWarning]
    }

    /// Encodes at `quality`; for lossy types over `cap`, binary-searches quality down to `ExportOptions.minimumCapQuality` for the best that fits.
    private static func encodeFitting(_ image: CGImage, as type: ExportFileType, quality: Double, cap: Int?, metadata: [CFString: Any]) throws -> Encoded {
        let first = try encode(image, as: type, quality: quality, metadata: metadata)
        guard type.isLossy, let cap, first.count > cap else { return Encoded(data: first, type: type, quality: quality, warnings: []) }
        let lowestQuality = min(ExportOptions.minimumCapQuality, quality)
        guard lowestQuality < quality else { return Encoded(data: first, type: type, quality: quality, warnings: []) }
        let lowest = try encode(image, as: type, quality: lowestQuality, metadata: metadata)
        guard lowest.count <= cap else {
            // Nothing fits; keep the smallest attempt and let the caller report it.
            let reduced = lowest.count < first.count
            return Encoded(data: reduced ? lowest : first, type: type, quality: reduced ? lowestQuality : quality, warnings: reduced ? [.qualityReduced(from: quality, to: lowestQuality, cap: cap)] : [])
        }
        var best = (data: lowest, quality: lowestQuality)
        var low = lowestQuality, high = quality
        for _ in 0..<7 {
            let middle = (low + high) / 2
            let data = try encode(image, as: type, quality: middle, metadata: metadata)
            if data.count <= cap { best = (data, middle); low = middle } else { high = middle }
        }
        return Encoded(data: best.data, type: type, quality: best.quality, warnings: [.qualityReduced(from: quality, to: best.quality, cap: cap)])
    }

    private static func encode(_ image: CGImage, as type: ExportFileType, quality: Double, metadata: [CFString: Any]) throws -> Data {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(buffer as CFMutableData, type.typeIdentifier as CFString, 1, nil) else { throw MatteError.cannotEncode(type.displayName) }
        var properties = metadata
        if type.isLossy { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MatteError.cannotEncode(type.displayName) }
        return buffer as Data
    }

    /// EXIF, EXIF aux, TIFF and IPTC from the source, minus GPS, pixel dimensions and subject coordinates; orientation reset to 1 because pixels are already upright.
    static func copyableMetadata(from url: URL) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        var result: [CFString: Any] = [:]
        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            for key in [kCGImagePropertyExifPixelXDimension, kCGImagePropertyExifPixelYDimension, kCGImagePropertyExifSubjectArea, kCGImagePropertyExifSubjectLocation] {
                exif.removeValue(forKey: key)
            }
            result[kCGImagePropertyExifDictionary] = exif
        }
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff.removeValue(forKey: kCGImagePropertyTIFFOrientation)
            result[kCGImagePropertyTIFFDictionary] = tiff
        }
        if let aux = properties[kCGImagePropertyExifAuxDictionary] { result[kCGImagePropertyExifAuxDictionary] = aux }
        if let iptc = properties[kCGImagePropertyIPTCDictionary] { result[kCGImagePropertyIPTCDictionary] = iptc }
        result[kCGImagePropertyOrientation] = 1
        return result
    }
}
