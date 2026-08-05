#!/usr/bin/env swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assetDir = root.appendingPathComponent("Sources/DouhuaPet/Resources/Assets/Douhua/v0.2", isDirectory: true)
let artDir = root.appendingPathComponent("Docs/Art", isDirectory: true)
try FileManager.default.createDirectory(at: assetDir, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: artDir, withIntermediateDirectories: true)

enum Pose: String, CaseIterable {
    case walk = "douhua_walk.png"
    case observe = "douhua_observe.png"
    case loaf = "douhua_loaf.png"
    case sleep = "douhua_sleep.png"
}

struct RGBA {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let a: CGFloat
}

extension NSColor {
    static let douhuaGold = NSColor(calibratedRed: 0.76, green: 0.58, blue: 0.32, alpha: 1)
    static let douhuaDarkGold = NSColor(calibratedRed: 0.31, green: 0.23, blue: 0.14, alpha: 1)
    static let douhuaShade = NSColor(calibratedRed: 0.46, green: 0.34, blue: 0.19, alpha: 1)
    static let douhuaCream = NSColor(calibratedRed: 0.96, green: 0.88, blue: 0.70, alpha: 1)
    static let douhuaGreen = NSColor(calibratedRed: 0.40, green: 0.66, blue: 0.35, alpha: 1)
    static let douhuaPink = NSColor(calibratedRed: 0.91, green: 0.54, blue: 0.55, alpha: 1)
    static let douhuaInk = NSColor(calibratedRed: 0.12, green: 0.09, blue: 0.06, alpha: 1)
}

func ellipse(_ rect: CGRect) -> NSBezierPath { NSBezierPath(ovalIn: rect) }

func fill(_ path: NSBezierPath, _ color: NSColor) {
    color.setFill()
    path.fill()
}

func stroke(_ path: NSBezierPath, _ color: NSColor, width: CGFloat) {
    color.setStroke()
    path.lineWidth = width
    path.stroke()
}

func drawTail(in rect: CGRect, lowered: CGFloat, alpha: CGFloat = 1) {
    let tail = NSBezierPath()
    tail.move(to: CGPoint(x: rect.midX + 48, y: rect.minY + 158 - lowered))
    tail.curve(
        to: CGPoint(x: rect.midX + 130, y: rect.minY + 110 - lowered),
        controlPoint1: CGPoint(x: rect.midX + 105, y: rect.minY + 172 - lowered),
        controlPoint2: CGPoint(x: rect.midX + 158, y: rect.minY + 132 - lowered)
    )
    NSColor.douhuaGold.withAlphaComponent(alpha).setStroke()
    tail.lineWidth = 46
    tail.lineCapStyle = .round
    tail.stroke()

    NSColor.douhuaShade.withAlphaComponent(0.35 * alpha).setStroke()
    tail.lineWidth = 14
    tail.stroke()

    fill(ellipse(CGRect(x: rect.midX + 100, y: rect.minY + 88 - lowered, width: 66, height: 48)), NSColor.douhuaInk.withAlphaComponent(alpha))
}

