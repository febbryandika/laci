import SwiftUI

/// The camera, wrapped for SwiftUI: the one `UIViewControllerRepresentable` in the app (SPEC §1).
struct ScannerPreview: UIViewControllerRepresentable {
    let debouncer: ScanDebouncer
    let torchOn: Bool
    let onRead: (String, String) -> Void
    let onFail: (ScanError) -> Void
    let onRecover: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(preview: self)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController(debouncer: debouncer)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: ScannerViewController, context: Context) {
        context.coordinator.preview = self
        controller.torchOn = torchOn
    }

    final class Coordinator: ScannerViewControllerDelegate {
        var preview: ScannerPreview

        init(preview: ScannerPreview) {
            self.preview = preview
        }

        func scanner(_: ScannerViewController, didRead code: String, symbology: String) {
            preview.onRead(code, symbology)
        }

        func scanner(_: ScannerViewController, didFailWith error: ScanError) {
            preview.onFail(error)
        }

        func scannerDidRecover(_: ScannerViewController) {
            preview.onRecover()
        }
    }
}
