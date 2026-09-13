import AVFoundation
import LaciCore
import Testing

/// `Symbology` stores what the camera read, so its raw values must be AVFoundation's type strings.
/// LaciCore cannot import AVFoundation, so the contract is pinned here, in the app target.
@Suite("Symbology raw values")
struct SymbologyTypesTests {
    @Test("Every case matches its AVMetadataObject.ObjectType, and nothing is missing")
    func matchesAVFoundation() {
        let expected: [Symbology: AVMetadataObject.ObjectType] = [
            .ean13: .ean13, .ean8: .ean8, .upce: .upce, .code128: .code128, .code39: .code39, .itf14: .itf14,
            .qrCode: .qr,
        ]
        #expect(expected.count == Symbology.allCases.count)
        for symbology in Symbology.allCases {
            #expect(expected[symbology]?.rawValue == symbology.rawValue, "\(symbology)")
        }
    }
}
