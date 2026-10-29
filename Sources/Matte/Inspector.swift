import MatteCore
import SwiftUI

struct Inspector: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Frame").sectionLabel()
                Picker("Mode", selection: $model.mode) { Text("Fit with frame").tag(RenderMode.fit); Text("Crop to fill").tag(RenderMode.fill) }.pickerStyle(.segmented).labelsHidden()
                HStack { Text("Padding").foregroundStyle(Theme.secondary); Spacer(); Text("\(Int((model.padding * 100).rounded()))%").monoCaption() }
                Slider(value: $model.padding, in: 0...0.3)
                Toggle("Always pad perfect fits", isOn: $model.alwaysPad).toggleStyle(.switch).controlSize(.mini).foregroundStyle(Theme.secondary)
                Divider().overlay(Theme.line)
                ColorControls(model: model)
                Divider().overlay(Theme.line)
                ExportOptionsSection(model: model)
                Divider().overlay(Theme.line)
                Text("Preview in context").sectionLabel()
                ContextPreview(image: model.focusedImage, format: model.selectedFormat, options: model.renderOptions(for: model.selectedFormat))
            }.padding(16)
        }.background(Theme.shell)
    }
}

private struct ContextPreview: View {
    let image: SourceImage?
    let format: MatteFormat
    let options: RenderOptions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Circle().fill(Theme.control).frame(width: 28, height: 28); VStack(alignment: .leading, spacing: 4) { Capsule().fill(Theme.secondary).frame(width: 80, height: 5); Capsule().fill(Theme.tertiary).frame(width: 52, height: 4) }; Spacer() }
            if let image {
                RenderedPreview(request: RenderRequest(image: image, format: format, options: options, maxDimension: 500))
                    .aspectRatio(format.aspectRatio, contentMode: .fit)
                    .overlay {
                        if let safe = format.safeInsets {
                            GeometryReader { proxy in
                                VStack(spacing: 0) { Color.black.opacity(0.38).frame(height: proxy.size.height * safe.top); Spacer(minLength: 0); Color.black.opacity(0.38).frame(height: proxy.size.height * safe.bottom) }
                            }.allowsHitTesting(false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: format.previewKind == .igStory ? 18 : 8))
                    .frame(maxHeight: format.previewKind == .igStory ? 310 : 185)
                    .frame(maxWidth: .infinity)
            } else { RoundedRectangle(cornerRadius: 8).fill(Theme.control).frame(height: 150) }
            HStack { ForEach(["heart", "bubble.left", "arrow.2.squarepath", "square.and.arrow.up"], id: \.self) { Image(systemName: $0).foregroundStyle(Theme.secondary) }; Spacer() }
        }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 0.5))
    }
}
