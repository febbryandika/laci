import Foundation
import LaciCore
import Observation

/// One saved close-out, read straight from the row (SPEC §4: `discrepancy` is stored, never
/// recomputed), plus the SPEC §10 attribution the owner sets afterwards.
@MainActor
@Observable
final class CloseOutDetailViewModel {
    let tradingDay: Date
    private(set) var closeOut: CloseOut?
    private(set) var failed = false

    private let closeOuts: any CloseOutRepository

    init(tradingDay: Date, dependencies: Dependencies) {
        self.tradingDay = tradingDay
        closeOuts = dependencies.closeOuts
    }

    func load() {
        do {
            closeOut = try closeOuts.closeOut(on: tradingDay)
        } catch {
            closeOut = nil
            failed = true
        }
    }

    func setAttribution(_ attribution: Attribution?) {
        do {
            try closeOuts.setAttribution(on: tradingDay, attribution)
            failed = false
        } catch {
            failed = true
        }
        load()
    }
}
