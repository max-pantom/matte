import AppKit
import MatteCore
import SwiftUI

/// Settings (⌘,): default file type and quality, output folder and the watched folder, in the same plain style as the inspector.
/// File type and quality are the same `exportOptions` the inspector's Export options edit.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export").sectionLabel()
            Picker("Type", selection: $model.exportOptions.fileType) {
                ForEach(ExportFileType.availableCases, id: \.self) { Text($0.displayName).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().fixedSize()
            if model.exportOptions.resolvedFileType.isLossy {
                HStack { Text("Quality").foregroundStyle(Theme.secondary); Spacer(); Text("\(Int((model.exportOptions.quality * 100).rounded()))%").monoCaption() }
                Slider(value: $model.exportOptions.quality, in: ExportOptions.minimumCapQuality...1)
            }
            Text(model.outputFolder.path.abbreviatingHome).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.tertiary).lineLimit(2)
            HStack {
                Button("Choose folder…") { model.chooseOutputFolder() }.buttonStyle(SecondaryButtonStyle())
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([model.outputFolder]) }.buttonStyle(LinkButtonStyle())
                    .disabled(!FileManager.default.fileExists(atPath: model.outputFolder.path))
            }
            Text("A single file (1 image × 1 format) is saved directly in this folder; larger exports get one subfolder per image.").font(.system(size: 11)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
            Divider().overlay(Theme.line)
            Text("Watched folder").sectionLabel()
            Toggle("Watch for new images", isOn: $model.watching).toggleStyle(.switch).controlSize(.mini).foregroundStyle(Theme.secondary)
            Text(model.watchedFolder?.path.abbreviatingHome ?? "No folder selected").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.tertiary).lineLimit(2)
            HStack {
                Button("Choose folder…") { model.chooseWatchedFolder() }.buttonStyle(SecondaryButtonStyle())
                Spacer()
                let status = model.watchStatus
                Text(status.tone == .positive ? "\(status.text) · \(model.watchedExportCount) exported" : status.text).font(.system(size: 11)).foregroundStyle(status.tone.text).lineLimit(1)
            }
            if let message = model.watchMessage { Text(message).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(2) }
            Text("New images in the folder are exported into a “Matte” folder inside it, with the formats checked in the main window and the current frame, colour and export options (existing files are replaced): directly when that is one file, otherwise one folder per image.")
                .font(.system(size: 11)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13))
        .padding(20)
        .frame(width: 440, alignment: .leading)
        .background(Theme.panel)
    }
}
