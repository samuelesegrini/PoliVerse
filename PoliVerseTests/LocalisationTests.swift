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

    /// The onboarding is the first English text anyone sees, and it is the
    /// easiest to ship untranslated: the catalogue is only regenerated when
    /// Xcode is opened, so a screen added from an editor arrives with its
    /// Italian keys intact and no test noticing.
    @Test("The onboarding screens are in the catalogue, not falling back to the keys")
    func onboardingIsTranslated() {
        let keys = [
            "L'orario, senza cercarlo",
            "Accedi con l'account del Politecnico",
            "Promemoria per lezioni ed esami",
            "Hai più di una carriera",
            "Collega WeBeep",
            "Tutto pronto",
            "Dati di esempio",
        ]
        for key in keys {
            let resolved = String(localized: String.LocalizationValue(key))
            #expect(!resolved.isEmpty)
            if PoliMiLanguage.current == .english {
                #expect(resolved != key, "\(key) still reads as the Italian key in English")
            }
        }
    }

    /// The updates feed, its notifications and Siri's answers, read from the
    /// English localisation directly — whatever language the test device
    /// runs in, a key that fell back to Italian shows up here.
    @Test("The updates feature is translated into English, plurals included")
    func updatesTranslated() throws {
        let path = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let english = try #require(Bundle(path: path))
        let keys = [
            "Esito pubblicato", "Puoi rifiutare il voto", "Aula cambiata", "Sei negli esiti",
            "Pubblicato un file di esiti", "Nuovo annuncio del docente", "Nuova consegna",
            "Consegna domani", "Novità esami", "Cronologia", "Aggiungi al calendario",
            "Corsi silenziati", "Cerca la mia matricola negli esiti", "Voto confermato sui Servizi Online",
        ]
        for key in keys {
            let resolved = english.localizedString(forKey: key, value: nil, table: "Localizable")
            #expect(resolved != key, "\(key) is not translated into English")
        }
        let one = String(localized: "\(1) nuovi file", bundle: english, locale: Locale(identifier: "en"))
        let many = String(localized: "\(3) nuovi file", bundle: english, locale: Locale(identifier: "en"))
        #expect(one == "1 new file")
        #expect(many == "3 new files")
    }
}
