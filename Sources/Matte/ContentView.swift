import AppKit
import MatteCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var dropTargeted = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 4) {
            Sidebar(model: model, dropTargeted: dropTargeted)
                .frame(width: 248)
            MainPanel(model: model, dropTargeted: dropTargeted)
            Inspector(model: model)
                .frame(width: 292)
        }
        .padding(4)
        .background(Theme.shell)
        .ignoresSafeArea(.container, edges: .top)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.brand, lineWidth: 1)
                    .background(Theme.brand.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(4)
                    .ignoresSafeArea(.container, edges: .top)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let toast = model.toast {
                ToastView(text: toast, canReveal: model.lastExportFolder != nil, reveal: { model.revealLastExport() }, dismiss: { model.toast = nil })
                    .padding(20)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Theme.motion, value: dropTargeted)
        .animation(.timingCurve(0, 0, 0.2, 1, duration: 0.2), value: model.toast)
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            let target = model
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { @Sendable url, _ in
                    guard let url else { return }
                    Task { @MainActor in target.add(urls: [url]) }
                }
            }
            return true
        }
        .sheet(item: $model.pendingExport) { plan in
            ExportConfirmSheet(plan: plan, cancel: { model.pendingExport = nil }, confirm: { model.confirmExport() })
        }
        .background(WindowConfigurator())
        .font(Theme.font(13))
        .foregroundStyle(Theme.fg1)
        .onAppear {
            if model.launchOpensSettings {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    openSettings()
                }
            }
        }
    }
}

// MARK: - Main panel

struct MainPanel: View {
    @ObservedObject var model: AppModel
    let dropTargeted: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.line).frame(height: 0.5)
            ZStack {
                switch model.mainTab {
                case .formats:
                    FormatsPanel(model: model, dropTargeted: dropTargeted).transition(.opacity)
                case .simulate:
                    SimulatorView(model: model).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Theme.motion, value: model.mainTab)
            Rectangle().fill(Theme.line).frame(height: 0.5)
            ExportBar(model: model)
        }
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hairline(16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.focusedImage?.name ?? "Matte")
                    .font(Theme.font(20, .semibold))
                    .foregroundStyle(Theme.fg1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(model.focusedImage.map { "Inspecting · \($0.dimensions)" } ?? "Add images to begin")
                    .monoCaption()
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            SegmentedControl(selection: $model.mainTab, options: [(MainTab.formats, "Formats"), (MainTab.simulate, "Simulate")])
                .fixedSize()
        }
        .padding(.horizontal, 24)
        .frame(height: 68)
    }
}

/// Footer: what will be exported and the primary action, or progress with cancel while exporting.
struct ExportBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            if let progress = model.exportProgress {
                Text("Exporting").font(Theme.font(13, .medium)).foregroundStyle(Theme.fg1)
                ProgressBar(value: progress).frame(maxWidth: 260)
                Text(model.exportStatus).monoCaption()
                Spacer(minLength: 8)
                Button("Cancel") { model.cancelExport() }.buttonStyle(MatteButtonStyle(kind: .secondary))
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.selection.count) image\(model.selection.count == 1 ? "" : "s") · \(model.checked.count) format\(model.checked.count == 1 ? "" : "s")")
                        .font(Theme.font(13, .medium)).foregroundStyle(Theme.fg2)
                    Text("To \(model.outputFolder.path.abbreviatingHome) · \(model.exportType == .png ? "PNG" : "JPEG")")
                        .monoCaption().lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let blocker = model.exportBlocker {
                    Badge(text: blocker, kind: .warning, icon: "exclamationmark.triangle.fill")
                        .transition(.opacity)
                }
                Button(model.exportLabel) { model.requestExport() }
                    .buttonStyle(MatteButtonStyle(kind: .primary))
                    .disabled(model.exportBlocker != nil)
            }
        }
        .animation(Theme.motion, value: model.exportBlocker)
        .padding(.horizontal, 24)
        .frame(height: 60)
    }
}

// MARK: - Toast and confirmation

struct ToastView: View {
    let text: String
    let canReveal: Bool
    let reveal: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(text).font(Theme.font(13, .medium)).foregroundStyle(Theme.fg1).lineLimit(2)
            if canReveal { Button("Reveal", action: reveal).buttonStyle(TextLinkButtonStyle()) }
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(IconButtonStyle(size: 24))
        }
        .padding(.leading, 16).padding(.trailing, 8)
        .frame(minHeight: 44)
        .frame(maxWidth: 460)
        .background(Theme.modal, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hairline(12)
        .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
    }
}

struct ExportConfirmSheet: View {
    let plan: ExportPlan
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export \(plan.total) file\(plan.total == 1 ? "" : "s")?")
                .font(Theme.font(15, .medium)).foregroundStyle(Theme.fg1)
            Text("\(plan.images.count) image\(plan.images.count == 1 ? "" : "s") × \(plan.formats.count) format\(plan.formats.count == 1 ? "" : "s") as \(plan.type == .png ? "PNG" : "JPEG")\(plan.usesSubfolders ? ", one folder per image," : ", saved directly") into:")
                .font(Theme.font(13)).foregroundStyle(Theme.fg2)
                .fixedSize(horizontal: false, vertical: true)
            Text(plan.root.path.abbreviatingHome)
                .font(Theme.mono(12)).foregroundStyle(Theme.fg1)
                .lineLimit(2).truncationMode(.middle)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .hairline(8)
            if !plan.existing.isEmpty {
                Badge(text: "\(plan.existing.count) file\(plan.existing.count == 1 ? " already exists" : "s already exist") and will be replaced", kind: .warning, icon: "exclamationmark.triangle.fill")
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(plan.existing.prefix(5), id: \.self) { url in
                        Text(url.pathComponents.suffix(2).joined(separator: "/")).monoCaption().lineLimit(1).truncationMode(.middle)
                    }
                    if plan.existing.count > 5 { Text("and \(plan.existing.count - 5) more").monoCaption() }
                }
            }
            if plan.total > 40 {
                Text("This is a large batch. It runs in the background and you can cancel it at any time.")
                    .font(Theme.font(12)).foregroundStyle(Theme.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(MatteButtonStyle(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
                Button(plan.existing.isEmpty ? "Export \(plan.total) files" : "Replace and export", action: confirm)
                    .buttonStyle(MatteButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18))
        .frame(width: 460)
        .background(Theme.modal)
        .preferredColorScheme(.dark)
    }
}
