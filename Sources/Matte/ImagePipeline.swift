import AppKit
import MatteCore
import SwiftUI

/// CGImage is immutable; this lets decoded images cross into background tasks.
struct SendableImage: @unchecked Sendable {
    let cgImage: CGImage
}

/// An image in the batch. Decoded once, off the main thread: a ≤1200px preview for every on-screen render and
/// a small list thumbnail. The full-resolution source is only decoded at export time.
struct SourceImage: Identifiable, Sendable {
    let id: UUID
    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let preview: SendableImage
    let thumbnail: SendableImage
    /// Edge colour sampled once from the preview; used whenever "Match edges" is on (preview and export alike).
    let edgeColor: FrameColor

    var name: String { url.lastPathComponent }
    var ratio: Double { Double(pixelWidth) / Double(max(1, pixelHeight)) }
    var pixelSize: CGSize { CGSize(width: pixelWidth, height: pixelHeight) }
    var dimensions: String { "\(pixelWidth)×\(pixelHeight) · \(Fit.displayRatio(width: pixelWidth, height: pixelHeight))" }
}

enum ImageLoader {
    static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "webp"]
    static let previewMaxPixels = 1200
    static let thumbnailMaxPixels = 160

    /// Synchronous decode; call from a background task.
    static func load(_ url: URL) -> SourceImage? {
        guard let size = try? MatteRenderer.orientedImageSize(at: url),
              let preview = try? MatteRenderer.loadImage(at: url, maxPixelSize: previewMaxPixels),
              let thumbnail = try? MatteRenderer.loadImage(at: url, maxPixelSize: thumbnailMaxPixels) else { return nil }
        return SourceImage(id: UUID(), url: url, pixelWidth: Int(size.width), pixelHeight: Int(size.height),
                           preview: SendableImage(cgImage: preview), thumbnail: SendableImage(cgImage: thumbnail),
                           edgeColor: MatteRenderer.autoMatchEdges(image: preview))
    }

    /// Decodes many files in parallel, off the main actor, preserving order and dropping unreadable files.
    static func loadAll(_ urls: [URL]) async -> [SourceImage] {
        await Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: (Int, SourceImage?).self) { group in
                for (index, url) in urls.enumerated() {
                    group.addTask { (index, ImageLoader.load(url)) }
                }
                var results = [SourceImage?](repeating: nil, count: urls.count)
                for await (index, image) in group { results[index] = image }
                return results.compactMap { $0 }
            }
        }.value
    }
}

extension RenderOptions {
    /// Replaces "match edges" with the image's pre-sampled edge colour so previews and exports agree and nothing re-samples per frame.
    func resolved(for image: SourceImage) -> RenderOptions {
        guard autoMatch else { return self }
        var copy = self
        copy.color = image.edgeColor
        copy.autoMatch = false
        return copy
    }
}

// MARK: - Preview cache

private final class CachedImage: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

/// Rendered previews keyed by image id + format id + options hash + size. NSCache is thread-safe.
final class PreviewCache: @unchecked Sendable {
    static let shared = PreviewCache()
    private let cache = NSCache<NSString, CachedImage>()

    private init() {
        cache.countLimit = 600
        cache.totalCostLimit = 400 * 1024 * 1024
    }

    func image(for key: String) -> CGImage? { cache.object(forKey: key as NSString)?.image }

    func store(_ image: CGImage, for key: String) {
        cache.setObject(CachedImage(image), forKey: key as NSString, cost: image.bytesPerRow * image.height)
    }
}

/// Everything needed to render one preview off the main thread.
struct RenderRequest: Sendable, Equatable {
    let key: String
    let source: SendableImage
    let format: MatteFormat
    let options: RenderOptions
    let maxDimension: Int

    init(image: SourceImage, format: MatteFormat, options: RenderOptions, maxDimension: Int) {
        let resolved = options.resolved(for: image)
        self.key = "\(image.id.uuidString)|\(format.id)|\(resolved.cacheKey)|\(maxDimension)"
        self.source = image.preview
        self.format = format
        self.options = resolved
        self.maxDimension = maxDimension
    }

    static func == (lhs: RenderRequest, rhs: RenderRequest) -> Bool { lhs.key == rhs.key }
}

/// Shows a rendered preview. Renders in a detached task, debounced ~80ms after the request changes, and caches the result.
/// Keeps the previous image on screen while a new one renders, so option changes never flash.
struct RenderedPreview: View {
    let request: RenderRequest?
    var contentMode: ContentMode = .fit
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Theme.cardSubtle)
            }
        }
        .task(id: request?.key) { await load() }
    }

    private func load() async {
        guard let request else { image = nil; return }
        if let cached = PreviewCache.shared.image(for: request.key) {
            image = cached
            return
        }
        try? await Task.sleep(for: .milliseconds(80))
        if Task.isCancelled { return }
        let rendered = await Task.detached(priority: .userInitiated) { () -> SendableImage? in
            guard let output = try? MatteRenderer.render(image: request.source.cgImage, format: request.format, options: request.options, previewMaxDimension: request.maxDimension) else { return nil }
            return SendableImage(cgImage: output)
        }.value
        guard let rendered else { return }
        PreviewCache.shared.store(rendered.cgImage, for: request.key)
        if Task.isCancelled { return }
        image = rendered.cgImage
    }
}
