import Foundation

/// Which language to ask the Politecnico's services for.
///
/// The catalogue, the agenda and the teaching pages answer in Italian or English
/// depending on a `lang` parameter, and requests carry ``current`` so that the
/// content matches the interface.
///
/// Only these two exist: the Politecnico publishes no others, and asking for a
/// language it does not have returns Italian.
nonisolated enum PoliMiLanguage: String, Sendable {
    /// Italian, and the answer for any interface language that is not English.
    case italian = "IT"
    /// English.
    case english = "EN"

    /// The language the app is currently displaying.
    ///
    /// Read from the bundle's preferred localizations rather than from `Locale`, since
    /// the bundle has already resolved the device's preference against what the app
    /// ships. Asking `Locale` directly would request English content for an app
    /// rendering in Italian.
    static var current: PoliMiLanguage {
        let identifier = Bundle.main.preferredLocalizations.first ?? "it"
        return identifier.hasPrefix("en") ? .english : .italian
    }

    /// The code in lower case, for the endpoints that want it that way.
    var lowercased: String { rawValue.lowercased() }

    /// The `Accept-Language` header value for this language.
    var acceptLanguage: String {
        switch self {
        case .italian: "it-IT,it;q=0.9"
        case .english: "en-GB,en;q=0.9"
        }
    }
}
