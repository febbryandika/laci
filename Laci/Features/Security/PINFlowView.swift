import SwiftUI

/// One PIN flow as a form. `SecureField` rather than a drawn keypad: the counter iPad lives in a
/// keyboard case, and the system field already handles VoiceOver, Dynamic Type and screen capture.
struct PINFlowView<Accessory: View>: View {
    private let onFinished: () -> Void
    private let accessory: Accessory
    @State private var model: PINFlowModel
    @State private var text = ""
    @FocusState private var isFocused: Bool

    init(
        flow: PINFlow, lock: AppLock, onFinished: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.onFinished = onFinished
        self.accessory = accessory()
        _model = State(initialValue: PINFlowModel(flow: flow, lock: lock))
    }

    var body: some View {
        Form {
            Section {
                SecureField(prompt, text: $text, prompt: Text(verbatim: "••••••"))
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isFocused)
                    .onChange(of: text) { entryChanged(to: text) }
                    .accessibilityIdentifier("PINFlowView.field")
            } header: {
                Text(prompt)
                    .accessibilityIdentifier("PINFlowView.prompt.\(String(describing: model.step))")
            } footer: {
                footer
            }
            accessory
        }
        // A focus request made while the push is still animating is dropped without a trace.
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            isFocused = true
        }
    }

    /// Read in `onChange`, never through a custom binding: a field whose binding is emptied while
    /// it is still reporting a keystroke sends its old text back, and that text would then pass as
    /// the confirmation of the PIN just typed. Finishing is reported here too, in the same update
    /// as the lock's new status.
    private func entryChanged(to entered: String) {
        let isFinished = model.enter(entered)
        if text != model.digits {
            text = model.digits
        }
        if isFinished {
            onFinished()
        }
    }

    private var prompt: LocalizedStringKey {
        switch model.step {
        case .current: "Masukkan PIN 6 angka"
        case .new: "Buat PIN baru 6 angka"
        case .confirm: "Ulangi PIN baru"
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let notice = model.notice {
            noticeText(notice)
                .foregroundStyle(.red)
                .accessibilityIdentifier("PINFlowView.notice")
        } else {
            switch model.flow {
            case .setup:
                Text("PIN melindungi tutup kas, pengaturan, katalog, dan stok opname. Menjual tidak perlu PIN.")
            case .reset: Text("Reset menghapus PIN. Layar pemilik berikutnya akan meminta PIN baru.")
            case .unlock, .change: EmptyView()
            }
        }
    }

    private func noticeText(_ notice: PINFlowModel.Notice) -> Text {
        switch notice {
        case .wrongPIN: Text("PIN salah. Coba lagi.")
        case .mismatch: Text("PIN tidak sama. Ulangi dari awal.")
        case .storeFailed: Text("PIN gagal disimpan. Coba lagi.")
        }
    }
}

/// A flow pushed from Settings: it pops itself when done.
struct PINFlowScreen: View {
    let title: LocalizedStringKey
    let flow: PINFlow
    let lock: AppLock
    let onFinished: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PINFlowView(flow: flow, lock: lock) {
            onFinished()
            dismiss()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
