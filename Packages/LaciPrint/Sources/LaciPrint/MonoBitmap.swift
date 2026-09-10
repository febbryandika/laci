import Foundation

/// A 1-bit-per-pixel image in the layout `GS v 0` wants: rows packed MSB first, 1 = black, each
/// row padded to a whole byte.
public struct MonoBitmap: Hashable, Sendable {
    public let width: Int
    public let height: Int
    public let packedRows: Data

    public var bytesPerRow: Int {
        (width + 7) / 8
    }

    /// `pixels` is row-major, `true` = black, exactly `width * height` entries.
    public init(width: Int, height: Int, pixels: [Bool]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height)
        let bytesPerRow = (width + 7) / 8
        var packed = Data(count: bytesPerRow * height)
        for row in 0 ..< height {
            for column in 0 ..< width where pixels[row * width + column] {
                packed[row * bytesPerRow + column / 8] |= UInt8(0x80 >> (column % 8))
            }
        }
        self.width = width
        self.height = height
        packedRows = packed
    }

    /// Atkinson error diffusion over 8-bit grey (0 = black, 255 = white). Three quarters of the
    /// quantisation error is spread to six neighbours; the rest is dropped, which is what keeps
    /// a photographed logo from smearing into a black rectangle on thermal paper.
    public static func atkinson(gray: [UInt8], width: Int, height: Int) -> MonoBitmap {
        precondition(gray.count == width * height)
        var buffer = gray.map { Int($0) }
        var pixels = [Bool](repeating: false, count: width * height)
        let neighbours = [(1, 0), (2, 0), (-1, 1), (0, 1), (1, 1), (0, 2)]
        for row in 0 ..< height {
            for column in 0 ..< width {
                let index = row * width + column
                let old = buffer[index]
                let new = old < 128 ? 0 : 255
                pixels[index] = new == 0
                let share = (old - new) / 8
                for (deltaX, deltaY) in neighbours {
                    let neighbourX = column + deltaX
                    let neighbourY = row + deltaY
                    guard neighbourX >= 0, neighbourX < width, neighbourY < height else { continue }
                    buffer[neighbourY * width + neighbourX] += share
                }
            }
        }
        return MonoBitmap(width: width, height: height, pixels: pixels)
    }
}
