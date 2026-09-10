import Foundation
import LaciMoney

/// Receipt → ESC/POS bytes. Money and dates are formatted with an explicit `id_ID` locale whatever
/// the device is set to (SPEC §9): a Bandung shop with an English iPad still prints `Rp 15.000`.
public enum ReceiptRenderer {
    public static func render(_ receipt: Receipt, paper: PaperWidth) -> Data {
        var builder = ESCPOSBuilder(codepage: .cp437, columns: paper.columns)
        builder.initialize()
        header(receipt, into: &builder)
        lines(receipt.lines, into: &builder)
        totals(receipt, into: &builder)
        tender(receipt.tender, into: &builder)
        footer(receipt.footerLines, into: &builder)
        return builder.data
    }

    private static func header(_ receipt: Receipt, into builder: inout ESCPOSBuilder) {
        builder.align(.center)
        if let logo = receipt.logo {
            builder.image(logo)
        }
        builder.bold(true)
        builder.doubleHeight(true)
        builder.line(receipt.shopName)
        builder.doubleHeight(false)
        builder.bold(false)
        for line in receipt.shopLines {
            builder.line(line)
        }
        if receipt.isReprint {
            builder.line("*** CETAK ULANG ***")
        }
        builder.align(.left)
        builder.rule()
        builder.row("No. \(receipt.number)", ReceiptDateFormat.string(receipt.occurredAt, in: receipt.timeZone))
        builder.rule()
    }

    private static func lines(_ lines: [Receipt.Line], into builder: inout ESCPOSBuilder) {
        for line in lines {
            builder.row(line.name, "") // clipped, never wrapped: a wrapped name shifts every row after it
            let quantity = line.quantity.formatted(RupiahFormat.number)
            builder.row(
                "  \(quantity) \(line.unit) x \(RupiahFormat.string(line.unitPrice))",
                RupiahFormat.string(line.unitPrice.times(line.quantity))
            )
            if line.discount > .zero {
                builder.row("  Diskon", RupiahFormat.string(.zero - line.discount))
            }
        }
        builder.rule()
    }

    private static func totals(_ receipt: Receipt, into builder: inout ESCPOSBuilder) {
        builder.row("Subtotal", RupiahFormat.string(receipt.subtotal))
        if receipt.saleDiscount > .zero {
            builder.row("Diskon", RupiahFormat.string(.zero - receipt.saleDiscount))
        }
        if receipt.taxTotal > .zero {
            let percent = ((receipt.taxRate ?? 0) * 100).formatted(RupiahFormat.number)
            builder.row("PPN \(percent)%", RupiahFormat.string(receipt.taxTotal))
        }
        if receipt.roundingDelta != .zero {
            builder.row("Pembulatan", RupiahFormat.signed(receipt.roundingDelta))
        }
        builder.bold(true)
        builder.row("TOTAL", RupiahFormat.string(receipt.total))
        builder.bold(false)
    }

    private static func tender(_ tender: Receipt.Tender, into builder: inout ESCPOSBuilder) {
        switch tender {
        case let .cash(tendered, change):
            builder.row("Tunai", RupiahFormat.string(tendered))
            builder.row("Kembali", RupiahFormat.string(change))
        case let .qris(reference):
            builder.row("QRIS", reference)
        case let .transfer(reference):
            builder.row("Transfer", reference)
        }
    }

    private static func footer(_ footerLines: [String], into builder: inout ESCPOSBuilder) {
        builder.rule()
        builder.align(.center)
        for line in footerLines {
            builder.line(line)
        }
        builder.align(.left)
        builder.cut(.partial)
    }
}

/// `Rp 15.000`, `-Rp 500`, `Rp 12.350,5`. The digits come from Foundation's `id_ID` number style;
/// the `Rp ` prefix is written here because the currency style's spacing between symbol and
/// digits is CLDR data that has changed between OS versions, and a golden byte fixture cannot
/// depend on which one the build machine has.
enum RupiahFormat {
    static let locale = Locale(identifier: "id_ID")
    static let number = Decimal.FormatStyle.number.locale(locale).precision(.fractionLength(0 ... 2))

    static func string(_ money: Money) -> String {
        let magnitude = abs(money.amount).formatted(number)
        return money.amount < 0 ? "-Rp \(magnitude)" : "Rp \(magnitude)"
    }

    /// Always carries a sign, for the rounding delta line.
    static func signed(_ money: Money) -> String {
        money.amount > 0 ? "+\(string(money))" : string(money)
    }
}

/// `10/09/2025 17.26` in the shop's time zone.
enum ReceiptDateFormat {
    static func string(_ date: Date, in timeZone: TimeZone) -> String {
        let style = Date.FormatStyle(locale: RupiahFormat.locale, timeZone: timeZone)
        let day = date.formatted(style.day(.twoDigits).month(.twoDigits).year(.defaultDigits))
        let time = date.formatted(style.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return "\(day) \(time)"
    }
}
