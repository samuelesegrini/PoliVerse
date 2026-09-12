import Foundation
import Testing
@testable import PoliVerse

/// The twelve SPID providers are hardcoded from a measurement, and a
/// measurement goes stale: providers join the federation, leave it, and get
/// renumbered. The page lists them every time we load it, so the app reads
/// them from there and keeps what it read — the same lesson the `maps_rest`
/// WADL taught, which is to ask the service to describe itself.
@Suite("SPID catalogue")
@MainActor
struct SPIDCatalogueTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "spid-tests-\(UUID().uuidString)")!
    }

    /// The shape the extraction script returns, taken from the live page.
    private let json = """
    [{"slug":"posteID","identifier":"1201","name":"Poste ID"},
     {"slug":"timID","identifier":"1200","name":"Tim ID"}]
    """

    @Test("With nothing stored, the measured list is used")
    func fallsBackToMeasuredList() {
        let catalogue = SPIDCatalogue(defaults: defaults())
        #expect(catalogue.providers.count == 12)
    }

    @Test("A list read from the page replaces the measured one")
    func adoptsPageList() {
        let catalogue = SPIDCatalogue(defaults: defaults())
        catalogue.adopt(json)
        #expect(catalogue.providers.map(\.slug) == ["posteID", "timID"])
    }

    @Test("What was read survives the next launch")
    func persists() {
        let defaults = defaults()
        SPIDCatalogue(defaults: defaults).adopt(json)
        #expect(SPIDCatalogue(defaults: defaults).providers.count == 2)
    }

    /// The page is not ours and can change shape without warning. Anything we
    /// cannot read is ignored in favour of what already worked — an empty SPID
    /// list would be a login method silently disappearing.
    @Test("An unreadable list is ignored")
    func ignoresGarbage() {
        let catalogue = SPIDCatalogue(defaults: defaults())
        catalogue.adopt("not json at all")
        #expect(catalogue.providers.count == 12)
        catalogue.adopt("[]")
        #expect(catalogue.providers.count == 12)
    }

    /// A provider with no slug cannot be pressed, so a list containing one is
    /// a list we would silently mis-serve.
    @Test("Entries missing what identifies them are dropped")
    func dropsIncompleteEntries() {
        let catalogue = SPIDCatalogue(defaults: defaults())
        catalogue.adopt("""
        [{"slug":"posteID","identifier":"1201","name":"Poste ID"},
         {"slug":"","identifier":"9","name":"Nameless"}]
        """)
        #expect(catalogue.providers.map(\.slug) == ["posteID"])
    }

    @Test("The extraction script reads what the page actually carries")
    func extractionScriptTargetsTheMarkup() {
        let script = SPIDCatalogue.extractionScript
        #expect(script.contains("data-idp"))
        #expect(script.contains("spid-sr-only"))
        #expect(script.contains("id_idp"))
    }
}

/// Which way in the student used last time. A student who signs in with Poste
/// ID every term should not have to go looking for it behind a SPID button
/// every time.
@Suite("Last login method")
@MainActor
struct LoginMethodMemoryTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "method-tests-\(UUID().uuidString)")!
    }

    @Test("With nothing remembered, the password is offered first")
    func defaultsToPassword() {
        #expect(LoginMethodMemory(defaults: defaults()).last() == .password)
    }

    @Test("A remembered method comes back, provider and all")
    func remembersSPIDProvider() {
        let defaults = defaults()
        let poste = SPIDProvider.all.first { $0.slug == "posteID" }!
        LoginMethodMemory(defaults: defaults).remember(.spid(poste))
        #expect(LoginMethodMemory(defaults: defaults).last() == .spid(poste))
    }

    @Test("Every method survives the round trip")
    func remembersEachMethod() {
        for method in [PoliMiLoginMethod.password, .cie, .eidas, .eduGAIN] {
            let defaults = defaults()
            LoginMethodMemory(defaults: defaults).remember(method)
            #expect(LoginMethodMemory(defaults: defaults).last() == method)
        }
    }

    /// A provider that has left the federation must not resurrect as a button
    /// that presses nothing.
    @Test("A provider that no longer exists falls back to the password")
    func forgetsVanishedProvider() {
        let defaults = defaults()
        defaults.set("spid-goneID", forKey: "lastLoginMethod")
        #expect(LoginMethodMemory(defaults: defaults).last() == .password)
    }

    /// The provider list the page last reported is what the memory resolves
    /// against — not the list the app shipped with.
    @Test("A provider the page has dropped is not offered again")
    func resolvesAgainstCurrentProviders() {
        let defaults = defaults()
        let poste = SPIDProvider.all.first { $0.slug == "posteID" }!
        LoginMethodMemory(defaults: defaults).remember(.spid(poste))
        let remaining = SPIDProvider.all.filter { $0.slug != "posteID" }
        #expect(LoginMethodMemory(defaults: defaults).last(in: remaining) == .password)
    }
}
