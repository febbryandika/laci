import Foundation

/// Renders a resource in a named language, whatever language the test host runs in. The simulator
/// CI uses is English, so a test that compares copy must say which table it means.
func localized(_ resource: LocalizedStringResource, in language: String = "id") -> String {
    var resource = resource
    resource.locale = Locale(identifier: language)
    return String(localized: resource)
}
