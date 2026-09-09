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
    RootView(dependencies: Dependencies())
}
