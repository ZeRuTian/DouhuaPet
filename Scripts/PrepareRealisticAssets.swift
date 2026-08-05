#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

// Normalizes the generated transparent cut-outs onto identically sized sprite
// canvases. A shared scale is intentional: it keeps Douhua's apparent body size
// consistent when the app switches between standing, sitting and resting poses.

private let canvasWidth = 480
private let canvasHeight = 440
private let minimumMargin = 16
private let targetBaseline = 424 // Measured from the top edge of the PNG.
private let alphaThreshold: UInt8 = 2

private struct PoseSpec {
    let state: String

    var sourceName: String { "douhua_\(state)_alpha.png" }
    var outputName: String { "douhua_\(state)_v1.png" }
}

private let poses = ["walk", "observe", "loaf", "sleep", "petted"].map(PoseSpec.init)

private struct PixelBounds {
    let minX: Int
    let minY: Int
    let maxX: Int
    let maxY: Int
    let visiblePixelCount: Int

    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
    var area: Int { width * height }

    var cgCropRect: CGRect {
        CGRect(x: minX, y: minY, width: width, height: height)
    }
}

private struct PreparedSource {
    let pose: PoseSpec
    let url: URL
    let bitmap: NSBitmapImageRep
    let cgImage: CGImage
    let bounds: PixelBounds
}

private struct RenderGeometry {
    let destination: CGRect
    let scaledWidth: Int
    let scaledHeight: Int
}

private struct ValidationResult {
    let bounds: PixelBounds
    let leftMargin: Int
    let rightMargin: Int
    let topMargin: Int
    let bottomMargin: Int
    let baseline: Int
    let canvasCoverage: Double
    let subjectCoverage: Double
}

private enum AssetError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message): message
        }
    }
}

private func fail(_ message: String) throws -> Never {
    throw AssetError.message(message)
}

private func validateRGBAStorage(_ bitmap: NSBitmapImageRep, label: String) throws {
    guard bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else {
        try fail("\(label) has an empty pixel canvas")
    }
    guard bitmap.bitsPerSample == 8,
          bitmap.bitsPerPixel == 32,
          bitmap.samplesPerPixel == 4,
          bitmap.hasAlpha,
          !bitmap.isPlanar else {
        try fail("\(label) must decode as non-planar 8-bit RGBA")
    }
    guard !bitmap.bitmapFormat.contains(.alphaFirst),
          !bitmap.bitmapFormat.contains(.thirtyTwoBitLittleEndian) else {
        try fail("\(label) must expose RGBA byte order (alpha-last)")
    }
    guard bitmap.bytesPerRow >= bitmap.pixelsWide * 4, bitmap.bitmapData != nil else {
        try fail("\(label) has invalid RGBA row storage")
    }
}

private func alpha(atX x: Int, y: Int, in bitmap: NSBitmapImageRep) -> UInt8 {
    let row = bitmap.bitmapData! + y * bitmap.bytesPerRow
    return row[x * 4 + 3]
}

/// Scans raw decoded rows. NSBitmapImageRep exposes PNG rows from top to bottom,
/// so these bounds also match CGImage's pixel-space cropping coordinates.
private func scanAlphaBounds(in bitmap: NSBitmapImageRep, label: String) throws -> PixelBounds {
    try validateRGBAStorage(bitmap, label: label)

    var minX = bitmap.pixelsWide
    var minY = bitmap.pixelsHigh
    var maxX = -1
    var maxY = -1
    var visiblePixelCount = 0

    for y in 0..<bitmap.pixelsHigh {
        let row = bitmap.bitmapData! + y * bitmap.bytesPerRow
        for x in 0..<bitmap.pixelsWide where row[x * 4 + 3] >= alphaThreshold {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
            visiblePixelCount += 1
        }
    }

    guard maxX >= minX, maxY >= minY else {
        try fail("\(label) has no visible alpha content")
    }
    return PixelBounds(
        minX: minX,
        minY: minY,
        maxX: maxX,
        maxY: maxY,
        visiblePixelCount: visiblePixelCount
    )
}

