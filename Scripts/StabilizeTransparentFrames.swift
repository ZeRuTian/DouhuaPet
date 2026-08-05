#!/usr/bin/env swift

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

enum StabilizeError: Error, CustomStringConvertible {
    case usage
    case message(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: StabilizeTransparentFrames.swift INPUT_DIR OUTPUT_DIR FRAME_COUNT"
        case let .message(value):
            return value
        }
    }
}

func loadImage(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw StabilizeError.message("Could not read \(url.path)") }
    return image
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else { throw StabilizeError.message("Could not create \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw StabilizeError.message("Could not write \(url.path)")
    }
}

func median(_ values: ArraySlice<CGFloat>) -> CGFloat {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    if sorted.count.isMultiple(of: 2) {
        return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }
    return sorted[sorted.count / 2]
}

func smoothed(_ values: [CGFloat], radius: Int = 4) -> [CGFloat] {
    values.indices.map { index in
        median(values[max(0, index - radius)...min(values.count - 1, index + radius)])
    }
}

func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 3,
          let frameCount = Int(arguments[2]),
          frameCount > 0
    else { throw StabilizeError.usage }

    let input = URL(fileURLWithPath: arguments[0]).standardizedFileURL
    let output = URL(fileURLWithPath: arguments[1]).standardizedFileURL
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let paths = (0..<frameCount).map {
        input.appendingPathComponent(String(format: "frame_%05d.png", $0))
    }
    let reference = try loadImage(paths[0])
    var xTransforms: [CGFloat] = []
    var yTransforms: [CGFloat] = []
    xTransforms.reserveCapacity(frameCount)
    yTransforms.reserveCapacity(frameCount)

    // Register the stable torso and coat texture against one fixed reference.
    // This estimates the camera translation without relying on the removed
    // background and leaves head, ear, paw, breathing, and tail motion intact.
    for (index, path) in paths.enumerated() {
        let image = try loadImage(path)
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: reference)
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw StabilizeError.message("Registration failed at frame \(index)")
        }
        xTransforms.append(observation.alignmentTransform.tx)
        yTransforms.append(observation.alignmentTransform.ty)
    }

    let stableX = smoothed(xTransforms)
    let stableY = smoothed(yTransforms)
    let context = CIContext(options: [.cacheIntermediates: false])
    let canvas = CGRect(x: 0, y: 0, width: reference.width, height: reference.height)
    for (index, path) in paths.enumerated() {
        autoreleasepool {
            do {
                let image = try loadImage(path)
                let translated = CIImage(cgImage: image).transformed(
                    // Vision reports the observed displacement from the fixed
                    // reference. Apply its inverse to cancel camera motion.
                    by: CGAffineTransform(translationX: -stableX[index], y: -stableY[index])
                )
                let clear = CIImage(color: .clear).cropped(to: canvas)
                let composited = translated.composited(over: clear).cropped(to: canvas)
                guard let rendered = context.createCGImage(composited, from: canvas) else {
                    throw StabilizeError.message("Render failed at frame \(index)")
                }
                let destination = output.appendingPathComponent(path.lastPathComponent)
                try writePNG(rendered, to: destination)
                if index % 30 == 0 { print("Stabilized \(index + 1)/\(frameCount)") }
            } catch {
                fputs("Frame \(index) failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    let records = zip(stableX, stableY).enumerated().map { index, transform in
        ["frame": index, "translationX": transform.0, "translationY": transform.1] as [String: Any]
    }
    let metadata: [String: Any] = [
        "frameCount": frameCount,
        "registration": "vision-translation-to-fixed-reference",
        "medianRadiusFrames": 4,
        "transforms": records,
    ]
    let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: output.appendingPathComponent("stabilization.json"), options: .atomic)
    print("Built \(frameCount) stabilized transparent frames in \(output.path)")
}

do {
    try main()
} catch {
    fputs("StabilizeTransparentFrames failed: \(error)\n", stderr)
    exit(1)
}
