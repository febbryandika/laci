import CoreGraphics
import Foundation
import LaciPrint
import Testing

@Suite("Logo rendering")
struct LogoRendererTests {
    /// A 100×50 horizontal grey ramp, the shape of a photographed logo that a flat threshold
    /// would turn into a black rectangle.
    static func gradient() throws -> CGImage {
        let width = 100, height = 50
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for row in 0 ..< height {
            for column in 0 ..< width {
                bytes[row * width + column] = UInt8(column * 255 / (width - 1))
            }
        }
        return try #require(context.makeImage())
    }

    @Test("The logo is rasterised at the paper's dot width, keeping its aspect ratio", arguments: [
        (PaperWidth.mm58, 384, 192), (PaperWidth.mm80, 576, 288),
    ])
    func sizes(paper: PaperWidth, width: Int, height: Int) throws {
        let bitmap = try #require(LogoRenderer.bitmap(from: Self.gradient(), paper: paper))
        #expect(bitmap.width == width)
        #expect(bitmap.height == height)
        #expect(bitmap.packedRows.count == (width / 8) * height)
    }

    @Test("A ramp dithers to mostly black on the left and mostly white on the right, not a solid block")
    func dithersRamp() throws {
        let bitmap = try #require(LogoRenderer.bitmap(from: Self.gradient(), paper: .mm58))
        let bytesPerRow = bitmap.bytesPerRow
        let rows = Array(bitmap.packedRows)
        var leftOnes = 0, rightOnes = 0
        for row in 0 ..< bitmap.height {
            let start = row * bytesPerRow
            let end = start + bytesPerRow
            leftOnes += rows[start ..< start + 8].reduce(0) { $0 + $1.nonzeroBitCount }
            rightOnes += rows[end - 8 ..< end].reduce(0) { $0 + $1.nonzeroBitCount }
        }
        let cells = bitmap.height * 64
        #expect(leftOnes > cells * 3 / 4, "left: \(leftOnes)/\(cells) black")
        #expect(rightOnes < cells / 4, "right: \(rightOnes)/\(cells) black")
        #expect(bitmap.packedRows.contains { $0 != 0x00 && $0 != 0xFF })
    }
}
