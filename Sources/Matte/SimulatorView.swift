import MatteCore
import SwiftUI

/// What a simulated tile shows: the original image, or Matte's export for a chosen format.
struct SimContext {
    let useExport: Bool
    let format: MatteFormat
    let options: RenderOptions

    func ratio(of image: SourceImage) -> Double { useExport ? format.aspectRatio : image.ratio }

    func request(for image: SourceImage) -> RenderRequest? {
        useExport ? RenderRequest(image: image, format: format, options: options, maxDimension: 800) : nil
    }
}

struct SimulatorView: View {
    @ObservedObject var model: AppModel

    private var xFormats: [MatteFormat] { MatteFormat.formats(for: .x).filter { $0.previewKind.isPostImage } }
    private var igFormats: [MatteFormat] { MatteFormat.formats(for: .instagram).filter { $0.previewKind.isPostImage } }

    private var activeFormat: MatteFormat {
        let id = model.simKind == .xPost ? model.simXFormatID : model.simIGFormatID
        let fallback = model.simKind == .xPost ? xFormats[0] : igFormats[0]
        return MatteFormat.format(id: id) ?? fallback
    }

    var body: some View {
        let images = model.selectedImagesInSelectionOrder
        let context = SimContext(useExport: model.simSource == .export, format: activeFormat, options: model.renderOptions)
        VStack(spacing: 0) {
            controls
            Rectangle().fill(Theme.line).frame(height: 0.5)
            if images.isEmpty {
                emptyState
            } else {
                ScrollView([.vertical]) {
                    Group {
                        switch model.simKind {
                        case .xPost: XPostsSimulation(images: images, context: context)
                        case .igCarousel: IGCarouselSimulation(images: images, context: context)
                        case .igGrid: IGGridSimulation(images: images, context: context)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                SegmentedControl(selection: $model.simKind, options: [(SimKind.xPost, "X post"), (SimKind.igCarousel, "IG carousel"), (SimKind.igGrid, "IG grid")])
                    .fixedSize()
                Spacer(minLength: 8)
                SegmentedControl(selection: $model.simSource, options: [(SimSource.original, "Original"), (SimSource.export, "Matte export")])
                    .fixedSize()
            }
            if model.simSource == .export {
                HStack(spacing: 8) {
                    Text("Rendered as").font(Theme.font(12)).foregroundStyle(Theme.fg3)
                    Menu {
                        ForEach(model.simKind == .xPost ? xFormats : igFormats) { format in
                            Button("\(format.name) · \(format.width)×\(format.height)") {
                                if format.platform == .x { model.simXFormatID = format.id } else { model.simIGFormatID = format.id }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(activeFormat.name).font(Theme.font(12, .medium))
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Theme.fg1)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Theme.component, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .hairline(6)
                    Text("with your current frame settings").font(Theme.font(12)).foregroundStyle(Theme.fg3).lineLimit(1)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .animation(Theme.motion, value: model.simSource)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.angled").font(.system(size: 34, weight: .light)).foregroundStyle(Theme.fg3)
            Text(model.images.isEmpty ? "Add images, then select the ones you want to post" : "Select images in the sidebar to simulate a post")
                .font(Theme.font(15, .medium)).foregroundStyle(Theme.fg1)
            Text("They appear in the order you select them, just like attaching them to a post.")
                .font(Theme.font(12)).foregroundStyle(Theme.fg3)
            if model.images.isEmpty {
                Button("Choose images…") { model.chooseImages() }.buttonStyle(MatteButtonStyle(kind: .primary))
            } else {
                Button("Select all images") { model.selectAllImages() }.buttonStyle(MatteButtonStyle(kind: .secondary))
            }
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tiles

struct SimTile: View {
    let image: SourceImage
    let context: SimContext
    let size: CGSize
    let displayRatio: Double
    var cornerRadius: CGFloat = 12

    var body: some View {
        let loss = Simulator.cropLoss(source: context.ratio(of: image), display: displayRatio)
        ZStack(alignment: .topLeading) {
            Group {
                if let request = context.request(for: image) {
                    RenderedPreview(request: request, contentMode: .fill)
                } else {
                    Image(decorative: image.preview.cgImage, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            CropBadge(loss: loss).padding(8)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .hairline(cornerRadius)
        .help("\(image.name): shown at \(String(format: "%.3f", displayRatio)):1")
    }
}

struct CropBadge: View {
    let loss: Double

    var body: some View {
        let percent = Int((loss * 100).rounded())
        HStack(spacing: 4) {
            Circle().fill(percent == 0 ? Theme.positive : Theme.warning).frame(width: 6, height: 6)
            Text(percent == 0 ? "full" : "cropped \(percent)%")
        }
        .font(Theme.font(11, .medium))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Color.black.opacity(0.68), in: Capsule())
    }
}

private struct SimNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.font(12))
            .foregroundStyle(Theme.fg2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 520, alignment: .leading)
    }
}

private struct Avatar: View {
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(red: 0.97, green: 0.42, blue: 0.08), Color(red: 0.45, green: 0.18, blue: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Text("M").font(Theme.font(size * 0.42, .semibold)).foregroundStyle(Color.white))
            .frame(width: size, height: size)
    }
}

// MARK: - X

private struct XPostsSimulation: View {
    let images: [SourceImage]
    let context: SimContext

    var body: some View {
        let posts = XCarousel.posts(images)
        VStack(alignment: .leading, spacing: 16) {
            SimNote(text: "X web and iOS: 2–4 images scroll sideways at a fixed height, the next one peeking. Each tile is cropped to between 3:4 and 20:17. A single image is shown uncropped from 3:4 to 2:1.")
            ForEach(posts.indices, id: \.self) { index in
                if index == 1 {
                    Badge(text: "X allows 4 images per post — images 5+ go in another post", kind: .danger, icon: "exclamationmark.octagon.fill")
                }
                if posts.count > 1 {
                    Text("Post \(index + 1) of \(posts.count)").sectionLabel()
                }
                XPostMock(images: posts[index], context: context)
            }
        }
    }
}

private struct XPostMock: View {
    let images: [SourceImage]
    let context: SimContext
    private let contentWidth: CGFloat = 400
    private let carouselHeight: CGFloat = 280
    private let singleMaxHeight: CGFloat = 440

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    Text("Matte").font(Theme.font(15, .semibold)).foregroundStyle(Theme.fg1)
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 12)).foregroundStyle(Theme.brand)
                    Text("@matteapp · 2m").font(Theme.font(15)).foregroundStyle(Theme.fg3)
                }
                Text(images.count == 1 ? "New piece, framed for the feed." : "\(images.count) new pieces, swipe →")
                    .font(Theme.font(15)).foregroundStyle(Theme.fg1)
                media
                HStack {
                    ForEach(["bubble.left", "arrow.2.squarepath", "heart", "chart.bar", "square.and.arrow.up"], id: \.self) { icon in
                        Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Theme.fg3)
                        if icon != "square.and.arrow.up" { Spacer() }
                    }
                }
                .frame(width: contentWidth)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hairline(16, color: Theme.lineStrong)
    }

    @ViewBuilder private var media: some View {
        if images.count == 1, let image = images.first {
            let ratio = XCarousel.tileRatio(for: context.ratio(of: image), count: 1)
            let width = min(contentWidth, singleMaxHeight * ratio)
            SimTile(image: image, context: context, size: CGSize(width: width, height: width / ratio), displayRatio: ratio, cornerRadius: 16)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(images) { image in
                        let ratio = XCarousel.tileRatio(for: context.ratio(of: image), count: images.count)
                        SimTile(image: image, context: context, size: CGSize(width: carouselHeight * ratio, height: carouselHeight), displayRatio: ratio, cornerRadius: 12)
                    }
                }
            }
            .frame(width: contentWidth, height: carouselHeight)
        }
    }
}

// MARK: - Instagram carousel

private struct IGCarouselSimulation: View {
    let images: [SourceImage]
    let context: SimContext
    @State private var page = 0
    private let width: CGFloat = 360

    var body: some View {
        let slides = Array(images.prefix(IGCarousel.maxSlides))
        let ratio = IGCarousel.slideRatio(firstImageRatio: context.ratio(of: slides[0]))
        let height = width / ratio
        let current = min(page, slides.count - 1)
        VStack(alignment: .leading, spacing: 16) {
            SimNote(text: "Instagram crops every slide to the first image's ratio, clamped to 4:5…1.91:1. This carousel uses \(String(format: "%.2f", ratio)):1. Up to \(IGCarousel.maxSlides) slides.")
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Avatar(size: 30)
                    Text("matteapp").font(Theme.font(13, .semibold)).foregroundStyle(Theme.fg1)
                    Spacer()
                    Image(systemName: "ellipsis").foregroundStyle(Theme.fg2)
                }
                .padding(.horizontal, 12)
                .frame(height: 50)

                ZStack {
                    HStack(spacing: 0) {
                        ForEach(slides) { image in
                            SimTile(image: image, context: context, size: CGSize(width: width, height: height), displayRatio: ratio, cornerRadius: 0)
                        }
                    }
                    .offset(x: -CGFloat(current) * width)
                    .frame(width: width, height: height, alignment: .leading)
                    .clipped()
                    .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.3), value: current)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 12).onEnded { gesture in
                            if gesture.translation.width < -40 { page = min(current + 1, slides.count - 1) }
                            if gesture.translation.width > 40 { page = max(current - 1, 0) }
                        }
                    )

