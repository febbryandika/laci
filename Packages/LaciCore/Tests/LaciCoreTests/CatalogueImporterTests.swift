import Foundation
import LaciCore
import SwiftData
import Testing

@MainActor
@Suite("Catalogue importer")
struct CatalogueImporterTests {
    static let header = "sku,name,unit,cost,price,tracks_stock,stock_on_hand,barcodes"

    let store: TestStore
    let products: SwiftDataProductRepository
    let stock: SwiftDataStockRepository
    let importer: CatalogueImporter
    let epoch = Date(timeIntervalSince1970: 0)

    init() throws {
        store = try TestStore()
        let transactor = Transactor(container: store.container)
        products = SwiftDataProductRepository(transactor: transactor)
        stock = SwiftDataStockRepository(transactor: transactor)
        importer = CatalogueImporter(products: products, stock: stock, transactor: transactor)
    }

    func preview(_ body: String) throws -> ImportPreview {
        try importer.preview(CatalogueCSV.parse("\(Self.header)\n\(body)\n"))
    }

    @Test("Preview classifies new SKUs as added, existing as updated, and a taken barcode as rejected")
    func classification() throws {
        try products.create(makeProduct("OLD"))
        try products.create(makeProduct("OWNER"))
        try products.addBarcode("5901234123457", symbology: .ean13, to: "OWNER")
        let preview = try preview("""
        NEW,Indomie,pcs,2500,3000,true,10,
        OLD,Indomie Renamed,pcs,2500,3000,true,10,
        CLASH,Clash,pcs,1,2,true,0,5901234123457
        """)
        #expect(preview.added.map(\.sku) == ["NEW"])
        #expect(preview.updated.map(\.sku) == ["OLD"])
        #expect(preview.rejected.map(\.sku) == ["CLASH"])
        #expect(preview.rejected.first?.reason == .barcodeTaken(value: "5901234123457", bySKU: "OWNER"))
    }

    @Test("Preview passes parser rejections through untouched")
    func parserRejectionsSurvive() throws {
        let preview = try preview("BAD,Indomie,pcs,abc,3000,true,10,")
        #expect(preview.added.isEmpty)
        #expect(preview.rejected.count == 1)
        #expect(preview.rejected.first?.line == 2)
    }

    @Test("Committing an added row creates the product, its barcodes and a stock_in movement when stocked")
    func commitAdded() throws {
        let preview = try preview("""
        A,Indomie,pcs,2500,3000,true,12,5901234123457|96385074
        B,Pulsa 10k,pcs,10000,12000,false,0,
        """)
        try importer.commit(preview, now: epoch)

        let created = try #require(try products.product(sku: "A"))
        #expect(created.stockOnHand == 12)
        #expect(created.updatedAt == epoch)
        #expect(Set(created.barcodes.map(\.value)) == ["5901234123457", "96385074"])
        #expect(created.barcodes.first { $0.value == "96385074" }?.symbologyKind == .ean8)
        let movements = try stock.movements(for: "A", limit: 10)
        #expect(movements.map(\.delta) == [12])
        #expect(movements.first?.reasonRaw == "stock_in")
        #expect(try stock.movements(for: "B", limit: 10).isEmpty)
    }

    @Test("Committing an updated row overwrites the catalogue fields, keeps stock and adds only new barcodes")
    func commitUpdated() throws {
        try products.create(makeProduct("A", stockOnHand: 7, price: 3000))
        try products.addBarcode("5901234123457", symbology: .ean13, to: "A")
        let preview = try preview("A,Indomie Goreng,bungkus,2700,3500,false,99,5901234123457|96385074")
        try importer.commit(preview, now: epoch)

        let updated = try #require(try products.product(sku: "A"))
        #expect(updated.name == "Indomie Goreng")
        #expect(updated.unit == "bungkus")
        #expect(updated.cost == 2700)
        #expect(updated.price == 3500)
        #expect(updated.tracksStock == false)
        #expect(updated.stockOnHand == 7)
        #expect(updated.updatedAt == epoch)
        #expect(Set(updated.barcodes.map(\.value)) == ["5901234123457", "96385074"])
        #expect(try stock.movements(for: "A", limit: 10).isEmpty)
    }

    @Test("A barcode taken between preview and commit rolls the whole batch back")
    func commitIsAtomic() throws {
        try products.create(makeProduct("OWNER"))
        let preview = try preview("""
        A,One,pcs,1,2,true,5,
        B,Two,pcs,1,2,true,5,96385074
        """)
        try products.addBarcode("96385074", symbology: .ean8, to: "OWNER")

        #expect(throws: CoreError.barcodeTaken(value: "96385074", existingSKU: "OWNER")) {
            try importer.commit(preview, now: epoch)
        }
        let fresh = ModelContext(store.container)
        #expect(try fresh.fetchCount(FetchDescriptor<Product>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<StockMovement>()) == 0)
    }

    @Test("Export then re-import previews as all updated with nothing rejected")
    func exportRoundTrip() throws {
        let preview = try preview("""
        A,"Mie Sedaap ""Ayam Krispi"" Goreng",pcs,2500,3000,true,12,5901234123457
        B,Susu Bendera Coklat 115ml x 6,pcs,10000,12000,true,3,
        """)
        try importer.commit(preview, now: epoch)

        let rows = try products.all(includeArchived: true).map(CatalogueRow.init)
        let text = CatalogueCSV.export(rows)
        let again = try importer.preview(CatalogueCSV.parse(text))
        #expect(again.rejected.isEmpty)
        #expect(again.added.isEmpty)
        #expect(again.updated.map(\.sku) == ["A", "B"])
        #expect(again.updated.first?.name == "Mie Sedaap \"Ayam Krispi\" Goreng")
    }
}
