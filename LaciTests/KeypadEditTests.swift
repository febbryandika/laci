import Foundation
@testable import Laci
import Testing

@Suite("Keypad edit")
struct KeypadEditTests {
    @Test("Digits append")
    func digits() {
        var text = ""
        for character in "125" {
            text = KeypadEdit.apply(.digit(character), to: text)
        }
        #expect(text == "125")
    }

    @Test("A leading zero is replaced, never kept")
    func leadingZero() {
        #expect(KeypadEdit.apply(.digit("0"), to: "") == "0")
        #expect(KeypadEdit.apply(.digit("0"), to: "0") == "0")
        #expect(KeypadEdit.apply(.digit("5"), to: "0") == "5")
        #expect(KeypadEdit.apply(.digit("0"), to: "5") == "50")
    }

    @Test("Triple zero multiplies by a thousand and does nothing to nothing")
    func tripleZero() {
        #expect(KeypadEdit.apply(.tripleZero, to: "") == "")
        #expect(KeypadEdit.apply(.tripleZero, to: "0") == "0")
        #expect(KeypadEdit.apply(.tripleZero, to: "12") == "12000")
    }

    @Test("Delete drops the last digit and is safe on empty text")
    func delete() {
        #expect(KeypadEdit.apply(.delete, to: "120") == "12")
        #expect(KeypadEdit.apply(.delete, to: "") == "")
    }
}
