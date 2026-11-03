import Foundation
@testable import Laci
import os
import Testing

/// The claim "Bagikan log" rests on: an entry written through `Log` comes back from this process's
/// own store with its public values, and a `.private` value never comes back as the amount or name.
@Suite("Log store reader")
struct LogStoreReaderTests {
    @Test("A notice comes back from the store with public values kept and private ones redacted")
    func readsBackRedacted() throws {
        let marker = UUID().uuidString
        let secret = "Indomie Goreng 85g Rp 3.500"
        let count = 7
        let isShort = true
        Log.sale.notice("""
        probe \(marker, privacy: .public) \(secret, privacy: .private) lines \(count, privacy: .public) \
        short \(isShort, privacy: .public) unmarked \(secret)
        """)
        let line = try #require(LogStoreReader.entries().last { $0.message.contains(marker) })
        #expect(line.category == "sale")
        #expect(line.level == "notice")
        #expect(!line.message.contains("Indomie"))
        #expect(line.message == "probe \(marker) <private> lines 7 short true unmarked <private>")
    }

    @Test("Placeholders decide: public shown, private hidden, unmarked text hidden, unmarked scalars shown")
    func rule() {
        let parts = [
            LogPart(literal: "a ", placeholder: "%{public}s", kind: .text, value: "shown"),
            LogPart(literal: " b ", placeholder: "%{private}ld", kind: .scalar, value: "15000"),
            LogPart(literal: " c ", placeholder: "%s", kind: .text, value: "name"),
            LogPart(literal: " d ", placeholder: "%ld", kind: .scalar, value: "3"),
            LogPart(literal: " end", placeholder: "", kind: .none, value: nil),
        ]
        #expect(LogStoreReader.message(parts) == "a shown b <private> c <private> d 3 end")
    }
}
