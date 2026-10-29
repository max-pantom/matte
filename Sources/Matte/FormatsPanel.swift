import MatteCore
import SwiftUI

struct FormatsPanel: View {
    @ObservedObject var model: AppModel
    let dropTargeted: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if model.images.isEmpty {
                    DropZone(title: "Drop images or click to choose", subtitle: "PNG, JPEG, HEIC, TIFF or WebP · folders work too", minHeight: 240, iconSize: 40, isTargeted: dropTargeted) { model.chooseImages() }
                }
                ForEach(Platform.allCases, id: \.self) { platform in
                    PlatformSection(model: model, platform: platform)
                }
            }
            .padding(24)
        }
        .scrollIndicators(.automatic)
    }
}

private struct PlatformSection: View {
    @ObservedObject var model: AppModel
    let platform: Platform
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12)]

    var body: some View {
        let formats = MatteFormat.formats(for: platform)
        let checkedCount = formats.filter { model.isChecked($0) }.count
        let image = model.focusedImage
        let options = model.renderOptions
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(platform.rawValue).font(Theme.font(15, .medium)).foregroundStyle(Theme.fg1)
                Text("\(checkedCount) of \(formats.count)").monoCaption()
                Spacer()
                Button("All") { model.setPlatform(platform, checked: true) }
                    .buttonStyle(MatteButtonStyle(kind: .ghost, height: 24))
                    .disabled(checkedCount == formats.count)
                Button("None") { model.setPlatform(platform, checked: false) }
                    .buttonStyle(MatteButtonStyle(kind: .ghost, height: 24))
                    .disabled(checkedCount == 0)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(formats) { format in
                    FormatCard(
                        format: format,
                        image: image,
                        request: image.map { RenderRequest(image: $0, format: format, options: options, maxDimension: 440) },
                        mode: model.mode,
                        isChecked: model.isChecked(format),
                        isInspected: model.selectedFormatID == format.id
                    ) { model.toggle(format) }
                }
            }
        }
    }
}

struct FormatCard: View {
    let format: MatteFormat
    let image: SourceImage?
    let request: RenderRequest?
    let mode: RenderMode
    let isChecked: Bool
    let isInspected: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.sunken)
                    if request != nil {
                        RenderedPreview(request: request)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .padding(10)
                    } else {
                        RatioSilhouette(ratio: format.aspectRatio, label: format.ratioLabel).padding(16)
                    }
                }
                .frame(height: 132)
                .hairline(8)

                HStack(alignment: .top, spacing: 8) {
                    Checkbox(isOn: isChecked).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(format.name)
                            .font(Theme.font(13, .medium))
                            .foregroundStyle(Theme.fg1)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(format.width)×\(format.height) · \(format.ratioLabel)").monoCaption()
                    }
                    Spacer(minLength: 0)
                }
                if !format.note.isEmpty {
                    Text(format.note)
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.fg3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let image {
                    VerdictBadge(analysis: Fit.analyze(imageSize: image.pixelSize, format: format, mode: mode))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(isChecked ? Theme.brand.opacity(hovering ? 0.12 : 0.08) : hovering ? Theme.cardStrong : Theme.cardSubtle,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isChecked ? Theme.brand : isInspected ? Theme.lineStrong : Theme.line, lineWidth: isChecked ? 1 : 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.motion, value: hovering)
        .animation(Theme.motion, value: isChecked)
    }
}

/// Placeholder for a format's shape when no image is loaded.
private struct RatioSilhouette: View {
    let ratio: Double
    let label: String

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .aspectRatio(ratio, contentMode: .fit)
            .overlay(Text(label).monoCaption())
    }
}

struct VerdictBadge: View {
    let analysis: FitAnalysis

    var body: some View {
        switch analysis.verdict {
        case .perfect: Badge(text: analysis.label, kind: .positive)
        case .needsFrame: Badge(text: analysis.label, kind: .warning)
        case .needsCrop: Badge(text: analysis.label, kind: .danger)
        }
    }
}