private func loadSource(_ pose: PoseSpec, from sourceDirectory: URL) throws -> PreparedSource {
    let url = sourceDirectory.appendingPathComponent(pose.sourceName)
    guard FileManager.default.fileExists(atPath: url.path) else {
        try fail("Missing source: \(url.path)")
    }

    let data = try Data(contentsOf: url)
    guard let bitmap = NSBitmapImageRep(data: data), let cgImage = bitmap.cgImage else {
        try fail("Cannot decode PNG: \(url.path)")
    }
    let bounds = try scanAlphaBounds(in: bitmap, label: pose.sourceName)
    return PreparedSource(pose: pose, url: url, bitmap: bitmap, cgImage: cgImage, bounds: bounds)
}

private func makeCanvas() throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: canvasWidth,
        pixelsHigh: canvasHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: canvasWidth * 4,
        bitsPerPixel: 32
    ) else {
        try fail("Cannot allocate \(canvasWidth)x\(canvasHeight) RGBA canvas")
    }
    return bitmap
}

private func render(_ source: PreparedSource, scale: CGFloat) throws -> (NSBitmapImageRep, RenderGeometry) {
    guard let croppedCGImage = source.cgImage.cropping(to: source.bounds.cgCropRect) else {
        try fail("Cannot crop alpha bounds for \(source.pose.sourceName)")
    }

    // Flooring guarantees the rasterized subject never crosses the 16 px safe area.
    let scaledWidth = max(1, Int(floor(CGFloat(source.bounds.width) * scale)))
    let scaledHeight = max(1, Int(floor(CGFloat(source.bounds.height) * scale)))
    let x = floor(CGFloat(canvasWidth - scaledWidth) / 2.0)
    let y = CGFloat(canvasHeight - targetBaseline)
    let destination = CGRect(
        x: x,
        y: y,
        width: CGFloat(scaledWidth),
        height: CGFloat(scaledHeight)
    )

    guard destination.minX >= CGFloat(minimumMargin),
          destination.maxX <= CGFloat(canvasWidth - minimumMargin),
          destination.minY >= CGFloat(minimumMargin),
          destination.maxY <= CGFloat(canvasHeight - minimumMargin) else {
        try fail("Computed destination violates safe margins for \(source.pose.state): \(destination)")
    }

    let canvas = try makeCanvas()
    guard let graphicsContext = NSGraphicsContext(bitmapImageRep: canvas) else {
        try fail("Cannot create AppKit graphics context for \(source.pose.state)")
    }

    let croppedImage = NSImage(
        cgImage: croppedCGImage,
        size: CGSize(width: source.bounds.width, height: source.bounds.height)
    )
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    graphicsContext.imageInterpolation = .high
    graphicsContext.shouldAntialias = true
    graphicsContext.cgContext.clear(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
    croppedImage.draw(
        in: destination,
        from: CGRect(origin: .zero, size: croppedImage.size),
        operation: .copy,
        fraction: 1.0,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
    graphicsContext.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return (
        canvas,
        RenderGeometry(destination: destination, scaledWidth: scaledWidth, scaledHeight: scaledHeight)
    )
}

private func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
    guard let data = bitmap.representation(using: .png, properties: [.compressionFactor: 1.0]) else {
        try fail("Cannot encode output PNG: \(url.path)")
    }
    try data.write(to: url, options: .atomic)
}

private func validateOutput(at url: URL) throws -> ValidationResult {
    let data = try Data(contentsOf: url)
    guard let bitmap = NSBitmapImageRep(data: data) else {
        try fail("Cannot reopen generated PNG: \(url.path)")
    }
    try validateRGBAStorage(bitmap, label: url.lastPathComponent)
    guard bitmap.pixelsWide == canvasWidth, bitmap.pixelsHigh == canvasHeight else {
        try fail("\(url.lastPathComponent) is \(bitmap.pixelsWide)x\(bitmap.pixelsHigh), expected \(canvasWidth)x\(canvasHeight)")
    }

    let corners = [
        alpha(atX: 0, y: 0, in: bitmap),
        alpha(atX: canvasWidth - 1, y: 0, in: bitmap),
        alpha(atX: 0, y: canvasHeight - 1, in: bitmap),
        alpha(atX: canvasWidth - 1, y: canvasHeight - 1, in: bitmap),
    ]
    guard corners.allSatisfy({ $0 < alphaThreshold }) else {
        try fail("Transparent-corner validation failed for \(url.lastPathComponent)")
    }

    let bounds = try scanAlphaBounds(in: bitmap, label: url.lastPathComponent)
    let leftMargin = bounds.minX
    let rightMargin = canvasWidth - bounds.maxX - 1
    let topMargin = bounds.minY
    let bottomMargin = canvasHeight - bounds.maxY - 1
    guard [leftMargin, rightMargin, topMargin, bottomMargin].allSatisfy({ $0 >= minimumMargin }) else {
        try fail(
            "Safe-margin validation failed for \(url.lastPathComponent): " +
            "L\(leftMargin) R\(rightMargin) T\(topMargin) B\(bottomMargin)"
        )
    }

    let baseline = bounds.maxY + 1
    guard abs(baseline - targetBaseline) <= 2 else {
        try fail("Baseline validation failed for \(url.lastPathComponent): \(baseline), expected about \(targetBaseline)")
    }

    let canvasCoverage = Double(bounds.visiblePixelCount) / Double(canvasWidth * canvasHeight)
    let subjectCoverage = Double(bounds.visiblePixelCount) / Double(bounds.area)
    guard bounds.width >= canvasWidth / 3,
          bounds.height >= canvasHeight / 4,
          canvasCoverage >= 0.08,
          subjectCoverage >= 0.20 else {
        try fail(
            "Subject-coverage validation failed for \(url.lastPathComponent): " +
            "bounds \(bounds.width)x\(bounds.height), canvas \(String(format: "%.1f", canvasCoverage * 100))%, " +
            "box \(String(format: "%.1f", subjectCoverage * 100))%"
        )
    }

    return ValidationResult(
        bounds: bounds,
        leftMargin: leftMargin,
        rightMargin: rightMargin,
        topMargin: topMargin,
        bottomMargin: bottomMargin,
        baseline: baseline,
        canvasCoverage: canvasCoverage,
        subjectCoverage: subjectCoverage
    )
}

private func projectRootURL() -> URL {
    let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let scriptURL = URL(fileURLWithPath: #filePath, relativeTo: workingDirectory).standardizedFileURL
    return scriptURL.deletingLastPathComponent().deletingLastPathComponent()
}

private func run() throws {
    let root = projectRootURL()
    let sourceDirectory = root.appendingPathComponent("tmp/imagegen", isDirectory: true)
    let outputDirectory = root.appendingPathComponent(
        "Sources/DouhuaPet/Resources/Assets/Douhua/v1.0-realistic",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    let sources = try poses.map { try loadSource($0, from: sourceDirectory) }
    let usableWidth = CGFloat(canvasWidth - minimumMargin * 2)
    let usableHeight = CGFloat(canvasHeight - minimumMargin * 2)
    guard let sharedScale = sources.map({ source in
        min(
            usableWidth / CGFloat(source.bounds.width),
            usableHeight / CGFloat(source.bounds.height)
        )
    }).min(), sharedScale > 0 else {
        try fail("Cannot determine a shared pose scale")
    }

    print("Preparing realistic Douhua assets")
    print("  project: \(root.path)")
    print("  canvas: \(canvasWidth)x\(canvasHeight) RGBA, safe margin: \(minimumMargin) px, baseline: \(targetBaseline) px")
    print("  shared scale: \(String(format: "%.5f", sharedScale))")

    for source in sources {
        let outputURL = outputDirectory.appendingPathComponent(source.pose.outputName)
        let (canvas, geometry) = try render(source, scale: sharedScale)
        try writePNG(canvas, to: outputURL)
        let result = try validateOutput(at: outputURL)
        print(
            "  ✓ \(source.pose.state.padding(toLength: 7, withPad: " ", startingAt: 0)) " +
            "source=\(source.bitmap.pixelsWide)x\(source.bitmap.pixelsHigh) " +
            "alpha=\(source.bounds.width)x\(source.bounds.height) " +
            "render=\(geometry.scaledWidth)x\(geometry.scaledHeight) " +
            "bounds=\(result.bounds.width)x\(result.bounds.height) " +
            "margins=L\(result.leftMargin)/R\(result.rightMargin)/T\(result.topMargin)/B\(result.bottomMargin) " +
            "baseline=\(result.baseline) coverage=\(String(format: "%.1f", result.canvasCoverage * 100))% " +
            "boxFill=\(String(format: "%.1f", result.subjectCoverage * 100))%"
        )
    }

    print("Done: \(outputDirectory.path)")
}

do {
    try run()
} catch {
    let message = "PrepareRealisticAssets failed: \(error.localizedDescription)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(EXIT_FAILURE)
}
