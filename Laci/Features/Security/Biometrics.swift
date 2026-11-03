import Foundation
import LocalAuthentication

nonisolated enum BiometricKind: Hashable, Sendable {
    case none
    case faceID
    case touchID
}

nonisolated protocol BiometricAuthenticating: Sendable {
    func kind() -> BiometricKind
    func authenticate() async -> Bool
}

/// `LAContext` is a door, not a safe (SPEC §15): nothing is encrypted behind it, and anyone whose
/// face or finger is enrolled on this iPad passes. That is enough to keep a nephew out of the
/// margins, which is the threat this gate exists for. The biometrics-only policy is deliberate:
/// the fallback is the app's PIN, because a device passcode the whole shop knows would open it.
nonisolated struct SystemBiometrics: BiometricAuthenticating {
    func kind() -> BiometricKind {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .none }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    /// Any failure, cancel or "Gunakan PIN" lands on the PIN pad, which is already on screen.
    func authenticate() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = String(localized: "Gunakan PIN")
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: String(localized: "Buka layar khusus pemilik.")
            )
        } catch {
            return false
        }
    }
}

/// The simulator's answer anyway, stated so UI tests never depend on its enrolment state.
nonisolated struct NoBiometrics: BiometricAuthenticating {
    func kind() -> BiometricKind {
        .none
    }

    func authenticate() async -> Bool {
        false
    }
}
