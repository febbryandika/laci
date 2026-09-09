import Foundation
import LaciCore
import LaciMoney
import Observation

/// Why a close-out step was refused. The view owns the wording.
enum CloseOutError: Hashable {
    case countInvalid
    case openingFloatRequired
    case amountInvalid
    case noteRequired
    case cashRemovedExceedsCount
    case countRequired
    /// A sale, refund or payout landed after the count was confirmed; count again (SPEC §10).
    case figuresChanged
    case alreadyClosed
    case failed
}

/// The close-out screen (SPEC §3.3). `inputs` and `result` do not exist until `enterCount()`, so
/// before the count is confirmed there is no expected figure anywhere in the view model to show.
/// Every figure is fetched from the repository or produced by `CloseOutEngine.reconcile`; the only
/// arithmetic here is comparing a discrepancy with the threshold.
@MainActor
@Observable
final class CloseOutViewModel {
    /// The day this screen closes: the first day after the last close-out, at the latest today.
    private(set) var targetDay: Date
    /// The target is before today: an earlier day was never closed (SPEC §3.3.5).
    private(set) var isPriorDay = false
    /// Set when the target day is already closed, including right after `save`.
    private(set) var closeOut: CloseOut?
    private(set) var latestClosed: CloseOut?
    /// No close-out exists yet, so the float cannot be carried forward and must be entered.
    private(set) var needsOpeningFloat = false
    private(set) var payouts: [Payout] = []
    private(set) var inputs: DrawerInputs?
    private(set) var result: DrawerResult?
    private(set) var error: CloseOutError?
    var openingFloatText = ""
    var countedText = ""

    private let closeOuts: any CloseOutRepository
    private let now: () -> Date
    private let threshold: Money

    init(
        dependencies: Dependencies, now: @escaping () -> Date = { Date() },
        threshold: Money = ShopDefaults.discrepancyThreshold
    ) {
        closeOuts = dependencies.closeOuts
        self.now = now
        self.threshold = threshold
        targetDay = Self.today(now())
    }

    /// Days are closed in sequence: the day after the last close-out comes first, and never a
    /// day that has not started. With no close-out at all, today.
    static func targetDay(latest: Date?, today: Date) -> Date {
        guard let latest else { return today }
        return min(ShopDefaults.tradingDay.next(after: latest, timeZone: ShopDefaults.timeZone), today)
    }

    func load() {
        do {
            let today = Self.today(now())
            latestClosed = try closeOuts.latest()
            targetDay = Self.targetDay(latest: latestClosed?.tradingDay, today: today)
            isPriorDay = targetDay < today
            closeOut = try closeOuts.closeOut(on: targetDay)
            payouts = try closeOuts.payouts(on: targetDay)
            needsOpeningFloat = try closeOuts.nextOpeningFloat() == nil
        } catch {
            self.error = .failed
        }
    }

    // MARK: Count

    func enterCount() {
        guard let counted = DecimalInput.parse(countedText) else { return fail(.countInvalid) }
        do {
            let openingFloat: Decimal
            if let carried = try closeOuts.nextOpeningFloat() {
                openingFloat = carried
            } else if let entered = DecimalInput.parse(openingFloatText) {
                openingFloat = entered
            } else {
                return fail(.openingFloatRequired)
            }
            let inputs = try figures(openingFloat: openingFloat)
            self.inputs = inputs
            result = CloseOutEngine.reconcile(inputs, counted: Money(counted))
            error = nil
        } catch {
            fail(.failed)
        }
    }

    /// Back to counting: the figures disappear until the count is confirmed again.
    func changeCount() {
        inputs = nil
        result = nil
    }

    // MARK: Payouts

    func addPayout(kind: PayoutKind, amountText: String, note: String) {
        guard let amount = DecimalInput.parse(amountText), amount > 0 else { return fail(.amountInvalid) }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fail(.noteRequired) }
        let payout = Payout(tradingDay: targetDay, kind: kind, amount: amount, note: trimmed, occurredAt: now())
        perform { try closeOuts.addPayout(payout) }
    }

    func deletePayout(_ payout: Payout) {
        perform { try closeOuts.deletePayout(payout) }
    }

    // MARK: Save

    /// `cashRemovedText` is the closing setoran (SPEC §3.3.4); blank means nothing was taken.
    func save(note: String, cashRemovedText: String) {
        guard let inputs, let result else { return fail(.countRequired) }
        let cashRemoved: Decimal
        if cashRemovedText.trimmingCharacters(in: .whitespaces).isEmpty {
            cashRemoved = 0
        } else if let parsed = DecimalInput.parse(cashRemovedText) {
            cashRemoved = parsed
        } else {
            return fail(.amountInvalid)
        }
        guard cashRemoved <= result.counted.amount else { return fail(.cashRemovedExceedsCount) }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.discrepancy.amount.magnitude > threshold.amount, trimmedNote.isEmpty {
            return fail(.noteRequired)
        }
        do {
            // The figures the cashier acknowledged are the ones that get stored; if anything moved
            // since the count was confirmed, the count is no longer against this day.
            guard try figures(openingFloat: inputs.openingFloat.amount) == inputs else {
                changeCount()
                return fail(.figuresChanged)
            }
        } catch {
            return fail(.failed)
        }
        let row = CloseOut(
            tradingDay: targetDay, openingFloat: inputs.openingFloat.amount, cashSales: inputs.cashSales.amount,
            cashRefunds: inputs.cashRefunds.amount, payouts: inputs.payouts.amount,
            expectedDrawer: result.expected.amount, countedDrawer: result.counted.amount,
            discrepancy: result.discrepancy.amount, note: trimmedNote.isEmpty ? nil : trimmedNote,
            closedAt: now(), attribution: nil
        )
        perform { try closeOuts.save(row, cashRemoved: cashRemoved) }
    }

    func clearError() {
        error = nil
    }

    // MARK: Private

    private static func today(_ date: Date) -> Date {
        ShopDefaults.tradingDay.bucket(for: date, timeZone: ShopDefaults.timeZone)
    }

    private func figures(openingFloat: Decimal) throws -> DrawerInputs {
        try DrawerInputs(
            openingFloat: Money(openingFloat),
            cashSales: Money(closeOuts.cashSales(on: targetDay)),
            cashRefunds: Money(closeOuts.cashRefunds(on: targetDay)),
            payouts: Money(closeOuts.payoutsTotal(on: targetDay))
        )
    }

    private func fail(_ failure: CloseOutError) {
        error = failure
    }

    /// A write changes the figures, so any confirmed count is discarded and the day is reloaded.
    private func perform(_ write: () throws -> Void) {
        do {
            try write()
            error = nil
        } catch let failure as CoreError {
            error = Self.map(failure)
        } catch {
            self.error = .failed
        }
        changeCount()
        load()
    }

    private static func map(_ error: CoreError) -> CloseOutError {
        switch error {
        case .dayAlreadyClosed: .alreadyClosed
        default: .failed
        }
    }
}
