import Foundation
import LaciCore
import Observation

/// The four files of SPEC §5.2, named as the SPEC names them.
enum ExportKind: String, CaseIterable, Identifiable {
    case sales
    case saleLines = "sale_lines"
    case stockMovements = "stock_movements"
    case closeOuts = "close_outs"

    var id: String {
        rawValue
    }
}

enum ExportError: Error, Hashable {
    case rangeInverted
    case fetchFailed
}

/// A date range of trading days and one prepared document at a time. The range is picked as
/// days in the shop's zone; sales and close-outs match on the stored trading day, and stock
/// movements on the instants those days cover, so a 01:00 movement lands on the day before.
@MainActor
@Observable
final class ExportViewModel {
    var firstDay: Date
    var lastDay: Date
    private(set) var document: CSVExportDocument?
    private(set) var filename = ""
    private(set) var error: ExportError?

    private let sales: any SaleRepository
    private let stock: any StockRepository
    private let closeOuts: any CloseOutRepository
    private let defaults: UserDefaults
    private let tradingDay = ShopDefaults.tradingDay
    private let timeZone = ShopDefaults.timeZone

    init(dependencies: Dependencies, defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }) {
        sales = dependencies.sales
        stock = dependencies.stock
        closeOuts = dependencies.closeOuts
        self.defaults = defaults
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = tradingDay.bucket(for: now(), timeZone: timeZone)
        firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        lastDay = today
    }

    /// The picked days as trading-day keys (00:00 in the shop's zone), whatever instant the
    /// picker handed back.
    private var days: (first: Date, last: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return (calendar.startOfDay(for: firstDay), calendar.startOfDay(for: lastDay))
    }

    func text(for kind: ExportKind) throws(ExportError) -> String {
        let (first, last) = days
        guard first <= last else { throw .rangeInverted }
        let delimiter = ExportSettings.delimiter(in: defaults)
        do {
            switch kind {
            case .sales:
                let rows = try sales.sales(tradingDaysFrom: first, through: last).map(SaleExportRow.init)
                return ExportCSV.sales(rows, delimiter: delimiter, timeZone: timeZone)
            case .saleLines:
                let rows = try sales.sales(tradingDaysFrom: first, through: last).flatMap(SaleLineExportRow.rows)
                return ExportCSV.saleLines(rows, delimiter: delimiter, timeZone: timeZone)
            case .stockMovements:
                let instants = tradingDay.instants(ofDays: first, through: last, timeZone: timeZone)
                let rows = try stock.movements(from: instants.lowerBound, before: instants.upperBound)
                    .map(StockMovementExportRow.init)
                return ExportCSV.stockMovements(rows, delimiter: delimiter, timeZone: timeZone)
            case .closeOuts:
                let rows = try closeOuts.closeOuts(from: first, through: last).map(CloseOutExportRow.init)
                return ExportCSV.closeOuts(rows, delimiter: delimiter, timeZone: timeZone)
            }
        } catch {
            throw .fetchFailed
        }
    }

    /// Builds the document the exporter will present; false, with `error` set, when it cannot.
    @discardableResult
    func prepare(_ kind: ExportKind) -> Bool {
        do {
            let text = try text(for: kind)
            let (first, last) = days
            let span = ISODate.day(first, timeZone: timeZone) + "_" + ISODate.day(last, timeZone: timeZone)
            filename = "\(kind.rawValue)_\(span).csv"
            document = CSVExportDocument(text: text)
            error = nil
            return true
        } catch {
            self.error = error
            document = nil
            return false
        }
    }

    func clearDocument() {
        document = nil
    }

    func clearError() {
        error = nil
    }
}
