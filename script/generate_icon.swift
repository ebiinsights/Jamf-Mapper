#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate_icon.swift /path/to/AppIcon.icns\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fileManager = FileManager.default
let iconsetURL = outputURL
    .deletingLastPathComponent()
    .appendingPathComponent("AppIcon.iconset", isDirectory: true)

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let variants: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in variants {
    let image = makeIcon(size: Int(size))
    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:])
    else {
        fputs("failed to render \(name)\n", stderr)
        exit(1)
    }
    try png.write(to: iconsetURL.appendingPathComponent(name))
}

try? fileManager.removeItem(at: outputURL)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    fputs("iconutil failed with status \(process.terminationStatus)\n", stderr)
    exit(process.terminationStatus)
}

try? fileManager.removeItem(at: iconsetURL)

func makeIcon(size: Int) -> NSImage {
    let edge = CGFloat(size)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    bitmap.size = NSSize(width: edge, height: edge)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let rect = NSRect(x: 0, y: 0, width: edge, height: edge)
    NSColor.clear.setFill()
    rect.fill()

    let markRect = rect.insetBy(dx: edge * 0.04, dy: edge * 0.04)
    let path = NSBezierPath(roundedRect: markRect, xRadius: edge * 0.18, yRadius: edge * 0.18)
    NSGradient(colors: [NSColor.systemTeal, NSColor.systemBlue])?.draw(in: path, angle: -35)

    drawNodeMark(in: rect, size: edge)

    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: edge, height: edge))
    image.addRepresentation(bitmap)
    return image
}

func drawNodeMark(in rect: NSRect, size: CGFloat) {
    let center = NSPoint(x: rect.midX, y: rect.midY)
    let spread = size * 0.19
    let topLeft = NSPoint(x: center.x - spread, y: center.y + spread * 0.62)
    let topRight = NSPoint(x: center.x + spread, y: center.y + spread * 0.62)
    let bottom = NSPoint(x: center.x, y: center.y - spread * 0.95)
    let strokeWidth = max(1.2, size * 0.028)
    let nodeRadius = max(2.2, size * 0.047)

    NSColor.white.setStroke()

    let line = NSBezierPath()
    line.lineWidth = strokeWidth
    line.lineCapStyle = .round
    line.lineJoinStyle = .round
    line.move(to: topLeft)
    line.line(to: topRight)
    line.line(to: bottom)
    line.line(to: topLeft)
    line.stroke()

    for point in [topLeft, topRight, bottom] {
        let nodeRect = NSRect(
            x: point.x - nodeRadius,
            y: point.y - nodeRadius,
            width: nodeRadius * 2,
            height: nodeRadius * 2
        )
        let node = NSBezierPath(ovalIn: nodeRect)
        NSColor(red: 0.04, green: 0.16, blue: 0.20, alpha: 0.92).setFill()
        node.fill()
        NSColor.white.setStroke()
        node.lineWidth = strokeWidth * 0.72
        node.stroke()
    }
}
