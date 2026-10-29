#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconDirectory = root.appendingPathComponent("Icon", isDirectory: true)
let iconset = iconDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func image(size: Int) throws -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
    let s = CGFloat(size)
    let outer = CGRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    context.setFillColor(CGColor(red: 0.015, green: 0.015, blue: 0.018, alpha: 1))
    context.addPath(CGPath(roundedRect: outer, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)); context.fillPath()
    let frame = CGRect(x: s * 0.17, y: s * 0.25, width: s * 0.66, height: s * 0.50)
    context.setFillColor(CGColor(gray: 0.96, alpha: 1))
    context.addPath(CGPath(roundedRect: frame, cornerWidth: s * 0.07, cornerHeight: s * 0.07, transform: nil)); context.fillPath()
    let picture = frame.insetBy(dx: s * 0.065, dy: s * 0.065)
    let gradient = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.02, green: 0.32, blue: 0.58, alpha: 1), CGColor(red: 0, green: 0.07, blue: 0.14, alpha: 1)] as CFArray, locations: [0, 1])!
    context.addPath(CGPath(roundedRect: picture, cornerWidth: s * 0.025, cornerHeight: s * 0.025, transform: nil)); context.clip()
    context.drawLinearGradient(gradient, start: CGPoint(x: picture.minX, y: picture.maxY), end: CGPoint(x: picture.maxX, y: picture.minY), options: [])
    guard let output = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    return output
}

func write(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

for point in [16, 32, 128, 256, 512] {
    try write(image(size: point), to: iconset.appendingPathComponent("icon_\(point)x\(point).png"))
    try write(image(size: point * 2), to: iconset.appendingPathComponent("icon_\(point)x\(point)@2x.png"))
}
try write(image(size: 256), to: iconDirectory.appendingPathComponent("preview.png"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", iconDirectory.appendingPathComponent("AppIcon.icns").path]
try process.run(); process.waitUntilExit()
if process.terminationStatus != 0 {
    let fallback = Process()
    fallback.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    fallback.arguments = ["-s", "format", "icns", iconDirectory.appendingPathComponent("preview.png").path, "--out", iconDirectory.appendingPathComponent("AppIcon.icns").path]
    try fallback.run(); fallback.waitUntilExit()
    guard fallback.terminationStatus == 0 else { exit(fallback.terminationStatus) }
}
try? FileManager.default.removeItem(at: iconset)
print("Wrote Icon/AppIcon.icns and Icon/preview.png")
