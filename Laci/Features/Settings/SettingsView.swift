import Foundation
import LaciPrint
import SwiftUI

/// Printer pairing, paper width, the test print, and the diagnostics SPEC §14 asks for. Shop
/// identity, PIN and export settings arrive in later phases.
struct SettingsView: View {
    private let dependencies: Dependencies
    private var printer: PrinterCoordinator {
        dependencies.printer
    }

    @State private var wedgeEnabled = ScannerSettings.wedgeEnabled()
    @State private var semicolonDelimiter = ExportSettings.semicolonDelimiter()

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var body: some View {
        Form {
            printerSection
            scannerSection
            exportSection
            diagnosticsSection
        }
        .navigationTitle("Pengaturan")
        .navigationBarTitleDisplayMode(.inline)
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

    private var diagnosticsSection: some View {
        Section("Diagnostik") {
            LabeledContent("MTU") { Text(printer.negotiatedMTU.map { "\($0) byte" } ?? "—") }
            LabeledContent("Cetak terakhir") { Text(outcomeLabel) }
            LabeledContent("Durasi") {
                Text(printer.lastDuration.map {
                    $0.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))
                } ?? "—")
            }
        }
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
        if let dependencies = try? Dependencies.inMemory() {
            NavigationStack {
                SettingsView(dependencies: dependencies)
            }
        } else {
            Text("In-memory store failed")
        }
    }
#endif