                    HStack {
                        if current > 0 { arrow("chevron.left") { page = current - 1 } }
                        Spacer()
                        if current < slides.count - 1 { arrow("chevron.right") { page = current + 1 } }
                    }
                    .padding(.horizontal, 10)

                    VStack {
                        HStack {
                            Spacer()
                            Text("\(current + 1)/\(slides.count)")
                                .font(Theme.font(12, .medium)).foregroundStyle(Color.white)
                                .padding(.horizontal, 8).frame(height: 22)
                                .background(Color.black.opacity(0.6), in: Capsule())
                        }
                        Spacer()
                    }
                    .padding(10)
                }
                .frame(width: width, height: height)

                HStack(spacing: 14) {
                    Image(systemName: "heart")
                    Image(systemName: "bubble.right")
                    Image(systemName: "paperplane")
                    Spacer()
                    Image(systemName: "bookmark")
                }
                .font(.system(size: 16))
                .foregroundStyle(Theme.fg1)
                .overlay {
                    HStack(spacing: 4) {
                        ForEach(0..<slides.count, id: \.self) { index in
                            Circle().fill(index == current ? Theme.brand : Theme.fg3).frame(width: 6, height: 6)
                        }
                    }
                    .animation(Theme.motion, value: current)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)

                Text("**matteapp** \(slides.count) slide\(slides.count == 1 ? "" : "s"), cropped to the first image")
                    .font(Theme.font(13)).foregroundStyle(Theme.fg1)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
            }
            .frame(width: width)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .hairline(20, color: Theme.lineStrong)

            if images.count > IGCarousel.maxSlides {
                Badge(text: "Instagram allows \(IGCarousel.maxSlides) slides — images \(IGCarousel.maxSlides + 1)+ need another post", kind: .danger, icon: "exclamationmark.octagon.fill")
            }
        }
        .onChange(of: images.map(\.id)) { _, _ in page = 0 }
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.8))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.85), in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Instagram profile grid

