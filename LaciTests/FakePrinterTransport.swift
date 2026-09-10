import Foundation
@testable import Laci
import LaciPrint
import Synchronization

/// A transport that never touches Bluetooth: it succeeds, fails with a chosen error, or hangs, and
/// records every payload it was asked to send.
final nonisolated class FakePrinterTransport: PrinterTransporting, Sendable {
    enum Mode: Sendable {
        case succeed
        case fail(PrintError)
        case hang
    }

    private struct State {
        var mode: Mode
        var payloads: [Data] = []
        var scanned = false
        var connected: [UUID] = []
        var forgotten = false
    }

    private let state: Mutex<State>
    let connection: AsyncStream<PrinterConnection>
    let discoverable: [DiscoveredPrinter]

    init(mode: Mode = .succeed, discoverable: [DiscoveredPrinter] = []) {
        state = Mutex(State(mode: mode))
        self.discoverable = discoverable
        connection = AsyncStream { continuation in
            continuation.yield(.connected(name: "Fake", mtu: 20))
        }
    }

    var payloads: [Data] {
        state.withLock { $0.payloads }
    }

    var connected: [UUID] {
        state.withLock { $0.connected }
    }

    var forgotten: Bool {
        state.withLock { $0.forgotten }
    }

    func start() async {}

    func scan() -> AsyncStream<DiscoveredPrinter> {
        state.withLock { $0.scanned = true }
        return AsyncStream { continuation in
            for printer in discoverable {
                continuation.yield(printer)
            }
            continuation.finish()
        }
    }

    func stopScan() async {}

    func connect(_ id: UUID) async throws -> String {
        state.withLock { $0.connected.append(id) }
        return "FF00"
    }

    func disconnect() async {
        state.withLock { $0.forgotten = true }
    }

    func reconnectRemembered(_: RememberedPrinter) async throws {}

    func send(_ payload: Data) async throws {
        state.withLock { $0.payloads.append(payload) }
        switch state.withLock({ $0.mode }) {
        case .succeed: return
        case let .fail(error): throw error
        case .hang: try await Task.sleep(for: .seconds(3600))
        }
    }
}

/// Polls the main actor until `condition` holds or the deadline passes, so a test can wait for a
/// detached print to land without the production code exposing its task.
@MainActor
func until(_ deadline: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let end = clock.now + deadline
    while !condition() {
        if clock.now > end {
            return false
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}
