import Foundation
import Testing
@testable import PoliVerse

/// The app now ships Italian and English, and the Politecnico's services take
/// a language too. Asking them for the wrong one produces the worst outcome:
/// an English interface full of Italian course descriptions.
@Suite("Localisation")
struct LocalisationTests {
    /// Both localisations are actually in the bundle. Without this the String
    /// Catalog could be present and empty and everything would silently fall
    /// back to the keys.
    @Test("The app ships Italian and English")
    func bundled() {
        let localisations = Set(Bundle.main.localizations)
        #expect(localisations.contains("it"))
        #expect(localisations.contains("en"))
    }

    /// Read from the bundle, not from the phone's preferred list: the bundle
    /// has resolved the preference against what the app actually ships, so the
    /// request agrees with the text beside it.
    @Test("The upstream language follows what the app is displaying")
    func followsDisplay() {
        let displaying = Bundle.main.preferredLocalizations.first ?? "it"
        let expected: PoliMiLanguage = displaying.hasPrefix("en") ? .english : .italian
        #expect(PoliMiLanguage.current == expected)
    }

    /// Anything that is not English asks for Italian — the Politecnico
    /// publishes no third language, and a student here whose phone is in
    /// German is better served by Italian than by a fallback.
    @Test("Only two values exist, and they are what the service expects")
    func values() {
        #expect(PoliMiLanguage.italian.rawValue == "IT")
        #expect(PoliMiLanguage.english.rawValue == "EN")
        #expect(PoliMiLanguage.italian.lowercased == "it")
    }

    @Test("Each language carries a matching Accept-Language")
    func acceptLanguage() {
        #expect(PoliMiLanguage.italian.acceptLanguage.hasPrefix("it"))
        #expect(PoliMiLanguage.english.acceptLanguage.hasPrefix("en"))
    }

    /// A spot check that the catalogue is wired up: a key the app uses
    /// resolves to something, in whichever language is active.
    @Test("A known key resolves through the catalogue")
    func catalogueResolves() {
        let resolved = String(localized: "Aule libere")
        #expect(!resolved.isEmpty)
        // In English it must not still be the Italian key.
        if PoliMiLanguage.current == .english {
            #expect(resolved == "Free rooms")
        } else {
            #expect(resolved == "Aule libere")
        }
    }
}
