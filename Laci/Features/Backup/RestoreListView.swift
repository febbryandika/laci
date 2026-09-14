import SwiftUI

/// The archives in the container, newest first. Picking one leads to the confirmation screen;
/// nothing on this screen changes any data.
struct RestoreListView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        List {
            Section {
                Text("Memulihkan mengganti semua data di iPad ini dengan isi cadangan yang dipilih.")
                    .foregroundStyle(.secondary)
            }
            if session.backups.location == nil {
                Text(BackupErrorText.label(.iCloudUnavailable))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("RestoreView.unavailable")
            } else if session.backups.archives.isEmpty {
                Text("Belum ada cadangan.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("RestoreView.empty")
            } else {
                Section("Cadangan") {
                    ForEach(session.backups.archives) { archive in
                        NavigationLink {
                            RestoreConfirmView(archive: archive)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: archive.createdAt.formatted(DateFormat.dateTime))
                                let size = ByteCountFormatStyle().format(Int64(archive.byteCount))
                                Text(verbatim: "\(archive.name) · \(size)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("RestoreView.archive.\(archive.name)")
                    }
                }
            }
        }
        .navigationTitle("Pulihkan cadangan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.backups.refreshArchives() }
    }
}