func drawFace(center: CGPoint, scale: CGFloat, eyesClosed: Bool, headTilt: CGFloat) {
    NSGraphicsContext.current?.cgContext.saveGState()
    NSGraphicsContext.current?.cgContext.translateBy(x: center.x, y: center.y)
    NSGraphicsContext.current?.cgContext.rotate(by: headTilt)
    NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)

    let leftEar = NSBezierPath()
    leftEar.move(to: CGPoint(x: -88, y: 24))
    leftEar.line(to: CGPoint(x: -66, y: 118))
    leftEar.line(to: CGPoint(x: -28, y: 52))
    leftEar.close()
    let rightEar = NSBezierPath()
    rightEar.move(to: CGPoint(x: 88, y: 24))
    rightEar.line(to: CGPoint(x: 66, y: 118))
    rightEar.line(to: CGPoint(x: 28, y: 52))
    rightEar.close()
    fill(leftEar, .douhuaGold); stroke(leftEar, .douhuaDarkGold, width: 5)
    fill(rightEar, .douhuaGold); stroke(rightEar, .douhuaDarkGold, width: 5)
    fill(ellipse(CGRect(x: -72, y: 46, width: 34, height: 42)), .douhuaCream)
    fill(ellipse(CGRect(x: 38, y: 46, width: 34, height: 42)), .douhuaCream)

    fill(ellipse(CGRect(x: -104, y: -58, width: 208, height: 166)), .douhuaGold)
    stroke(ellipse(CGRect(x: -104, y: -58, width: 208, height: 166)), .douhuaDarkGold, width: 5)
    fill(ellipse(CGRect(x: -62, y: -48, width: 124, height: 68)), .douhuaCream)

    for x in stride(from: -66, through: 66, by: 22) {
        let mark = NSBezierPath()
        mark.move(to: CGPoint(x: CGFloat(x), y: 88))
        mark.curve(to: CGPoint(x: CGFloat(x) * 0.55, y: 58), controlPoint1: CGPoint(x: CGFloat(x) * 0.9, y: 76), controlPoint2: CGPoint(x: CGFloat(x) * 0.7, y: 66))
        stroke(mark, NSColor.douhuaShade.withAlphaComponent(0.42), width: 5)
    }

    for eyeX in [-42.0, 42.0] {
        if eyesClosed {
            let line = NSBezierPath()
            line.move(to: CGPoint(x: eyeX - 22, y: 28))
            line.curve(to: CGPoint(x: eyeX + 22, y: 28), controlPoint1: CGPoint(x: eyeX - 8, y: 18), controlPoint2: CGPoint(x: eyeX + 8, y: 18))
            stroke(line, .douhuaInk, width: 7)
        } else {
            fill(ellipse(CGRect(x: eyeX - 25, y: 8, width: 50, height: 62)), .douhuaInk)
            fill(ellipse(CGRect(x: eyeX - 19, y: 14, width: 38, height: 50)), .douhuaGreen)
            fill(ellipse(CGRect(x: eyeX - 5, y: 15, width: 10, height: 42)), .douhuaInk)
            fill(ellipse(CGRect(x: eyeX + 5, y: 43, width: 9, height: 12)), .white.withAlphaComponent(0.82))
        }
    }

    let nose = NSBezierPath()
    nose.move(to: CGPoint(x: -13, y: 1))
    nose.line(to: CGPoint(x: 13, y: 1))
    nose.line(to: CGPoint(x: 0, y: -13))
    nose.close()
    fill(nose, .douhuaPink)

    let mouth = NSBezierPath()
    mouth.move(to: CGPoint(x: 0, y: -13))
    mouth.curve(to: CGPoint(x: -20, y: -27), controlPoint1: CGPoint(x: -4, y: -22), controlPoint2: CGPoint(x: -12, y: -27))
    mouth.move(to: CGPoint(x: 0, y: -13))
    mouth.curve(to: CGPoint(x: 20, y: -27), controlPoint1: CGPoint(x: 4, y: -22), controlPoint2: CGPoint(x: 12, y: -27))
    stroke(mouth, NSColor.douhuaInk.withAlphaComponent(0.5), width: 3)

    NSGraphicsContext.current?.cgContext.restoreGState()
}

func drawCat(pose: Pose, in rect: CGRect, label: String? = nil) {
    let isLoaf = pose == .loaf
    let isSleep = pose == .sleep
    let bodyY = rect.minY + (isSleep ? 72 : isLoaf ? 82 : 92)
    let bodyH: CGFloat = isSleep ? 130 : isLoaf ? 148 : 190

    drawTail(in: rect, lowered: isSleep ? 50 : isLoaf ? 32 : 0, alpha: isSleep ? 0.95 : 1)
    fill(ellipse(CGRect(x: rect.midX - 104, y: bodyY, width: 208, height: bodyH)), .douhuaGold)
    stroke(ellipse(CGRect(x: rect.midX - 104, y: bodyY, width: 208, height: bodyH)), .douhuaDarkGold, width: 5)
    fill(ellipse(CGRect(x: rect.midX - 55, y: bodyY + 24, width: 110, height: bodyH * 0.62)), .douhuaCream)

    if isLoaf || isSleep {
        fill(ellipse(CGRect(x: rect.midX - 92, y: bodyY - 10, width: 184, height: 52)), .douhuaCream)
        stroke(ellipse(CGRect(x: rect.midX - 92, y: bodyY - 10, width: 184, height: 52)), .douhuaDarkGold, width: 4)
    } else {
        for x in [-68.0, 28.0] {
            fill(ellipse(CGRect(x: rect.midX + x, y: bodyY - 18, width: 54, height: 62)), .douhuaCream)
            stroke(ellipse(CGRect(x: rect.midX + x, y: bodyY - 18, width: 54, height: 62)), .douhuaDarkGold, width: 4)
        }
    }

    let faceY = rect.minY + (isSleep ? 220 : isLoaf ? 238 : 286)
    let tilt: CGFloat = pose == .observe ? -0.05 : pose == .walk ? 0.035 : 0
    drawFace(center: CGPoint(x: rect.midX, y: faceY), scale: isSleep ? 0.92 : 1, eyesClosed: isSleep, headTilt: tilt)

    if let label {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1)
        ]
        label.draw(at: CGPoint(x: rect.minX + 12, y: rect.maxY - 34), withAttributes: attributes)
    }
}

func image(size: CGSize, opaque: Bool = false, drawing: (CGRect) -> Void) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    if opaque {
        NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.90, alpha: 1).setFill()
        CGRect(origin: .zero, size: size).fill()
    } else {
        NSColor.clear.setFill()
        CGRect(origin: .zero, size: size).fill(using: .copy)
    }
    drawing(CGRect(origin: .zero, size: size))
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DouhuaAssets", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode \(url.path)"])
    }
    try data.write(to: url, options: .atomic)
}

