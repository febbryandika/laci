import Foundation
@testable import Laci
import Testing

@Suite("Owner screen relock")
struct OwnerRelockTests {
    private let start = ContinuousClock.now

    @Test("The grace period is a minute")
    func defaultGracePeriod() {
        #expect(OwnerRelock().gracePeriod == .seconds(60))
    }

    @Test("Coming back keeps the screen inside the grace period and locks it from the boundary on", arguments: [
        (0, false), (59, false), (60, true), (61, true), (3600, true),
    ])
    func boundary(seconds: Int, relocks: Bool) {
        var relock = OwnerRelock()
        relock.didEnterBackground(at: start)
        let relocked = relock.shouldRelockOnReturn(at: start + .seconds(seconds))
        #expect(relocked == relocks)
    }

    @Test("A return with no trip to the background locks nothing")
    func noBackground() {
        var relock = OwnerRelock()
        let relocked = relock.shouldRelockOnReturn(at: start + .seconds(3600))
        #expect(!relocked)
    }

    @Test("A phase change after the return does not count as a second return")
    func answersOncePerTrip() {
        var relock = OwnerRelock()
        relock.didEnterBackground(at: start)
        let first = relock.shouldRelockOnReturn(at: start + .seconds(60))
        let second = relock.shouldRelockOnReturn(at: start + .seconds(120))
        #expect(first)
        #expect(!second)
    }

    @Test("Each trip to the background is timed from its own start")
    func timedPerTrip() {
        var relock = OwnerRelock()
        relock.didEnterBackground(at: start)
        let first = relock.shouldRelockOnReturn(at: start + .seconds(30))
        relock.didEnterBackground(at: start + .seconds(100))
        let second = relock.shouldRelockOnReturn(at: start + .seconds(130))
        #expect(!first)
        #expect(!second)
    }

    @Test("A zero grace period locks at once")
    func zeroGrace() {
        var relock = OwnerRelock(gracePeriod: .zero)
        relock.didEnterBackground(at: start)
        let relocked = relock.shouldRelockOnReturn(at: start)
        #expect(relocked)
    }
}
