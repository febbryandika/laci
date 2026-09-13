import Foundation
import LaciCore
import SwiftData
import Testing

@Suite("Export CSV codecs")
struct ExportCSVTests {
    static let saleID = UUID(uuidString: "0B9A8E2C-6C1D-4E3B-9F2A-1D2E3F4A5B6C")!
    static let utc = TimeZone(identifier: "UTC")!

    static func sale(
        occurredAt: Date, reference: String? = nil, voidedAt: Date? = nil, voidReason: String? = nil
    ) throws -> SaleExportRow {
        try SaleExportRow(
            number: 7, id: saleID, occurredAt: occurredAt, tradingDay: wib(2026, 9, 13), subtotal: dec("15000.5"),
            discountTotal: 0, taxTotal: 0, roundingDelta: dec("-0.5"), total: 15000, paymentMethod: "cash",
            amountTendered: 20000, changeGiven: 5000, reference: reference, voidedAt: voidedAt,
            voidReason: voidReason, refundsSaleID: nil, receiptFailedAt: nil
        )
    }

    static func lines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    @Test("Each document starts with its fixed header")
    func headersMatchSpec() {
        let sales = ExportCSV.sales([], delimiter: ",", timeZone: jakarta)
        let lines = ExportCSV.saleLines([], delimiter: ",", timeZone: jakarta)
        let movements = ExportCSV.stockMovements([], delimiter: ",", timeZone: jakarta)
        let closeOuts = ExportCSV.closeOuts([], delimiter: ",", timeZone: jakarta)
        #expect(sales == ExportCSV.salesColumns.joined(separator: ",") + "\n")
        #expect(lines == ExportCSV.saleLinesColumns.joined(separator: ",") + "\n")
        #expect(movements == ExportCSV.stockMovementsColumns.joined(separator: ",") + "\n")
        #expect(closeOuts == ExportCSV.closeOutsColumns.joined(separator: ",") + "\n")
        #expect(ExportCSV.salesColumns.count == 17)
        #expect(ExportCSV.closeOutsColumns.first == "trading_day")
    }

    @Test("Money is an unformatted decimal string, never grouped or localised")
    func moneyIsUnformatted() throws {
        let row = try Self.sale(occurredAt: wib(2026, 9, 13, 15, 4, second: 5))
        let text = ExportCSV.sales([row], delimiter: ",", timeZone: jakarta)
        let fields = Self.lines(text)[1].split(separator: ",", omittingEmptySubsequences: false)
        #expect(fields[4] == "15000.5")
        #expect(fields[7] == "-0.5")
        #expect(fields[8] == "15000")
        #expect(fields[10] == "20000")
        #expect(!text.contains("15.000"))
    }

    @Test("A field holding the delimiter, a quote or a newline is quoted; nothing else is")
    func delimiterQuoteAndNewlineAreEscaped() throws {
        let row = try StockMovementExportRow(
            occurredAt: wib(2026, 9, 13, 8), productSKU: "A", delta: -2, reason: "waste", saleID: nil,
            note: "basah, \"rusak\"\ndibuang"
        )
        let comma = ExportCSV.stockMovements([row], delimiter: ",", timeZone: jakarta)
        #expect(comma.hasSuffix(",A,-2,waste,,\"basah, \"\"rusak\"\"\ndibuang\"\n"))

        let semicolon = ExportCSV.stockMovements([row], delimiter: ";", timeZone: jakarta)
        #expect(semicolon.hasSuffix(";A;-2;waste;;\"basah, \"\"rusak\"\"\ndibuang\"\n"))

        let plain = try StockMovementExportRow(
            occurredAt: wib(2026, 9, 13, 8), productSKU: "A", delta: 1, reason: "stock_in", saleID: nil,
            note: "kiriman; pagi"
        )
        #expect(ExportCSV.stockMovements([plain], delimiter: ",", timeZone: jakarta).hasSuffix(",kiriman; pagi\n"))
        #expect(ExportCSV.stockMovements([plain], delimiter: ";", timeZone: jakarta).hasSuffix(";\"kiriman; pagi\"\n"))
    }

    @Test("The semicolon delimiter joins the header and every row")
    func semicolonDelimiterJoinsFields() throws {
        let row = try CloseOutExportRow(
            tradingDay: wib(2026, 9, 13), openingFloat: 200_000, cashSales: 350_000, cashRefunds: 0,
            payouts: 50000, expectedDrawer: 500_000, countedDrawer: 495_000, discrepancy: -5000, note: "kurang",
            closedAt: wib(2026, 9, 13, 21, 5), attribution: "operator"
        )
        let lines = Self.lines(ExportCSV.closeOuts([row], delimiter: ";", timeZone: jakarta))
        #expect(lines[0] == ExportCSV.closeOutsColumns.joined(separator: ";"))
        let expected = "2026-09-13;200000;350000;0;50000;500000;495000;-5000;kurang;2026-09-13T21:05:00+07:00;operator"
        #expect(lines[1] == expected)
        #expect(!lines[1].contains(","))
    }

