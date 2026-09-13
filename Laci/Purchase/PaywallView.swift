import Foundation
import StoreKit
import SwiftUI

/// SPEC §9, the locked state: the price, restore, and a sentence saying the rest of the app stays
/// open. Reached from a blocked Bayar or from Settings, never at launch (SPEC §5.1).
struct PaywallView: View {
    enum Origin {
        case checkout
        case settings
    }

    private enum Notice: Hashable {
        case unverified
        case purchaseFailed(String)
        case restoreFailed(String)
        case nothingToRestore
    }

    private let unlock: UnlockStore
    private let origin: Origin
    @Environment(\.dismiss) private var dismiss
    @State private var notice: Notice?
    @State private var isBusy = false

    init(unlock: UnlockStore, origin: Origin) {
        self.unlock = unlock
        self.origin = origin
    }

    var body: some View {
        NavigationStack {
            Form {
                headingSection
                if unlock.isUnlocked {
                    Section {
                        Label("Laci sudah dibuka.", systemImage: "checkmark.seal")
                            .accessibilityIdentifier("PaywallView.unlocked")
                    }
                } else {
                    purchaseSection
                }
                if let notice {
                    Section {
                        Text(label(for: notice))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("PaywallView.notice")
                    }
                }
            }
            .navigationTitle("Buka Laci")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Tutup") { dismiss() }
                        .accessibilityIdentifier("PaywallView.close")
                }
            }
            .task { await unlock.loadProduct() }
            .onChange(of: unlock.isUnlocked) {
                if unlock.isUnlocked, origin == .checkout {
                    dismiss()
                }
            }
        }
    }

    private var headingSection: some View {
        Section {
            switch origin {
            case .checkout:
                Text("Masa percobaan \(TrialPolicy.saleLimit()) penjualan sudah habis.")
            case .settings:
                Text("Laci gratis untuk \(TrialPolicy.saleLimit()) penjualan pertama.")
            }
            Text("Sekali beli, tanpa akun, tanpa langganan.")
        } footer: {
            Text("Katalog, riwayat, ekspor CSV dan tutup kas tetap bisa dipakai tanpa membeli.")
                .accessibilityIdentifier("PaywallView.staysOpen")
        }
    }

    private var purchaseSection: some View {
        Section {
            LabeledContent("Harga") {
                Text(unlock.product?.displayPrice ?? "…")
                    .accessibilityIdentifier("PaywallView.price")
            }
            if unlock.productLoadFailed {
                Text("Harga tidak bisa dimuat. Periksa koneksi internet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Beli") { buy() }
                .disabled(unlock.product == nil || isBusy || !AppStore.canMakePayments)
                .accessibilityIdentifier("PaywallView.buy")
            Button("Pulihkan pembelian") { restore() }
                .disabled(isBusy)
                .accessibilityIdentifier("PaywallView.restore")
            if isBusy {
                ProgressView()
            }
        }
    }

    /// SPEC §5.1: `.unverified` is locked-with-restore, not an error; a cancelled sheet says nothing.
    private func buy() {
        guard let product = unlock.product, !isBusy else { return }
        isBusy = true
        notice = nil
        Task {
            defer { isBusy = false }
            do {
                try await unlock.purchase(product)
            } catch UnlockError.unverified {
                notice = .unverified
            } catch StoreKitError.userCancelled {
                return
            } catch {
                notice = .purchaseFailed(error.localizedDescription)
            }
        }
    }

    private func restore() {
        guard !isBusy else { return }
        isBusy = true
        notice = nil
        Task {
            defer { isBusy = false }
            do {
                try await unlock.restore()
                if !unlock.isUnlocked {
                    notice = .nothingToRestore
                }
            } catch StoreKitError.userCancelled {
                return
            } catch {
                notice = .restoreFailed(error.localizedDescription)
            }
        }
    }

    private func label(for notice: Notice) -> String {
        switch notice {
        case .unverified: "Pembelian tidak bisa diverifikasi di perangkat ini. Coba Pulihkan pembelian."
        case let .purchaseFailed(reason): "Pembelian gagal: \(reason)"
        case let .restoreFailed(reason): "Tidak bisa menghubungi App Store: \(reason)"
        case .nothingToRestore: "Tidak ada pembelian Laci di Apple ID ini."
        }
    }
}

#if DEBUG
    #Preview {
        PaywallView(unlock: UnlockStore(), origin: .checkout)
    }
#endif
