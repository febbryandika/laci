import SwiftUI

/// The first-launch question (SPEC §5.4, §14). It names exactly what is sent and what never is, and
/// both answers weigh the same: a shop owner who says no has lost nothing.
struct CrashConsentView: View {
    let consent: CrashConsent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Laporan crash")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("""
                Jika Laci tertutup sendiri, Laci bisa mengirim laporan ke Google Firebase Crashlytics \
                supaya masalahnya bisa diperbaiki.
                """)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Yang dikirim")
                        .font(.headline)
                    Text("• Jejak crash (bagian kode yang sedang berjalan)")
                    Text("• Model perangkat")
                    Text("• Versi iOS dan versi Laci")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tidak pernah dikirim")
                        .font(.headline)
                    Text("Penjualan, nama produk, harga, jumlah uang, atau data toko apa pun.")
                }
                Text("Pilihan ini bisa diubah kapan saja di Pengaturan › Diagnostik.")
                    .foregroundStyle(.secondary)
                VStack(spacing: 12) {
                    Button {
                        consent.grant()
                        dismiss()
                    } label: {
                        Text("Izinkan").frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("CrashConsentView.grant")
                    Button {
                        consent.decline()
                        dismiss()
                    } label: {
                        Text("Jangan kirim").frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("CrashConsentView.decline")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .interactiveDismissDisabled()
    }
}
