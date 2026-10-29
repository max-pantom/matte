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
}

func usage() {
    print("matte-cli <images...> [--out DIR] [--formats all|id,id] [--pad 0.06] [--mode fit|fill] [--color #RRGGBB|auto] [--jpeg] [--always-pad]")
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
