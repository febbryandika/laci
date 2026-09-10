import Foundation
import SwiftUI

/// Scan, list, tap to pair. Scanning runs only while this screen is showing, and only when
/// Bluetooth can actually scan; a failure is a line of text, never an alert.
struct PrinterPairingView: View {
    let printer: PrinterCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var found: [DiscoveredPrinter] = []
    @State private var pairing: DiscoveredPrinter?
    @State private var failure: PrintError?

    var body: some View {
        List {
            if let failure {
                Section {
                    Text("Gagal menghubungkan: \(PrintErrorText.label(failure))")
                        .foregroundStyle(.red)
                }
            }
            Section {
                ForEach(found, id: \.id) { candidate in
                    Button {
                        pair(candidate)
                    } label: {
                        LabeledContent(candidate.name) {
                            if pairing == candidate {
                                Text("Menghubungkan…")
                            }
                        }
                    }
                    .tint(.primary)
                    .disabled(pairing != nil)
                }
            } footer: {
                if canScan {
                    Text("Nyalakan printer; printer muncul di sini saat ditemukan.")
                }
            }
        }
        .overlay {
            if !canScan {
                ContentUnavailableView(unavailableTitle, systemImage: "antenna.radiowaves.left.and.right.slash")
            } else if found.isEmpty {
                ContentUnavailableView("Mencari printer", systemImage: "printer")
            }
        }
        .navigationTitle("Cari printer")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: canScan) {
            guard canScan else { return }
            // Ending the iteration (leaving the screen) stops the scan.
            for await candidate in printer.scan() where !found.contains(candidate) {
                found.append(candidate)
            }
        }
    }

    private var canScan: Bool {
        switch printer.connection {
        case .unavailable, .off: false
        case .disconnected, .connecting, .connected: true
        }
    }

    private var unavailableTitle: String {
        printer.connection == .off ? "Bluetooth mati" : "Bluetooth tidak tersedia di perangkat ini"
    }

    private func pair(_ candidate: DiscoveredPrinter) {
        pairing = candidate
        failure = nil
        Task {
            await printer.stopScan()
            do {
                try await printer.pair(candidate)
                dismiss()
            } catch let error as PrintError {
                failure = error
            } catch {
                failure = .transport(String(describing: error))
            }
            pairing = nil
        }
    }
}
