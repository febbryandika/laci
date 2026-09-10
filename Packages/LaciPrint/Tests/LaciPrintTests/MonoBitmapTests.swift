import Foundation
import LaciPrint
import Testing

@Suite("MonoBitmap packing")
struct MonoBitmapTests {
    @Test("A 16×16 image packs MSB first, 1 = black, two bytes per row")
    func packsHandComputedFixture() {
        #expect(sampleLogo16.bytesPerRow == 2)
        #expect(sampleLogo16.packedRows.count == 32)
        #expect(Array(sampleLogo16.packedRows) == sampleLogo16Bytes)
    }

    @Test("A width that is not a multiple of 8 pads the last byte with zero bits")
    func padsPartialBytes() {
        let bitmap = MonoBitmap(width: 12, height: 2, pixels: [Bool](repeating: true, count: 24))
        #expect(bitmap.bytesPerRow == 2)
        #expect(Array(bitmap.packedRows) == [0xFF, 0xF0, 0xFF, 0xF0])
    }

    @Test("Atkinson keeps pure black and pure white untouched")
    func dithersExtremes() {
        let black = MonoBitmap.atkinson(gray: [UInt8](repeating: 0, count: 64), width: 8, height: 8)
        let white = MonoBitmap.atkinson(gray: [UInt8](repeating: 255, count: 64), width: 8, height: 8)
        #expect(black.packedRows.allSatisfy { $0 == 0xFF })
        #expect(white.packedRows.allSatisfy { $0 == 0x00 })
    }

    @Test("Atkinson turns mid grey into a mix of black and white instead of a solid block")
    func dithersMidGrey() {
        let grey = MonoBitmap.atkinson(gray: [UInt8](repeating: 128, count: 256), width: 16, height: 16)
        let ones = grey.packedRows.reduce(0) { $0 + $1.nonzeroBitCount }
        #expect(ones > 64 && ones < 192, "\(ones) black pixels of 256")
    }
}
