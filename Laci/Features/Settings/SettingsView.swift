import Foundation
import LaciCore
import LaciPrint
import SwiftUI

/// Printer pairing, paper width, the test print, and the diagnostics SPEC §14 asks for. Shop
/// identity, PIN and export settings arrive in later phases.
struct SettingsView: View {
    private let dependencies: Dependencies
    private var printer: PrinterCoordinator {
        dependencies.printer
    }

    @Environment(AppSession.self) private var session
    @State private var wedgeEnabled = ScannerSettings.wedgeEnabled()
    @State private var semicolonDelimiter = ExportSettings.semicolonDelimiter()
    @State private var committedSales = 0
    @State private var paywallShown = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var body: some View {
        Form {
            printerSection
            scannerSection
            exportSection
            backupSection
            purchaseSection
            diagnosticsSection
        }
        .navigationTitle("Pengaturan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.backups.refreshArchives() }
        // Display only; a count that cannot be read shows as zero, the same policy as the gate.
        .onAppear { committedSales = (try? dependencies.sales.committedSaleCount()) ?? 0 }
        .sheet(isPresented: $paywallShown) { PaywallView(unlock: session.unlock, origin: .settings) }
    }

    private var printerSection: some View {
        Section("Printer") {
            LabeledContent("Status") { Text(connectionLabel) }
                .accessibilityIdentifier("SettingsView.printerStatus")
            if let remembered = printer.remembered {
                LabeledContent("Printer tersimpan") {
                    Text(remembered.name.isEmpty ? "Tanpa nama" : remembered.name)
                }
            }
            Picker("Lebar kertas", selection: paperWidth) {
                Text("58 mm").tag(PaperWidth.mm58)
                Text("80 mm").tag(PaperWidth.mm80)
            }
            NavigationLink("Cari printer") {
                PrinterPairingView(printer: printer)
            }
            .accessibilityIdentifier("SettingsView.findPrinter")
            if printer.remembered != nil {
                Button("Lupakan printer", role: .destructive) {
                    Task { await printer.forget() }
                }
            }
            Button("Cetak tes") { printer.printTest() }
                .disabled(!printer.isConnected)
                .accessibilityIdentifier("SettingsView.testPrint")
        }
    }

    /// SPEC §3.4. Restore is reachable here before the limit, not only from a blocked checkout.
    private var purchaseSection: some View {
        Section("Pembelian") {
            if session.unlock.isUnlocked {
                Label("Laci sudah dibuka", systemImage: "checkmark.seal")
                    .accessibilityIdentifier("SettingsView.unlocked")
            } else {
                LabeledContent("Masa percobaan") {
                    Text("\(committedSales) dari \(TrialPolicy.saleLimit()) penjualan")
                }
                .accessibilityIdentifier("SettingsView.trialStatus")
                Button("Buka Laci…") { paywallShown = true }
                    .accessibilityIdentifier("SettingsView.unlock")
            }
        }
    }

    /// SPEC §6: the keyboard-wedge path. Off by default, because a focused field on a device with
    /// no hardware keyboard keeps the software keyboard on the sell screen.
    private var scannerSection: some View {
        Section("Pemindai") {
            Toggle("Scanner Bluetooth (mode keyboard)", isOn: $wedgeEnabled)
                .onChange(of: wedgeEnabled) { ScannerSettings.save(wedgeEnabled: wedgeEnabled) }
                .accessibilityIdentifier("SettingsView.wedgeToggle")
        }
    }

    /// SPEC §5.2: the semicolon toggle exists because Indonesian-locale Excel splits on `;`.
    private var exportSection: some View {
        Section("Ekspor") {
            Toggle("Pemisah titik koma (;) untuk Excel Indonesia", isOn: $semicolonDelimiter)
                .onChange(of: semicolonDelimiter) { ExportSettings.save(semicolonDelimiter: semicolonDelimiter) }
                .accessibilityIdentifier("SettingsView.semicolonToggle")
            NavigationLink("Ekspor CSV") {
                ExportView(dependencies: dependencies)
            }
            .accessibilityIdentifier("SettingsView.export")
        }
    }

    /// SPEC §5.3: a file copy into iCloud Documents, opt-in, and never a sync engine.
    private var backupSection: some View {
        @Bindable var backups = session.backups
        return Section {
            Toggle("Cadangkan otomatis saat mengisi daya", isOn: $backups.automaticEnabled)
                .accessibilityIdentifier("SettingsView.automaticBackup")
            Button("Cadangkan sekarang") {
                Task { await backups.backupNow() }
            }
            .disabled(backups.status == .running)
            .accessibilityIdentifier("SettingsView.backupNow")
            LabeledContent("Cadangan terakhir") {
                Text(backups.lastBackupAt.map { $0.formatted(DateFormat.dateTime) } ?? "—")
                    .accessibilityIdentifier("SettingsView.lastBackup")
            }
            if let status = backupStatusText {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(backupFailed ? .red : .secondary)
                    .accessibilityIdentifier("SettingsView.backupStatus")
            }
            NavigationLink("Pulihkan dari cadangan…") {
                RestoreListView()
            }
            .accessibilityIdentifier("SettingsView.restore")
        } header: {
            Text(backups.location?.isLocalFallback == true ? "Cadangan lokal (simulator)" : "Cadangan iCloud")
        } footer: {
            Text("Jika iPad hilang, yang tersimpan adalah data sampai cadangan terakhir.")
        }
    }

    private var backupFailed: Bool {
        if case .failed = session.backups.status {
            true
        } else {
            false
        }
    }

    private var backupStatusText: String? {
        switch session.backups.status {
        case .idle: nil
        case .running: "Menyalin…"
        case .finished: "Cadangan tersimpan."
        case let .failed(error): BackupErrorText.label(error)
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostik") {
            LabeledContent("MTU") { Text(printer.negotiatedMTU.map { "\($0) byte" } ?? "—") }
            LabeledContent("Cetak terakhir") { Text(outcomeLabel) }
            LabeledContent("Durasi") {
                Text(printer.lastDuration.map {
                    $0.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))
                } ?? "—")
            }
            LabeledContent("Ukuran berkas") { Text(storeSizeLabel) }
            LabeledContent("Skema") { Text(BackupService.schemaVersion) }
        }
    }

    private var storeSizeLabel: String {
        let store = session.backups.storeURL
        guard let size = try? store.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "—" }
        return ByteCountFormatStyle().format(Int64(size))
    }

    private var paperWidth: Binding<PaperWidth> {
        Binding(get: { printer.paperWidth }, set: { printer.setPaperWidth($0) })
    }

    private var connectionLabel: String {
        switch printer.connection {
        case .unavailable: "Bluetooth tidak tersedia di perangkat ini"
        case .off: "Bluetooth mati"
        case .disconnected: "Tidak terhubung"
        case .connecting: "Menghubungkan…"
        case let .connected(name, _): "Terhubung: \(name)"
        }
    }

    private var outcomeLabel: String {
        switch printer.lastOutcome {
        case nil: "—"
        case .printed: "Berhasil"
        case let .failed(error): "Gagal: \(PrintErrorText.label(error))"
        }
    }
}

