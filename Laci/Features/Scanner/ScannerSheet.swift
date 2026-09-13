import AVFoundation
import LaciCore
import SwiftUI
import UIKit

/// The scan sheet (SPEC §9): a scan window and a torch toggle. Every failure is a state with the
/// manual-entry field, never a black rectangle. An interruption keeps the preview mounted so the
/// single restart can bring it back; denied permission and a missing camera replace it.
struct ScannerSheet: View {
    private enum Phase: Hashable {
        case scanning
        case failed(ScanError)
    }

    let viewModel: any ScanReceiving
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var phase: Phase = .scanning
    @State private var torchOn = false
    @State private var manualCode = ""

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Pindai")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Tutup") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                            .accessibilityIdentifier("ScannerSheet.close")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            torchOn.toggle()
                        } label: {
                            Label("Senter", systemImage: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        }
                        .disabled(phase != .scanning)
                        .accessibilityIdentifier("ScannerSheet.torch")
                    }
                }
                .scanFeedback(trigger: viewModel.scansAccepted, isActive: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .scanning:
            preview.overlay(alignment: .bottom) { notice }
        case let .failed(.interrupted(reason)):
            preview.overlay { failurePanel(Self.interruptionText(reason), showsSettings: false) }
        case .failed(.permissionDenied):
            failurePanel("Izin kamera ditolak", showsSettings: true)
        case .failed(.unavailable):
            failurePanel("Kamera tidak tersedia", showsSettings: false)
        }
    }

    private var preview: some View {
        ScannerPreview(
            debouncer: viewModel.scanDebouncer, torchOn: torchOn,
            onRead: { code, type in viewModel.didRead(code: code, symbology: Symbology(rawValue: type)) },
            onFail: { phase = .failed($0) },
            onRecover: { phase = .scanning }
        )
        .ignoresSafeArea()
        .overlay { scanWindow }
    }

    /// Mirrors the controller's rect of interest: 10 % in from the sides, 30 % from top and bottom.
    private var scanWindow: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.8), lineWidth: 2)
                .padding(.horizontal, geometry.size.width * 0.1)
                .padding(.vertical, geometry.size.height * 0.3)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var notice: some View {
        if let notice = viewModel.scanNotice {
            Text(ScanNoticeText.label(notice))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 32)
                .accessibilityIdentifier("ScannerSheet.notice")
        }
    }

    /// Scrolls, so the manual-entry field is reachable at every Dynamic Type size.
    private func failurePanel(_ title: LocalizedStringKey, showsSettings: Bool) -> some View {
        ScrollView {
            failureContent(title, showsSettings: showsSettings)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private func failureContent(_ title: LocalizedStringKey, showsSettings: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "camera")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Ketik barcode di bawah ini, atau pakai scanner Bluetooth.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("Ketik barcode", text: $manualCode)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    viewModel.didRead(code: manualCode, symbology: nil)
                    manualCode = ""
                }
                .frame(maxWidth: 320)
                .padding(.top, 8)
                .accessibilityIdentifier("ScannerSheet.manualEntry")
            if let notice = viewModel.scanNotice {
                Text(ScanNoticeText.label(notice))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if showsSettings, let settings = URL(string: UIApplication.openSettingsURLString) {
                Button("Buka Pengaturan") { openURL(settings) }
                    .accessibilityIdentifier("ScannerSheet.openSettings")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private static func interruptionText(_ reason: AVCaptureSession.InterruptionReason) -> LocalizedStringKey {
        switch reason {
        case .videoDeviceNotAvailableWithMultipleForegroundApps: "Kamera dipakai aplikasi lain (Split View)"
        case .videoDeviceInUseByAnotherClient: "Kamera sedang dipakai aplikasi lain"
        case .videoDeviceNotAvailableDueToSystemPressure: "Perangkat terlalu panas, kamera dijeda"
        default: "Kamera dijeda"
        }
    }
}

/// One wording per outcome, shared by the sheet and the sell screen (SPEC §6): a misread says
/// "scan again", never "unknown product".
enum ScanNoticeText {
    static func label(_ notice: ScanNotice) -> LocalizedStringResource {
        switch notice {
        case .scanAgain: "Pindai ulang: barcode tidak terbaca dengan benar"
        case .lookupFailed: "Tidak bisa mencari produk"
        case .unknownProduct: "Barcode tidak dikenal"
        case .untrackedProduct: "Produk ini tidak melacak stok"
        }
    }
}
