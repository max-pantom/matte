#!/usr/bin/env swift
// Renders Matte's macOS app icon. Run from the repo root:
//   swift scripts/make-icon.swift && iconutil -c icns Icon/AppIcon.iconset -o Icon/AppIcon.icns
// (scripts/make-icon.sh does both.) Writes Icon/AppIcon.iconset (all ten sizes) and Icon/preview.png (1024).
//
// Layout follows the Big Sur grid: 1024 canvas, 824×824 body with ~100px margins and a soft drop shadow.
// Motif: a white passe-partout (matte) holding a warm 16:9 image tile, with brand-orange crop marks.
// Every size is drawn natively (not downscaled) and snapped to whole pixels; small sizes drop fine detail.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

/// Continuous-corner body: a superellipse (n = 5) inscribed in `rect`.
func squircle(in rect: CGRect, exponent n: CGFloat = 5, steps: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    for step in 0..<steps {
        let theta = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let c = cos(theta), s = sin(theta)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// A rect given in 1024-unit coordinates, scaled to `size` pixels and snapped to whole pixels.
func snapped(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, scale: CGFloat) -> CGRect {
    let minX = (x * scale).rounded(), minY = (y * scale).rounded()
    let maxX = ((x + w) * scale).rounded(), maxY = ((y + h) * scale).rounded()
    return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
}

func renderIcon(size: Int) throws -> CGImage {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CocoaError(.fileWriteUnknown) }
    let scale = CGFloat(size) / 1024
    let tiny = size <= 32      // 16, 16@2x, 32
    let small = size <= 64     // adds 32@2x
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Body: graphite gradient squircle with a drop shadow.
    let bodyRect = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let body = squircle(in: bodyRect)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: max(1, 24 * scale), color: rgb(0x000000, 0.35))
    ctx.addPath(body)
    ctx.setFillColor(rgb(0x1C1C1F))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let bodyGradient = CGGradient(colorsSpace: space, colors: [rgb(0x3C3C42), rgb(0x232326), rgb(0x121214)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bodyGradient, start: CGPoint(x: 0, y: bodyRect.maxY), end: CGPoint(x: 0, y: bodyRect.minY), options: [])
    // Soft top glow.
    let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: bodyRect.midX, y: bodyRect.maxY), startRadius: 0, endCenter: CGPoint(x: bodyRect.midX, y: bodyRect.maxY), endRadius: 620 * scale, options: [])
    // Inner rim highlight (only the inner half of the stroke shows, because of the clip).
    if !tiny {
        ctx.addPath(body)
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.14))
        ctx.setLineWidth(max(1, 4 * scale))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Passe-partout: portrait 4:5 frame. Tiny sizes enlarge it for legibility.
    let frameW: CGFloat = tiny ? 560 : 480
    let frameH: CGFloat = tiny ? 680 : 600
    let frame = snapped(512 - frameW / 2, 512 - frameH / 2, frameW, frameH, scale: scale)
    let frameRadius = max(tiny ? 0.5 : 1, 16 * scale)
    let framePath = CGPath(roundedRect: frame, cornerWidth: frameRadius, cornerHeight: frameRadius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8 * scale), blur: max(1, 20 * scale), color: rgb(0x000000, small ? 0.35 : 0.5))
    ctx.addPath(framePath)
    ctx.setFillColor(rgb(0xF7F4EE))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(framePath)
    ctx.clip()
    let paper = CGGradient(colorsSpace: space, colors: [rgb(0xFFFDF9), rgb(0xEDE8DE)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(paper, start: CGPoint(x: 0, y: frame.maxY), end: CGPoint(x: 0, y: frame.minY), options: [])
    ctx.restoreGState()

    // Image tile: a wide 16:9 picture centred in the matte, warm sunset gradient.
    let margin: CGFloat = tiny ? 46 : 52
    let tileW = frameW - 2 * margin
    let tileH = tileW * 9 / 16
    let tile = snapped(512 - tileW / 2, 512 - tileH / 2, tileW, tileH, scale: scale)
    if !small {
        // Bevel of the cut window.
        let bevel = tile.insetBy(dx: -7 * scale, dy: -7 * scale)
        ctx.setFillColor(rgb(0xDCD5C7))
        ctx.fill(bevel)
        ctx.setFillColor(rgb(0xFFFFFF, 0.9))
        ctx.fill(CGRect(x: bevel.minX, y: bevel.minY, width: bevel.width, height: 3 * scale))
    }
    ctx.saveGState()
    ctx.clip(to: tile)
    let warm = CGGradient(colorsSpace: space, colors: [rgb(0xFFC66D), rgb(0xF76B15), rgb(0xC0305E)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(warm, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    if !small {
        // Low sun and a dark horizon band suggest a landscape.
        let sun = CGRect(x: tile.minX + tile.width * 0.62, y: tile.minY + tile.height * 0.38, width: tile.height * 0.34, height: tile.height * 0.34)
        ctx.setFillColor(rgb(0xFFEBC9, 0.92))
        ctx.fillEllipse(in: sun)
        ctx.setFillColor(rgb(0x5A1838, 0.55))
        ctx.fill(CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: tile.height * 0.26))
    }
    ctx.restoreGState()

    // Crop marks in brand orange just outside each frame corner.
    if !tiny {
        let gap = 26 * scale
        let arm = 70 * scale
        let thickness = max(1.5, 14 * scale)
        ctx.setStrokeColor(rgb(0xF76B15))
        ctx.setLineWidth(thickness)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: frame.minX - gap, y: frame.minY - gap), 1, 1),
            (CGPoint(x: frame.maxX + gap, y: frame.minY - gap), -1, 1),
            (CGPoint(x: frame.minX - gap, y: frame.maxY + gap), 1, -1),
            (CGPoint(x: frame.maxX + gap, y: frame.maxY + gap), -1, -1),
        ]
        for (point, dx, dy) in corners {
            ctx.move(to: CGPoint(x: point.x + dx * arm, y: point.y))
            ctx.addLine(to: point)
            ctx.addLine(to: CGPoint(x: point.x, y: point.y + dy * arm))
        }
        ctx.strokePath()
    }

    guard let image = ctx.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    return image
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

func run() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let iconDirectory = root.appendingPathComponent("Icon", isDirectory: true)
    let iconset = iconDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for point in [16, 32, 128, 256, 512] {
        try writePNG(renderIcon(size: point), to: iconset.appendingPathComponent("icon_\(point)x\(point).png"))
        try writePNG(renderIcon(size: point * 2), to: iconset.appendingPathComponent("icon_\(point)x\(point)@2x.png"))
    }
    try writePNG(renderIcon(size: 1024), to: iconDirectory.appendingPathComponent("preview.png"))
    print("Wrote Icon/AppIcon.iconset (10 sizes) and Icon/preview.png")
}

do {
    try run()
} catch {
    print("make-icon: \(error)")
    exit(1)
}
