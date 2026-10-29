import MatteCore
import SwiftUI

struct Inspector: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Color.clear.frame(height: 12)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Frame").sectionLabel()
                    SegmentedControl(selection: $model.mode, options: [(RenderMode.fit, "Fit with frame"), (RenderMode.fill, "Crop to fill")], fillWidth: true)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Padding").font(Theme.font(13, .medium)).foregroundStyle(model.mode == .fit ? Theme.fg2 : Theme.fgDisabled)
                            Spacer()
                            Text("\(Int((model.padding * 100).rounded()))%").font(Theme.mono(12)).foregroundStyle(Theme.fg1)
                                .contentTransition(.numericText())
                        }
                        MatteSlider(value: $model.padding, range: 0...0.3, step: 0.01)
                            .disabled(model.mode == .fill)
                            .opacity(model.mode == .fit ? 1 : 0.4)
                    }
                }
                divider
                ColorControls(model: model)
                divider
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Preview in context").sectionLabel()
                        Spacer()
                        Text(model.selectedFormat.ratioLabel).monoCaption()
                    }
                    Text(model.selectedFormat.name).font(Theme.font(12)).foregroundStyle(Theme.fg2).lineLimit(1)
                    ContextPreview(image: model.focusedImage, format: model.selectedFormat, options: model.renderOptions)
                }
                divider
                VStack(alignment: .leading, spacing: 8) {
                    Text("Output").sectionLabel()
                    Text(model.outputFolder.path.abbreviatingHome)
                        .font(Theme.mono(11)).foregroundStyle(Theme.fg2)
                        .lineLimit(2).truncationMode(.middle)
                    HStack(spacing: 12) {
                        SettingsLink { Text("Change in Settings") }.buttonStyle(TextLinkButtonStyle())
                        if model.lastExportFolder != nil { Button("Reveal last export") { model.revealLastExport() }.buttonStyle(TextLinkButtonStyle()) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
        .background(Theme.shell)
    }

    private var divider: some View { Rectangle().fill(Theme.line).frame(height: 0.5) }
}

/// The inspected format in a minimal feed mock, with safe-zone shading.
struct ContextPreview: View {
    let image: SourceImage?
    let format: MatteFormat
    let options: RenderOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Theme.component).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(Theme.fg2).frame(width: 80, height: 5)
                    Capsule().fill(Theme.fg3).frame(width: 52, height: 4)
                }
                Spacer()
            }
            if let image {
                RenderedPreview(request: RenderRequest(image: image, format: format, options: options, maxDimension: 600))
                    .aspectRatio(format.aspectRatio, contentMode: .fit)
                    .overlay {
                        if let safe = format.safeInsets {
                            GeometryReader { proxy in
                                VStack(spacing: 0) {
                                    Color.black.opacity(0.4).frame(height: proxy.size.height * safe.top)
                                    Spacer(minLength: 0)
                                    Color.black.opacity(0.4).frame(height: proxy.size.height * safe.bottom)
                                }
                            }
                            .allowsHitTesting(false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: format.previewKind == .igStory ? 14 : 8, style: .continuous))
                    .frame(maxHeight: format.previewKind == .igStory ? 300 : 200)
                    .frame(maxWidth: .infinity)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.component)
                    .aspectRatio(format.aspectRatio, contentMode: .fit)
                    .frame(maxHeight: 160)
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 18) {
                ForEach(["bubble.left", "arrow.2.squarepath", "heart", "square.and.arrow.up"], id: \.self) {
                    Image(systemName: $0).font(.system(size: 12)).foregroundStyle(Theme.fg3)
                }
                Spacer()
            }
        }
        .padding(12)
        .card(12)
    }
}