for pose in Pose.allCases {
    let sprite = image(size: CGSize(width: 360, height: 440)) { rect in
        drawCat(pose: pose, in: rect)
    }
    try writePNG(sprite, to: assetDir.appendingPathComponent(pose.rawValue))
}

let sheet = image(size: CGSize(width: 1440, height: 980), opaque: true) { rect in
    let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: NSColor.black]
    "Douhua v0.2 offline model sheet".draw(at: CGPoint(x: 48, y: rect.maxY - 72), withAttributes: title)
    let note: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: 1)]
    "British Shorthair golden shaded: round face, small upright ears, green eyeliner eyes, pink nose, cream muzzle/chest/belly, compact legs, thick dark-tipped tail.".draw(at: CGPoint(x: 48, y: rect.maxY - 108), withAttributes: note)
    let cells = [
        (Pose.walk, CGRect(x: 56, y: 452, width: 300, height: 370), "walking"),
        (Pose.observe, CGRect(x: 396, y: 452, width: 300, height: 370), "observing"),
        (Pose.loaf, CGRect(x: 736, y: 452, width: 300, height: 370), "loafing"),
        (Pose.sleep, CGRect(x: 1076, y: 452, width: 300, height: 370), "sleeping"),
        (Pose.observe, CGRect(x: 180, y: 48, width: 420, height: 380), "front identity"),
        (Pose.walk, CGRect(x: 820, y: 48, width: 420, height: 380), "tail / body")
    ]
    for cell in cells {
        NSColor.white.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: cell.1, xRadius: 12, yRadius: 12).fill()
        drawCat(pose: cell.0, in: cell.1.insetBy(dx: -30, dy: -20), label: cell.2)
    }
}
try writePNG(sheet, to: artDir.appendingPathComponent("douhua-model-sheet-v0.2-offline.png"))

let manifest = """
{
  "version": "v0.2-offline",
  "generatedBy": "Scripts/GenerateDouhuaAssets.swift",
  "date": "2026-07-10",
  "source": "Deterministic repository-local CoreGraphics/AppKit drawing based on Docs/DouhuaCharacterBible.md and the reference board; no original photos/videos copied or bundled.",
  "limitation": "Offline vector/raster approximation, not final approved semi-realistic generative art.",
  "sprites": [
    "douhua_walk.png",
    "douhua_observe.png",
    "douhua_loaf.png",
    "douhua_sleep.png"
  ],
  "modelSheet": "Docs/Art/douhua-model-sheet-v0.2-offline.png"
}
"""
try manifest.write(to: assetDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

func pixel(_ rep: NSBitmapImageRep, x: Int, y: Int) -> RGBA {
    let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) ?? .clear
    return RGBA(r: color.redComponent, g: color.greenComponent, b: color.blueComponent, a: color.alphaComponent)
}

func validateSprite(_ url: URL) throws {
    guard let image = NSImage(contentsOf: url),
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else {
        throw NSError(domain: "DouhuaAssets", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot read \(url.path)"])
    }
    let w = rep.pixelsWide
    let h = rep.pixelsHigh
    let corners = [pixel(rep, x: 0, y: 0), pixel(rep, x: w - 1, y: 0), pixel(rep, x: 0, y: h - 1), pixel(rep, x: w - 1, y: h - 1)]
    precondition(corners.allSatisfy { $0.a < 0.02 }, "transparent corners failed for \(url.lastPathComponent)")
    var visible = 0
    var greenEye = 0
    var darkTail = 0
    var upperEar = 0
    for y in 0..<h {
        for x in 0..<w {
            let p = pixel(rep, x: x, y: y)
            if p.a > 0.2 { visible += 1 }
            if p.a > 0.5 && p.g > 0.45 && p.g > p.r * 1.18 && p.g > p.b * 1.25 { greenEye += 1 }
            if x > Int(Double(w) * 0.72) && p.a > 0.5 && p.r < 0.25 && p.g < 0.22 && p.b < 0.20 { darkTail += 1 }
            if y < Int(Double(h) * 0.38) && p.a > 0.4 { upperEar += 1 }
        }
    }
    precondition(visible > 30_000, "sprite is too sparse: \(url.lastPathComponent)")
    if !url.lastPathComponent.contains("sleep") {
        precondition(greenEye > 300, "green eyes missing: \(url.lastPathComponent)")
    }
    precondition(darkTail > 120, "dark tail tip missing: \(url.lastPathComponent)")
    precondition(upperEar > 500, "ear/head top integrity failed: \(url.lastPathComponent)")
}

for pose in Pose.allCases {
    try validateSprite(assetDir.appendingPathComponent(pose.rawValue))
}

print("Generated and validated Douhua v0.2 offline assets in \(assetDir.path)")
