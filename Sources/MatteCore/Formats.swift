import CoreGraphics

public enum Platform: String, Codable, CaseIterable, Sendable {
    case x = "X"
    case instagram = "Instagram"
}

public enum PreviewKind: String, Codable, Sendable {
    case xFeedSingle, xGrid2, xGrid3Lead, xGrid3Side, xGrid4, xHeader, xArticle
    case igFeed, igGrid, igStory
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
        .init(id: "x-landscape", platform: .x, name: "X post, landscape 16:9", width: 1600, height: 900, ratioLabel: "16:9", note: "Single image, shown in full", safeInsets: nil, previewKind: .xFeedSingle),
        .init(id: "x-square", platform: .x, name: "X post, square 1:1", width: 1080, height: 1080, ratioLabel: "1:1", note: "", safeInsets: nil, previewKind: .xFeedSingle),
        .init(id: "x-portrait-45", platform: .x, name: "X post, portrait 4:5", width: 1080, height: 1350, ratioLabel: "4:5", note: "", safeInsets: nil, previewKind: .xFeedSingle),
        .init(id: "x-portrait-34", platform: .x, name: "X post, portrait 3:4", width: 1080, height: 1440, ratioLabel: "3:4", note: "Tallest ratio X shows uncropped", safeInsets: nil, previewKind: .xFeedSingle),
        .init(id: "x-grid-2", platform: .x, name: "X 2-image grid tile", width: 700, height: 800, ratioLabel: "7:8", note: "Each side-by-side tile", safeInsets: nil, previewKind: .xGrid2),
        .init(id: "x-grid-3-lead", platform: .x, name: "X 3-image grid, lead tile", width: 700, height: 800, ratioLabel: "7:8", note: "Left large tile", safeInsets: nil, previewKind: .xGrid3Lead),
        .init(id: "x-grid-3-side", platform: .x, name: "X 3-image grid, side tile", width: 1200, height: 675, ratioLabel: "16:9", note: "Two stacked right tiles", safeInsets: nil, previewKind: .xGrid3Side),
        .init(id: "x-grid-4", platform: .x, name: "X 4-image grid tile", width: 1200, height: 675, ratioLabel: "16:9", note: "2×2 grid", safeInsets: nil, previewKind: .xGrid4),
        .init(id: "x-header", platform: .x, name: "X header", width: 1500, height: 500, ratioLabel: "3:1", note: "Top and bottom may crop", safeInsets: .init(top: 0.12, bottom: 0.12, avatarOverlap: true), previewKind: .xHeader),
        .init(id: "x-article", platform: .x, name: "X Article cover", width: 2000, height: 800, ratioLabel: "5:2", note: "", safeInsets: nil, previewKind: .xArticle),
        .init(id: "ig-feed-45", platform: .instagram, name: "IG feed portrait", width: 1080, height: 1350, ratioLabel: "4:5", note: "Works via scheduling/API", safeInsets: nil, previewKind: .igFeed),
        .init(id: "ig-square", platform: .instagram, name: "IG square", width: 1080, height: 1080, ratioLabel: "1:1", note: "", safeInsets: nil, previewKind: .igFeed),
        .init(id: "ig-grid-34", platform: .instagram, name: "IG profile grid tile", width: 1080, height: 1440, ratioLabel: "3:4", note: "Profile grid crop", safeInsets: nil, previewKind: .igGrid),
        .init(id: "ig-story", platform: .instagram, name: "IG stories / reels", width: 1080, height: 1920, ratioLabel: "9:16", note: "Keep overlay zones clear", safeInsets: .init(top: 0.14, leading: 0.06, bottom: 0.35, trailing: 0.06), previewKind: .igStory),
    ]
}

extension MatteFormat {
    public static func == (lhs: MatteFormat, rhs: MatteFormat) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
