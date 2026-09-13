import SwiftUI

/// SPEC §6: a Bluetooth scanner that pretends to be a keyboard types its payload plus Return into
/// whatever is focused. This field is one point wide and exists only to be focused; it works with
/// the camera sheet closed and with camera permission denied. The owning screen decides when it
/// is focused; the field only keeps focus after each submit.
struct WedgeField<Field: Hashable>: View {
    let focus: FocusState<Field?>.Binding
    let field: Field
    let identifier: String
    let onSubmit: (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField("", text: $text)
            .focused(focus, equals: field)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit {
                onSubmit(text)
                text = ""
                focus.wrappedValue = field
            }
            .frame(width: 1, height: 1)
            .opacity(0.02)
            .accessibilityIdentifier(identifier)
    }
}
