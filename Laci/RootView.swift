import SwiftUI

/// Placeholder root. Replaced by the sell screen and three-pane layout in a later phase.
struct RootView: View {
    let dependencies: Dependencies

    var body: some View {
        Text("Laci")
            .font(.largeTitle)
            .accessibilityIdentifier("RootView.title")
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
