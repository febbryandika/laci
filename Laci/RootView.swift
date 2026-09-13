import SwiftUI

/// The sell screen is the launch screen (SPEC §3.1.1). The three-pane layout is a later phase.
/// The tree is keyed on the session generation so a restore rebuilds every screen on the new store.
struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        SellView(dependencies: session.dependencies)
            .id(session.generation)
    }
}

#Preview {
    // A preview body cannot throw; a failed in-memory store is a preview problem, not an app one.
    if let session = try? AppSession.inMemory() {
        RootView()
            .environment(session)
    } else {
        Text("In-memory store failed")
    }
}
