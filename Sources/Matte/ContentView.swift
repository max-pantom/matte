import AppKit
import MatteCore
import SwiftUI
import UniformTypeIdentifiers

private enum Theme {
    static let shell = Color.black
    static let panel = Color(red: 0.067, green: 0.067, blue: 0.067)
    static let card = Color.white.opacity(0.035)
    static let control = Color.white.opacity(0.07)
    static let line = Color.white.opacity(0.07)
    static let primary = Color.white.opacity(0.93)
    static let secondary = Color.white.opacity(0.69)
    static let tertiary = Color.white.opacity(0.39)
    static let brand = Color(red: 0, green: 0.565, blue: 1)
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var dropTarget = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 4) {
                Sidebar(model: model).frame(width: 256)
                MainPanel(model: model)
                Inspector(model: model).frame(width: 300)
            }
            .padding(4)
            .background(Theme.shell)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTarget) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in model.add(urls: [url]) }
                    }
                }
                return true
            }
            if dropTarget {
                RoundedRectangle(cornerRadius: 16).stroke(Theme.brand, lineWidth: 2).background(Theme.brand.opacity(0.08)).padding(8).allowsHitTesting(false)
            }
            if let toast = model.toast {
                HStack(spacing: 12) {
                    Text(toast).foregroundStyle(Theme.primary)
                    if model.lastExportFolder != nil { Button("Reveal") { model.reveal() }.buttonStyle(LinkButtonStyle()) }
                    Button { model.toast = nil } label: { Image(systemName: "xmark") }.buttonStyle(IconButtonStyle())
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.leading, 16).padding(.trailing, 8).frame(height: 44)
                .background(Color(red: 0.14, green: 0.14, blue: 0.14), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 8).padding(20)
            }
        }
        .font(.system(size: 13))
    }
}

private struct Sidebar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Matte").font(.system(size: 20, weight: .semibold)); Spacer(); Button { model.chooseImages() } label: { Image(systemName: "plus") }.buttonStyle(IconButtonStyle()) }
                .foregroundStyle(Theme.primary).padding(.horizontal, 12).frame(height: 52)
            Text("Images").sectionLabel().padding(.horizontal, 12).padding(.top, 8)
            if model.images.isEmpty {
                Button(action: model.chooseImages) {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 22)).foregroundStyle(Theme.tertiary)
                        Text("Drop images here").foregroundStyle(Theme.secondary)
                        Text("or click to choose").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    }.frame(maxWidth: .infinity, minHeight: 132)
                }.buttonStyle(.plain).background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, style: .init(lineWidth: 0.5, dash: [4]))).padding(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.images) { image in
                            Button { model.selectedImageID = image.id } label: {
                                HStack(spacing: 9) {
                                    Image(decorative: image.image, scale: 1).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(image.name).lineLimit(1).foregroundStyle(Theme.primary)
                                        Text(image.dimensions).monoCaption()
                                    }
                                    Spacer()
                                    Button { model.remove(image) } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(IconButtonStyle())
                                }.padding(6).background(model.selectedImageID == image.id ? Theme.control : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 6)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("Watched folder").sectionLabel()
                Toggle("Watch for new images", isOn: $model.watching).toggleStyle(.switch).controlSize(.mini).foregroundStyle(Theme.secondary)
                Text(model.watchedFolder?.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") ?? "No folder selected").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.tertiary).lineLimit(2)
                Button("Choose folder…") { model.chooseWatchedFolder() }.buttonStyle(SecondaryButtonStyle())
                if model.watching, let folder = model.watchedFolder {
                    Text("Watching \(folder.lastPathComponent) · \(model.watchedExportCount) exported").font(.system(size: 11)).foregroundStyle(Color(red: 0.275, green: 0.996, blue: 0.647).opacity(0.83))
                }
            }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).padding(8)
        }.background(Theme.shell)
    }
}

