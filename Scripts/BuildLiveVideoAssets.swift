#!/usr/bin/env swift

import AppKit
import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

struct Arguments {
    let input: URL
    let outputDirectory: URL
    let start: Double
    let duration: Double
    let fps: Double
    let canvasWidth: Int
    let canvasHeight: Int
}

enum LiveVideoBuildError: Error, CustomStringConvertible {
    case usage
    case message(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: BuildLiveVideoAssets.swift INPUT OUTPUT_DIR START_SECONDS DURATION_SECONDS [FPS]"
        case let .message(value):
            return value
        }
    }
}

func parseArguments() throws -> Arguments {
    let values = Array(CommandLine.arguments.dropFirst())
    guard (4...5).contains(values.count),
          let start = Double(values[2]),
          let duration = Double(values[3]),
          let fps = Double(values.count == 5 ? values[4] : "30"),
          start >= 0, duration > 0, fps > 0
    else { throw LiveVideoBuildError.usage }
    return Arguments(
        input: URL(fileURLWithPath: values[0]).standardizedFileURL,
        outputDirectory: URL(fileURLWithPath: values[1]).standardizedFileURL,
        start: start,
        duration: duration,
        fps: fps,
        canvasWidth: 480,
        canvasHeight: 440
    )
}

func generatedImage(
    at seconds: Double,
    generator: AVAssetImageGenerator
) throws -> CGImage {
    let time = CMTime(seconds: seconds, preferredTimescale: 600)
    return try generator.copyCGImage(at: time, actualTime: nil)
}

