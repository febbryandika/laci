import Foundation
import LaciCore
import Observation

/// Why a void or refund was refused. The view owns the wording.
enum CorrectionError: Hashable {
    case reasonRequired
    case alreadyVoided
    case hasRefund
    case isRefund
    case failed
}

/// One sale, its refunds, and the two corrections SPEC §3.1.6 allows. Every write goes through
/// the repository; the view model never touches a stored field.
@MainActor
@Observable
final class SaleDetailViewModel {
    let saleID: UUID
    private(set) var sale: Sale?
    /// Non-voided refunds of this sale.
    private(set) var refunds: [Sale] = []
    /// The original, when this sale is itself a refund.
    private(set) var refundedSale: Sale?
    private(set) var error: CorrectionError?
    private(set) var lastRefund: Sale?

    private let sales: any SaleRepository
    private let now: () -> Date

    init(saleID: UUID, dependencies: Dependencies, now: @escaping () -> Date = { Date() }) {
        self.saleID = saleID
        sales = dependencies.sales
        self.now = now
    }

    var canVoid: Bool {
        guard let sale else { return false }
        return sale.voidedAt == nil && refunds.isEmpty
    }

    var canRefund: Bool {
        guard let sale else { return false }
        return sale.voidedAt == nil && sale.refundsSaleID == nil && refunds.isEmpty
    }

    func load() {
        do {
            sale = try sales.sale(id: saleID)
            refunds = try sales.refunds(of: saleID)
            refundedSale = try sale?.refundsSaleID.flatMap { try sales.sale(id: $0) }
        } catch {
            sale = nil
            refunds = []
            refundedSale = nil
            self.error = .failed
        }
    }

    /// The blank check lives here so an empty reason never reaches the store (SPEC §3.1.5 spirit).
    func void(reason: String) {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = .reasonRequired
            return
        }
        perform { try sales.void(saleID: saleID, reason: trimmed, occurredAt: now()) }
    }

    func refund() {
        perform {
            lastRefund = try sales.refund(
                saleID: saleID, occurredAt: now(), tradingDay: ShopDefaults.tradingDay, timeZone: ShopDefaults.timeZone
            )
        }
    }

    func clearError() {
        error = nil
    }

    private func perform(_ correction: () throws -> Void) {
        do {
            try correction()
            error = nil
        } catch let failure as CoreError {
            error = Self.map(failure)
        } catch {
            self.error = .failed
        }
        load()
    }

    private static func map(_ error: CoreError) -> CorrectionError {
        switch error {
        case .voidReasonRequired: .reasonRequired
        case .saleAlreadyVoided: .alreadyVoided
        case .saleHasLiveRefund: .hasRefund
        case .saleIsRefund: .isRefund
        default: .failed
        }
    }
}
