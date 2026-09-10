import Foundation

public extension Data {
    /// Splits the payload into writes of at most `size` bytes, in order. The transport asks the
    /// peripheral for `size` (SPEC §7.3); a non-positive answer sends everything in one write
    /// rather than looping forever.
    func chunked(into size: Int) -> [Data] {
        guard !isEmpty else { return [] }
        guard size > 0 else { return [self] }
        return stride(from: startIndex, to: endIndex, by: size).map { start in
            self[start ..< Swift.min(start + size, endIndex)]
        }
    }
}

/// ESC/POS real-time status requests. The reply, when a printer sends one, comes back on its
/// notify characteristic.
public enum RealTimeStatus {
    /// DLE EOT 4 — paper sensor status.
    public static let paperQuery = Data([0x10, 0x04, 0x04])
}

/// One reply byte to `RealTimeStatus.paperQuery`.
public struct PaperStatus: Hashable, Sendable {
    public let byte: UInt8

    public init(byte: UInt8) {
        self.byte = byte
    }

    /// Bit 5 is "near end", bit 6 is "out"; either one means the receipt will not finish
    /// (SPEC §7.3). Bits 0, 1, 4 and 7 are fixed and carry no information.
    public var isOut: Bool {
        byte & 0b0110_0000 != 0
    }
}
