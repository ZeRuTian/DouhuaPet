#if canImport(XCTest)
import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import DouhuaPet

final class SpriteHitMaskTests: XCTestCase {
    func testMapsBottomLeftSceneCoordinatesToTopDownImageRows() throws {
        let image = try makeImage(alphaRows: [
            [0, 255, 0, 255],
            [255, 0, 128, 0],
        ])
        let mask = try XCTUnwrap(SpriteHitMask(
            cgImage: image,
            maximumDimension: nil,
            alphaThreshold: 1
        ))
        let canvas = CGSize(width: 400, height: 200)

        XCTAssertTrue(mask.contains(point: CGPoint(x: 50, y: 50), canvasSize: canvas))
        XCTAssertFalse(mask.contains(point: CGPoint(x: 50, y: 150), canvasSize: canvas))
        XCTAssertFalse(mask.contains(point: CGPoint(x: 150, y: 50), canvasSize: canvas))
        XCTAssertTrue(mask.contains(point: CGPoint(x: 150, y: 150), canvasSize: canvas))
    }

    func testHorizontalFlipMirrorsThePixelLookup() throws {
        let image = try makeImage(alphaRows: [[255, 0, 0, 0]])
        let mask = try XCTUnwrap(SpriteHitMask(
            cgImage: image,
            maximumDimension: nil,
            alphaThreshold: 1
        ))
        let canvas = CGSize(width: 400, height: 100)
        let left = CGPoint(x: 50, y: 50)
        let right = CGPoint(x: 350, y: 50)

        XCTAssertTrue(mask.contains(point: left, canvasSize: canvas))
        XCTAssertFalse(mask.contains(point: right, canvasSize: canvas))
        XCTAssertFalse(mask.contains(
            point: left,
            canvasSize: canvas,
            flippedHorizontally: true
        ))
        XCTAssertTrue(mask.contains(
            point: right,
            canvasSize: canvas,
            flippedHorizontally: true
        ))
    }

    func testAlphaThresholdIsInclusiveAndZeroAlphaNeverHits() throws {
        let image = try makeImage(alphaRows: [[0, 127, 128, 255]])
        let inclusiveMask = try XCTUnwrap(SpriteHitMask(
            cgImage: image,
            maximumDimension: nil,
            alphaThreshold: 128
        ))
        let anyVisibleAlphaMask = try XCTUnwrap(SpriteHitMask(
            cgImage: image,
            maximumDimension: nil,
            alphaThreshold: 0
        ))
        let canvas = CGSize(width: 400, height: 100)

        XCTAssertFalse(inclusiveMask.contains(
            point: CGPoint(x: 150, y: 50),
            canvasSize: canvas
        ))
        XCTAssertTrue(inclusiveMask.contains(
            point: CGPoint(x: 250, y: 50),
            canvasSize: canvas
        ))
        XCTAssertFalse(anyVisibleAlphaMask.contains(
            point: CGPoint(x: 50, y: 50),
            canvasSize: canvas
        ))
        XCTAssertTrue(anyVisibleAlphaMask.contains(
            point: CGPoint(x: 150, y: 50),
            canvasSize: canvas
        ))
    }

    func testCanUseOriginalOrDownsampledMaskDimensions() throws {
        let image = try makeImage(alphaRows: Array(
            repeating: [UInt8](repeating: 255, count: 8),
            count: 4
        ))
        let original = try XCTUnwrap(SpriteHitMask(
            cgImage: image,
            maximumDimension: nil
        ))
        let downsampled = try XCTUnwrap(SpriteHitMask(
            cgImage: image,
            maximumDimension: 4
        ))

        XCTAssertEqual(original.pixelWidth, 8)
        XCTAssertEqual(original.pixelHeight, 4)
        XCTAssertEqual(original.pixelSize, CGSize(width: 8, height: 4))
        XCTAssertEqual(downsampled.pixelWidth, 4)
        XCTAssertEqual(downsampled.pixelHeight, 2)
        XCTAssertTrue(downsampled.contains(
            point: CGPoint(x: 799, y: 399),
            canvasSize: CGSize(width: 800, height: 400)
        ))
    }

    func testNSImageInitializerBuildsTheSameCachedMask() throws {
        let cgImage = try makeImage(alphaRows: [[0, 255]])
        let image = NSImage(cgImage: cgImage, size: CGSize(width: 20, height: 10))
        let mask = try XCTUnwrap(SpriteHitMask(
            image: image,
            maximumDimension: nil,
            alphaThreshold: 1
        ))

        XCTAssertFalse(mask.contains(
            point: CGPoint(x: 5, y: 5),
            canvasSize: CGSize(width: 20, height: 10)
        ))
        XCTAssertTrue(mask.contains(
            point: CGPoint(x: 15, y: 5),
            canvasSize: CGSize(width: 20, height: 10)
        ))
    }

    func testRejectsPointsOutsideCanvasAndInvalidCanvasSizes() throws {
        let image = try makeImage(alphaRows: [[255]])
        let mask = try XCTUnwrap(SpriteHitMask(cgImage: image))
        let canvas = CGSize(width: 100, height: 100)

        XCTAssertFalse(mask.contains(point: CGPoint(x: -0.1, y: 50), canvasSize: canvas))
        XCTAssertFalse(mask.contains(point: CGPoint(x: 50, y: -0.1), canvasSize: canvas))
        XCTAssertFalse(mask.contains(point: CGPoint(x: 100, y: 50), canvasSize: canvas))
        XCTAssertFalse(mask.contains(point: CGPoint(x: 50, y: 100), canvasSize: canvas))
        XCTAssertFalse(mask.contains(
            point: CGPoint(x: 0, y: 0),
            canvasSize: CGSize(width: 0, height: 100)
        ))
        XCTAssertFalse(mask.contains(
            point: CGPoint(x: .infinity, y: 0),
            canvasSize: canvas
        ))
    }

    func testRejectsNonPositiveMaximumDimension() throws {
        let image = try makeImage(alphaRows: [[255]])

        XCTAssertNil(SpriteHitMask(cgImage: image, maximumDimension: 0))
        XCTAssertNil(SpriteHitMask(cgImage: image, maximumDimension: -1))
    }

    private func makeImage(alphaRows: [[UInt8]]) throws -> CGImage {
        let height = alphaRows.count
        let width = try XCTUnwrap(alphaRows.first?.count)
        XCTAssertGreaterThan(width, 0)
        XCTAssertTrue(alphaRows.allSatisfy { $0.count == width })

        let rgba = alphaRows.flatMap { row in
            row.flatMap { alpha in [alpha, alpha, alpha, alpha] }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(rgba) as CFData))
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }
}
#endif
