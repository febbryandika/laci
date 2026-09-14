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
    #if DEBUG
        @State private var languageOverride = LanguageSettings.override()
    #endif

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var body: some View {
        Form {
            catalogueSection
            printerSection
            scannerSection
            exportSection
            backupSection
            purchaseSection
            diagnosticsSection
            #if DEBUG
                languageSection
            #endif
        }
        .navigationTitle("Pengaturan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.backups.refreshArchives() }
        // Display only; a count that cannot be read shows as zero, the same policy as the gate.
        .onAppear { committedSales = (try? dependencies.sales.committedSaleCount()) ?? 0 }
        .sheet(isPresented: $paywallShown) { PaywallView(unlock: session.unlock, origin: .settings) }
    }

    /// The catalogue's home on an iPhone (SPEC §9: push navigation); an iPad also reaches it from
    /// the sell toolbar.
    private var catalogueSection: some View {
        Section("Katalog") {
            NavigationLink("Katalog") {
                CatalogueView(dependencies: dependencies)
            }
            .accessibilityIdentifier("SettingsView.catalogue")
        }
    }

    private var printerSection: some View {
        Section("Printer") {
            LabeledContent("Status") { Text(connectionLabel) }
                .accessibilityIdentifier("SettingsView.printerStatus")
            if let remembered = printer.remembered {
                LabeledContent("Printer tersimpan") {
                    if remembered.name.isEmpty {
                        Text("Tanpa nama")
                    } else {
                        Text(remembered.name)
                    }
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
            if backups.location?.isLocalFallback == true {
                Text("Cadangan lokal (simulator)")
            } else {
                Text("Cadangan iCloud")
            }
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

    private var backupStatusText: LocalizedStringResource? {
        switch session.backups.status {
        case .idle: nil
        case .running: "Menyalin…"
        case .finished: "Cadangan tersimpan."
        case let .failed(error): BackupErrorText.label(error)
        }
    }

    private var diagnosticsSection: some View {
        Section("Diagnostik") {
            LabeledContent("MTU") {
                if let mtu = printer.negotiatedMTU {
                    Text("\(mtu) byte")
                } else {
                    Text(verbatim: "—")
                }
            }
            LabeledContent("Cetak terakhir") {
                if let outcomeLabel {
                    Text(outcomeLabel)
                } else {
                    Text(verbatim: "—")
                }
            }
            LabeledContent("Durasi") {
                Text(printer.lastDuration.map {
                    $0.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))
                } ?? "—")
            }
            LabeledContent("Ukuran berkas") { Text(storeSizeLabel) }
            LabeledContent("Skema") { Text(BackupService.schemaVersion) }
        }
    }

    #if DEBUG
        /// Debug builds only: the shop never picks a language here, the device does. Money and
        /// dates stay Indonesian whichever language is chosen, which is the point of looking.
        private var languageSection: some View {
            Section {
                Picker("Bahasa", selection: $languageOverride) {
                    Text("Sistem").tag(LanguageSettings.Language?.none)
                    Text(verbatim: "Indonesia").tag(Optional(LanguageSettings.Language.indonesian))
                    Text(verbatim: "English").tag(Optional(LanguageSettings.Language.english))
                    Text(verbatim: "日本語").tag(Optional(LanguageSettings.Language.japanese))
                }
                .onChange(of: languageOverride) { LanguageSettings.save(languageOverride) }
                .accessibilityIdentifier("SettingsView.languageOverride")
            } header: {
                Text("Bahasa (debug)")
            } footer: {
                Text("Tutup dan buka lagi Laci untuk menerapkan. Uang dan tanggal tetap Indonesia.")
            }
        }
    #endif

    private var storeSizeLabel: String {
        let store = session.backups.storeURL
        guard let size = try? store.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return "—" }
        return ByteCountFormatStyle().format(Int64(size))
    }

    private var paperWidth: Binding<PaperWidth> {
        Binding(get: { printer.paperWidth }, set: { printer.setPaperWidth($0) })
    }

    private var connectionLabel: LocalizedStringResource {
        switch printer.connection {
        case .unavailable: "Bluetooth tidak tersedia di perangkat ini"
        case .off: "Bluetooth mati"
        case .disconnected: "Tidak terhubung"
        case .connecting: "Menghubungkan…"
        case let .connected(name, _): "Terhubung: \(name)"
        }
    }

    private var outcomeLabel: LocalizedStringResource? {
        switch printer.lastOutcome {
        case nil: nil
        case .printed: "Berhasil"
        case let .failed(error): "Gagal: \(String(localized: PrintErrorText.label(error)))"
        }
    }
}

/// One wording per backup failure, for Settings and the restore screen.
enum BackupErrorText {
    static func label(_ error: BackupError) -> LocalizedStringResource {
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
    static func label(_ error: PrintError) -> LocalizedStringResource {
        switch error {
        case .bluetoothUnavailable: "Bluetooth tidak tersedia"
        case .bluetoothOff: "Bluetooth mati"
        case .notConnected: "printer tidak terhubung"
        case .notFound: "printer tidak ditemukan"
        case .busy: "printer sedang sibuk"
        case .paperOut: "kertas habis"
        case .saleNotFound: "penjualan tidak ditemukan"
        // A raw reason from CoreBluetooth; the catalog key is the placeholder alone.
        case let .transport(reason): "\(reason)"
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
            Text(verbatim: "In-memory store failed")
        }
    }
#endif
