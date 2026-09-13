import SwiftUI

/// A segmented picker that becomes a menu at accessibility sizes (SPEC §9): three labels do not
/// fit a segment at AX5, and a clipped segment is a control nobody can read.
struct AdaptivePicker<Selection: Hashable, Content: View>: View {
    private let title: LocalizedStringKey
    @Binding private var selection: Selection
    private let content: () -> Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ title: LocalizedStringKey, selection: Binding<Selection>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        _selection = selection
        self.content = content
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker(title, selection: $selection, content: content)
                .pickerStyle(.menu)
        } else {
            Picker(title, selection: $selection, content: content)
                .pickerStyle(.segmented)
        }
    }
}
