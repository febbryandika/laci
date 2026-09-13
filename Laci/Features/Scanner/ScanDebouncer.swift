import Foundation

/// The rule matches how a cashier works, not how a timer works (SPEC §6): accept a code, then
/// reject *that same code* for the window, but accept a *different* code immediately, so ten
/// different items in eight seconds are never throttled.
///
/// Confined to the main actor: the metadata delegate hops to main before asking, and `reset()`
/// comes from the cart, which is already there. No lock is needed or wanted. The clock is
/// injected so the window is testable without sleeping.
@MainActor
final class ScanDebouncer {
    private let window: DispatchTimeInterval
    private let now: () -> DispatchTime
    private var lastValue: String?
    private var lastAt: DispatchTime

    init(window: DispatchTimeInterval, now: @escaping () -> DispatchTime = { .now() }) {
        self.window = window
        self.now = now
        lastAt = now()
    }

    func shouldAccept(_ value: String) -> Bool {
        let current = now()
        defer {
            lastValue = value
            lastAt = current
        }
        // A different code is always accepted.
        guard value == lastValue else { return true }
        return current > lastAt.advanced(by: window)
    }

    /// Called when a cart line is deleted, so re-scanning the item just removed works at once.
    func reset() {
        lastValue = nil
    }
}
