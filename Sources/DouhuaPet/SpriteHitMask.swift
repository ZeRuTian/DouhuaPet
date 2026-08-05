import AppKit
import CoreGraphics

/// A cached alpha-only hit mask for a sprite image.
///
/// The source image is decoded once when the mask is initialized. Hit tests only
/// perform coordinate mapping and an array lookup, so pointer movement does not
/// repeatedly decode a realistic PNG.
struct SpriteHitMask: Sendable {
    /// The default keeps the mask small while retaining enough detail for fur,
    /// ears, paws, and tail silhouettes.
    static let defaultMaximumDimension = 256

    let pixelWidth: Int
    let pixelHeight: Int
    let alphaThreshold: UInt8

    private let alphaValues: [UInt8]

    var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }

    /// Creates a mask from an AppKit image.
    ///
    /// Pass `nil` for `maximumDimension` to retain the image's original pixel
    /// dimensions. A positive value downsamples only when the source is larger.
    init?(
        image: NSImage,
        maximumDimension: Int? = SpriteHitMask.defaultMaximumDimension,
        alphaThreshold: UInt8 = 16
    ) {
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else {
            return nil
        }
        self.init(
            cgImage: cgImage,
            maximumDimension: maximumDimension,
            alphaThreshold: alphaThreshold
        )
    }

    /// Creates a mask from a Core Graphics image.
    ///
    /// Pass `nil` for `maximumDimension` to retain the original dimensions. The
    /// threshold is inclusive; fully transparent pixels never count as hits,
    /// including when the threshold is zero.
    init?(
        cgImage: CGImage,
        maximumDimension: Int? = SpriteHitMask.defaultMaximumDimension,
        alphaThreshold: UInt8 = 16
    ) {
        guard let dimensions = Self.maskDimensions(
            sourceWidth: cgImage.width,
            sourceHeight: cgImage.height,
            maximumDimension: maximumDimension
        ) else {
            return nil
        }

        guard let alphaValues = Self.decodeAlpha(
            from: cgImage,
            width: dimensions.width,
            height: dimensions.height
        ) else {
            return nil
        }

        self.pixelWidth = dimensions.width
        self.pixelHeight = dimensions.height
        self.alphaThreshold = alphaThreshold
        self.alphaValues = alphaValues
    }

    /// Maps a point in a SpriteKit-style, bottom-left-origin canvas to the
    /// source image and tests its cached alpha value.
    func contains(
        point: CGPoint,
        canvasSize: CGSize,
        flippedHorizontally: Bool = false
    ) -> Bool {
        guard canvasSize.width.isFinite,
              canvasSize.height.isFinite,
              canvasSize.width > 0,
              canvasSize.height > 0,
              point.x.isFinite,
              point.y.isFinite,
              point.x >= 0,
              point.y >= 0,
              point.x < canvasSize.width,
              point.y < canvasSize.height else {
            return false
        }

        let xFromLeft = min(
            pixelWidth - 1,
            Int((point.x / canvasSize.width) * CGFloat(pixelWidth))
        )
        let pixelX = flippedHorizontally
            ? pixelWidth - 1 - xFromLeft
            : xFromLeft

        let yFromBottom = min(
            pixelHeight - 1,
            Int((point.y / canvasSize.height) * CGFloat(pixelHeight))
        )
        let pixelYFromTop = pixelHeight - 1 - yFromBottom
        let alpha = alphaValues[(pixelYFromTop * pixelWidth) + pixelX]

        return alpha != 0 && alpha >= alphaThreshold
    }

    private static func maskDimensions(
        sourceWidth: Int,
        sourceHeight: Int,
        maximumDimension: Int?
    ) -> (width: Int, height: Int)? {
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        guard let maximumDimension else {
            return (sourceWidth, sourceHeight)
        }
        guard maximumDimension > 0 else { return nil }

        let sourceMaximum = max(sourceWidth, sourceHeight)
        guard sourceMaximum > maximumDimension else {
            return (sourceWidth, sourceHeight)
        }

        let scale = Double(maximumDimension) / Double(sourceMaximum)
        let width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let height = max(1, Int((Double(sourceHeight) * scale).rounded()))
        return (width, height)
    }

    private static func decodeAlpha(
        from image: CGImage,
        width: Int,
        height: Int
    ) -> [UInt8]? {
        let channelCount = 4
        guard width <= Int.max / channelCount else { return nil }
        let bytesPerRow = width * channelCount
        guard height <= Int.max / bytesPerRow else { return nil }

        var rgba = [UInt8](repeating: 0, count: bytesPerRow * height)
        let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }

            context.setBlendMode(.copy)
            context.interpolationQuality = (width == image.width && height == image.height)
                ? .none
                : .medium
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard rendered else { return nil }

        var alphaValues = [UInt8]()
        alphaValues.reserveCapacity(width * height)
        for alphaIndex in stride(from: 3, to: rgba.count, by: channelCount) {
            alphaValues.append(rgba[alphaIndex])
        }
        return alphaValues
    }
}
