import Foundation
@testable import Laci
import Testing

/// A clock advanced by hand, so the 1.2 s window is tested without sleeping.
@MainActor
private final class FakeClock {
    private(set) var now = DispatchTime(uptimeNanoseconds: 1_000_000_000)

    func advance(milliseconds: UInt64) {
        now = DispatchTime(uptimeNanoseconds: now.uptimeNanoseconds + milliseconds * 1_000_000)
    }
}

@MainActor
@Suite("Scan debouncer")
struct ScanDebouncerTests {
    private let clock = FakeClock()
    private let debouncer: ScanDebouncer

    init() {
        let clock = clock
        debouncer = ScanDebouncer(window: .milliseconds(1200), now: { clock.now })
    }

    @Test("The first read of a code is accepted")
    func firstRead() {
        #expect(debouncer.shouldAccept("A"))
    }

    @Test("The same code inside the window is rejected, including at exactly the window")
    func sameCodeInsideWindow() {
        #expect(debouncer.shouldAccept("A"))
        clock.advance(milliseconds: 1000)
        #expect(!debouncer.shouldAccept("A"))
        clock.advance(milliseconds: 200)
        #expect(!debouncer.shouldAccept("A"))
    }

    @Test("The same code after the window is accepted again")
    func sameCodeAfterWindow() {
        #expect(debouncer.shouldAccept("A"))
        clock.advance(milliseconds: 1201)
        #expect(debouncer.shouldAccept("A"))
    }

    @Test("A code held in frame keeps refreshing the window and is never re-accepted")
    func heldInFrame() {
        #expect(debouncer.shouldAccept("A"))
        for _ in 0 ..< 6 {
            clock.advance(milliseconds: 500)
            #expect(!debouncer.shouldAccept("A"))
        }
    }

    @Test("A different code is accepted immediately, and so is the first code after it")
    func differentCode() {
        #expect(debouncer.shouldAccept("A"))
        clock.advance(milliseconds: 100)
        #expect(debouncer.shouldAccept("B"))
        clock.advance(milliseconds: 100)
        #expect(debouncer.shouldAccept("A"))
    }

    @Test("reset() lets the code just accepted through at once: delete a line, rescan it")
    func resetAfterDelete() {
        #expect(debouncer.shouldAccept("A"))
        #expect(!debouncer.shouldAccept("A"))
        debouncer.reset()
        #expect(debouncer.shouldAccept("A"))
    }
}