func foreground(
    from image: CGImage,
    request: VNGenerateForegroundInstanceMaskRequest,
    context: CIContext
) throws -> (image: CGImage, bounds: CGRect) {
    let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
    try handler.perform([request])
    guard let observation = request.results?.first,
          !observation.allInstances.isEmpty
    else { throw LiveVideoBuildError.message("Vision did not find a foreground subject") }

    let maskBuffer = try observation.generateScaledMaskForImage(
        forInstances: observation.allInstances,
        from: handler
    )
    let source = CIImage(cgImage: image)
    let mask = CIImage(cvPixelBuffer: maskBuffer)
    let clear = CIImage(color: .clear).cropped(to: source.extent)
    let cutout = source.applyingFilter(
        "CIBlendWithMask",
        parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: mask,
        ]
    )
    guard let output = context.createCGImage(cutout, from: source.extent) else {
        throw LiveVideoBuildError.message("Core Image could not render the foreground")
    }

    guard let data = output.dataProvider?.data,
          let bytes = CFDataGetBytePtr(data)
    else { throw LiveVideoBuildError.message("Could not inspect the foreground alpha channel") }
    let bytesPerRow = output.bytesPerRow
    let bytesPerPixel = max(1, output.bitsPerPixel / 8)
    var minX = output.width
    var minY = output.height
    var maxX = -1
    var maxY = -1
    for y in 0..<output.height {
        let row = bytes + y * bytesPerRow
        for x in 0..<output.width where row[x * bytesPerPixel + 3] > 24 {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY else {
        throw LiveVideoBuildError.message("Foreground mask was empty")
    }
    return (
        output,
        CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    )
}

func padded(_ rect: CGRect, within size: CGSize) -> CGRect {
    let padding = max(rect.width, rect.height) * 0.08
    let candidate = rect.insetBy(dx: -padding, dy: -padding)
    return candidate.intersection(CGRect(origin: .zero, size: size)).integral
}

func renderCanvas(
    foreground: CGImage,
    crop: CGRect,
    width: Int,
    height: Int
) throws -> Data {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: width * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { throw LiveVideoBuildError.message("Could not create the output canvas") }

    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    let availableWidth = CGFloat(width - 24)
    let availableHeight = CGFloat(height - 20)
    let scale = min(availableWidth / crop.width, availableHeight / crop.height)
    let drawWidth = crop.width * scale
    let drawHeight = crop.height * scale
    let destination = CGRect(
        x: (CGFloat(width) - drawWidth) / 2,
        y: 10,
        width: drawWidth,
        height: drawHeight
    )
    guard let cropped = foreground.cropping(to: crop) else {
        throw LiveVideoBuildError.message("Could not crop the foreground")
    }
    context.interpolationQuality = .high
    context.draw(cropped, in: destination)
    guard let image = context.makeImage(),
          let destinationData = CFDataCreateMutable(nil, 0),
          let imageDestination = CGImageDestinationCreateWithData(
              destinationData,
              UTType.png.identifier as CFString,
              1,
              nil
          )
    else { throw LiveVideoBuildError.message("Could not create a PNG writer") }
    CGImageDestinationAddImage(imageDestination, image, nil)
    guard CGImageDestinationFinalize(imageDestination) else {
        throw LiveVideoBuildError.message("Could not finalize a PNG frame")
    }
    return destinationData as Data
}

func main() throws {
    let arguments = try parseArguments()
    guard FileManager.default.fileExists(atPath: arguments.input.path) else {
        throw LiveVideoBuildError.message("Missing input video: \(arguments.input.path)")
    }
    try FileManager.default.createDirectory(
        at: arguments.outputDirectory,
        withIntermediateDirectories: true
    )
    let asset = AVURLAsset(url: arguments.input)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let request = VNGenerateForegroundInstanceMaskRequest()
    let context = CIContext(options: [.cacheIntermediates: false])
    let frameCount = max(1, Int((arguments.duration * arguments.fps).rounded(.down)))

    // Use a fixed crop for the entire shot. Per-frame recentering makes fur and
    // paws look as if they are vibrating even when the source video is stable.
    var union = CGRect.null
    let scanCount = min(frameCount, max(8, Int(arguments.duration * 2)))
    for index in 0..<scanCount {
        let progress = scanCount == 1 ? 0 : Double(index) / Double(scanCount - 1)
        let seconds = arguments.start + progress * max(0, arguments.duration - 1 / arguments.fps)
        let image = try generatedImage(at: seconds, generator: generator)
        let result = try foreground(from: image, request: request, context: context)
        union = union.union(result.bounds)
    }
    guard !union.isNull else {
        throw LiveVideoBuildError.message("Could not determine a stable subject crop")
    }
    let reference = try generatedImage(at: arguments.start, generator: generator)
    let crop = padded(
        union,
        within: CGSize(width: reference.width, height: reference.height)
    )

    for index in 0..<frameCount {
        autoreleasepool {
            do {
                let seconds = arguments.start + Double(index) / arguments.fps
                let image = try generatedImage(at: seconds, generator: generator)
                let result = try foreground(from: image, request: request, context: context)
                let png = try renderCanvas(
                    foreground: result.image,
                    crop: crop,
                    width: arguments.canvasWidth,
                    height: arguments.canvasHeight
                )
                let name = String(format: "frame_%05d.png", index)
                try png.write(to: arguments.outputDirectory.appendingPathComponent(name), options: .atomic)
                if index % max(1, Int(arguments.fps)) == 0 {
                    print("Rendered \(index + 1)/\(frameCount)")
                }
            } catch {
                fputs("Frame \(index) failed: \(error)\n", stderr)
                exit(1)
            }
        }
    }
    let metadata: [String: Any] = [
        "input": arguments.input.path,
        "start": arguments.start,
        "duration": arguments.duration,
        "fps": arguments.fps,
        "frameCount": frameCount,
        "canvas": [arguments.canvasWidth, arguments.canvasHeight],
        "stableCrop": [crop.minX, crop.minY, crop.width, crop.height],
        "renderer": "vision-foreground-continuous-video",
    ]
    let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: arguments.outputDirectory.appendingPathComponent("metadata.json"), options: .atomic)
    print("Built \(frameCount) continuous frames in \(arguments.outputDirectory.path)")
}

do {
    try main()
} catch {
    fputs("BuildLiveVideoAssets failed: \(error)\n", stderr)
    exit(1)
}
