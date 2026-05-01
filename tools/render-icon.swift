#!/usr/bin/env swift
//
// Renders the Claude Meter app icon at every macOS AppIcon size into a target
// directory, by drawing the spec procedurally with CoreGraphics. Source of
// truth is `assets/icon.svg` and `docs/brand.md`; this script encodes the same
// geometry so re-running it after a design change is one command.
//
// Usage:
//   swift tools/render-icon.swift [out-dir]
// Defaults to ClaudeMeter/ClaudeMeter/Resources/Assets.xcassets/AppIcon.appiconset.

import AppKit
import CoreGraphics
import Foundation

let defaultOut = "ClaudeMeter/ClaudeMeter/Resources/Assets.xcassets/AppIcon.appiconset"
let outURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? defaultOut)
try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)

// Spec (1024-canvas units, mirrors assets/icon.svg).
let canvas: CGFloat = 1024
let bgCorner: CGFloat = 225
let pillRect = CGRect(x: 348, y: 152, width: 328, height: 720)
let pillCorner: CGFloat = 164
// In CG (y-up) the "lower half" of the pill is y = 152 .. 512.
let deepRect = CGRect(x: 348, y: 152, width: 328, height: 360)

let terracotta = CGColor(red: 0xB5/255.0, green: 0x56/255.0, blue: 0x3D/255.0, alpha: 1)
let cream      = CGColor(red: 0xF4/255.0, green: 0xE8/255.0, blue: 0xDD/255.0, alpha: 1)
let deep       = CGColor(red: 0x8A/255.0, green: 0x3F/255.0, blue: 0x2C/255.0, alpha: 1)

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let scale = s / canvas
    let space = CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: info) else {
        fatalError("CGContext")
    }
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: scale, y: scale)

    // Background squircle.
    let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: canvas, height: canvas),
                    cornerWidth: bgCorner, cornerHeight: bgCorner, transform: nil)
    ctx.addPath(bg)
    ctx.setFillColor(terracotta)
    ctx.fillPath()

    // Cream vessel pill.
    let pill = CGPath(roundedRect: pillRect, cornerWidth: pillCorner,
                      cornerHeight: pillCorner, transform: nil)
    ctx.addPath(pill)
    ctx.setFillColor(cream)
    ctx.fillPath()

    // Deep terracotta fill, clipped to the pill.
    ctx.saveGState()
    ctx.addPath(pill)
    ctx.clip()
    ctx.setFillColor(deep)
    ctx.fill(deepRect)
    ctx.restoreGState()

    guard let cg = ctx.makeImage() else { fatalError("makeImage") }
    let bitmap = NSBitmapImageRep(cgImage: cg)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("png")
    }
    return png
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let url = outURL.appendingPathComponent("icon-\(size).png")
    try render(size: size).write(to: url)
    print("✓ \(url.lastPathComponent)")
}