private struct MainPanel: View {
    @ObservedObject var model: AppModel
    let columns = [GridItem(.adaptive(minimum: 210, maximum: 280), spacing: 12)]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selectedImage?.name ?? "Add an image to begin").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.primary).lineLimit(1)
                    if let image = model.selectedImage { Text(image.dimensions).monoCaption() }
                }
                Spacer()
                Button("Export all images") { model.exportAll() }.buttonStyle(SecondaryButtonStyle()).disabled(model.images.isEmpty)
                Button("Export selected") { model.exportSelected() }.buttonStyle(PrimaryButtonStyle()).disabled(model.selectedImage == nil)
            }.padding(.horizontal, 24).frame(height: 72).overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
            HStack(spacing: 18) {
                ForEach(["All", "X", "Instagram"], id: \.self) { tab in
                    Button(tab) { model.platformFilter = tab }.buttonStyle(.plain).foregroundStyle(model.platformFilter == tab ? Theme.primary : Theme.secondary).padding(.vertical, 12).overlay(alignment: .bottom) { if model.platformFilter == tab { Rectangle().fill(Theme.primary).frame(height: 1) } }
                }
                Spacer()
                Text("\(model.checked.count) selected").monoCaption()
            }.padding(.horizontal, 24)
            ScrollView {
                if model.selectedImage == nil {
                    VStack(spacing: 12) { Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 36)).foregroundStyle(Theme.tertiary); Text("Add PNG, JPEG, HEIC, TIFF or WebP images").foregroundStyle(Theme.secondary); Button("Choose images…") { model.chooseImages() }.buttonStyle(PrimaryButtonStyle()) }.frame(maxWidth: .infinity, minHeight: 430)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(model.visibleFormats) { format in FormatCard(model: model, format: format) }
                    }.padding(24)
                }
            }
        }.background(Theme.panel, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 0.5))
    }
}

private struct FormatCard: View {
    @ObservedObject var model: AppModel
    let format: MatteFormat
    var analysis: FitAnalysis? { model.selectedImage.map { Fit.analyze(imageSize: CGSize(width: $0.image.width, height: $0.image.height), format: format, mode: model.mode) } }
    var preview: CGImage? { guard let image = model.selectedImage?.image else { return nil }; return try? MatteRenderer.render(image: image, format: format, options: model.renderOptions, previewMaxDimension: 440) }
    var body: some View {
        Button { model.selectedFormatID = format.id } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35))
                    if let preview { Image(decorative: preview, scale: 1).resizable().scaledToFit().padding(8) }
                }.frame(height: 128).clipped()
                HStack(alignment: .top) {
                    Button { model.toggle(format) } label: { Image(systemName: model.checked.contains(format.id) ? "checkmark.square.fill" : "square").foregroundStyle(model.checked.contains(format.id) ? Theme.brand : Theme.tertiary) }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 3) { Text(format.name).fontWeight(.medium).foregroundStyle(Theme.primary).lineLimit(2); Text("\(format.width)×\(format.height) · \(format.ratioLabel)").monoCaption() }
                    Spacer()
                }
                if let analysis { VerdictBadge(analysis: analysis) }
            }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(model.selectedFormatID == format.id ? Theme.brand : Theme.line, lineWidth: model.selectedFormatID == format.id ? 1 : 0.5))
        }.buttonStyle(.plain)
    }
}

private struct VerdictBadge: View {
    let analysis: FitAnalysis
    var palette: (Color, Color, Color) {
        switch analysis.verdict {
        case .perfect: (Color(red: 0.188, green: 0.643, blue: 0.424), Color(red: 0.133, green: 1, blue: 0.6).opacity(0.12), Color(red: 0.275, green: 0.996, blue: 0.647).opacity(0.83))
        case .needsFrame: (Color(red: 0.969, green: 0.42, blue: 0.082), Color(red: 0.984, green: 0.416, blue: 0).opacity(0.15), Color(red: 1, green: 0.627, blue: 0.341))
        case .needsCrop: (Color(red: 0.898, green: 0.302, blue: 0.18), Color(red: 1, green: 0.208, blue: 0.137).opacity(0.17), Color(red: 1, green: 0.592, blue: 0.49))
        }
    }
    var body: some View { HStack(spacing: 5) { Circle().fill(palette.0).frame(width: 6, height: 6); Text(analysis.label).lineLimit(1) }.font(.system(size: 11)).foregroundStyle(palette.2).padding(.horizontal, 6).frame(height: 20).background(palette.1, in: RoundedRectangle(cornerRadius: 4)) }
}

