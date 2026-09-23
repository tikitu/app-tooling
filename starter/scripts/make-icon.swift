#!/usr/bin/env swift
// make-icon.swift — render the Mac app icon at every macOS size.
//
// A placeholder: a checklist, white on a slate-blue rounded-rect tile. Replace
// `drawGlyph` and the tile's colours with the app's own mark. Pure CoreGraphics, no assets, no dependencies — runs under plain `swift`.
// The Makefile runs `iconutil -c icns build/AppIcon.iconset` on the PNGs this
// writes.

import AppKit

let iconsetDir = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// (filename, pixel dimension) — the set iconutil expects.
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64), ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512), ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func draw(into ctx: CGContext, size s: CGFloat) {
    let inset = s * 0.06
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let corner = s * 0.22
    let tilePath = CGPath(
        roundedRect: tile, cornerWidth: corner, cornerHeight: corner, transform: nil)

    let grad = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.36, green: 0.52, blue: 0.80, alpha: 1),
            CGColor(red: 0.20, green: 0.31, blue: 0.55, alpha: 1),
        ] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    drawGlyph(into: ctx, tile: tile)
}

/// Three rows, each a tick box and a line. Drawn from proportions of the tile
/// so it is the same mark at 16 points and at 1024; two rows at the smallest
/// sizes, where three are mud.
func drawGlyph(into ctx: CGContext, tile: CGRect) {
    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 0.96)
    let w = tile.width
    let rows = w >= 96 ? 3 : 2
    let rowHeight = w * 0.14
    let gap = w * 0.08
    let total = CGFloat(rows) * rowHeight + CGFloat(rows - 1) * gap
    ctx.setFillColor(white)
    for row in 0..<rows {
        let y = tile.midY + total / 2 - rowHeight - CGFloat(row) * (rowHeight + gap)
        let box = CGRect(x: tile.minX + w * 0.2, y: y, width: rowHeight, height: rowHeight)
        ctx.addPath(
            CGPath(
                roundedRect: box, cornerWidth: rowHeight * 0.25, cornerHeight: rowHeight * 0.25,
                transform: nil))
        let line = CGRect(
            x: box.maxX + w * 0.07, y: y + rowHeight * 0.3, width: w * 0.39,
            height: rowHeight * 0.4)
        ctx.addPath(
            CGPath(
                roundedRect: line, cornerWidth: line.height / 2, cornerHeight: line.height / 2,
                transform: nil))
    }
    ctx.fillPath()
}

for (name, side) in variants {
    guard
        let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("could not create the bitmap context for \(name)") }

    draw(into: ctx, size: CGFloat(side))

    guard let image = ctx.makeImage() else { fatalError("could not render \(name)") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode \(name)")
    }
    try png.write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name)"))
}

print("✓ wrote \(variants.count) PNGs to \(iconsetDir)")
