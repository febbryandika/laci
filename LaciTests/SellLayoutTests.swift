import Foundation
@testable import Laci
import SwiftUI
import Testing

@MainActor
@Suite("Sell layout")
struct SellLayoutTests {
    @Test("A full-width iPad at a reading size shows three panes", arguments: [
        DynamicTypeSize.xSmall, .large, .xxxLarge, .accessibility1, .accessibility2,
    ])
    func threePanes(size: DynamicTypeSize) {
        #expect(SellLayout.resolve(horizontal: .regular, vertical: .regular, dynamicTypeSize: size) == .threePane)
    }

    @Test("From AX3 the catalogue pane folds away and two panes remain", arguments: [
        DynamicTypeSize.accessibility3, .accessibility4, .accessibility5,
    ])
    func twoPanes(size: DynamicTypeSize) {
        #expect(SellLayout.resolve(horizontal: .regular, vertical: .regular, dynamicTypeSize: size) == .twoPane)
    }

    @Test("Anything narrower or shorter than a full iPad is the iPhone layout")
    func compact() {
        #expect(SellLayout.resolve(horizontal: .compact, vertical: .regular, dynamicTypeSize: .large) == .compact)
        #expect(SellLayout.resolve(horizontal: .regular, vertical: .compact, dynamicTypeSize: .large) == .compact)
        #expect(SellLayout.resolve(horizontal: .compact, vertical: .compact, dynamicTypeSize: .large) == .compact)
        #expect(SellLayout.resolve(horizontal: nil, vertical: nil, dynamicTypeSize: .accessibility5) == .compact)
    }

    @Test("Which panes each layout shows")
    func panes() {
        #expect(SellLayout.threePane.showsCataloguePane)
        #expect(SellLayout.threePane.showsTenderPane)
        #expect(!SellLayout.twoPane.showsCataloguePane)
        #expect(SellLayout.twoPane.showsTenderPane)
        #expect(!SellLayout.compact.showsCataloguePane)
        #expect(!SellLayout.compact.showsTenderPane)
    }
}
