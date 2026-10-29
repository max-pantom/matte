import Foundation
import MatteCore

struct CLIOptions {
    var images: [String] = []
    var output = "out"
    var formatIDs: [String]?
    var padding = 0.06
    var alwaysPad = false
    var mode = RenderMode.fit
    var color = FrameColor.white
    var autoMatch = false
    var type = ExportFileType.png
    var quality = ExportOptions.defaultQuality
    var scale = ExportScale.x1
    var namePattern = ExportOptions.defaultFilenamePattern
    var overrides: [String: FormatOverride] = [:]
    var colorSpace = ExportColorSpace.sRGB
    var keepMetadata = false
    var maxSize: Int?
    var platformCaps = false
    var lossyFallback = false
    var overwrite = false
    var list = false
    var simulate = false
    var selftest = false
}

func cliError(_ message: String) -> NSError {
    NSError(domain: "matte-cli", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
}

func usage() {
    let available = ExportFileType.allCases.map { $0.isAvailable ? $0.rawValue : "\($0.rawValue) (unavailable here)" }.joined(separator: ", ")
    print("""
    matte-cli <images...> [options]
      --out DIR                 export location (default: out)
      --formats all|id,id       formats to export (default: all; see --list)
      --pad 0.06                padding in fit mode, 0...0.3
      --mode fit|fill
      --color #RRGGBB|auto      matte colour, or sample the image edges
      --always-pad              pad even when the ratio already matches
      --type png|jpeg|heic|webp file type (default png); --jpeg is an alias for --type jpeg
      --quality 0-100           JPEG/HEIC/WebP quality (default 92)
      --scale 1x|2x|max:N       2x doubles each format's pixels; max:N caps the long edge at N px
      --name "<pattern>"        tokens {name} {format} {w} {h} {ratio} {date} {index}
                                (default "{name}__{format}_{w}x{h}")
      --override id:pad=0.1,mode=fill   per-format padding/mode (repeatable)
      --colorspace srgb|p3      output colour space (default srgb)
      --keep-metadata           copy source EXIF/TIFF/IPTC (never GPS); stripped by default
      --max-size 5MB            byte cap (B/KB/MB, decimal); lossy types lower quality down to 40 to fit
      --platform-caps           cap at each platform's limit (X 5 MB, Instagram 8 MB) unless --max-size is set
      --allow-lossy-fallback    write JPEG when a PNG is over the cap
      --overwrite               replace existing files instead of appending -2, -3
    matte-cli --simulate <images...>   print how X and Instagram crop these images when posted together, in order
    matte-cli --list                    list format ids
    matte-cli --selftest                exercise the export engine in a temporary folder
    File types on this Mac: \(available)
    """)
}

func padded(_ text: String, _ width: Int) -> String {
    text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
}

func describe(ratio: Double, loss: Double) -> String {
    let percent = Int((loss * 100).rounded())
    return String(format: "%.3f ", ratio) + (percent == 0 ? "full" : "crop \(percent)%")
}

func simulate(paths: [String]) throws {
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var names: [String] = []
    var ratios: [Double] = []
    for path in paths {
        let url = URL(fileURLWithPath: path, relativeTo: cwd).standardizedFileURL
        let size = try MatteRenderer.orientedImageSize(at: url)
        names.append("\(url.lastPathComponent) \(Int(size.width))x\(Int(size.height))")
        ratios.append(size.width / size.height)
    }
    let rows = Simulator.simulate(ratios: ratios)
    let posts = XCarousel.posts(rows)
    print("Simulating \(rows.count) image\(rows.count == 1 ? "" : "s") in order. X: \(posts.count) post\(posts.count == 1 ? "" : "s") (max \(XCarousel.maxImagesPerPost) per post); tiles 3:4...20:17 in multi-image posts, 3:4...2:1 alone.")
    print("Instagram carousel: every slide uses the first image's ratio clamped to 4:5...1.91:1; profile grid tiles are 3:4.")
    let nameWidth = max(24, (names.map(\.count).max() ?? 0) + 2)
    let header: [String] = [padded("image", nameWidth), padded("ratio", 8), padded("X post", 6), padded("X carousel", 18), padded("X single", 18), padded("IG carousel", 18), "IG grid 3:4"]
    print(header.joined())
    for (postIndex, post) in posts.enumerated() {
        for row in post {
            let columns: [String] = [
                padded(names[row.index], nameWidth),
                padded(String(format: "%.3f", row.sourceRatio), 8),
                padded(String(postIndex + 1), 6),
                padded(describe(ratio: row.xCarouselRatio, loss: row.xCarouselLoss), 18),
                padded(describe(ratio: row.xSingleRatio, loss: row.xSingleLoss), 18),
                padded(describe(ratio: row.igCarouselRatio, loss: row.igCarouselLoss), 18),
                describe(ratio: row.igGridRatio, loss: row.igGridLoss),
            ]
            print(columns.joined())
        }
    }
    if rows.count > IGCarousel.maxSlides { print("Note: Instagram carousels hold \(IGCarousel.maxSlides) slides; images \(IGCarousel.maxSlides + 1)+ need another post.") }
}

/// `id:pad=0.1,mode=fill`
func parseOverride(_ text: String) throws -> (String, FormatOverride) {
    guard let colon = text.firstIndex(of: ":") else { throw cliError("Override must look like id:pad=0.1,mode=fill") }
    let id = String(text[..<colon])
    guard MatteFormat.format(id: id) != nil else { throw cliError("Unknown format in override: \(id)") }
    var entry = FormatOverride()
    for pair in text[text.index(after: colon)...].split(separator: ",") {
        let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { throw cliError("Override setting must be key=value: \(pair)") }
        switch parts[0] {
        case "pad", "padding":
            guard let value = Double(parts[1]), (0...0.3).contains(value) else { throw cliError("Override padding must be between 0 and 0.3") }
            entry.padding = value
        case "mode":
            guard let mode = RenderMode(rawValue: parts[1]) else { throw cliError("Override mode must be fit or fill") }
            entry.mode = mode
        default: throw cliError("Unknown override setting: \(parts[0])")
        }
    }
    guard !entry.isEmpty else { throw cliError("Override for \(id) sets nothing") }
    return (id, entry)
}

func parse(_ arguments: [String]) throws -> CLIOptions {
    var options = CLIOptions()
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        func nextValue() throws -> String {
            guard index + 1 < arguments.count else { throw NSError(domain: "matte-cli", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing value after \(argument)"]) }
            index += 1; return arguments[index]
        }
        switch argument {
        case "--help", "-h": usage(); exit(0)
        case "--list": options.list = true
        case "--simulate": options.simulate = true
        case "--selftest": options.selftest = true
        case "--always-pad": options.alwaysPad = true
        case "--out": options.output = try nextValue()
        case "--formats":
            let value = try nextValue(); options.formatIDs = value == "all" ? nil : value.split(separator: ",").map(String.init)
        case "--pad":
            guard let value = Double(try nextValue()), (0...0.3).contains(value) else { throw NSError(domain: "matte-cli", code: 2, userInfo: [NSLocalizedDescriptionKey: "Padding must be between 0 and 0.3"]) }
            options.padding = value
        case "--mode":
            guard let value = RenderMode(rawValue: try nextValue()) else { throw NSError(domain: "matte-cli", code: 2, userInfo: [NSLocalizedDescriptionKey: "Mode must be fit or fill"]) }
            options.mode = value
        case "--color":
            let value = try nextValue()
            if value == "auto" { options.autoMatch = true }
            else if let color = FrameColor(hex: value) { options.color = color }
            else { throw NSError(domain: "matte-cli", code: 2, userInfo: [NSLocalizedDescriptionKey: "Colour must be #RRGGBB or auto"]) }
        case "--jpeg": options.type = .jpeg
        case "--type":
            let value = try nextValue().lowercased()
            guard let type = ExportFileType(rawValue: value == "jpg" ? "jpeg" : value) else { throw cliError("Type must be png, jpeg, heic or webp") }
            options.type = type
        case "--quality":
            guard let value = Double(try nextValue()), (0...100).contains(value) else { throw cliError("Quality must be between 0 and 100") }
            options.quality = value / 100
        case "--scale":
            let value = try nextValue()
            guard let scale = ExportScale(argument: value) else { throw cliError("Scale must be 1x, 2x or max:N") }
            options.scale = scale
        case "--name": options.namePattern = try nextValue()
        case "--override":
            let (id, formatOverride) = try parseOverride(try nextValue())
            options.overrides[id] = formatOverride
        case "--colorspace":
            guard let space = ExportColorSpace(rawValue: try nextValue().lowercased()) else { throw cliError("Colour space must be srgb or p3") }
            options.colorSpace = space
        case "--keep-metadata": options.keepMetadata = true
        case "--max-size":
            let value = try nextValue()
            guard let bytes = ByteSize.parse(value) else { throw cliError("Max size must look like 5MB, 800KB or 200000") }
            options.maxSize = bytes
        case "--platform-caps": options.platformCaps = true
        case "--allow-lossy-fallback": options.lossyFallback = true
        case "--overwrite": options.overwrite = true
        default:
            if argument.hasPrefix("-") { throw NSError(domain: "matte-cli", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown option: \(argument)"]) }
            options.images.append(argument)
        }
        index += 1
    }
    return options
}

do {
    let options = try parse(Array(CommandLine.arguments.dropFirst()))
    if options.list {
        for format in MatteFormat.all { print("\(format.id)\t\(format.width)x\(format.height)\t\(format.platform.rawValue)\t\(format.name)") }
        exit(0)
    }
    if options.selftest { exit(runSelfTest() ? 0 : 1) }
    guard !options.images.isEmpty else { usage(); exit(2) }
    if options.simulate {
        try simulate(paths: options.images)
        exit(0)
    }
    let selected: [MatteFormat]
    if let ids = options.formatIDs {
        let known = Dictionary(uniqueKeysWithValues: MatteFormat.all.map { ($0.id, $0) })
        let unknown = ids.filter { known[$0] == nil }
        guard unknown.isEmpty else { throw NSError(domain: "matte-cli", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown format: \(unknown.joined(separator: ", "))"]) }
        selected = ids.compactMap { known[$0] }
    } else { selected = MatteFormat.all }
    let outputRoot = URL(fileURLWithPath: options.output, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
    let exportOptions = ExportOptions(fileType: options.type, quality: options.quality, scale: options.scale, filenamePattern: options.namePattern, overrides: options.overrides, colorSpace: options.colorSpace, stripMetadata: !options.keepMetadata, maxFileSizeBytes: options.maxSize, usePlatformSizeCaps: options.platformCaps, allowLossyFallback: options.lossyFallback, overwriteExisting: options.overwrite, outputDirectory: outputRoot)
    if !options.type.isAvailable { print("Note: \(options.type.displayName) is not supported on this Mac; writing PNG.") }
    var written = 0
    var warned = 0
    var usedNames: Set<String> = []
    for (imageIndex, path) in options.images.enumerated() {
        let sourceURL = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        let image = try MatteRenderer.loadImage(at: sourceURL)
        let ratio = Fit.displayRatio(width: image.width, height: image.height)
        print("\(sourceURL.lastPathComponent): \(image.width)x\(image.height) · \(ratio)")
        let renderOptions = RenderOptions(mode: options.mode, padding: options.padding, alwaysPadPerfect: options.alwaysPad, color: options.color, autoMatch: options.autoMatch)
        for format in selected {
            let formatOptions = exportOptions.renderOptions(renderOptions, for: format)
            let analysis = Fit.analyze(imageSize: CGSize(width: image.width, height: image.height), format: format, mode: formatOptions.mode)
            print("  \(format.id): \(format.width)x\(format.height) · \(analysis.label)")
            let result = try MatteRenderer.export(image: image, format: format, options: exportOptions, renderOptions: renderOptions, sourceURL: sourceURL, index: imageIndex + 1, avoiding: options.overwrite ? usedNames : [])
            usedNames.insert(result.url.lastPathComponent)
            let verified = try MatteRenderer.imageSize(at: result.url)
            let quality = result.quality.map { " q\(Int(($0 * 100).rounded()))" } ?? ""
            print("  wrote \(result.url.path) \(Int(verified.width))x\(Int(verified.height)) \(ByteSize.format(result.bytes)) \(result.fileType.displayName)\(quality)")
            for warning in result.warnings { print("    warning: \(warning)") }
            if !result.warnings.isEmpty { warned += 1 }
            written += 1
        }
    }
    print("Verified \(written) output\(written == 1 ? "" : "s") at exact pixel sizes.\(warned > 0 ? " \(warned) with warnings." : "")")
} catch {
    fputs("matte-cli: \(error.localizedDescription)\n", stderr)
    exit(1)
}
