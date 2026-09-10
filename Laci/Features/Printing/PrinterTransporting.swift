import Foundation

/// A printer seen while scanning.
nonisolated struct DiscoveredPrinter: Hashable, Sendable {
    let id: UUID
    let name: String
}

/// The printer the shop paired. The CoreBluetooth identifier is stable per device pair; the service
/// UUID is what a fallback scan filters on when the printer was off at boot (SPEC §7.3).
nonisolated struct RememberedPrinter: Hashable, Sendable {
    let peripheralID: UUID
    let serviceUUID: String
    let name: String
}

nonisolated enum PrinterConnection: Hashable, Sendable {
    /// No Bluetooth on this device (the simulator, for one).
    case unavailable
    case off
    case disconnected
    case connecting
    /// `mtu` is the negotiated `.withResponse` write length, not an assumption (SPEC §7.3).
    case connected(name: String, mtu: Int)
}

nonisolated enum PrintOutcome: Hashable, Sendable {
    case printed
    case failed(PrintError)
}

/// The sale behind the "Struk gagal dicetak" banner.
nonisolated struct FailedSale: Hashable, Sendable {
    let id: UUID
    let number: Int
}

/// What the print pipeline needs from a transport. `PrinterTransport` is the CoreBluetooth one; the
/// seam exists so the checkout tests can prove a hung or failing printer never blocks a sale.
nonisolated protocol PrinterTransporting: Sendable {
    /// Connection changes, for as long as the transport lives.
    var connection: AsyncStream<PrinterConnection> { get }
    /// Loads the remembered printer and begins reconnecting once Bluetooth is on.
    func start() async
    /// Yields printers as they advertise; ending the iteration stops the scan.
    func scan() -> AsyncStream<DiscoveredPrinter>
    func stopScan() async
    /// Connects and discovers the write characteristic; returns the UUID of its service.
    func connect(_ id: UUID) async throws -> String
    /// Drops the connection and stops reconnecting.
    func disconnect() async
    func reconnectRemembered(_ printer: RememberedPrinter) async throws
    /// Paper pre-flight, then chunked `.withResponse` writes, one outstanding at a time.
    func send(_ payload: Data) async throws
}

/// The transport for previews and in-memory stores: there is no printer, and every send says so.
nonisolated struct UnavailablePrinterTransport: PrinterTransporting {
    let connection: AsyncStream<PrinterConnection>

    init() {
        connection = AsyncStream { continuation in
            continuation.yield(.unavailable)
        }
    }

    func start() async {}

    func scan() -> AsyncStream<DiscoveredPrinter> {
        AsyncStream { $0.finish() }
    }

    func stopScan() async {}

    func connect(_ id: UUID) async throws -> String {
        throw PrintError.bluetoothUnavailable
    }

    func disconnect() async {}

    func reconnectRemembered(_ printer: RememberedPrinter) async throws {
        throw PrintError.bluetoothUnavailable
    }

    func send(_ payload: Data) async throws {
        throw PrintError.notConnected
    }
}
