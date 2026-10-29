import AppKit
import MatteCore
import SwiftUI

struct Sidebar: View {
    @ObservedObject var model: AppModel
    let dropTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title-bar strip: leaves room for the traffic lights and stays draggable.
            Color.clear.frame(height: 28)
            HStack(spacing: 8) {
                Text("Matte").font(Theme.font(20, .semibold)).foregroundStyle(Theme.fg1)
                Spacer()
                Button { model.chooseImages() } label: { Image(systemName: "plus") }
                    .buttonStyle(IconButtonStyle())
                    .help("Add images (⌘O)")
            }
            .padding(.horizontal, 12)
            .frame(height: 40)

            HStack(spacing: 6) {
                Text("Images").sectionLabel()
                if !model.images.isEmpty { Text("\(model.images.count)").monoCaption() }
                if model.loadingCount > 0 { ProgressView().controlSize(.mini) }
                Spacer()
                if !model.images.isEmpty {
                    if model.selection.isEmpty {
                        Button("Select all") { model.selectAllImages() }.buttonStyle(MatteButtonStyle(kind: .ghost, height: 22))
                    } else {
                        Button("Deselect") { model.deselectAll() }.buttonStyle(MatteButtonStyle(kind: .ghost, height: 22))
                    }
                }
            }
            .padding(.leading, 12).padding(.trailing, 8)
            .frame(height: 30)
            .padding(.top, 6)

            if model.images.isEmpty {
                DropZone(title: "Drop images here", subtitle: "or click to choose", minHeight: 132, iconSize: 22, isTargeted: dropTargeted) { model.chooseImages() }
                    .padding(8)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.images) { image in
                            ImageRow(
                                image: image,
                                isSelected: model.selection.contains(image.id),
                                isFocused: model.focusedImage?.id == image.id,
                                onClick: { model.click(image.id, modifiers: NSEvent.modifierFlags) },
                                onRemove: { model.remove(image.id) }
                            )
                            .contextMenu {
                                Button("Reveal in Finder") { model.reveal(image) }
                                Button("Remove") { model.remove(image.id) }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                footer
            }
        }
        .background(Theme.shell)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.selection.isEmpty ? "No images selected" : "\(model.selection.count) of \(model.images.count) selected")
                .font(Theme.font(12, .medium))
                .foregroundStyle(model.selection.isEmpty ? Theme.fg3 : Theme.brandText)
            Text("⌘-click to add · ⇧-click for a range · ⌘A all · Esc clears")
                .font(Theme.font(11)).foregroundStyle(Theme.fg3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
    }
}

struct ImageRow: View {
    let image: SourceImage
    let isSelected: Bool
    let isFocused: Bool
    let onClick: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    private var background: Color {
        if isSelected { return hovering ? Theme.brand.opacity(0.3) : Theme.brandSubtle }
        if hovering { return Theme.componentHover }
        return isFocused ? Theme.cardStrong : .clear
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(decorative: image.thumbnail.cgImage, scale: 1)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .hairline(6)
            VStack(alignment: .leading, spacing: 2) {
                Text(image.name)
                    .font(Theme.font(13, .medium))
                    .foregroundStyle(Theme.fg1)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(image.dimensions).monoCaption().lineLimit(1)
            }
            Spacer(minLength: 4)
            ZStack {
                if hovering {
                    Button(action: onRemove) { Image(systemName: "xmark") }
                        .buttonStyle(IconButtonStyle(size: 20))
                        .help("Remove from batch")
                        .transition(.opacity)
                } else if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Theme.brand)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: 20, height: 20)
        }
        .padding(6)
        .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Theme.brand : isFocused ? Theme.lineStrong : Color.clear, lineWidth: isSelected ? 1 : 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onClick)
        .onHover { hovering = $0 }
        .animation(Theme.motion, value: hovering)
        .animation(Theme.motion, value: isSelected)
        .animation(Theme.motion, value: isFocused)
        .help(image.url.path.abbreviatingHome)
    }
}
