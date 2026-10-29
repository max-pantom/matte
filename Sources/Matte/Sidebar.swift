import AppKit
import MatteCore
import SwiftUI

struct Sidebar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Matte").font(.system(size: 20, weight: .semibold)); Spacer(); Button { model.chooseImages() } label: { Image(systemName: "plus") }.buttonStyle(IconButtonStyle()).help("Add images (⌘O)") }
                .foregroundStyle(Theme.primary).padding(.horizontal, 12).frame(height: 52)
            HStack(spacing: 6) {
                Text("Images").sectionLabel()
                if model.loadingCount > 0 { ProgressView().controlSize(.mini) }
                Spacer()
                if !model.images.isEmpty { Text("\(model.selection.count) of \(model.images.count) selected").monoCaption() }
            }.padding(.horizontal, 12).padding(.top, 8)
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
                            let isSelected = model.selection.contains(image.id)
                            Button { model.click(image.id, modifiers: NSEvent.modifierFlags) } label: {
                                HStack(spacing: 9) {
                                    Image(decorative: image.thumbnail.cgImage, scale: 1).resizable().scaledToFill().frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(image.name).lineLimit(1).truncationMode(.middle).foregroundStyle(Theme.primary)
                                        Text(image.dimensions).monoCaption()
                                    }
                                    Spacer()
                                    Button { model.remove(image.id) } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(IconButtonStyle())
                                }
                                .padding(6)
                                // Selected rows use v0.1's highlight; the inspected-but-unselected row gets a fainter one.
                                .background(isSelected ? Theme.control : model.focusedImage?.id == image.id ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(image.url.path.abbreviatingHome)
                            .contextMenu {
                                Button("Reveal in Finder") { model.reveal(image) }
                                Button("Remove") { model.remove(image.id) }
                            }
                        }
                    }.padding(.horizontal, 6)
                }
                if model.selection.isEmpty {
                    Text("Click to select · ⌘ or ⇧ to add · ⌘A all").font(.system(size: 11)).foregroundStyle(Theme.tertiary).padding(.horizontal, 12).padding(.vertical, 6)
                }
            }
            Spacer(minLength: 0)
        }.background(Theme.shell)
    }
}
