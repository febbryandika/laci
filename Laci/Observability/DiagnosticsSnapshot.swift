import AVFoundation
import Foundation
import LaciCore

/// The camera permission as the diagnostics screen reports it. Reading it never prompts.
nonisolated enum CameraPermission: String, Hashable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined = "not determined"

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .notDetermined
        }
    }

    static var current: CameraPermission {
        CameraPermission(AVCaptureDevice.authorizationStatus(for: .video))
    }
}

/// Everything SPEC §14's diagnostics screen shows, read once, so the screen and the header of a
/// shared log say the same thing. Each field answers a question asked over WhatsApp: "which
/// version?", "which printer, and did the last struk print?", "did you allow the camera?", "how
/// big is the store, and when was the last backup?".
nonisolated struct DiagnosticsSnapshot: Hashable, Sendable {
    let appVersion: String
    let osVersion: String
    let deviceModel: String
    let printerName: String?
    let negotiatedMTU: Int?
    let lastPrint: PrintRecord?
    let camera: CameraPermission
    let salesCount: Int?
    let storeBytes: Int64?
    let lastBackupAt: Date?
    let schemaVersion: String

    @MainActor
    static func make(
        session: AppSession, bundle: Bundle = .main, camera: CameraPermission = .current
    ) -> DiagnosticsSnapshot {
        let printer = session.dependencies.printer
        let connectedName: String? = if case let .connected(name, _) = printer.connection {
            name
        } else {
            nil
        }
        let remembered = printer.remembered?.name
        let lastPrint = printer.lastOutcome.map {
            PrintRecord(outcome: $0, duration: printer.lastDuration, printedAt: printer.lastPrintedAt ?? .distantPast)
        }
        return DiagnosticsSnapshot(
            appVersion: appVersion(bundle),
            osVersion: osVersion(ProcessInfo.processInfo.operatingSystemVersion),
            deviceModel: deviceModel(),
            printerName: connectedName ?? (remembered?.isEmpty == false ? remembered : nil),
            negotiatedMTU: printer.negotiatedMTU,
            lastPrint: lastPrint,
            camera: camera,
            salesCount: try? session.dependencies.sales.committedSaleCount(),
            storeBytes: storeSize(of: session.backups.storeURL),
            lastBackupAt: session.backups.lastBackupAt,
            schemaVersion: BackupService.schemaVersion
        )
    }

    /// "1.0 (12)".
    static func appVersion(_ bundle: Bundle) -> String {
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// "26.5", or "26.5.1" when there is a patch.
    static func osVersion(_ version: OperatingSystemVersion) -> String {
        let base = "\(version.majorVersion).\(version.minorVersion)"
        return version.patchVersion == 0 ? base : "\(base).\(version.patchVersion)"
    }

    /// The hardware identifier, e.g. "iPad12,1": it tells an iPad 9th gen from an Air, which
    /// matters for the camera and Bluetooth. A simulator reports its host architecture.
    static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? "?"
        }
    }

    /// The store and its SQLite sidecars, which is what a backup copies; nil when none exists.
    static func storeSize(of store: URL) -> Int64? {
        let folder = store.deletingLastPathComponent()
        let urls = [
            store,
            folder.appending(path: store.lastPathComponent + "-wal"),
            folder.appending(path: store.lastPathComponent + "-shm"),
        ]
        let sizes = urls.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
        return sizes.isEmpty ? nil : Int64(sizes.reduce(0, +))
    }

    /// Fixed English `key: value` lines for the top of a shared log. Not localized: I read them,
    /// and "Last print" must mean the same thing whatever language the iPad is in.
    func logHeader(generatedAt: Date, timeZone: TimeZone) -> [String] {
        let iso = Date.ISO8601FormatStyle(timeZone: timeZone)
        let printLine = if let lastPrint {
            switch lastPrint.outcome {
            case .printed: "printed"
            case let .failed(error): "failed (\(error))"
            }
        } else {
            "none"
        }
        let duration = lastPrint?.duration.map { " in \($0.formatted(.units(allowed: [.seconds, .milliseconds])))" }
        return [
            "Laci \(appVersion)",
            "iOS \(osVersion) · \(deviceModel)",
            "Printer: \(printerName ?? "none") · MTU \(negotiatedMTU.map(String.init) ?? "-")",
            "Last print: \(printLine)\(duration ?? "")\(lastPrint.map { " at \(iso.format($0.printedAt))" } ?? "")",
            "Camera: \(camera.rawValue)",
            "Sales: \(salesCount.map(String.init) ?? "-")",
            "Store: \(storeBytes.map { "\($0) bytes" } ?? "-")",
            "Last backup: \(lastBackupAt.map(iso.format) ?? "never")",
            "Schema: \(schemaVersion)",
            "Generated: \(iso.format(generatedAt))",
        ]
    }
}
