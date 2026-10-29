import MatteCore
import SwiftUI

struct FormatsGrid: View {
    @ObservedObject var model: AppModel
    let columns = [GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 12)]

    var body: some View {
        ScrollView {
            if let image = model.focusedImage {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.visibleFormats) { format in
                        FormatCard(
                            format: format,
                            request: RenderRequest(image: image, format: format, options: model.renderOptions(for: format), maxDimension: 440),
                            analysis: Fit.analyze(imageSize: image.pixelSize, format: format, mode: model.renderOptions(for: format).mode),
                            isChecked: model.isChecked(format),
                            isInspected: model.selectedFormatID == format.id,
                            inspect: { model.selectedFormatID = format.id },
                            toggle: { model.toggle(format) }
                        )
                    }
                }.padding(24)
            } else {
                VStack(spacing: 12) {
                    if model.loadingCount > 0 {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 36)).foregroundStyle(Theme.tertiary)
                        Text("Add PNG, JPEG, HEIC, TIFF or WebP images").foregroundStyle(Theme.secondary)
                        Button("Choose images…") { model.chooseImages() }.buttonStyle(PrimaryButtonStyle())
                    }
                }.frame(maxWidth: .infinity, minHeight: 430)
            }
        }
    }
}

/// Click the card to inspect the format; click the checkbox to include it in exports.
private struct FormatCard: View {
    let format: MatteFormat
    let request: RenderRequest
    let analysis: FitAnalysis
    let isChecked: Bool
    let isInspected: Bool
    let inspect: () -> Void
    let toggle: () -> Void

    var body: some View {
        Button(action: inspect) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35))
                    RenderedPreview(request: request).padding(8)
                }.frame(height: 128).clipped()
                HStack(alignment: .top) {
                    Button(action: toggle) { Image(systemName: isChecked ? "checkmark.square.fill" : "square").foregroundStyle(isChecked ? Theme.brand : Theme.tertiary) }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 3) { Text(format.name).fontWeight(.medium).foregroundStyle(Theme.primary).lineLimit(2); Text("\(format.width)×\(format.height) · \(format.ratioLabel)").monoCaption() }
                    Spacer()
                }
                VerdictBadge(analysis: analysis)
            }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(isInspected ? Theme.brand : Theme.line, lineWidth: isInspected ? 1 : 0.5))
        }
        .buttonStyle(.plain)
        .help(format.note)
    }
}

struct VerdictBadge: View {
    let analysis: FitAnalysis
    var body: some View {
        switch analysis.verdict {
        case .perfect: Pill(text: analysis.label, tone: .positive)
        case .needsFrame: Pill(text: analysis.label, tone: .warning)
        case .needsCrop: Pill(text: analysis.label, tone: .danger)
        }
    }
}
