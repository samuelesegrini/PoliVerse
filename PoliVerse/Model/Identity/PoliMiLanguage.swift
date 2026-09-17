import Foundation

/// Which language to ask the Politecnico's services for.
///
/// The catalogue, the agenda and the teaching pages all answer in Italian or
/// English depending on a `lang` parameter, and every call in the app asked
/// for `IT` regardless. That was right while the interface was hardcoded
/// Italian; with a String Catalog it means an English-reading student gets an
/// English app full of Italian course descriptions.
///
/// Only these two: the Politecnico publishes no others, and asking for a
/// language it does not have returns Italian anyway — so anything that is not
/// English asks for Italian, which is also the right answer for the many
/// students whose phone is set to a third language but who study here.
nonisolated enum PoliMiLanguage: String, Sendable {
    case italian = "IT"
    case english = "EN"

    /// The language the app is currently displaying.
    ///
    /// Read from the bundle rather than the phone's preferred list: the bundle
    /// has already resolved the preference against what the app actually
    /// ships, so this agrees with the text beside it. Asking `Locale` directly
    /// would request English content for an app rendering in Italian.
    static var current: PoliMiLanguage {
        let identifier = Bundle.main.preferredLocalizations.first ?? "it"
        return identifier.hasPrefix("en") ? .english : .italian
    }

    /// Lowercase, for the handful of endpoints that want it that way.
    var lowercased: String { rawValue.lowercased() }

    /// The `Accept-Language` header value to go with it.
    var acceptLanguage: String {
        switch self {
        case .italian: "it-IT,it;q=0.9"
        case .english: "en-GB,en;q=0.9"
        }
    }
}
