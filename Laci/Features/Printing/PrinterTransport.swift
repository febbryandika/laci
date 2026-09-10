import Foundation

/// Placeholder until the CoreBluetooth actor lands.
actor PrinterTransport: PrinterTransporting {
    nonisolated let connection: AsyncStream<PrinterConnection>
    private let connectionContinuation: AsyncStream<PrinterConnection>.Continuation

    init() {
        (connection, connectionContinuation) = AsyncStream.makeStream()
    }

    func start() async {}
    nonisolated func scan() -> AsyncStream<DiscoveredPrinter> { AsyncStream { $0.finish() } }
    func stopScan() async {}
    func connect(_ id: UUID) async throws -> String { throw PrintError.bluetoothUnavailable }
    func disconnect() async {}
    func reconnectRemembered(_ printer: RememberedPrinter) async throws { throw PrintError.bluetoothUnavailable }
    func send(_ payload: Data) async throws { throw PrintError.notConnected }
}
