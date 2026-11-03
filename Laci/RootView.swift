import SwiftUI

/// The sell screen is the launch screen (SPEC §3.1.1). The three-pane layout is a later phase.
/// The tree is keyed on the session generation so a restore rebuilds every screen on the new store.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @State private var consentShown = false

    var body: some View {
        SellView(dependencies: session.dependencies, unlock: session.unlock, ownerGracePeriod: session.lock.gracePeriod)
            .id(session.generation)
            .sheet(isPresented: $consentShown) { CrashConsentView(consent: session.crashConsent) }
            .onAppear { consentShown = session.crashConsent.shouldAsk(launch: .current) }
            .alert("Pemulihan data", isPresented: noticeShown, presenting: session.restoreNotice) { _ in
                Button("OK") { session.dismissRestoreNotice() }
            } message: { notice in
                switch notice {
                case let .succeeded(name): Text("Data dipulihkan dari cadangan \(name).")
                case let .failed(error): Text(BackupErrorText.label(error))
                }
            }
    }

    private var noticeShown: Binding<Bool> {
        Binding(
            get: { session.restoreNotice != nil },
            set: { shown in
                if !shown {
                    session.dismissRestoreNotice()
                }
            }
        )
    }
}

#Preview {
    // A preview body cannot throw; a failed in-memory store is a preview problem, not an app one.
    if let session = try? AppSession.inMemory() {
        RootView()
            .environment(session)
    } else {
        Text(verbatim: "In-memory store failed")
    }
}
