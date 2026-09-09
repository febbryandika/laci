import SwiftUI

/// The sell screen is the launch screen (SPEC §3.1.1). The three-pane layout is a later phase.
struct RootView: View {
    let dependencies: Dependencies

    var body: some View {
        SellView(dependencies: dependencies)
    }
}

#Preview {
    // A preview body cannot throw; a failed in-memory store is a preview problem, not an app one.
    if let dependencies = try? Dependencies.inMemory() {
        RootView(dependencies: dependencies)
    } else {
        Text("In-memory store failed")
    }
}
