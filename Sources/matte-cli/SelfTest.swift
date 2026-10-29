import CoreGraphics
import Foundation
import ImageIO
import MatteCore

/// `matte-cli --selftest`: exercises the export engine against a synthetic image in a temporary folder.
func runSelfTest() -> Bool {
    var test = SelfTest(root: FileManager.default.temporaryDirectory.appendingPathComponent("matte-selftest-\(UUID().uuidString)"))
    test.run()
    return test.failures == 0
}

struct SelfTest {
    let root: URL
    private(set) var failures = 0
    private var passes = 0

    init(root: URL) { self.root = root }

    mutating func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition { passes += 1; print("PASS \(name)") } else { failures += 1; print("FAIL \(name)\(detail.isEmpty ? "" : ": \(detail)")") }
    }

    mutating func attempt(_ name: String, _ body: (inout SelfTest) throws -> Void) {
        do { try body(&self) } catch { check(name, false, "threw \(error.localizedDescription)") }
    }

    mutating func run() {
        print("Self-test in \(root.path)")
        print("File types: " + ExportFileType.allCases.map { "\($0.displayName) \($0.isAvailable ? "yes" : "no")" }.joined(separator: ", "))
        guard let image = Self.syntheticImage(width: 1920, height: 1080) else { check("synthetic image", false); return }
        let landscape = MatteFormat.format(id: "x-landscape")!
        let square = MatteFormat.format(id: "x-square")!
        let sourceURL = root.appendingPathComponent("selftest-source.jpg")

        attempt("write source") { test in
            try FileManager.default.createDirectory(at: test.root, withIntermediateDirectories: true)
            try Self.writeSource(image, to: sourceURL)
        }

        // Every type writes, reads back at the right size and in the right container (or falls back to PNG with a warning).
        for type in ExportFileType.allCases {
            attempt("type \(type.rawValue)") { test in
                let options = ExportOptions(fileType: type, outputDirectory: test.root.appendingPathComponent("types"))
                let result = try MatteRenderer.export(image: image, format: landscape, options: options, sourceURL: sourceURL)
                let size = try MatteRenderer.imageSize(at: result.url)
                test.check("type \(type.rawValue) dimensions", Int(size.width) == 1600 && Int(size.height) == 900, "got \(Int(size.width))x\(Int(size.height))")
                let written = Self.containerType(of: result.url)
                if type.isAvailable {
                    test.check("type \(type.rawValue) container", written == type.typeIdentifier && result.fileType == type, "got \(written ?? "nil")")
                } else {
                    let warned = result.warnings.contains(ExportWarning.typeUnavailable(requested: type, used: ExportFileType.png))
                    test.check("type \(type.rawValue) falls back to PNG", result.fileType == ExportFileType.png && written == ExportFileType.png.typeIdentifier && warned)
                }
                test.check("type \(type.rawValue) byte count", Self.fileSize(result.url) == result.bytes)
            }
        }

        attempt("scale") { test in
            let directory = test.root.appendingPathComponent("scale")
            let double = try MatteRenderer.export(image: image, format: square, options: ExportOptions(scale: .x2, outputDirectory: directory), sourceURL: sourceURL)
            let doubleSize = try MatteRenderer.imageSize(at: double.url)
            test.check("scale 2x", Int(doubleSize.width) == 2160 && Int(doubleSize.height) == 2160 && double.url.lastPathComponent == "selftest-source__x-square_2160x2160.png", "got \(double.url.lastPathComponent) \(Int(doubleSize.width))x\(Int(doubleSize.height))")
            let capped = try MatteRenderer.export(image: image, format: landscape, options: ExportOptions(scale: .maxLongEdge(1000), outputDirectory: directory), sourceURL: sourceURL)
            let cappedSize = try MatteRenderer.imageSize(at: capped.url)
            test.check("scale max:1000", Int(cappedSize.width) == 1000 && Int(cappedSize.height) == 563, "got \(Int(cappedSize.width))x\(Int(cappedSize.height))")
            test.check("scale max:5000 does not upscale", ExportScale.maxLongEdge(5000).pixelSize(for: square) == PixelSize(width: 1080, height: 1080))
            let parsedScales: [ExportScale?] = ["2x", "max:2048", "max:0"].map { ExportScale(argument: $0) }
            test.check("scale parsing", parsedScales == [ExportScale.x2, ExportScale.maxLongEdge(2048), nil])
        }

        attempt("pattern") { test in
            let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 12))!
            let size = PixelSize(width: 1600, height: 900)
            let expanded = FilenamePattern.expand("{name}_{format}_{w}x{h}_{ratio}_{date}_{index}", name: "shot", format: landscape, pixelSize: size, date: date, index: 7)
            test.check("pattern tokens", expanded == "shot_x-landscape_1600x900_16-9_2026-03-04_7", "got \(expanded)")
            let defaultName = FilenamePattern.expand(ExportOptions.defaultFilenamePattern, name: "shot", format: landscape, pixelSize: size)
            let legacy = MatteRenderer.outputURL(sourceURL: URL(fileURLWithPath: "/tmp/shot.png"), format: landscape, type: .png, outputDirectory: URL(fileURLWithPath: "/tmp"))
            test.check("pattern default matches legacy naming", "\(defaultName).png" == legacy.lastPathComponent, "got \(defaultName) vs \(legacy.lastPathComponent)")
            let sanitized = ["a/b:c", ".hidden", "  "].map { FilenamePattern.sanitize($0) }
            test.check("pattern sanitising", sanitized == ["a-b-c", "hidden", "image"], "got \(sanitized)")
            test.check("pattern unknown token kept", FilenamePattern.expand("{name}-{nope}", name: "a", format: landscape, pixelSize: size) == "a-{nope}")

            let options = ExportOptions(filenamePattern: "{name}-{w}", outputDirectory: test.root.appendingPathComponent("pattern"))
            let first = try MatteRenderer.export(image: image, format: landscape, options: options, sourceURL: sourceURL)
            let second = try MatteRenderer.export(image: image, format: landscape, options: options, sourceURL: sourceURL)
            let renamed = second.warnings.contains(where: { if case .renamed = $0 { return true }; return false })
            let firstOK = first.url.lastPathComponent == "selftest-source-1600.png"
            let secondOK = second.url.lastPathComponent == "selftest-source-1600-2.png"
            test.check("pattern collision -2", firstOK && secondOK && renamed, "got \(first.url.lastPathComponent), \(second.url.lastPathComponent)")
            var overwriting = options
            overwriting.overwriteExisting = true
            let third = try MatteRenderer.export(image: image, format: landscape, options: overwriting, sourceURL: sourceURL)
            test.check("pattern overwrite", third.url.lastPathComponent == "selftest-source-1600.png")
            let fourth = try MatteRenderer.export(image: image, format: landscape, options: overwriting, sourceURL: sourceURL, avoiding: [third.url.lastPathComponent])
            test.check("pattern avoids batch names", fourth.url.lastPathComponent == "selftest-source-1600-2.png", "got \(fourth.url.lastPathComponent)")
        }

        attempt("max size jpeg") { test in
            let directory = test.root.appendingPathComponent("cap")
            let high = try MatteRenderer.export(image: image, format: landscape, options: ExportOptions(fileType: .jpeg, quality: 0.92, filenamePattern: "high", outputDirectory: directory))
            let low = try MatteRenderer.export(image: image, format: landscape, options: ExportOptions(fileType: .jpeg, quality: ExportOptions.minimumCapQuality, filenamePattern: "low", outputDirectory: directory))
            test.check("max size jpeg quality affects size", low.bytes < high.bytes, "q40 \(low.bytes) vs q92 \(high.bytes)")
            let cap = (low.bytes + high.bytes) / 2
            let capped = try MatteRenderer.export(image: image, format: landscape, options: ExportOptions(fileType: .jpeg, quality: 0.92, filenamePattern: "capped", maxFileSizeBytes: cap, outputDirectory: directory))
            let onDisk = Self.fileSize(capped.url) ?? Int.max
            let reduced = capped.warnings.contains(where: { if case .qualityReduced = $0 { return true }; return false })
            let over = capped.warnings.contains(where: { if case .overSizeCap = $0 { return true }; return false })
            test.check("max size jpeg respected", capped.bytes <= cap && onDisk <= cap && reduced && !over, "cap \(cap), wrote \(onDisk), warnings \(capped.warnings)")
            let impossible = try MatteRenderer.export(image: image, format: landscape, options: ExportOptions(fileType: .jpeg, filenamePattern: "impossible", maxFileSizeBytes: 1_000, outputDirectory: directory))
            test.check("max size jpeg unreachable warns", impossible.warnings.contains(where: { if case .overSizeCap = $0 { return true }; return false }))

            let png = try MatteRenderer.export(image: image, format: landscape, options: ExportOptions(filenamePattern: "png", outputDirectory: directory))
            let pngCap = png.bytes / 2
            let warnedPNG = try MatteRenderer.export(image: image, format: landscape, options: ExportOptions(filenamePattern: "png-capped", maxFileSizeBytes: pngCap, outputDirectory: directory))
            let pngWarned = warnedPNG.warnings.contains(ExportWarning.overSizeCap(bytes: warnedPNG.bytes, cap: pngCap))
            test.check("max size png warns", warnedPNG.fileType == ExportFileType.png && pngWarned)
            let fallback = try MatteRenderer.export(image: image, format: landscape, options: ExportOptions(filenamePattern: "png-fallback", maxFileSizeBytes: pngCap, allowLossyFallback: true, outputDirectory: directory))
            let fellBack = fallback.warnings.contains(ExportWarning.lossyFallback(from: ExportFileType.png, to: ExportFileType.jpeg))
            test.check("max size png lossy fallback", fallback.fileType == ExportFileType.jpeg && fallback.url.pathExtension == "jpg" && fellBack, "wrote \(fallback.url.lastPathComponent) \(fallback.warnings)")
            let parsed: [Int?] = ["5MB", "800KB", "1.5mb", "200000", "abc"].map { ByteSize.parse($0) }
            test.check("byte size parsing", parsed == [5_000_000, 800_000, 1_500_000, 200_000, nil], "got \(parsed)")
        }

        attempt("metadata") { test in
            let directory = test.root.appendingPathComponent("metadata")
            let kept = try MatteRenderer.export(image: image, format: square, options: ExportOptions(fileType: .jpeg, stripMetadata: false, outputDirectory: directory), sourceURL: sourceURL)
            let keptProps = Self.properties(of: kept.url)
            let make = (keptProps[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] as? String
            let keptGPS = keptProps[kCGImagePropertyGPSDictionary] != nil
            test.check("metadata kept without GPS", make == "MatteSelfTest" && !keptGPS, "make \(make ?? "nil"), gps \(keptGPS)")
            let stripped = try MatteRenderer.export(image: image, format: square, options: ExportOptions(fileType: .jpeg, filenamePattern: "stripped", outputDirectory: directory), sourceURL: sourceURL)
            let strippedProps = Self.properties(of: stripped.url)
            let strippedMake = (strippedProps[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFMake] as? String
            let strippedGPS = strippedProps[kCGImagePropertyGPSDictionary] != nil
            test.check("metadata stripped", strippedMake == nil && !strippedGPS, "make \(strippedMake ?? "nil"), gps \(strippedGPS)")
        }

        attempt("overrides and colour space") { test in
            let directory = test.root.appendingPathComponent("misc")
            let options = ExportOptions(overrides: ["x-square": FormatOverride(padding: 0.2, mode: .fill)], colorSpace: .displayP3, outputDirectory: directory)
            let resolved = options.renderOptions(RenderOptions(), for: square)
            let untouched = options.renderOptions(RenderOptions(), for: landscape)
            test.check("override applied", resolved.mode == RenderMode.fill && abs(resolved.padding - 0.2) < 0.0001 && untouched.mode == RenderMode.fit)
            let p3 = try MatteRenderer.export(image: image, format: square, options: options, sourceURL: sourceURL)
            let profile = Self.properties(of: p3.url)[kCGImagePropertyProfileName] as? String
            test.check("colour space p3 writes", p3.pixelSize == PixelSize(width: 1080, height: 1080))
            print("info: P3 export profile = \(profile ?? "none")")
            let data = try JSONEncoder().encode(options)
            var decoded = try JSONDecoder().decode(ExportOptions.self, from: data)
            let decodedPath = decoded.outputDirectory?.standardizedFileURL.path
            decoded.outputDirectory = options.outputDirectory
            test.check("options codable round trip", decoded == options && decodedPath == options.outputDirectory?.standardizedFileURL.path)
            test.check("options decode tolerates missing keys", (try? JSONDecoder().decode(ExportOptions.self, from: Data("{}".utf8))) == ExportOptions())
        }

        attempt("legacy export") { test in
            let directory = test.root.appendingPathComponent("legacy")
            let url = try MatteRenderer.export(image: image, sourceURL: sourceURL, format: landscape, options: RenderOptions(), type: .jpeg, outputDirectory: directory)
            let again = try MatteRenderer.export(image: image, sourceURL: sourceURL, format: landscape, options: RenderOptions(), type: .jpeg, outputDirectory: directory)
            let expected = MatteRenderer.outputURL(sourceURL: sourceURL, format: landscape, type: .jpeg, outputDirectory: directory)
            let container = Self.containerType(of: url)
            test.check("legacy export path and overwrite", url == expected && again == expected && container == ExportFileType.jpeg.typeIdentifier, "got \(url.lastPathComponent), \(again.lastPathComponent)")
        }

        print("\(passes) passed, \(failures) failed")
        if failures == 0 { try? FileManager.default.removeItem(at: root) } else { print("Kept outputs in \(root.path)") }
    }

    /// Gradient plus deterministic noise, so lossy sizes respond to quality.
    static func syntheticImage(width: Int, height: Int) -> CGImage? {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        var seed: UInt32 = 0x5EED
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = UInt8(truncatingIfNeeded: seed >> 26)
                let offset = (y * width + x) * 4
                bytes[offset] = UInt8(x * 200 / width) &+ noise
                bytes[offset + 1] = UInt8(y * 200 / height) &+ noise
                bytes[offset + 2] = UInt8((x + y) % 200) &+ noise
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// A JPEG source with a TIFF Make and a GPS block, for the metadata checks.
    static func writeSource(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, ExportFileType.jpeg.typeIdentifier as CFString, 1, nil) else { throw MatteError.cannotCreateDestination(url) }
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "MatteSelfTest"] as [CFString: Any],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 0.1, kCGImagePropertyGPSLongitudeRef: "W"] as [CFString: Any],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MatteError.cannotWrite(url) }
    }

    static func containerType(of url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) else { return nil }
        return type as String
    }

    static func properties(of url: URL) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    static func fileSize(_ url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }
}
