import CoreGraphics
import Foundation

/// Draws the shop's logo at the printer's dot width and thresholds it with Atkinson dithering.
/// Dithering is not polish: a photographic logo thresholded flat prints as a black rectangle,
/// and every shop owner sends a photograph.
public enum LogoRenderer {
    /// nil only when CoreGraphics refuses the bitmap context, which for these sizes it does not.
    public static func bitmap(from image: CGImage, paper: PaperWidth) -> MonoBitmap? {
        let width = paper.dots
        let scaled = Double(image.height) * Double(width) / Double(max(1, image.width))
        let height = max(1, Int(scaled.rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(bounds)
        context.interpolationQuality = .high
        context.draw(image, in: bounds)
        guard let base = context.data else { return nil }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let gray = Array(UnsafeBufferPointer(start: bytes, count: width * height))
        return MonoBitmap.atkinson(gray: gray, width: width, height: height)
    }
}
