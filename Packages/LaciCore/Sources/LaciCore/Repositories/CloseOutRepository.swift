import Foundation
import SwiftData

@MainActor
public protocol CloseOutRepository: AnyObject {
    func closeOut(on tradingDay: Date) throws -> CloseOut?
    func latest() throws -> CloseOut?
    /// A day cannot be closed twice (SPEC §3.3.5). `discrepancy` arrives computed and is stored as-is.
    /// `cashRemoved` is the closing setoran (SPEC §3.3.4): taken out after the count, so it is not in
    /// `closeOut.payouts`; when non-zero it is recorded as a setoran `Payout` dated `closedAt`, in the
    /// same transaction as the row.
    func save(_ closeOut: CloseOut, cashRemoved: Decimal) throws
    /// Payouts recorded on the day, oldest first.
    func payouts(on tradingDay: Date) throws -> [Payout]
    /// Σ `amount` of every payout on the day, the closing setoran included once the day is closed.
    func payoutsTotal(on tradingDay: Date) throws -> Decimal
    /// Both refuse a closed day: a payout recorded after the close-out was computed is a SPEC §10 failure.
    func addPayout(_ payout: Payout) throws
    func deletePayout(_ payout: Payout) throws
    /// Tomorrow's opening float (SPEC §3.3.4): the latest counted drawer minus what was removed after
    /// the count, which is every payout on that day not already in `CloseOut.payouts`. `nil` before the
    /// first close-out, when the cashier must enter the float.
    func nextOpeningFloat() throws -> Decimal?
    /// SPEC §10: set on a saved close-out, with the owner on the phone; `nil` clears it.
    func setAttribution(on tradingDay: Date, _ attribution: Attribution?) throws
    /// Σ `total` of non-voided cash sales on the day, refunds excluded: the rounded figure, which is
    /// what entered the drawer.
    func cashSales(on tradingDay: Date) throws -> Decimal
    /// Σ of what non-voided cash refunds on the day paid out of the drawer, as a positive figure.
    /// Feeds `DrawerInputs.cashRefunds`; a refund netted into `cashSales` is the SPEC §10 failure.
    func cashRefunds(on tradingDay: Date) throws -> Decimal
}

@MainActor
public final class SwiftDataCloseOutRepository: CloseOutRepository {
    private let transactor: Transactor
    private var context: ModelContext {
        transactor.context
    }

    public init(transactor: Transactor) {
        self.transactor = transactor
    }

    public func closeOut(on tradingDay: Date) throws -> CloseOut? {
        var descriptor = FetchDescriptor<CloseOut>(predicate: #Predicate { $0.tradingDay == tradingDay })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func latest() throws -> CloseOut? {
        var descriptor = FetchDescriptor<CloseOut>(sortBy: [SortDescriptor(\.tradingDay, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func save(_ closeOut: CloseOut, cashRemoved: Decimal) throws {
        try transactor.perform {
            try assertOpen(closeOut.tradingDay)
            context.insert(closeOut)
            if cashRemoved > 0 {
                context.insert(Payout(
                    tradingDay: closeOut.tradingDay, kind: .setoran, amount: cashRemoved, note: "Setoran",
                    occurredAt: closeOut.closedAt
                ))
            }
        }
    }

    public func payouts(on tradingDay: Date) throws -> [Payout] {
        let descriptor = FetchDescriptor<Payout>(
            predicate: #Predicate { $0.tradingDay == tradingDay }, sortBy: [SortDescriptor(\.occurredAt)]
        )
        return try context.fetch(descriptor)
    }

    public func payoutsTotal(on tradingDay: Date) throws -> Decimal {
        var descriptor = FetchDescriptor<Payout>(predicate: #Predicate { $0.tradingDay == tradingDay })
        descriptor.propertiesToFetch = [\.amount]
        return try context.fetch(descriptor).reduce(0) { $0 + $1.amount }
    }

    public func addPayout(_ payout: Payout) throws {
        try transactor.perform {
            try assertOpen(payout.tradingDay)
            context.insert(payout)
        }
    }

    public func deletePayout(_ payout: Payout) throws {
        try transactor.perform {
            try assertOpen(payout.tradingDay)
            context.delete(payout)
        }
    }

    public func nextOpeningFloat() throws -> Decimal? {
        guard let latest = try latest() else { return nil }
        let removedAfterCount = try payoutsTotal(on: latest.tradingDay) - latest.payouts
        return latest.countedDrawer - removedAfterCount
    }

    public func setAttribution(on tradingDay: Date, _ attribution: Attribution?) throws {
        try transactor.perform {
            guard let closeOut = try self.closeOut(on: tradingDay) else {
                throw CoreError.closeOutNotFound(tradingDay: tradingDay)
            }
            closeOut.attribution = attribution?.rawValue
        }
    }

    private func assertOpen(_ tradingDay: Date) throws {
        if try closeOut(on: tradingDay) != nil {
            throw CoreError.dayAlreadyClosed(tradingDay: tradingDay)
        }
    }

    public func cashSales(on tradingDay: Date) throws -> Decimal {
        let cash = PaymentMethod.cash.rawValue
        var descriptor = FetchDescriptor<Sale>(predicate: #Predicate {
            $0.tradingDay == tradingDay && $0.paymentMethodRaw == cash && $0.voidedAt == nil
                && $0.refundsSaleID == nil
        })
        descriptor.propertiesToFetch = [\.total]
        return try context.fetch(descriptor).reduce(0) { $0 + $1.total }
    }

    public func cashRefunds(on tradingDay: Date) throws -> Decimal {
        let cash = PaymentMethod.cash.rawValue
        var descriptor = FetchDescriptor<Sale>(predicate: #Predicate {
            $0.tradingDay == tradingDay && $0.paymentMethodRaw == cash && $0.voidedAt == nil
                && $0.refundsSaleID != nil
        })
        descriptor.propertiesToFetch = [\.total]
        return try context.fetch(descriptor).reduce(0) { $0 - $1.total }
    }
}
