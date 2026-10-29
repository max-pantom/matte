import CoreGraphics

public enum Platform: String, Codable, CaseIterable, Sendable {
    case x = "X"
    case instagram = "Instagram"
}

public enum PreviewKind: String, Codable, Sendable {
    case xFeedSingle, xCarousel, xHeader, xArticle
    case igFeed, igGrid, igStory

    /// Formats that can be posted as a feed image (and so make sense in the post simulator).
    public var isPostImage: Bool {
        switch self {
        case .xFeedSingle, .xCarousel, .igFeed, .igGrid: true
        case .xHeader, .xArticle, .igStory: false
        }
    }
}

public struct SafeInsets: Codable, Sendable, Equatable {
    public let top: Double
    public let leading: Double
    public let bottom: Double
    public let trailing: Double
    public let avatarOverlap: Bool

    public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0, avatarOverlap: Bool = false) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
        self.avatarOverlap = avatarOverlap
    }
}

public struct MatteFormat: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let platform: Platform
    public let name: String
    public let width: Int
    public let height: Int
    public let ratioLabel: String
    public let note: String
    public let safeInsets: SafeInsets?
    public let previewKind: PreviewKind

    public var aspectRatio: Double { Double(width) / Double(height) }
    public var size: CGSize { CGSize(width: width, height: height) }

    public static let all: [MatteFormat] = [
        // X, single-image posts. X Help: 2:1 to 3:4 are shown uncropped when the post has one image.
        .init(id: "x-landscape", platform: .x, name: "X single image 16:9", width: 1600, height: 900, ratioLabel: "16:9", note: "Single-image posts only, cropped to 20:17 in multi-image posts", safeInsets: nil, previewKind: .xFeedSingle),
        .init(id: "x-square", platform: .x, name: "X single image 1:1", width: 1080, height: 1080, ratioLabel: "1:1", note: "Single-image post", safeInsets: nil, previewKind: .xFeedSingle),
        .init(id: "x-portrait-45", platform: .x, name: "X single image 4:5", width: 1080, height: 1350, ratioLabel: "4:5", note: "Single-image post", safeInsets: nil, previewKind: .xFeedSingle),
        // X, multi-image posts (2–4 images): a swipeable carousel since July–August 2026, tiles capped at 20:17 wide and 3:4 tall.
        .init(id: "x-carousel-wide", platform: .x, name: "X carousel, widest 20:17", width: 1600, height: 1360, ratioLabel: "20:17", note: "Max width before X crops multi-image posts", safeInsets: nil, previewKind: .xCarousel),
        .init(id: "x-carousel-square", platform: .x, name: "X carousel 1:1", width: 1080, height: 1080, ratioLabel: "1:1", note: "Uncropped in multi-image posts", safeInsets: nil, previewKind: .xCarousel),
        .init(id: "x-carousel-45", platform: .x, name: "X carousel 4:5 (safest, matches IG)", width: 1080, height: 1350, ratioLabel: "4:5", note: "Uncropped in multi-image posts and on Instagram", safeInsets: nil, previewKind: .xCarousel),
        .init(id: "x-portrait-34", platform: .x, name: "X portrait 3:4", width: 1080, height: 1440, ratioLabel: "3:4", note: "Tallest shown uncropped on web", safeInsets: nil, previewKind: .xCarousel),
        .init(id: "x-header", platform: .x, name: "X header", width: 1500, height: 500, ratioLabel: "3:1", note: "Top and bottom may crop", safeInsets: .init(top: 0.12, bottom: 0.12, avatarOverlap: true), previewKind: .xHeader),
        .init(id: "x-article", platform: .x, name: "X Article cover", width: 2000, height: 800, ratioLabel: "5:2", note: "", safeInsets: nil, previewKind: .xArticle),
        // Instagram
        .init(id: "ig-feed-45", platform: .instagram, name: "IG feed portrait", width: 1080, height: 1350, ratioLabel: "4:5", note: "Works via scheduling/API", safeInsets: nil, previewKind: .igFeed),
        .init(id: "ig-square", platform: .instagram, name: "IG square", width: 1080, height: 1080, ratioLabel: "1:1", note: "", safeInsets: nil, previewKind: .igFeed),
        .init(id: "ig-grid-34", platform: .instagram, name: "IG profile grid tile", width: 1080, height: 1440, ratioLabel: "3:4", note: "Profile grid crop", safeInsets: nil, previewKind: .igGrid),
        .init(id: "ig-story", platform: .instagram, name: "IG stories / reels", width: 1080, height: 1920, ratioLabel: "9:16", note: "Keep overlay zones clear", safeInsets: .init(top: 0.14, leading: 0.06, bottom: 0.35, trailing: 0.06), previewKind: .igStory),
    ]

    public static func format(id: String) -> MatteFormat? { all.first { $0.id == id } }

    public static func formats(for platform: Platform) -> [MatteFormat] { all.filter { $0.platform == platform } }
}

extension MatteFormat {
    public static func == (lhs: MatteFormat, rhs: MatteFormat) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