private struct Inspector: View {
    @ObservedObject var model: AppModel
    let presets = ["#FFFFFF", "#F4F1EA", "#000000", "#FAFAF7", "#111111"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Frame").sectionLabel()
                Picker("Mode", selection: $model.mode) { Text("Fit with frame").tag(RenderMode.fit); Text("Crop to fill").tag(RenderMode.fill) }.pickerStyle(.segmented).labelsHidden()
                HStack { Text("Padding").foregroundStyle(Theme.secondary); Spacer(); Text("\(Int((model.padding * 100).rounded()))%").monoCaption() }
                Slider(value: $model.padding, in: 0...0.3)
                Toggle("Always pad perfect fits", isOn: $model.alwaysPad).toggleStyle(.switch).controlSize(.mini).foregroundStyle(Theme.secondary)
                Divider().overlay(Theme.line)
                Text("Colour").sectionLabel()
                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { hex in Button { model.colorHex = hex; model.autoMatch = false } label: { Circle().fill(Color(nsColor: NSColor(hex: hex))).frame(width: 25, height: 25).overlay(Circle().stroke(model.colorHex.uppercased() == hex ? Theme.brand : Theme.line, lineWidth: 2)) }.buttonStyle(.plain).help(hex) }
                    Spacer(); Button { model.sampleColor() } label: { Image(systemName: "eyedropper") }.buttonStyle(IconButtonStyle())
                }
                HStack { TextField("#RRGGBB", text: $model.colorHex).textFieldStyle(.plain).font(.system(size: 12, design: .monospaced)).padding(8).background(Theme.control, in: RoundedRectangle(cornerRadius: 8)); ColorPicker("", selection: Binding(get: { Color(nsColor: NSColor(hex: model.colorHex)) }, set: { color in if let rgb = NSColor(color).usingColorSpace(.sRGB) { model.colorHex = FrameColor(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent).hex } })).labelsHidden() }
                Toggle("Auto-match edges", isOn: $model.autoMatch).toggleStyle(.switch).controlSize(.mini).foregroundStyle(Theme.secondary)
                Divider().overlay(Theme.line)
                Text("Export").sectionLabel()
                Picker("Type", selection: $model.exportType) { Text("PNG").tag(ExportType.png); Text("JPEG").tag(ExportType.jpeg) }.pickerStyle(.segmented).labelsHidden()
                Text(model.outputFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.tertiary).lineLimit(2)
                HStack { Button("Choose folder…") { model.chooseOutputFolder() }.buttonStyle(SecondaryButtonStyle()); if model.lastExportFolder != nil { Button("Reveal") { model.reveal() }.buttonStyle(LinkButtonStyle()) } }
                Divider().overlay(Theme.line)
                Text("Preview in context").sectionLabel()
                ContextPreview(model: model, format: model.selectedFormat)
            }.padding(16)
        }.background(Theme.shell)
    }
}

private struct ContextPreview: View {
    @ObservedObject var model: AppModel
    let format: MatteFormat
    var preview: CGImage? { guard let image = model.selectedImage?.image else { return nil }; return try? MatteRenderer.render(image: image, format: format, options: model.renderOptions, previewMaxDimension: 500) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Circle().fill(Theme.control).frame(width: 28, height: 28); VStack(alignment: .leading, spacing: 4) { Capsule().fill(Theme.secondary).frame(width: 80, height: 5); Capsule().fill(Theme.tertiary).frame(width: 52, height: 4) }; Spacer() }
            if let preview {
                ZStack(alignment: .top) {
                    Image(decorative: preview, scale: 1).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: format.previewKind == .igStory ? 18 : 8))
                    if let safe = format.safeInsets {
                        GeometryReader { proxy in
                            VStack(spacing: 0) { Color.black.opacity(0.38).frame(height: proxy.size.height * safe.top); Spacer(); Color.black.opacity(0.38).frame(height: proxy.size.height * safe.bottom) }
                        }.clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }.frame(maxHeight: format.previewKind == .igStory ? 310 : 185)
            } else { RoundedRectangle(cornerRadius: 8).fill(Theme.control).frame(height: 150) }
            HStack { ForEach(["heart", "bubble.left", "arrow.2.squarepath", "square.and.arrow.up"], id: \.self) { Image(systemName: $0).foregroundStyle(Theme.secondary) }; Spacer() }
        }.padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 0.5))
    }
}

private struct PrimaryButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(.black).padding(.horizontal, 10).frame(height: 28).background(Color.white.opacity(configuration.isPressed ? 0.8 : 0.95), in: RoundedRectangle(cornerRadius: 6)).scaleEffect(configuration.isPressed ? 0.98 : 1) } }
private struct SecondaryButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.primary).padding(.horizontal, 10).frame(height: 28).background(configuration.isPressed ? Color.white.opacity(0.13) : Theme.control, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 0.5)) } }
private struct IconButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.foregroundStyle(Theme.secondary).frame(width: 28, height: 28).background(configuration.isPressed ? Theme.control : .clear, in: RoundedRectangle(cornerRadius: 6)) } }
private struct LinkButtonStyle: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(configuration.isPressed ? Color.white : Theme.brand) } }

private extension View {
    func sectionLabel() -> some View { self.font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.tertiary) }
    func monoCaption() -> some View { self.font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.tertiary) }
}
private extension NSColor {
    convenience init(hex: String) { let c = FrameColor(hex: hex) ?? .white; self.init(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha) }
}
