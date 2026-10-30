import SwiftUI

/// Settings › Diagnostik (SPEC §14): what I ask a shop owner over WhatsApp, on one screen, plus the
/// log they can send me. Every row answers a support question; nothing here is a statistic.
struct DiagnosticsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        // Rebuilt on every render, so a print finishing while the screen is open shows up.
        let snapshot = DiagnosticsSnapshot.make(session: session)
        Form {
            Section {
                row("Versi Laci", "appVersion") { Text(verbatim: snapshot.appVersion) }
                row("iOS", "osVersion") { Text(verbatim: snapshot.osVersion) }
                row("Printer", "printer") {
                    if let name = snapshot.printerName {
                        Text(verbatim: name)
                    } else {
                        Text("Belum dipasangkan")
                    }
                }
                row("MTU", "mtu") {
                    if let mtu = snapshot.negotiatedMTU {
                        Text("\(mtu) byte")
                    } else {
                        Text(verbatim: "—")
                    }
                }
                lastPrintRow(snapshot.lastPrint)
                row("Durasi", "printDuration") {
                    Text(verbatim: snapshot.lastPrint?.duration.map {
                        $0.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))
                    } ?? "—")
                }
                row("Kamera", "camera") { Text(Self.cameraLabel(snapshot.camera)) }
                row("Jumlah penjualan", "salesCount") { Text(verbatim: snapshot.salesCount.map(String.init) ?? "—") }
                row("Ukuran berkas", "storeSize") {
                    Text(verbatim: snapshot.storeBytes.map { ByteCountFormatStyle().format($0) } ?? "—")
                }
                row("Cadangan terakhir", "lastBackup") {
                    if let date = snapshot.lastBackupAt {
                        Text(verbatim: date.formatted(DateFormat.dateTime))
                    } else {
                        Text("Belum pernah")
                    }
                }
                row("Skema", "schema") { Text(verbatim: snapshot.schemaVersion) }
            }
            Section {
                ShareLink(
                    item: supportLog(snapshot),
                    preview: SharePreview(Text(verbatim: "Laci log"))
                ) {
                    Text("Bagikan log")
                }
                .accessibilityIdentifier("DiagnosticsView.shareLog")
            } footer: {
                Text("Berisi 500 baris log terakhir sejak Laci dibuka. Jumlah uang dan nama produk tidak ikut.")
            }
            if session.crashConsent.isAvailable {
                crashReportingSection
            }
        }
        .navigationTitle("Diagnostik")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var crashReportingSection: some View {
        let consent = session.crashConsent
        let enabled = Binding(
            get: { consent.decision == .granted },
            set: { $0 ? consent.grant() : consent.decline() }
        )
        return Section {
            Toggle("Kirim laporan crash", isOn: enabled)
                .accessibilityIdentifier("DiagnosticsView.crashReporting")
        } footer: {
            Text("""
            Hanya jejak crash, model perangkat, versi iOS dan versi Laci, ke Google Firebase Crashlytics. \
            Tidak pernah data penjualan. Mematikannya berlaku penuh setelah Laci dibuka ulang.
            """)
        }
    }

    private func row(
        _ title: LocalizedStringKey, _ identifier: String, @ViewBuilder value: () -> some View
    ) -> some View {
        LabeledContent(title) { value() }
            .accessibilityIdentifier("DiagnosticsView.\(identifier)")
    }

    private func lastPrintRow(_ record: PrintRecord?) -> some View {
        LabeledContent {
            if let record {
                switch record.outcome {
                case .printed: Text("Berhasil")
                case let .failed(error): Text("Gagal: \(String(localized: PrintErrorText.label(error)))")
                }
            } else {
                Text(verbatim: "—")
            }
        } label: {
            Text("Cetak terakhir")
            if let record {
                Text(verbatim: record.printedAt.formatted(DateFormat.dateTime))
            }
        }
        .accessibilityIdentifier("DiagnosticsView.lastPrint")
    }

    private func supportLog(_ snapshot: DiagnosticsSnapshot) -> SupportLog {
        let now = Date()
        return SupportLog(
            header: snapshot.logHeader(generatedAt: now, timeZone: ShopDefaults.timeZone),
            timeZone: ShopDefaults.timeZone,
            fileName: SupportLog.fileName(at: now, timeZone: ShopDefaults.timeZone)
        )
    }

    static func cameraLabel(_ permission: CameraPermission) -> LocalizedStringResource {
        switch permission {
        case .authorized: "Diizinkan"
        case .denied: "Ditolak"
        case .restricted: "Dibatasi"
        case .notDetermined: "Belum ditanya"
        }
    }
}

#if DEBUG
    #Preview {
        if let session = try? AppSession.inMemory() {
            NavigationStack {
                DiagnosticsView()
            }
            .environment(session)
        } else {
            Text(verbatim: "In-memory store failed")
        }
    }
#endif