    @Test("Instants carry the shop zone's offset, whatever the zone")
    func timestampsCarryShopOffset() throws {
        let instant = try wib(2026, 9, 13, 15, 4, second: 5)
        #expect(ISODate.timestamp(instant, timeZone: jakarta) == "2026-09-13T15:04:05+07:00")
        #expect(ISODate.timestamp(instant, timeZone: Self.utc) == "2026-09-13T08:04:05+00:00")
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        #expect(ISODate.timestamp(instant, timeZone: newYork) == "2026-09-13T04:04:05-04:00")
        #expect(ISODate.compact(instant, timeZone: jakarta) == "20260913-150405")
    }

    @Test("A trading day prints as the shop's calendar date, not the UTC date")
    func tradingDayPrintsShopDate() throws {
        let day = try wib(2026, 9, 13) // 17:00 UTC on the 12th
        #expect(ISODate.day(day, timeZone: jakarta) == "2026-09-13")
        #expect(ISODate.day(day, timeZone: Self.utc) == "2026-09-12")
        let row = try Self.sale(occurredAt: wib(2026, 9, 13, 10))
        let fields = Self.lines(ExportCSV.sales([row], delimiter: ",", timeZone: jakarta))[1].split(
            separator: ",", omittingEmptySubsequences: false
        )
        #expect(fields[3] == "2026-09-13")
    }

    @Test("An absent optional is an empty field; a present one is written in full")
    func optionalsAreEmpty() throws {
        let open = try Self.sale(occurredAt: wib(2026, 9, 13, 10))
        let voided = try Self.sale(
            occurredAt: wib(2026, 9, 13, 10), reference: "INV-1", voidedAt: wib(2026, 9, 13, 11, 30),
            voidReason: "salah input"
        )
        let lines = Self.lines(ExportCSV.sales([open, voided], delimiter: ",", timeZone: jakarta))
        #expect(lines[1].hasSuffix(",cash,20000,5000,,,,,\n".dropLast()))
        #expect(lines[2].hasSuffix(",cash,20000,5000,INV-1,2026-09-13T11:30:00+07:00,salah input,,"))
        #expect(lines[1].hasPrefix("7,0B9A8E2C-6C1D-4E3B-9F2A-1D2E3F4A5B6C,2026-09-13T10:00:00+07:00,"))
    }

    @Test("A stock movement's sale id and note are written when present")
    func movementOptionals() throws {
        let row = try StockMovementExportRow(
            occurredAt: wib(2026, 9, 13, 8), productSKU: "A", delta: -1, reason: "sale", saleID: Self.saleID,
            note: nil
        )
        let text = ExportCSV.stockMovements([row], delimiter: ",", timeZone: jakarta)
        #expect(Self.lines(text)[1] == "2026-09-13T08:00:00+07:00,A,-1,sale,0B9A8E2C-6C1D-4E3B-9F2A-1D2E3F4A5B6C,")
    }
}

@MainActor
@Suite("Export rows from the store")
struct ExportRowsTests {
    let store: TestStore
    let products: SwiftDataProductRepository
    let sales: SwiftDataSaleRepository

    init() throws {
        store = try TestStore()
        let transactor = Transactor(container: store.container)
        products = SwiftDataProductRepository(transactor: transactor)
        sales = SwiftDataSaleRepository(transactor: transactor)
    }

    @Test("Sale lines export sorted by SKU with the sale's number and id on every row")
    func saleLinesSortedBySKU() throws {
        try products.create(makeProduct("B"))
        try products.create(makeProduct("A"))
        try products.create(makeProduct("C"))
        let draft = try cashDraft([line("C", qty: 2), line("A"), line("B", qty: 3)])
        let sale = try sales.commit(draft, tradingDay: TradingDay(cutoverHour: 4), timeZone: jakarta)

        let rows = SaleLineExportRow.rows(of: sale)
        #expect(rows.map(\.productSKU) == ["A", "B", "C"])
        #expect(rows.map(\.quantity) == [1, 3, 2])
        #expect(rows.allSatisfy { $0.saleNumber == sale.number && $0.saleID == sale.id })

        let exported = SaleExportRow(sale)
        #expect(exported.number == sale.number)
        #expect(exported.paymentMethod == "cash")
        #expect(exported.total == sale.total)
        #expect(exported.voidedAt == nil)
    }
}
