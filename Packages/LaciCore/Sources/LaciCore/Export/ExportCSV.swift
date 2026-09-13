import Foundation

/// The four exports of SPEC §5.2. Money and quantities are unformatted decimal strings, instants
/// are ISO 8601 in the shop's zone, trading days are `yyyy-MM-dd`, and an absent optional is an
/// empty field. The delimiter is the caller's: Indonesian-locale Excel splits on `;`.
public enum ExportCSV {
    public static let salesColumns = [
        "number", "id", "occurred_at", "trading_day", "subtotal", "discount_total", "tax_total", "rounding_delta",
        "total", "payment_method", "amount_tendered", "change_given", "reference", "voided_at", "void_reason",
        "refunds_sale_id", "receipt_failed_at",
    ]
    public static let saleLinesColumns = [
        "sale_number", "sale_id", "product_sku", "name", "quantity", "unit_price", "list_price", "discount_amount",
        "line_total",
    ]
    public static let stockMovementsColumns = ["occurred_at", "product_sku", "delta", "reason", "sale_id", "note"]
    public static let closeOutsColumns = [
        "trading_day", "opening_float", "cash_sales", "cash_refunds", "payouts", "expected_drawer",
        "counted_drawer", "discrepancy", "note", "closed_at", "attribution",
    ]

    public static func sales(_ rows: [SaleExportRow], delimiter: Character, timeZone: TimeZone) -> String {
        CSVWriter.document(columns: salesColumns, rows: rows.map { row in
            [
                String(row.number), row.id.uuidString, ISODate.timestamp(row.occurredAt, timeZone: timeZone),
                ISODate.day(row.tradingDay, timeZone: timeZone), "\(row.subtotal)", "\(row.discountTotal)",
                "\(row.taxTotal)", "\(row.roundingDelta)", "\(row.total)", row.paymentMethod,
                decimal(row.amountTendered), decimal(row.changeGiven), row.reference ?? "",
                instant(row.voidedAt, timeZone), row.voidReason ?? "", row.refundsSaleID?.uuidString ?? "",
                instant(row.receiptFailedAt, timeZone),
            ]
        }, delimiter: delimiter)
    }

    public static func saleLines(_ rows: [SaleLineExportRow], delimiter: Character, timeZone _: TimeZone) -> String {
        CSVWriter.document(columns: saleLinesColumns, rows: rows.map { row in
            [
                String(row.saleNumber), row.saleID.uuidString, row.productSKU, row.name, "\(row.quantity)",
                "\(row.unitPrice)", "\(row.listPrice)", "\(row.discountAmount)", "\(row.lineTotal)",
            ]
        }, delimiter: delimiter)
    }

    public static func stockMovements(
        _ rows: [StockMovementExportRow], delimiter: Character, timeZone: TimeZone
    ) -> String {
        CSVWriter.document(columns: stockMovementsColumns, rows: rows.map { row in
            [
                ISODate.timestamp(row.occurredAt, timeZone: timeZone), row.productSKU, "\(row.delta)", row.reason,
                row.saleID?.uuidString ?? "", row.note ?? "",
            ]
        }, delimiter: delimiter)
    }

    public static func closeOuts(_ rows: [CloseOutExportRow], delimiter: Character, timeZone: TimeZone) -> String {
        CSVWriter.document(columns: closeOutsColumns, rows: rows.map { row in
            [
                ISODate.day(row.tradingDay, timeZone: timeZone), "\(row.openingFloat)", "\(row.cashSales)",
                "\(row.cashRefunds)", "\(row.payouts)", "\(row.expectedDrawer)", "\(row.countedDrawer)",
                "\(row.discrepancy)", row.note ?? "", ISODate.timestamp(row.closedAt, timeZone: timeZone),
                row.attribution ?? "",
            ]
        }, delimiter: delimiter)
    }

    private static func decimal(_ value: Decimal?) -> String {
        value.map { "\($0)" } ?? ""
    }

    private static func instant(_ value: Date?, _ timeZone: TimeZone) -> String {
        value.map { ISODate.timestamp($0, timeZone: timeZone) } ?? ""
    }
}
