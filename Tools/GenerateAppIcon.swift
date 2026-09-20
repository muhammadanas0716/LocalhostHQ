#!/usr/bin/env swift
//
//  GenerateAppIcon.swift
//  Renders the Localhost HQ app icon set with CoreGraphics.
//
//  The icon is a "listening beacon": a solid node broadcasting two concentric
//  rings, sitting on an indigo squircle. The same mark is reproduced as a
//  SwiftUI shape in `Views/BeaconMark.swift`, so the app icon, the menu bar
//  glyph and the in-app branding all stay in sync.
//
//  Usage: swift Tools/GenerateAppIcon.swift <output.appiconset directory>
//

import AppKit
import CoreGraphics
import Foundation

// MARK: - Geometry

/// Apple's macOS icon grid: on a 1024pt canvas the rounded body is 824pt wide.
private let canvasRatioBody: CGFloat = 824.0 / 1024.0
/// Exponent of the superellipse that approximates the macOS squircle.
private let squircleExponent: CGFloat = 5.0

private func squirclePath(center: CGPoint, radius a: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosT = cos(t), sinT = sin(t)
        let exponent = 2 / squircleExponent
        let x = a * (cosT < 0 ? -1 : 1) * pow(abs(cosT), exponent)
        let y = a * (sinT < 0 ? -1 : 1) * pow(abs(sinT), exponent)
        let point = CGPoint(x: center.x + x, y: center.y + y)
        step == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

/// Proportions of the hub mark, expressed as fractions of the body radius.
/// `Views/HubMarkShape.swift` mirrors these so the in-app mark matches the icon.
enum HubMark {
    static let hubRadius: CGFloat = 0.235
    static let satelliteRadius: CGFloat = 0.150
    static let orbit: CGFloat = 0.625
    static let connectorWidth: CGFloat = 0.098
    static let angles: [CGFloat] = [90, 210, 330]
}

// MARK: - Palette

private func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

private let indigoTop = rgb(129, 140, 248)   // indigo-400
private let indigoMid = rgb(79, 70, 229)     // indigo-600
private let indigoDeep = rgb(49, 46, 129)    // indigo-900

// MARK: - Drawing

private func drawIcon(in context: CGContext, size: CGFloat) {
    let scale = size / 1024.0
    context.saveGState()
    context.scaleBy(x: scale, y: scale)

    let canvas: CGFloat = 1024
    let center = CGPoint(x: canvas / 2, y: canvas / 2)

    // Full-bleed artwork: the gradient fills the entire canvas and macOS applies
    // its own icon shape and shadow. Baking in a squircle plus a transparent
    // margin makes modern macOS nest that squircle inside the system container,
    // which renders as a small tile on a dark square.
    let body = CGPath(rect: CGRect(x: 0, y: 0, width: canvas, height: canvas), transform: nil)
    // The mark is sized against this radius, not the canvas, so the glyph keeps
    // its proportions now that the surrounding margin is gone.
    let bodyRadius = canvas * canvasRatioBody / 2

    context.saveGState()
    context.addPath(body)
    context.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(
        colorsSpace: space,
        colors: [indigoTop, indigoMid, indigoDeep] as CFArray,
        locations: [0.0, 0.55, 1.0]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: center.x, y: canvas),
            end: CGPoint(x: center.x, y: 0),
            options: []
        )
    }

    // Soft specular highlight in the upper-left, keeps the face from reading flat.
    if let highlight = CGGradient(
        colorsSpace: space,
        colors: [rgb(255, 255, 255, 0.30), rgb(255, 255, 255, 0.0)] as CFArray,
        locations: [0.0, 1.0]
    ) {
        context.drawRadialGradient(
            highlight,
            startCenter: CGPoint(x: center.x - bodyRadius * 0.35, y: center.y + bodyRadius * 0.55),
            startRadius: 0,
            endCenter: CGPoint(x: center.x - bodyRadius * 0.35, y: center.y + bodyRadius * 0.55),
            endRadius: bodyRadius * 1.15,
            options: []
        )
    }
    context.restoreGState()

    // MARK: Hub mark
    // One large node (the HQ) with three smaller service nodes wired to it.
    let markUnit = bodyRadius
    let hubRadius = markUnit * HubMark.hubRadius
    let satelliteRadius = markUnit * HubMark.satelliteRadius
    let orbit = markUnit * HubMark.orbit

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -canvas * 0.006),
        blur: canvas * 0.022,
        color: rgb(23, 20, 80, 0.45)
    )
    context.setLineCap(.round)

    let satellites = HubMark.angles.map { degrees -> CGPoint in
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + cos(radians) * orbit, y: center.y + sin(radians) * orbit)
    }

    // Connectors, inset at both ends so they meet the nodes flush.
    context.setStrokeColor(rgb(255, 255, 255, 0.55))
    context.setLineWidth(markUnit * HubMark.connectorWidth)
    for satellite in satellites {
        let dx = satellite.x - center.x, dy = satellite.y - center.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        let ux = dx / length, uy = dy / length
        let inner = hubRadius * 0.82
        let outer = length - satelliteRadius * 0.82
        context.move(to: CGPoint(x: center.x + ux * inner, y: center.y + uy * inner))
        context.addLine(to: CGPoint(x: center.x + ux * outer, y: center.y + uy * outer))
        context.strokePath()
    }

    context.setFillColor(rgb(255, 255, 255, 0.88))
    for satellite in satellites {
        context.addArc(center: satellite, radius: satelliteRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        context.fillPath()
    }

    context.setFillColor(rgb(255, 255, 255, 1.0))
    context.addArc(center: center, radius: hubRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    context.fillPath()
    context.restoreGState()

    context.restoreGState()
}

private func renderPNG(size: Int) -> Data? {
    let width = size, height = size
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    drawIcon(in: context, size: CGFloat(size))

    guard let image = context.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: width, height: height)
    return rep.representation(using: .png, properties: [:])
}

// MARK: - Asset catalog emission

private struct IconSpec {
    let size: Int       // points
    let scale: Int
    var pixels: Int { size * scale }
    var filename: String { "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png" }
}

private let specs: [IconSpec] = [
    .init(size: 16, scale: 1), .init(size: 16, scale: 2),
    .init(size: 32, scale: 1), .init(size: 32, scale: 2),
    .init(size: 128, scale: 1), .init(size: 128, scale: 2),
    .init(size: 256, scale: 1), .init(size: 256, scale: 2),
    .init(size: 512, scale: 1), .init(size: 512, scale: 2),
]

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: GenerateAppIcon.swift <AppIcon.appiconset>\n".utf8))
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

var emitted: [[String: String]] = []
var renderedPixelSizes: Set<Int> = []

for spec in specs {
    let url = outputDirectory.appendingPathComponent(spec.filename)
    if !renderedPixelSizes.contains(spec.pixels) || !FileManager.default.fileExists(atPath: url.path) {
        guard let data = renderPNG(size: spec.pixels) else {
            FileHandle.standardError.write(Data("failed to render \(spec.pixels)px\n".utf8))
            exit(1)
        }
        try data.write(to: url)
        renderedPixelSizes.insert(spec.pixels)
    }
    emitted.append([
        "filename": spec.filename,
        "idiom": "mac",
        "scale": "\(spec.scale)x",
        "size": "\(spec.size)x\(spec.size)",
    ])
}

let contents: [String: Any] = [
    "images": emitted,
    "info": ["author": "xcode", "version": 1],
]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDirectory.appendingPathComponent("Contents.json"))

print("Wrote \(emitted.count) entries to \(outputDirectory.path)")
