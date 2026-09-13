import AVFoundation
import Foundation
import UIKit

enum ScanError: Error, Hashable {
    case permissionDenied
    case unavailable
    case interrupted(AVCaptureSession.InterruptionReason)
}

@MainActor
protocol ScannerViewControllerDelegate: AnyObject {
    func scanner(_ controller: ScannerViewController, didRead code: String, symbology: String)
    func scanner(_ controller: ScannerViewController, didFailWith error: ScanError)
    /// The single restart after an interruption succeeded; the preview is live again.
    func scannerDidRecover(_ controller: ScannerViewController)
}

/// The camera preview (SPEC §6). A view controller, not a SwiftUI view, because the preview layer
/// needs a lifecycle for rotation and interruption, and because the session must start and stop
/// against `viewWillAppear` / `viewDidDisappear`, not `onAppear`. The blocking work is on
/// `ScannerSession`; this class owns the layer, the permission prompt and the notifications.
final class ScannerViewController: UIViewController {
    weak var delegate: (any ScannerViewControllerDelegate)?
    let debouncer: ScanDebouncer
    var torchOn = false {
        didSet {
            guard torchOn != oldValue else { return }
            let torchOn = torchOn
            Task { await capture.setTorch(torchOn) }
        }
    }

    private lazy var capture = ScannerSession { [weak self] value, type in
        self?.handleRead(value, type: type)
    }

    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: capture.session)
    private var observers: [any NSObjectProtocol] = []

    init(debouncer: ScanDebouncer) {
        self.debouncer = debouncer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("ScannerViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        // Rotate from the *interface* orientation, not the device's: an iPad flat on a counter
        // reports .faceUp forever, and a device-orientation preview never rotates.
        if let connection = previewLayer.connection, let scene = view.window?.windowScene {
            let angle: CGFloat = switch scene.effectiveGeometry.interfaceOrientation {
            case .landscapeLeft: 180
            case .landscapeRight: 0
            case .portraitUpsideDown: 270
            default: 90
            }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
        // rectOfInterest lives in the capture device's coordinate space; converting through the
        // preview layer is the only way to get a rect that is still correct in landscape.
        let window = view.bounds.insetBy(dx: view.bounds.width * 0.1, dy: view.bounds.height * 0.3)
        let interest = previewLayer.metadataOutputRectConverted(fromLayerRect: window)
        Task { await capture.setRectOfInterest(interest) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        observe()
        Task { await startIfPermitted() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        unobserve()
        Task { await capture.stop() }
    }

    private func startIfPermitted() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                delegate?.scanner(self, didFailWith: .permissionDenied)
                return
            }
        default:
            delegate?.scanner(self, didFailWith: .permissionDenied)
            return
        }
        // The sheet may have been closed while the permission prompt was up.
        guard view.window != nil else { return }
        if let error = await capture.start() {
            delegate?.scanner(self, didFailWith: error)
        } else {
            // The preview connection exists only now; rotation and the rect of interest need a pass.
            view.setNeedsLayout()
        }
    }

    private func handleRead(_ value: String, type: String) {
        guard debouncer.shouldAccept(value) else { return }
        delegate?.scanner(self, didRead: value, symbology: type)
    }

    // MARK: Interruptions

    /// Observed only while visible, so the observers go away with the session.
    private func observe() {
        let center = NotificationCenter.default
        // `capture.session` is read per call: each read is its own value for the region checker,
        // and the object filter is all the notification centre does with it.
        let interrupted = center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: capture.session, queue: nil
        ) { [weak self] note in
            // .videoDeviceNotAvailableWithMultipleForegroundApps is the iPad case: Split View took the camera.
            let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int)
                .flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
                ?? .videoDeviceNotAvailableInBackground
            Task { @MainActor in
                guard let self else { return }
                self.delegate?.scanner(self, didFailWith: .interrupted(reason))
            }
        }
        let resumable = [AVCaptureSession.interruptionEndedNotification, AVCaptureSession.runtimeErrorNotification]
        observers = [interrupted] + resumable.map { name in
            center.addObserver(forName: name, object: capture.session, queue: nil) { [weak self] _ in
                Task { @MainActor in self?.resume() }
            }
        }
    }

    private func unobserve() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
    }

    private func resume() {
        Task {
            if await capture.restartOnce() {
                delegate?.scannerDidRecover(self)
            } else {
                delegate?.scanner(self, didFailWith: .unavailable)
            }
        }
    }
}
