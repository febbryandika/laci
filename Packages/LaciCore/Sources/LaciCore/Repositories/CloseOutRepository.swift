import Foundation
import SwiftData

@MainActor
public protocol CloseOutRepository: AnyObject {
    func closeOut(on tradingDay: Date) throws -> CloseOut?
    func latest() throws -> CloseOut?
    /// A day cannot be closed twice (SPEC §3.3.5). `discrepancy` arrives computed and is stored as-is.
    func save(_ closeOut: CloseOut) throws
    /// Σ `total` of non-voided cash sales on the day: the rounded figure, which is what entered the drawer.
    func cashSales(on tradingDay: Date) throws -> Decimal
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

    public func save(_ closeOut: CloseOut) throws {
        try transactor.perform {
            if try self.closeOut(on: closeOut.tradingDay) != nil {
                throw CoreError.dayAlreadyClosed(tradingDay: closeOut.tradingDay)
            }
            context.insert(closeOut)
        }
    }

    public func cashSales(on tradingDay: Date) throws -> Decimal {
        let cash = PaymentMethod.cash.rawValue
        var descriptor = FetchDescriptor<Sale>(predicate: #Predicate {
            $0.tradingDay == tradingDay && $0.paymentMethodRaw == cash && $0.voidedAt == nil
        })
        descriptor.propertiesToFetch = [\.total]
        return try context.fetch(descriptor).reduce(0) { $0 + $1.total }
    }
}