private struct IGGridSimulation: View {
    let images: [SourceImage]
    let context: SimContext
    private let tileWidth: CGFloat = 126

    var body: some View {
        let items = Array(images.reversed())
        let tileHeight = tileWidth / IGGrid.tileRatio
        VStack(alignment: .leading, spacing: 16) {
            SimNote(text: "Instagram profile grids show every post as a 3:4 tile, centre-cropped. Most recent first (the last image you selected is top-left).")
            VStack(spacing: 0) {
                HStack(spacing: 20) {
                    Avatar(size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("matteapp").font(Theme.font(15, .semibold)).foregroundStyle(Theme.fg1)
                        HStack(spacing: 16) {
                            stat("\(items.count)", "posts")
                            stat("1,204", "followers")
                            stat("180", "following")
                        }
                    }
                    Spacer()
                }
                .padding(16)
                HStack {
                    Spacer()
                    Image(systemName: "squareshape.split.3x3").foregroundStyle(Theme.fg1)
                    Spacer()
                    Image(systemName: "play.rectangle").foregroundStyle(Theme.fg3)
                    Spacer()
                    Image(systemName: "person.crop.square").foregroundStyle(Theme.fg3)
                    Spacer()
                }
                .font(.system(size: 15))
                .frame(height: 40)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: 2), count: IGGrid.columns), spacing: 2) {
                    ForEach(items) { image in
                        SimTile(image: image, context: context, size: CGSize(width: tileWidth, height: tileHeight), displayRatio: IGGrid.tileRatio, cornerRadius: 0)
                    }
                }
            }
            .frame(width: tileWidth * CGFloat(IGGrid.columns) + 4)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .hairline(20, color: Theme.lineStrong)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(Theme.font(13, .semibold)).foregroundStyle(Theme.fg1)
            Text(label).font(Theme.font(11)).foregroundStyle(Theme.fg3)
        }
    }
}
