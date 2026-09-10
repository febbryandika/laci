import CoreBluetooth
import Foundation
import LaciPrint
import os

/// The CoreBluetooth central (SPEC §7.3). The actor executes on the very queue it hands to
/// `CBCentralManager`, so every delegate callback is already on the actor's executor and enters
/// it with `assumeIsolated`. Only identifiers, names, state and error text cross that boundary;
/// the actor fetches every `CBPeripheral` it needs from its own central, so no CoreBluetooth
/// object is ever sent between isolation domains and there is no `@unchecked Sendable` anywhere.
/// It holds no business logic; chunking, status parsing and the bytes come from `LaciPrint`.
actor PrinterTransport: PrinterTransporting {
    private let queue: DispatchSerialQueue
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    nonisolated let connection: AsyncStream<PrinterConnection>
    private let connectionContinuation: AsyncStream<PrinterConnection>.Continuation
    private let central: CBCentralManager
    private let delegate: CentralDelegate
    private let log = Logger(subsystem: "id.laci", category: "print")

    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?
    /// Retained while a pairing scan runs: CoreBluetooth drops a discovered peripheral nobody holds.
    private var discovered: [UUID: CBPeripheral] = [:]
    private var remembered: RememberedPrinter?
    /// True from a successful connect until `disconnect()`: a drop is followed by a pending
    /// `connect` with no timeout, which completes the moment the printer is switched on.
    private var autoReconnect = false
    private var pendingServices = 0

    private var connectContinuation: CheckedContinuation<Void, any Error>?
    private var writeContinuation: CheckedContinuation<Void, any Error>?
    private var statusContinuation: CheckedContinuation<Data?, Never>?
    private var scanContinuation: AsyncStream<DiscoveredPrinter>.Continuation?
    private var rememberedScan: (id: UUID, continuation: CheckedContinuation<UUID, any Error>)?
    private var rememberedScanTimeout: Task<Void, Never>?

    init() {
        let queue = DispatchSerialQueue(label: "id.laci.printer")
        self.queue = queue
        (connection, connectionContinuation) = AsyncStream.makeStream()
        delegate = CentralDelegate()
        // No system "Bluetooth is off" alert on a shop counter; Settings shows the state instead.
        central = CBCentralManager(
            delegate: nil, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }

    /// The delegate is attached here, on the executor, so no callback can precede `transport` being set.
    func start() {
        delegate.transport = self
        central.delegate = delegate
        remembered = PrinterSettings.remembered()
        didUpdateState(central.state)
    }

    // MARK: Discovery and pairing

    nonisolated func scan() -> AsyncStream<DiscoveredPrinter> {
        let (stream, continuation) = AsyncStream.makeStream(of: DiscoveredPrinter.self)
        continuation.onTermination = { _ in
            Task { await self.stopScan() }
        }
        Task { await self.beginScan(continuation) }
        return stream
    }

    private func beginScan(_ continuation: AsyncStream<DiscoveredPrinter>.Continuation) {
        guard central.state == .poweredOn else {
            continuation.finish()
            return
        }
        scanContinuation?.finish()
        scanContinuation = continuation
        discovered = [:]
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        guard let scanContinuation else { return }
        self.scanContinuation = nil
        scanContinuation.finish()
        if rememberedScan == nil, central.isScanning {
            central.stopScan()
        }
    }

    func connect(_ id: UUID) async throws -> String {
        try requirePoweredOn()
        guard let target = discovered[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else {
            throw PrintError.notFound
        }
        stopScan()
        try await connect(to: target)
        guard let service = writeChar?.service?.uuid.uuidString else { throw PrintError.notFound }
        autoReconnect = true
        remembered = RememberedPrinter(peripheralID: id, serviceUUID: service, name: target.name ?? "")
        return service
    }

    func disconnect() {
        autoReconnect = false
        remembered = nil
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        dropPeripheral()
        connectionContinuation.yield(central.state == .poweredOn ? .disconnected : stateLabel(central.state))
    }

    /// The remembered printer: the cache first, then a bounded scan filtered by its service, because
    /// a printer that was off since the last boot is not in the cache either (SPEC §7.3).
    func reconnectRemembered(_ printer: RememberedPrinter) async throws {
        try requirePoweredOn()
        guard connectContinuation == nil, peripheral?.state != .connected else { return }
        connectionContinuation.yield(.connecting)
        do {
            let cached = central.retrievePeripherals(withIdentifiers: [printer.peripheralID]).first
            let target: CBPeripheral = if let cached {
                cached
            } else {
                try await scanForRemembered(printer)
            }
            try await connect(to: target)
            autoReconnect = true
        } catch {
            connectionContinuation.yield(.disconnected)
            throw error
        }
    }

    private func scanForRemembered(_ printer: RememberedPrinter) async throws -> CBPeripheral {
        guard rememberedScan == nil, scanContinuation == nil else { throw PrintError.busy }
        defer {
            rememberedScan = nil
            rememberedScanTimeout?.cancel()
            rememberedScanTimeout = nil
            if central.isScanning {
                central.stopScan()
            }
        }
        let id: UUID = try await withCheckedThrowingContinuation { continuation in
            rememberedScan = (printer.peripheralID, continuation)
            central.scanForPeripherals(withServices: [CBUUID(string: printer.serviceUUID)])
            rememberedScanTimeout = Task {
                try? await Task.sleep(for: .seconds(10))
                timeOutRememberedScan()
            }
        }
        guard let target = central.retrievePeripherals(withIdentifiers: [id]).first else {
            throw PrintError.notFound
        }
        return target
    }

    private func timeOutRememberedScan() {
        guard let rememberedScan else { return }
        self.rememberedScan = nil
        rememberedScan.continuation.resume(throwing: PrintError.notFound)
    }

    private func connect(to target: CBPeripheral) async throws {
        guard connectContinuation == nil else { throw PrintError.busy }
        if let current = peripheral, current !== target {
            central.cancelPeripheralConnection(current)
        }
        peripheral = target
        writeChar = nil
        statusChar = nil
        target.delegate = delegate
        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
            central.connect(target)
        }
    }

    // MARK: Printing

    func send(_ payload: Data) async throws {
        guard let peripheral, let writeChar, peripheral.state == .connected else { throw PrintError.notConnected }
        if statusChar != nil {
            try await assertPaperPresent(peripheral, writeChar)
        }
        // MTU is negotiated, not assumed: 20 bytes on a 2019 printer, 244 on a recent one.
        let mtu = peripheral.maximumWriteValueLength(for: .withResponse)
        let chunks = payload.chunked(into: mtu)
        for (index, chunk) in chunks.enumerated() {
            log.info("""
            print chunk \(index + 1, privacy: .public)/\(chunks.count, privacy: .public), mtu \(mtu, privacy: .public)
            """)
            try await write(chunk, to: writeChar, on: peripheral)
        }
    }

    /// One outstanding write at a time. `.withResponse` gives back-pressure; `.withoutResponse`
    /// drops bytes on these printers under load, which prints half a receipt.
    private func write(_ chunk: Data, to characteristic: CBCharacteristic, on target: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            guard writeContinuation == nil else { return continuation.resume(throwing: PrintError.busy) }
            writeContinuation = continuation
            target.writeValue(chunk, for: characteristic, type: .withResponse)
        }
    }

    /// DLE EOT 4. No reply within 600 ms is "unknown, proceed": half these printers never answer.
    private func assertPaperPresent(_ target: CBPeripheral, _ characteristic: CBCharacteristic) async throws {
        try await write(RealTimeStatus.paperQuery, to: characteristic, on: target)
        let reply = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            statusContinuation = continuation
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                resumeStatus(with: nil)
            }
        }
        guard let byte = reply?.first else { return }
        if PaperStatus(byte: byte).isOut {
            throw PrintError.paperOut
        }
    }

    /// Resumes exactly once: the reply and the timeout both come here, and the second finds nil.
    private func resumeStatus(with data: Data?) {
        guard let statusContinuation else { return }
        self.statusContinuation = nil
        statusContinuation.resume(returning: data)
    }
}

