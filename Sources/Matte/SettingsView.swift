import AppKit
import MatteCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            WatchedFolderSettings(model: model)
                .tabItem { Label("Watched folder", systemImage: "folder.badge.gearshape") }
        }
        .frame(width: 540)
        .font(Theme.font(13))
        .foregroundStyle(Theme.fg1)
    }
}

/// Hairline card holding one settings group.
private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.font(13, .medium)).foregroundStyle(Theme.fg1)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(12)
    }
}

private struct PathWell: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.mono(12))
            .foregroundStyle(Theme.fg2)
            .lineLimit(2)
            .truncationMode(.middle)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .hairline(8)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(title: "Default output folder") {
                PathWell(text: model.outputFolder.path.abbreviatingHome)
                HStack(spacing: 8) {
                    Button("Choose…") { model.chooseOutputFolder() }.buttonStyle(MatteButtonStyle(kind: .secondary))
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([model.outputFolder]) }
                        .buttonStyle(MatteButtonStyle(kind: .ghost))
                        .disabled(!FileManager.default.fileExists(atPath: model.outputFolder.path))
                }
                Text("A single file is saved directly here; multi-file exports get one subfolder per image.").font(Theme.font(12)).foregroundStyle(Theme.fg3)
            }
            SettingsCard(title: "File type") {
                SegmentedControl(selection: $model.exportType, options: [(ExportType.png, "PNG"), (ExportType.jpeg, "JPEG")])
                    .fixedSize()
                if model.exportType == .jpeg {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Quality").font(Theme.font(13, .medium)).foregroundStyle(Theme.fg2)
                            Spacer()
                            Text("\(Int((model.jpegQuality * 100).rounded()))%").font(Theme.mono(12)).foregroundStyle(Theme.fg1)
                        }
                        MatteSlider(value: $model.jpegQuality, range: 0.5...1, step: 0.01)
                    }
                    .transition(.opacity)
                } else {
                    Text("Lossless. Best for flat colour and type.").font(Theme.font(12)).foregroundStyle(Theme.fg3)
                }
            }
            SettingsCard(title: "Padding") {
                MatteSwitch(title: "Always pad perfect fits", isOn: $model.alwaysPad,
                            subtitle: "Adds the frame even when an image already matches a format's ratio.")
            }
        }
        .padding(20)
        .animation(Theme.motion, value: model.exportType)
        .background(Theme.panel)
    }
}

private struct WatchedFolderSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let status = model.watchStatus
        let formats = model.checkedFormats
        VStack(alignment: .leading, spacing: 12) {
            SettingsCard(title: "Folder") {
                PathWell(text: model.watchedFolder?.path.abbreviatingHome ?? "No folder chosen")
                HStack(spacing: 8) {
                    Button("Choose…") { model.chooseWatchedFolder() }.buttonStyle(MatteButtonStyle(kind: .secondary))
                    Spacer()
                    Badge(text: status.text, kind: status.kind)
                }
                MatteSwitch(title: "Watch for new images", isOn: $model.watching)
                    .disabled(model.watchedFolder == nil)
                    .opacity(model.watchedFolder == nil ? 0.5 : 1)
                HStack(spacing: 6) {
                    Text("Exported this session").font(Theme.font(12)).foregroundStyle(Theme.fg3)
                    Text("\(model.watchedExportCount) image\(model.watchedExportCount == 1 ? "" : "s")").font(Theme.mono(12)).foregroundStyle(Theme.fg1)
                }
                if let message = model.watchMessage {
                    Text(message).font(Theme.font(12)).foregroundStyle(Theme.fg3).lineLimit(2)
                }
            }
            SettingsCard(title: "Formats to auto-export") {
                if formats.isEmpty {
                    Badge(text: "None checked. Pick formats in the main window.", kind: .warning, icon: "exclamationmark.triangle.fill")
                } else {
                    Text(formats.map(\.name).joined(separator: " · "))
                        .font(Theme.font(12)).foregroundStyle(Theme.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Uses the formats currently checked in the main window, with the current frame, colour and file type.")
                    .font(Theme.font(12)).foregroundStyle(Theme.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("New images that appear in the folder are exported to a “Matte” subfolder inside it once their size stops changing (directly into “Matte” when that is one file, otherwise one folder per image). Files already in the folder are left alone.")
                .font(Theme.font(12)).foregroundStyle(Theme.fg3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .padding(20)
        .background(Theme.panel)
    }
}
