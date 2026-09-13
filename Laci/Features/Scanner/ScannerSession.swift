import AVFoundation
import Foundation
import os

/// The capture stack, confined to the session queue (SPEC §6). The actor executes on that queue,
/// so `startRunning()`, configuration, torch and the rect of interest never touch main, and the
/// camera's device, output and flags never leave this isolation. Only Strings and a `CGRect`
/// cross the boundary.
actor ScannerSession {
    private let queue: DispatchSerialQueue
    nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// The one object AVFoundation requires in two isolation domains: the preview layer must own it
    /// on main, and it must be configured, started and stopped here. Neither class is Sendable in
    /// the iOS 26.5 SDK, so Swift cannot express that split honestly. The invariant that makes this
    /// safe: this actor is the only place that configures, starts or stops the session, and main
    /// reads it exactly once, to build the preview layer, before the first `start()`.
    nonisolated(unsafe) let session = AVCaptureSession()

    private let metadataQueue = DispatchQueue(label: "id.laci.capture-metadata")
    private let receiver: MetadataReceiver
    private let log = Logger(subsystem: "id.laci", category: "scan")
    private var device: AVCaptureDevice?
    private var output: AVCaptureMetadataOutput?
    private var isConfigured = false
    private var restartAttempted = false

    init(onRead: @escaping @MainActor (String, String) -> Void) {
        queue = DispatchSerialQueue(label: "id.laci.capture-session")
        receiver = MetadataReceiver(onRead: onRead)
    }

    /// Blocking, on this executor and never on main. Returns what the sheet should show instead
    /// of a preview when the camera cannot run.
    func start() -> ScanError? {
        restartAttempted = false
        if !isConfigured {
            configure()
        }
        guard isConfigured else { return .unavailable }
        if !session.isRunning {
            session.startRunning()
        }
        return nil
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    /// One restart after an interruption ends or the media services reset, then give up and let
    /// the sheet show manual entry. A retry loop here spins the camera forever on a wedged device.
    func restartOnce() -> Bool {
        guard !restartAttempted else { return false }
        restartAttempted = true
        if !session.isRunning {
            session.startRunning()
        }
        return session.isRunning
    }

    func setTorch(_ enabled: Bool) {
        guard let device, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            // Level 0.6, not .on: full brightness blows out a glossy label at 15 cm and thermally
            // throttles a long stocktake.
            if enabled {
                try device.setTorchModeOn(level: 0.6)
            } else {
                device.torchMode = .off
            }
        } catch {
            log.error("torch: \(String(describing: error), privacy: .public)")
        }
    }

    /// Already converted through the preview layer, so it is in the capture device's space.
    func setRectOfInterest(_ rect: CGRect) {
        output?.rectOfInterest = rect
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // 4K buys nothing for a 1D barcode and costs thermals.
        session.sessionPreset = .hd1280x720

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input)
        else {
            log.error("no usable back camera")
            return
        }
        session.addInput(input)
        device = camera

        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            // Barcodes arrive 10–20 cm from the lens; the near restriction stops it hunting to infinity.
            if camera.isAutoFocusRangeRestrictionSupported {
                camera.autoFocusRangeRestriction = .near
            }
            camera.unlockForConfiguration()
        } catch {
            log.error("focus: \(String(describing: error), privacy: .public)")
        }

        let metadata = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadata) else {
            log.error("metadata output refused")
            return
        }
        session.addOutput(metadata)
        // Must be set AFTER addOutput: availableMetadataObjectTypes is empty before it.
        metadata.metadataObjectTypes = [.ean13, .ean8, .upce, .code128, .code39, .itf14, .qr]
        metadata.setMetadataObjectsDelegate(receiver, queue: metadataQueue)
        output = metadata
        isConfigured = true
    }
}

/// Runs on the metadata queue at the frame rate. It reads the payload and its type, both Strings,
/// and hands them to main; nothing AVFoundation owns crosses with them.
private final nonisolated class MetadataReceiver: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    private let onRead: @MainActor (String, String) -> Void

    init(onRead: @escaping @MainActor (String, String) -> Void) {
        self.onRead = onRead
    }

    func metadataOutput(
        _: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from _: AVCaptureConnection
    ) {
        guard let code = objects.first as? AVMetadataMachineReadableCodeObject,
              let value = code.stringValue, !value.isEmpty else { return }
        let type = code.type.rawValue
        let onRead = onRead
        Task { @MainActor in onRead(value, type) }
    }
}
