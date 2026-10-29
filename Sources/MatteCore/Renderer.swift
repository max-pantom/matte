import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum MatteError: LocalizedError {
    case cannotRead(URL), cannotCreateContext, cannotCreateDestination(URL), cannotWrite(URL), verificationFailed(URL, expected: CGSize, actual: CGSize)
    public var errorDescription: String? {
        switch self {
        case .cannotRead(let url): "Could not read image: \(url.path)"
        case .cannotCreateContext: "Could not create image context"
        case .cannotCreateDestination(let url): "Could not create image destination: \(url.path)"
        case .cannotWrite(let url): "Could not write image: \(url.path)"
        case .verificationFailed(let url, let expected, let actual): "Pixel verification failed for \(url.lastPathComponent): expected \(Int(expected.width))×\(Int(expected.height)), got \(Int(actual.width))×\(Int(actual.height))"
        }
    }
}

public enum ExportType: String, Codable, Sendable, CaseIterable {
    case png, jpeg
    public var fileExtension: String { self == .png ? "png" : "jpg" }
}

public enum MatteRenderer {
    /// Decodes the full-resolution image, applying any EXIF orientation.
    public static func loadImage(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw MatteError.cannotRead(url) }
        if orientation(of: source) != 1, let size = rawPixelSize(of: source) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(max(size.width, size.height)),
            ]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) { return image }
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary) else { throw MatteError.cannotRead(url) }
        return image
    }

    /// Decodes a downscaled copy whose longest side is at most `maxPixelSize`, applying EXIF orientation. Used for on-screen previews.
    public static func loadImage(at url: URL, maxPixelSize: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw MatteError.cannotRead(url) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw MatteError.cannotRead(url) }
        return image
    }

    public static func imageSize(at url: URL) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let size = rawPixelSize(of: source) else { throw MatteError.cannotRead(url) }
        return size
    }

    /// Pixel size as displayed, i.e. with width and height swapped for rotated EXIF orientations (5–8).
    public static func orientedImageSize(at url: URL) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let size = rawPixelSize(of: source) else { throw MatteError.cannotRead(url) }
        return orientation(of: source) >= 5 ? CGSize(width: size.height, height: size.width) : size
    }

    private static func rawPixelSize(of source: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let width = props[kCGImagePropertyPixelWidth] as? NSNumber, let height = props[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private static func orientation(of source: CGImageSource) -> Int {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let value = props[kCGImagePropertyOrientation] as? NSNumber else { return 1 }
        return value.intValue
    }

    public static func render(image: CGImage, format: MatteFormat, options: RenderOptions, previewMaxDimension: Int? = nil) throws -> CGImage {
        let factor: Double = if let previewMaxDimension { min(1, Double(previewMaxDimension) / Double(max(format.width, format.height))) } else { 1 }
        let width = max(1, Int((Double(format.width) * factor).rounded()))
        let height = max(1, Int((Double(format.height) * factor).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw MatteError.cannotCreateContext }

        let frameColor = options.autoMatch ? autoMatchEdges(image: image) : options.color
        context.setFillColor(CGColor(red: frameColor.red, green: frameColor.green, blue: frameColor.blue, alpha: frameColor.alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high

        let sourceW = Double(image.width), sourceH = Double(image.height)
        let targetW = Double(width), targetH = Double(height)
        let analysis = Fit.analyze(imageSize: CGSize(width: sourceW, height: sourceH), format: format, mode: options.mode)
        let requestedPadding = options.mode == .fit && (analysis.verdict != .perfect || options.alwaysPadPerfect) ? options.padding : 0
        let scale: Double
        if options.mode == .fill {
            scale = max(targetW / sourceW, targetH / sourceH)
        } else {
            scale = min(targetW * (1 - 2 * requestedPadding) / sourceW, targetH * (1 - 2 * requestedPadding) / sourceH)
        }
        let drawW = (sourceW * scale).rounded(), drawH = (sourceH * scale).rounded()
        let originX: Double
        let originY: Double
        if options.mode == .fill {
            originX = ((targetW - drawW) * min(1, max(0, options.focalPoint.x))).rounded()
            originY = ((targetH - drawH) * min(1, max(0, 1 - options.focalPoint.y))).rounded()
        } else {
            originX = ((targetW - drawW) / 2).rounded(); originY = ((targetH - drawH) / 2).rounded()
        }
        let rect = CGRect(x: originX, y: originY, width: drawW, height: drawH)
        if options.cornerRadius > 0 {
            context.saveGState(); context.addPath(CGPath(roundedRect: rect, cornerWidth: options.cornerRadius * factor, cornerHeight: options.cornerRadius * factor, transform: nil)); context.clip(); context.draw(image, in: rect); context.restoreGState()
        } else { context.draw(image, in: rect) }
        guard let result = context.makeImage() else { throw MatteError.cannotCreateContext }
        return result
    }

    public static func autoMatchEdges(image: CGImage) -> FrameColor {
        guard let data = normalizedPixels(image: image) else { return .black }
        let w = image.width, h = image.height, row = w * 4
        var buckets: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        func sample(_ x: Int, _ y: Int) {
            let offset = y * row + x * 4
            let r = Int(data[offset]), g = Int(data[offset + 1]), b = Int(data[offset + 2])
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            let old = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (old.count + 1, old.r + r, old.g + g, old.b + b)
        }
        if w > 0 && h > 0 {
            for x in stride(from: 0, to: w, by: 8) { sample(x, 0); if h > 1 { sample(x, h - 1) } }
            for y in stride(from: 0, to: h, by: 8) { sample(0, y); if w > 1 { sample(w - 1, y) } }
        }
        guard let winning = buckets.values.max(by: { $0.count < $1.count }), winning.count > 0 else { return .black }
        return FrameColor(red: Double(winning.r) / Double(winning.count * 255), green: Double(winning.g) / Double(winning.count * 255), blue: Double(winning.b) / Double(winning.count * 255))
    }

    /// Where `export` writes a given source/format pair.
    public static func outputURL(sourceURL: URL, format: MatteFormat, type: ExportType, outputDirectory: URL) -> URL {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        return outputDirectory.appendingPathComponent("\(base)__\(format.id)_\(format.width)x\(format.height).\(type.fileExtension)")
    }

    public static func export(image: CGImage, sourceURL: URL, format: MatteFormat, options: RenderOptions, type: ExportType, quality: Double = 0.92, outputDirectory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let rendered = try render(image: image, format: format, options: options)
        let url = outputURL(sourceURL: sourceURL, format: format, type: type, outputDirectory: outputDirectory)
        let uti = type == .png ? UTType.png.identifier : UTType.jpeg.identifier
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, uti as CFString, 1, nil) else { throw MatteError.cannotCreateDestination(url) }
        let properties: CFDictionary = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: min(1, max(0.1, quality))] as CFDictionary : [:] as CFDictionary
        CGImageDestinationAddImage(destination, rendered, properties)
        guard CGImageDestinationFinalize(destination) else { throw MatteError.cannotWrite(url) }
        let actual = try imageSize(at: url)
        let expected = format.size
        guard Int(actual.width) == format.width, Int(actual.height) == format.height else { throw MatteError.verificationFailed(url, expected: expected, actual: actual) }
        return url
    }

    private static func normalizedPixels(image: CGImage) -> [UInt8]? {
        let count = image.width * image.height * 4
        var bytes = [UInt8](repeating: 0, count: count)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let ok = bytes.withUnsafeMutableBytes { pointer -> Bool in
            guard let context = CGContext(data: pointer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return true
        }
        return ok ? bytes : nil
    }
}
