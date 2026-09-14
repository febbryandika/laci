import SwiftUI

/// The destructive step (SPEC §5.3, §15): what the archive holds, what restoring loses, the
/// stolen-iPad sentence, and three gates before anything moves.
struct RestoreConfirmView: View {
    @Environment(AppSession.self) private var session
    @State private var viewModel: RestoreViewModel
    @State private var confirming = false

    init(archive: BackupArchive) {
        _viewModel = State(initialValue: RestoreViewModel(archive: archive))
    }

    var body: some View {
        Form {
            Section("Cadangan") {
                LabeledContent("Dibuat") { Text(verbatim: viewModel.archive.createdAt.formatted(DateFormat.dateTime)) }
                LabeledContent("Ukuran") { Text(ByteCountFormatStyle().format(Int64(viewModel.archive.byteCount))) }
                LabeledContent("Versi Laci") {
                    Text(verbatim: "\(viewModel.archive.manifest.appVersion) (\(viewModel.archive.manifest.build))")
                }
            }
            Section {
                Text(viewModel.warning)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("RestoreConfirmView.warning")
                Text("Cadangan dari iPad yang dicuri bisa dibaca oleh siapa pun yang memegang Apple ID ini.")
                    .foregroundStyle(.secondary)
            }
            Section {
                TextField("Ketik nama toko untuk melanjutkan", text: $viewModel.typedName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("RestoreConfirmView.shopName")
                Button("Pulihkan", role: .destructive) { confirming = true }
                    .disabled(!viewModel.canConfirm)
                    .accessibilityIdentifier("RestoreConfirmView.confirm")
            } header: {
                Text("Konfirmasi")
            } footer: {
                Text("Nama toko: \(viewModel.expectedName)")
            }
        }
        .navigationTitle("Pulihkan")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Ganti semua data dengan cadangan ini?", isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("Pulihkan dan ganti data", role: .destructive) {
                Task { await viewModel.confirm(session: session) }
            }
        } message: {
            Text(viewModel.warning)
        }
        .disabled(viewModel.isRestoring)
    }
}
