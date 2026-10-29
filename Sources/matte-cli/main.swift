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
    var type = ExportType.png
    var list = false
    var simulate = false
}

func usage() {
    print("matte-cli <images...> [--out DIR] [--formats all|id,id] [--pad 0.06] [--mode fit|fill] [--color #RRGGBB|auto] [--jpeg] [--always-pad]")
    print("matte-cli --simulate <images...>   print how X and Instagram crop these images when posted together, in order")
    print("matte-cli --list                    list format ids")
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
    var written = 0
    for path in options.images {
        let sourceURL = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        let image = try MatteRenderer.loadImage(at: sourceURL)
        let ratio = Fit.displayRatio(width: image.width, height: image.height)
        print("\(sourceURL.lastPathComponent): \(image.width)x\(image.height) · \(ratio)")
        let perImage = outputRoot
        let renderOptions = RenderOptions(mode: options.mode, padding: options.padding, alwaysPadPerfect: options.alwaysPad, color: options.color, autoMatch: options.autoMatch)
        for format in selected {
            let analysis = Fit.analyze(imageSize: CGSize(width: image.width, height: image.height), format: format, mode: options.mode)
            print("  \(format.id): \(format.width)x\(format.height) · \(analysis.label)")
            let result = try MatteRenderer.export(image: image, sourceURL: sourceURL, format: format, options: renderOptions, type: options.type, outputDirectory: perImage)
            let verified = try MatteRenderer.imageSize(at: result)
            print("  wrote \(result.path) \(Int(verified.width))x\(Int(verified.height))")
            written += 1
        }
    }
    print("Verified \(written) output\(written == 1 ? "" : "s") at exact pixel sizes.")
} catch {
    fputs("matte-cli: \(error.localizedDescription)\n", stderr)
    exit(1)
}
