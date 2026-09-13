import SwiftUI

/// The search-or-SKU field, the same on every layout: Return adds the top match (SPEC §16.3).
struct SellSearchField: View {
    let viewModel: SellViewModel
    let focus: FocusState<SellField?>.Binding
    let onSubmit: () -> Void

    var body: some View {
        @Bindable var viewModel = viewModel
        TextField("Cari produk atau SKU", text: $viewModel.query)
            .focused(focus, equals: .search)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit {
                viewModel.addFirstResult()
                onSubmit()
            }
            .accessibilityIdentifier("SellView.search")
    }
}
