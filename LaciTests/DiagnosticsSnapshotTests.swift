import AVFoundation
import Foundation
@testable import Laci
import Testing

private let jakarta = TimeZone(identifier: "Asia/Jakarta") ?? .gmt

@MainActor
@Suite("Diagnostics snapshot")
struct DiagnosticsSnapshotTests {
    @Test("Every camera state reads as itself and none prompts")
    func camera() {
        #expect(CameraPermission(.authorized) == .authorized)
        #expect(CameraPermission(.denied) == .denied)
        #expect(CameraPermission(.restricted) == .restricted)
        #expect(CameraPermission(.notDetermined) == .notDetermined)
    }

    @Test("The OS version drops a zero patch")
    func osVersion() {
        let plain = OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 0)
        let patched = OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 1)
        #expect(DiagnosticsSnapshot.osVersion(plain) == "26.5")
        #expect(DiagnosticsSnapshot.osVersion(patched) == "26.5.1")
    }

    @Test("The store size counts the store and its SQLite sidecars, and is nil with no store")
    func storeSize() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "diag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = folder.appending(path: "Laci.store")
        #expect(DiagnosticsSnapshot.storeSize(of: store) == nil)
        try Data(count: 100).write(to: store)
        try Data(count: 30).write(to: folder.appending(path: "Laci.store-wal"))
        #expect(DiagnosticsSnapshot.storeSize(of: store) == 130)
    }

    @Test("A fresh in-memory session reads as nothing printed, no backup, no sales")
    func freshSession() throws {
        let session = try AppSession.inMemory()
        let snapshot = DiagnosticsSnapshot.make(session: session, camera: .denied)
        #expect(snapshot.salesCount == 0)
        #expect(snapshot.lastBackupAt == nil)
        #expect(snapshot.negotiatedMTU == nil)
        #expect(snapshot.camera == .denied)
        #expect(snapshot.schemaVersion == BackupService.schemaVersion)
        #expect(!snapshot.deviceModel.isEmpty)
    }

    @Test("The log header names every field in fixed English")
    func header() {
        let snapshot = DiagnosticsSnapshot(
            appVersion: "1.0 (7)", osVersion: "26.5", deviceModel: "iPad12,1", printerName: "PT-210",
            negotiatedMTU: 20,
            lastPrint: PrintRecord(
                outcome: .failed(.paperOut), duration: .milliseconds(1500),
                printedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            camera: .authorized, salesCount: 42, storeBytes: 2048, lastBackupAt: nil, schemaVersion: "1.0.0"
        )
        let header = snapshot.logHeader(generatedAt: Date(timeIntervalSince1970: 1_800_000_000), timeZone: jakarta)
        #expect(header[0] == "Laci 1.0 (7)")
        #expect(header[1] == "iOS 26.5 · iPad12,1")
        #expect(header[2] == "Printer: PT-210 · MTU 20")
        #expect(header[3].hasPrefix("Last print: failed (paperOut) in "))
        #expect(header[3].hasSuffix(" at 2027-01-15T15:00:00+0700"))
        #expect(header[4] == "Camera: authorized")
        #expect(header[5] == "Sales: 42")
        #expect(header[6] == "Store: 2048 bytes")
        #expect(header[7] == "Last backup: never")
        #expect(header[8] == "Schema: 1.0.0")
    }
}
