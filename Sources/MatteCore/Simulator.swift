import Foundation

/// Crop maths for how X and Instagram display posted images. Ratios are width / height.
public enum Simulator {
    /// Fraction (0...1) of the source image's area hidden when it is aspect-filled and centre-cropped into a frame of `display` ratio.
    public static func cropLoss(source: Double, display: Double) -> Double {
        guard source > 0, display > 0 else { return 0 }
        return source > display ? 1 - display / source : 1 - source / display
    }

    static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double { min(upper, max(lower, value)) }

    /// One row of `matte-cli --simulate`, for the image at `index` among `ratios`.
    public struct Row: Sendable {
        public let index: Int
        public let sourceRatio: Double
        public let xCarouselRatio: Double
        public let xSingleRatio: Double
        public let igCarouselRatio: Double
        public let igGridRatio: Double

        public var xCarouselLoss: Double { Simulator.cropLoss(source: sourceRatio, display: xCarouselRatio) }
        public var xSingleLoss: Double { Simulator.cropLoss(source: sourceRatio, display: xSingleRatio) }
        public var igCarouselLoss: Double { Simulator.cropLoss(source: sourceRatio, display: igCarouselRatio) }
        public var igGridLoss: Double { Simulator.cropLoss(source: sourceRatio, display: igGridRatio) }
    }

    /// Simulates posting `ratios` in order: X splits into posts of four, Instagram crops every slide to the first image's ratio.
    public static func simulate(ratios: [Double]) -> [Row] {
        let posts = XCarousel.posts(Array(ratios.indices))
        var postSize = [Int: Int]()
        for post in posts { for index in post { postSize[index] = post.count } }
        let igSlide = ratios.first.map { IGCarousel.slideRatio(firstImageRatio: $0) } ?? 1
        return ratios.enumerated().map { index, ratio in
            Row(index: index, sourceRatio: ratio,
                xCarouselRatio: XCarousel.tileRatio(for: ratio, count: postSize[index] ?? ratios.count),
                xSingleRatio: XSingle.displayRatio(for: ratio),
                igCarouselRatio: igSlide,
                igGridRatio: IGGrid.tileRatio)
        }
    }
}

/// A post with one image: X shows ratios from 3:4 (tall) to 2:1 (wide) uncropped.
public enum XSingle {
    public static let minRatio = 0.75
    public static let maxRatio = 2.0

    public static func displayRatio(for ratio: Double) -> Double { Simulator.clamp(ratio, minRatio, maxRatio) }
}

/// A post with 2–4 images: since July 2026 (iOS) and August 2026 (web, Android) a horizontal, fixed-height carousel.
/// Each tile is cropped to at most 20:17 wide and at least 3:4 tall (web).
public enum XCarousel {
    public static let maxTileRatio = 20.0 / 17.0
    public static let minTileRatio = 0.75
    public static let maxImagesPerPost = 4

    /// Displayed tile ratio for an image of `ratio` in a post of `count` images. One image uses the single-image rule.
    public static func tileRatio(for ratio: Double, count: Int) -> Double {
        if count <= 1 { return XSingle.displayRatio(for: ratio) }
        return Simulator.clamp(ratio, minTileRatio, maxTileRatio)
    }

    /// Splits items into consecutive posts of at most four.
    public static func posts<T>(_ items: [T]) -> [[T]] {
        stride(from: 0, to: items.count, by: maxImagesPerPost).map { Array(items[$0..<min($0 + maxImagesPerPost, items.count)]) }
    }
}

/// Instagram carousel: every slide is cropped to the first image's ratio, clamped to 4:5...1.91:1. Up to 20 slides.
public enum IGCarousel {
    public static let minRatio = 0.8
    public static let maxRatio = 1.91
    public static let maxSlides = 20

    public static func slideRatio(firstImageRatio: Double) -> Double { Simulator.clamp(firstImageRatio, minRatio, maxRatio) }
}

/// Instagram profile grid: 3 columns of 3:4 tiles.
public enum IGGrid {
    public static let tileRatio = 0.75
    public static let columns = 3
}
