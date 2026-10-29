import MatteCore
import SwiftUI

/// Collapsible "Export options" in the inspector: file type and quality, scale, file name, colour space, metadata, size cap,
/// and the padding / fit-fill override for the inspected format. Everything edits `model.exportOptions` (also used by Settings).
struct ExportOptionsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { model.exportOptionsExpanded.toggle() } label: {
                HStack(spacing: 6) {
                    Text("Export options").sectionLabel()
                    Image(systemName: model.exportOptionsExpanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tertiary)
                    Spacer()
                    if !model.exportOptionsExpanded { Text(model.exportOptionsSummary).monoCaption().lineLimit(1) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if model.exportOptionsExpanded { options }
        }
    }

    @ViewBuilder private var options: some View {
        let fileType = model.exportOptions.resolvedFileType
        Picker("Type", selection: $model.exportOptions.fileType) {
            ForEach(ExportFileType.availableCases, id: \.self) { Text($0.displayName).tag($0) }
        }.pickerStyle(.segmented).labelsHidden()
        if fileType.isLossy {
            HStack { Text("Quality").foregroundStyle(Theme.secondary); Spacer(); Text("\(Int((model.exportOptions.quality * 100).rounded()))%").monoCaption() }
            Slider(value: $model.exportOptions.quality, in: ExportOptions.minimumCapQuality...1)
        }

        HStack {
            Text("Scale").foregroundStyle(Theme.secondary).lineLimit(1).fixedSize().layoutPriority(1)
            Spacer()
            if model.scaleChoice == .max {
                TextField("2048", value: $model.maxLongEdge, format: .number).fieldStyle().frame(width: 64)
                Text("px").monoCaption()
            }
            Picker("Scale", selection: $model.scaleChoice) { Text("1×").tag(ScaleChoice.x1); Text("2×").tag(ScaleChoice.x2); Text("Max").tag(ScaleChoice.max) }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("File name").foregroundStyle(Theme.secondary)
            TextField(ExportOptions.defaultFilenamePattern, text: $model.exportOptions.filenamePattern).fieldStyle()
            Text(FilenamePattern.tokens.joined(separator: " ")).monoCaption().lineLimit(1).minimumScaleFactor(0.8)
            if let example = exampleFileName { Text(example).monoCaption().lineLimit(1).truncationMode(.middle) }
        }

        HStack {
            Text("Colour space").foregroundStyle(Theme.secondary).lineLimit(1).fixedSize().layoutPriority(1)
            Spacer()
            Picker("Colour space", selection: $model.exportOptions.colorSpace) { Text("sRGB").tag(ExportColorSpace.sRGB); Text("P3").tag(ExportColorSpace.displayP3) }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
        Toggle("Strip metadata", isOn: $model.exportOptions.stripMetadata).toggleStyle(.switch).controlSize(.mini).foregroundStyle(Theme.secondary)
            .help("Off copies EXIF, TIFF and IPTC from the source (never GPS)")

        // Label above: "Off / Platform / Custom" leaves no room beside it in the 300 pt inspector.
        VStack(alignment: .leading, spacing: 6) {
            Text("Max size").foregroundStyle(Theme.secondary).lineLimit(1)
            Picker("Max size", selection: $model.sizeCapChoice) { Text("Off").tag(SizeCapChoice.off); Text("Platform").tag(SizeCapChoice.platform); Text("Custom").tag(SizeCapChoice.custom) }
                .pickerStyle(.segmented).labelsHidden()
        }
        switch model.sizeCapChoice {
        case .off: EmptyView()
        case .platform: Text(Platform.allCases.map { "\($0.rawValue) \($0.recommendedMaxFileSizeBytes / 1_000_000) MB" }.joined(separator: " · ")).monoCaption()
        case .custom:
            HStack {
                TextField("5", value: $model.customMaxSizeMB, format: .number.precision(.fractionLength(0...2))).fieldStyle().frame(width: 64)
                Text("MB").monoCaption()
                Spacer()
            }
        }
        if model.sizeCapChoice != .off {
            if fileType.isLossy {
                Text("Quality is lowered (to \(Int(ExportOptions.minimumCapQuality * 100))% at most) to fit.").font(.system(size: 11)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
            } else {
                Toggle("Write JPEG when PNG is too big", isOn: $model.exportOptions.allowLossyFallback).toggleStyle(.switch).controlSize(.mini).foregroundStyle(Theme.secondary)
            }
        }

        FormatOverrideControls(model: model)
    }

    /// The file the inspected image and format would produce, e.g. `photo__x-carousel-45_1080x1350.png`.
    private var exampleFileName: String? {
        guard let image = model.focusedImage else { return nil }
        let options = model.exportOptions
        let format = model.selectedFormat
        let base = FilenamePattern.expand(options.filenamePattern, name: image.url.deletingPathExtension().lastPathComponent, format: format, pixelSize: options.pixelSize(for: format))
        return "\(base).\(options.resolvedFileType.fileExtension)"
    }
}

/// Padding and fit/fill for the inspected format only, with a reset back to the Frame settings.
private struct FormatOverrideControls: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let format = model.selectedFormat
        let hasOverride = !model.formatOverride(for: format).isEmpty
        HStack {
            Text(format.name).foregroundStyle(Theme.secondary).lineLimit(1).truncationMode(.tail)
            Spacer()
            if hasOverride { Button("Reset") { model.resetOverride(for: format) }.buttonStyle(LinkButtonStyle()) } else { Text("follows Frame").monoCaption() }
        }
        Picker("Mode", selection: $model.inspectedModeOverride) {
            Text("Frame").tag(RenderMode?.none)
            Text("Fit").tag(RenderMode?.some(.fit))
            Text("Fill").tag(RenderMode?.some(.fill))
        }.pickerStyle(.segmented).labelsHidden()
        Toggle("Own padding", isOn: $model.inspectedHasPaddingOverride).toggleStyle(.switch).controlSize(.mini).foregroundStyle(Theme.secondary)
        if model.inspectedHasPaddingOverride {
            HStack { Text("Padding").foregroundStyle(Theme.secondary); Spacer(); Text("\(Int((model.inspectedPadding * 100).rounded()))%").monoCaption() }
            Slider(value: $model.inspectedPadding, in: 0...0.3)
        }
    }
}

private extension View {
    /// The hex field's look: plain, monospaced, on the control fill.
    func fieldStyle() -> some View {
        self.textFieldStyle(.plain).font(.system(size: 12, design: .monospaced)).padding(8).background(Theme.control, in: RoundedRectangle(cornerRadius: 8))
    }
}