/// One wording per backup failure, for Settings and the restore screen.
enum BackupErrorText {
    static func label(_ error: BackupError) -> String {
        switch error {
        case .iCloudUnavailable: "iCloud tidak tersedia. Masuk ke iCloud dan nyalakan iCloud Drive di Pengaturan iPad."
        case let .copyFailed(reason): "Gagal menyalin berkas: \(reason)"
        case let .pruneFailed(reason): "Cadangan tersimpan, tetapi cadangan lama gagal dihapus: \(reason)"
        case let .manifestUnreadable(reason): "Cadangan tidak terbaca: \(reason)"
        case let .incompatibleSchema(found): "Cadangan dari versi Laci lain (skema \(found)) tidak bisa dipulihkan"
        case .notDownloaded: "Cadangan belum terunduh dari iCloud. Coba lagi sebentar lagi."
        case let .restoreFailed(reason): "Gagal memulihkan: \(reason)"
        }
    }
}

/// One wording per failure, shared by Settings and the pairing screen.
enum PrintErrorText {
    static func label(_ error: PrintError) -> String {
        switch error {
        case .bluetoothUnavailable: "Bluetooth tidak tersedia"
        case .bluetoothOff: "Bluetooth mati"
        case .notConnected: "printer tidak terhubung"
        case .notFound: "printer tidak ditemukan"
        case .busy: "printer sedang sibuk"
        case .paperOut: "kertas habis"
        case .saleNotFound: "penjualan tidak ditemukan"
        case let .transport(reason): reason
        }
    }
}

#if DEBUG
    #Preview {
        if let session = try? AppSession.inMemory() {
            NavigationStack {
                SettingsView(dependencies: session.dependencies)
            }
            .environment(session)
        } else {
            Text("In-memory store failed")
        }
    }
#endif
