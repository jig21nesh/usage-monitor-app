#!/usr/bin/env swift
// Renders the AI Usage Monitor app icon at every macOS size from vector drawing code, so the
// artwork is reproducible from source. Usage:
//   swift scripts/generate-app-icon.swift <output-dir> [--preview <sheet.png>]
// Design: a deep indigo-to-teal squircle carrying a three-ring gauge, one ring per provider,
// each filled to a different level. Neutral palette; no vendor brand colours.

import AppKit
import Foundation

struct IconSize {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var filename: String { scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png" }
}

let sizes: [IconSize] = [
    IconSize(points: 16, scale: 1), IconSize(points: 16, scale: 2),
    IconSize(points: 32, scale: 1), IconSize(points: 32, scale: 2),
    IconSize(points: 128, scale: 1), IconSize(points: 128, scale: 2),
    IconSize(points: 256, scale: 1), IconSize(points: 256, scale: 2),
    IconSize(points: 512, scale: 1), IconSize(points: 512, scale: 2),
]

struct Palette {
    static let backgroundTop = NSColor(srgbRed: 0.19, green: 0.20, blue: 0.47, alpha: 1)
    static let backgroundBottom = NSColor(srgbRed: 0.04, green: 0.33, blue: 0.42, alpha: 1)
    static let highlight = NSColor(srgbRed: 0.55, green: 0.75, blue: 1.0, alpha: 0.22)
    static let track = NSColor(white: 1, alpha: 0.13)
    static let rings: [NSColor] = [
        NSColor(srgbRed: 1.00, green: 0.71, blue: 0.35, alpha: 1), // amber, outer
        NSColor(srgbRed: 1.00, green: 0.40, blue: 0.64, alpha: 1), // rose, middle
        NSColor(srgbRed: 0.58, green: 0.53, blue: 1.00, alpha: 1), // violet, inner
    ]
    static let fills: [CGFloat] = [0.76, 0.52, 0.36]
}

func squirclePath(in rect: CGRect) -> CGPath {
    // Apple's macOS icon shape: corner radius about 22.4% of the side.
    let radius = rect.width * 0.2237
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)

    let side = CGFloat(pixels)
    // NSBitmapImageRep does not zero its buffer; without this the margins are garbage, not clear.
    cg.clear(CGRect(x: 0, y: 0, width: side, height: side))
    let small = pixels <= 64
    // The artwork occupies the standard 824/1024 area, leaving transparent margins like every
    // system icon; small sizes use a slightly larger footprint so the rings stay readable.
    let inset = side * (small ? 0.06 : 0.0977)
    let shape = CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let path = squirclePath(in: shape)

    // Drop shadow beneath the squircle (skipped when tiny; it only muddies the pixels).
    if !small {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -side * 0.012), blur: side * 0.03,
                     color: NSColor(white: 0, alpha: 0.35).cgColor)
        cg.addPath(path)
        cg.setFillColor(Palette.backgroundBottom.cgColor)
        cg.fillPath()
        cg.restoreGState()
    }

    // Background gradient, clipped to the squircle.
    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    let colors = [Palette.backgroundTop.cgColor, Palette.backgroundBottom.cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    cg.drawLinearGradient(gradient, start: CGPoint(x: shape.minX, y: shape.maxY),
                          end: CGPoint(x: shape.maxX, y: shape.minY), options: [])
    // Soft light from the top so the glass treatment on macOS 26 has something to catch.
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [Palette.highlight.cgColor, NSColor.clear.cgColor] as CFArray,
                          locations: [0, 1])!
    cg.drawRadialGradient(glow, startCenter: CGPoint(x: shape.midX, y: shape.maxY + shape.height * 0.15),
                          startRadius: 0, endCenter: CGPoint(x: shape.midX, y: shape.maxY + shape.height * 0.15),
                          endRadius: shape.height * 0.95, options: [])
    cg.restoreGState()

    // Gauge rings: a 240° sweep open at the bottom, filled clockwise from the left end.
    let center = CGPoint(x: shape.midX, y: shape.midY - shape.height * 0.02)
    let startAngle = CGFloat(210 * Double.pi / 180)
    let sweep = CGFloat(240 * Double.pi / 180)
    let ringWidth = shape.width * (small ? 0.16 : 0.072)
    let gap = shape.width * (small ? 0.08 : 0.048)
    let outerRadius = shape.width * (small ? 0.34 : 0.35)
    // Below 64 px the third ring is noise; two bold rings keep the gauge readable.
    let ringCount = small ? 2 : 3

    for index in 0..<ringCount {
        let radius = outerRadius - CGFloat(index) * (ringWidth + gap)
        // Track (dropped at tiny sizes where it only greys the background).
        if !small {
            cg.saveGState()
            cg.setLineWidth(ringWidth)
            cg.setLineCap(.round)
            cg.setStrokeColor(Palette.track.cgColor)
            cg.addArc(center: center, radius: radius, startAngle: startAngle,
                      endAngle: startAngle - sweep, clockwise: true)
            cg.strokePath()
            cg.restoreGState()
        }

        // Fill with a glow.
        let fillEnd = startAngle - sweep * Palette.fills[index]
        cg.saveGState()
        cg.setLineWidth(ringWidth)
        cg.setLineCap(.round)
        cg.setStrokeColor(Palette.rings[index].cgColor)
        if !small {
            cg.setShadow(offset: .zero, blur: ringWidth * 0.9,
                         color: Palette.rings[index].withAlphaComponent(0.75).cgColor)
        }
        cg.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: fillEnd, clockwise: true)
        cg.strokePath()
        cg.restoreGState()
    }

    // Inner edge highlight for a subtle bevel.
    if !small {
        cg.saveGState()
        cg.addPath(squirclePath(in: shape.insetBy(dx: side * 0.004, dy: side * 0.004)))
        cg.setLineWidth(side * 0.006)
        cg.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
        cg.strokePath()
        cg.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "png encode failed"])
    }
    try data.write(to: url)
}

func renderPreviewSheet(to url: URL) throws {
    // Icon at several sizes on light and dark strips, to judge legibility.
    let previewSizes = [1024, 256, 128, 64, 32, 16]
    let padding = 40
    let width = 1024 + padding * 2
    let height = 1024 + 256 + padding * 4 + 64
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: width, height: height))
    cg.setFillColor(NSColor(white: 0.94, alpha: 1).cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
    cg.setFillColor(NSColor(white: 0.12, alpha: 1).cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: width, height: 256 + padding * 2))

    func place(_ rep: NSBitmapImageRep, at rect: NSRect) {
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
    place(render(pixels: 1024), at: NSRect(x: padding, y: height - padding - 1024, width: 1024, height: 1024))
    var x = padding
    for size in previewSizes.dropFirst() {
        place(render(pixels: size), at: NSRect(x: x, y: padding + (256 - size) / 2, width: size, height: size))
        x += size + padding
    }
    NSGraphicsContext.restoreGraphicsState()
    try writePNG(rep, to: url)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: generate-app-icon.swift <output-dir> [--preview <sheet.png>]\n".utf8))
    exit(2)
}
let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for size in sizes {
    try writePNG(render(pixels: size.pixels), to: outputDirectory.appendingPathComponent(size.filename))
}
if let flag = arguments.firstIndex(of: "--preview"), arguments.count > flag + 1 {
    try renderPreviewSheet(to: URL(fileURLWithPath: arguments[flag + 1]))
}
print("wrote \(sizes.count) icon files to \(outputDirectory.path)")
