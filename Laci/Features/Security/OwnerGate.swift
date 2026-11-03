import SwiftUI

/// The door in front of an owner screen (SPEC §15). Nothing of the screen is built until it opens,
/// and it opens per push: the state dies with the navigation entry, so leaving is locking.
/// `SellView` pops these entries when the app comes back after the grace period (`OwnerRelock`).
struct OwnerGate<Content: View>: View {
    private let title: LocalizedStringKey
    private let content: () -> Content
    @Environment(AppSession.self) private var session
    @State private var isOpen = false

    init(title: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        if isOpen || !session.lock.isEnforced {
            content()
        } else {
            lockScreen
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var lockScreen: some View {
        switch session.lock.status {
        case .noPIN:
            PINFlowView(flow: .setup, lock: session.lock) { isOpen = true }
        case .set:
            PINFlowView(flow: .unlock, lock: session.lock) { isOpen = true } accessory: {
                biometricSection
                forgotSection
            }
            .task { await authenticateWithBiometrics() }
        case .unreadable:
            Form {
                Section {
                    Text("PIN tidak bisa dibaca di iPad ini. Coba tutup dan buka lagi Laci.")
                        .accessibilityIdentifier("OwnerGate.unreadable")
                }
                forgotSection
            }
        }
    }

    @ViewBuilder
    private var biometricSection: some View {
        switch session.lock.biometricKind {
        case .none: EmptyView()
        case .faceID: biometricButton("Gunakan Face ID", systemImage: "faceid")
        case .touchID: biometricButton("Gunakan Touch ID", systemImage: "touchid")
        }
    }

    private func biometricButton(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Section {
            Button {
                Task { await authenticateWithBiometrics() }
            } label: {
                Label(title, systemImage: systemImage)
            }
            .accessibilityIdentifier("OwnerGate.biometrics")
        }
    }

    private var forgotSection: some View {
        Section {
            NavigationLink("Lupa PIN?") {
                ForgotPINView(dependencies: session.dependencies)
            }
            .accessibilityIdentifier("OwnerGate.forgot")
        }
    }

    private func authenticateWithBiometrics() async {
        guard session.lock.biometricKind != .none else { return }
        if await session.lock.authenticateWithBiometrics() {
            isOpen = true
        }
    }
}

/// What a forgotten PIN still leaves open. Sales data is the shop's whatever happens to the PIN
/// (SPEC §3.4), and none of the exports carries a cost, so this does not show margins.
struct ForgotPINView: View {
    let dependencies: Dependencies

    var body: some View {
        Form {
            Section {
                Text("PIN tidak bisa dipulihkan, karena tidak disimpan di mana pun selain iPad ini.")
                NavigationLink("Ekspor CSV") {
                    ExportView(dependencies: dependencies)
                }
                .accessibilityIdentifier("ForgotPINView.export")
            } footer: {
                Text("Semua data penjualan tetap bisa diekspor tanpa PIN.")
            }
            Section("Mulai lagi dengan PIN baru") {
                Text("Ekspor dulu, lalu hapus dan pasang lagi Laci. Menghapus Laci menghapus semua data di iPad ini.")
                Text("Setelah itu, buat PIN baru dan pulihkan data dari cadangan iCloud di Pengaturan.")
            }
        }
        .navigationTitle("Lupa PIN")
        .navigationBarTitleDisplayMode(.inline)
    }
}
