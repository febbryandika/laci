import Foundation

/// When an unlocked owner screen locks again after the app has been in the background. Popping is
/// what relocks, and popping throws away a stocktake in progress, so a quick look at WhatsApp must
/// not cost the count. `ContinuousClock`, not `Date`: it keeps counting while the iPad sleeps, and
/// setting the device clock back cannot stretch the window.
nonisolated struct OwnerRelock: Hashable, Sendable {
    static let defaultGracePeriod: Duration = .seconds(60)

    let gracePeriod: Duration
    private(set) var backgroundedAt: ContinuousClock.Instant?

    init(gracePeriod: Duration = Self.defaultGracePeriod) {
        self.gracePeriod = gracePeriod
    }

    mutating func didEnterBackground(at now: ContinuousClock.Instant = .now) {
        backgroundedAt = now
    }

    /// True when the owner screens must lock. Answers once per trip to the background.
    mutating func shouldRelockOnReturn(at now: ContinuousClock.Instant = .now) -> Bool {
        guard let backgroundedAt else { return false }
        self.backgroundedAt = nil
        return backgroundedAt.duration(to: now) >= gracePeriod
    }
}