extension PrinterTransport {
    // MARK: Delegate events (already on the executor)

    func didUpdateState(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            if peripheral?.state != .connected {
                connectionContinuation.yield(.disconnected)
            }
            if let remembered, peripheral?.state != .connected {
                Task { try? await reconnectRemembered(remembered) }
            }
        case .poweredOff, .unsupported, .unauthorized:
            failPending(PrintError.notConnected)
            dropPeripheral()
            connectionContinuation.yield(stateLabel(state))
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }
    }

    func didDiscover(id: UUID, name: String) {
        if let rememberedScan, rememberedScan.id == id {
            self.rememberedScan = nil
            rememberedScan.continuation.resume(returning: id)
            return
        }
        guard let scanContinuation, discovered[id] == nil, !name.isEmpty,
              let target = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        discovered[id] = target
        scanContinuation.yield(DiscoveredPrinter(id: id, name: name))
    }

    func didConnect(_ id: UUID) {
        guard let peripheral, peripheral.identifier == id else { return }
        pendingServices = 0
        peripheral.discoverServices(nil)
    }

    func didFailToConnect(_ id: UUID, reason: String?) {
        guard peripheral?.identifier == id else { return }
        finishConnect(throwing: PrintError.transport(reason ?? "gagal terhubung"))
    }

    func didDisconnect(_ id: UUID) {
        guard let peripheral, peripheral.identifier == id else { return }
        writeChar = nil
        statusChar = nil
        failPending(PrintError.notConnected)
        connectionContinuation.yield(.disconnected)
        if autoReconnect, central.state == .poweredOn {
            // No timeout: CoreBluetooth holds this until the printer is switched on, at 7am or
            // whenever, and it costs nothing while waiting.
            central.connect(peripheral)
        }
    }

    func didDiscoverServices(_ id: UUID, failure: String?) {
        guard let peripheral, peripheral.identifier == id else { return }
        if let failure {
            return finishConnect(throwing: PrintError.transport(failure))
        }
        let services = peripheral.services ?? []
        pendingServices = services.count
        guard !services.isEmpty else {
            return finishConnect(throwing: PrintError.transport("printer tidak punya layanan"))
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func didDiscoverCharacteristics(_ id: UUID, serviceUUID: String, failure: String?) {
        guard let peripheral, peripheral.identifier == id else { return }
        pendingServices -= 1
        let service = peripheral.services?.first { $0.uuid.uuidString == serviceUUID }
        for characteristic in service?.characteristics ?? [] where failure == nil {
            if writeChar == nil, characteristic.properties.contains(.write) {
                writeChar = characteristic
            }
            if statusChar == nil, characteristic.properties.contains(.notify) {
                statusChar = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        if let writeChar {
            let mtu = peripheral.maximumWriteValueLength(for: .withResponse)
            let name = peripheral.name ?? remembered?.name ?? "Printer"
            let service = writeChar.service?.uuid.uuidString ?? "-"
            let hasStatus = statusChar != nil
            log.info("""
            connected \(name, privacy: .public), service \(service, privacy: .public), \
            mtu \(mtu, privacy: .public), status \(hasStatus, privacy: .public)
            """)
            connectionContinuation.yield(.connected(name: name, mtu: mtu))
            finishConnect(throwing: nil)
        } else if pendingServices == 0 {
            finishConnect(throwing: PrintError.transport("printer tidak punya karakteristik tulis"))
        }
    }

    func didWrite(failure: String?) {
        guard let writeContinuation else { return }
        self.writeContinuation = nil
        if let failure {
            writeContinuation.resume(throwing: PrintError.transport(failure))
        } else {
            writeContinuation.resume()
        }
    }

    func didUpdateValue(characteristicUUID: String, value: Data?) {
        guard statusChar?.uuid.uuidString == characteristicUUID, let value else { return }
        resumeStatus(with: value)
    }

    // MARK: Helpers

    private func requirePoweredOn() throws {
        switch central.state {
        case .poweredOn: return
        case .poweredOff: throw PrintError.bluetoothOff
        default: throw PrintError.bluetoothUnavailable
        }
    }

    private func stateLabel(_ state: CBManagerState) -> PrinterConnection {
        state == .poweredOff ? .off : .unavailable
    }

    private func finishConnect(throwing error: PrintError?) {
        guard let connectContinuation else { return }
        self.connectContinuation = nil
        if let error {
            connectContinuation.resume(throwing: error)
        } else {
            connectContinuation.resume()
        }
    }

    private func failPending(_ error: PrintError) {
        finishConnect(throwing: error)
        if let writeContinuation {
            self.writeContinuation = nil
            writeContinuation.resume(throwing: error)
        }
        resumeStatus(with: nil)
        timeOutRememberedScan()
    }

    private func dropPeripheral() {
        peripheral = nil
        writeChar = nil
        statusChar = nil
    }
}
