import Foundation
@testable import Laci
import Observation

/// The gate without StoreKit: the tests decide what the shop owns.
@MainActor
@Observable
final class FakeUnlockStore: UnlockGating {
    var isUnlocked: Bool

    init(isUnlocked: Bool) {
        self.isUnlocked = isUnlocked
    }
}

/// Suites that are not about the gate ring sales through an unlocked shop. The production
/// initializer has no default on purpose: nothing ships as "always unlocked".
extension SellViewModel {
    convenience init(dependencies: Dependencies, now: @escaping () -> Date = { Date() }) {
        self.init(dependencies: dependencies, unlock: FakeUnlockStore(isUnlocked: true), now: now)
    }
}
