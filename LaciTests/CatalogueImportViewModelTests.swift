import Foundation
@testable import Laci
import LaciCore
import Testing

private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
private let header = "sku,name,unit,cost,price,tracks_stock,stock_on_hand,barcodes"
private let twoRows = """
\(header)
W001,Indomie Goreng 85g,bungkus,2800,3500,true,5,8991128170404
W002,Aqua 600ml,pcs,2500,3500,true,0,
"""

@MainActor
@Suite("Catalogue import view model")
struct CatalogueImportViewModelTests {
    let dependencies: Dependencies
    let viewModel: CatalogueImportViewModel

    init() throws {
        dependencies = try Dependencies.inMemory()
        viewModel = CatalogueImportViewModel(dependencies: dependencies, delimiter: ",", now: { fixedNow })
    }

    @Test("A valid file previews as additions and writes nothing until committed")
    func previewThenCommit() throws {
        viewModel.preview(text: twoRows)
        guard case let .previewed(preview) = viewModel.phase else {
            Issue.record("expected a preview, got \(viewModel.phase)")
            return
        }
        #expect(preview.added.count == 2)
        #expect(preview.updated.isEmpty)
        #expect(preview.rejected.isEmpty)
        let before = try dependencies.products.all(includeArchived: false)
        #expect(before.isEmpty)

        viewModel.commit()
        #expect(viewModel.phase == .done(added: 2, updated: 0))
        let after = try dependencies.products.all(includeArchived: false)
        #expect(after.map(\.sku) == ["W002", "W001"])
        let indomie = try #require(after.first { $0.sku == "W001" })
        #expect(indomie.stockOnHand == 5)
        #expect(indomie.barcodes.map(\.value) == ["8991128170404"])
    }

    @Test("The same file again previews as updates")
    func secondImportUpdates() {
        viewModel.preview(text: twoRows)
        viewModel.commit()
        viewModel.preview(text: twoRows)
        guard case let .previewed(preview) = viewModel.phase else {
            Issue.record("expected a preview, got \(viewModel.phase)")
            return
        }
        #expect(preview.added.isEmpty)
        #expect(preview.updated.count == 2)
    }

    @Test("A wrong header fails before any classification")
    func headerMismatch() {
        viewModel.preview(text: "sku,name\nA,B\n")
        guard case let .failed(failure) = viewModel.phase else {
            Issue.record("expected a failure, got \(viewModel.phase)")
            return
        }
        #expect(failure == .parse(.headerMismatch(found: ["sku", "name"])))
        let message = localized(failure.message)
        let expected = CatalogueCSV.columns.joined(separator: ", ")
        #expect(message == "Kolom tidak sesuai. Diharapkan: \(expected). Ditemukan: sku, name")
    }

    @Test("A rejected row is listed with its line and stays out of the commit")
    func rejectedRow() {
        viewModel.preview(text: "\(header)\nW001,Indomie,bungkus,2800,3500,true,5,\nW001,Ganda,pcs,1,2,true,0,\n")
        guard case let .previewed(preview) = viewModel.phase else {
            Issue.record("expected a preview, got \(viewModel.phase)")
            return
        }
        #expect(preview.added.isEmpty)
        #expect(preview.rejected.map(\.line) == [2, 3])
        #expect(localized(ImportErrorText.label(preview.rejected[0].reason)) == "SKU muncul dua kali dalam berkas")
    }

    @Test("Commit without a preview does nothing")
    func commitWithoutPreview() {
        viewModel.commit()
        #expect(viewModel.phase == .picking)
    }
}
