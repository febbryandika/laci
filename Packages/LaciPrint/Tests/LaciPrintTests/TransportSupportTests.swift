import Foundation
import LaciPrint
import Testing

@Suite("Chunked writes")
struct DataChunkingTests {
    @Test("Chunks reassemble to the original and none exceeds the size", arguments: [1, 20, 244, 1000])
    func reassembles(size: Int) {
        let payload = Data((0 ..< 797).map { UInt8($0 % 251) })
        let chunks = payload.chunked(into: size)
        #expect(Data(chunks.joined()) == payload)
        #expect(chunks.allSatisfy { $0.count <= size })
        #expect(chunks.dropLast().allSatisfy { $0.count == size })
        #expect(chunks.count == (payload.count + size - 1) / size)
    }

    @Test("Empty data yields no chunks")
    func empty() {
        #expect(Data().chunked(into: 20).isEmpty)
    }

    @Test("A non-positive size sends the payload in one write rather than looping forever")
    func nonPositiveSize() {
        let payload = Data([1, 2, 3])
        #expect(payload.chunked(into: 0) == [payload])
        #expect(payload.chunked(into: -5) == [payload])
    }

    @Test("A sliced Data chunks from its own start, not the parent's")
    func slice() {
        let parent = Data([9, 9, 9, 1, 2, 3, 4, 5])
        let slice = parent[3...]
        #expect(slice.chunked(into: 2) == [Data([1, 2]), Data([3, 4]), Data([5])])
    }
}

@Suite("Real-time paper status")
struct PaperStatusTests {
    @Test("DLE EOT 4 is the paper sensor query")
    func query() {
        #expect(RealTimeStatus.paperQuery == Data([0x10, 0x04, 0x04]))
    }

    @Test("Bit 5 (near end) and bit 6 (out) each mean the printer cannot finish the receipt")
    func outBits() {
        #expect(PaperStatus(byte: 0b0010_0000).isOut)
        #expect(PaperStatus(byte: 0b0100_0000).isOut)
        #expect(PaperStatus(byte: 0b0110_0000).isOut)
        #expect(PaperStatus(byte: 0x12).isOut == false) // the fixed bits every reply carries
        #expect(PaperStatus(byte: 0b1001_1111).isOut == false)
    }
}
