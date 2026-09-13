import AudioToolbox
import SwiftUI

/// A successful scan is haptic *and* audible (SPEC §9): the screen is often not being looked at,
/// and an iPad has no Taptic Engine, so the sound is what the counter hears.
enum ScanFeedback {
    /// System "Tink". A system sound needs no bundled asset and respects the device volume.
    static func play() {
        AudioServicesPlaySystemSound(1057)
    }
}

extension View {
    /// Fires once per accepted scan. `isActive` lets the sell screen stay quiet while the camera
    /// sheet, which carries its own copy of this modifier, is up.
    func scanFeedback(trigger: Int, isActive: Bool) -> some View {
        sensoryFeedback(.success, trigger: trigger) { _, _ in isActive }
            .onChange(of: trigger) {
                if isActive {
                    ScanFeedback.play()
                }
            }
    }
}
