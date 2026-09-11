import Testing
import Foundation
@testable import PoliVerse

/// Shapes here follow `italia/cieid-ios-sdk`
/// (`CieIDWKWebViewController.redirectFlow` and the demo `SceneDelegate`).
@Suite("CieID hand-off")
struct CieIDBridgeTests {
    // MARK: - Outbound

    @Test("An IdP URL carrying nextUrl is recognised as the hand-off")
    func detectsHandoff() throws {
        let url = try #require(URL(string:
            "https://ios.idserver.servizicie.interno.gov.it/idp/Authn/SSO?nextUrl=https%3A%2F%2Fx"))
        #expect(CieIDBridge.isHandoffToCieID(url))
    }

    /// The SDK also triggers on the assurance-level paths, which do not carry
    /// `nextUrl`.
    @Test("livello1 and livello2 paths are recognised")
    func detectsAssuranceLevels() throws {
        for level in ["livello1", "livello2"] {
            let url = try #require(URL(string: "https://idserver.servizicie.interno.gov.it/idp/\(level)/x"))
            #expect(CieIDBridge.isHandoffToCieID(url), "\(level) should be a hand-off")
        }
    }

    @Test("Ordinary navigation is left alone")
    func ignoresUnrelated() throws {
        for candidate in [
            "https://webeep.polimi.it/my/",
            "https://shibidp.polimi.it/idp/profile/SAML2/Redirect/SSO",
            "https://polimiapp.polimi.it/polimi_app/app?code=ABC",
        ] {
            let url = try #require(URL(string: candidate))
            #expect(CieIDBridge.isHandoffToCieID(url) == false, "\(candidate) should not be a hand-off")
        }
    }

    /// Without `sourceApp` CieID has no idea who called it and returns the
    /// authenticated URL to the default browser — the bug this all exists to
    /// fix.
    @Test("The hand-off URL carries sourceApp and the CIEID scheme")
    func buildsHandoffURL() throws {
        let idp = try #require(URL(string:
            "https://ios.idserver.servizicie.interno.gov.it/idp/Authn/SSO?nextUrl=abc"))
        let handoff = try #require(CieIDBridge.handoffURL(for: idp))

        let string = handoff.absoluteString
        #expect(string.hasPrefix("CIEID://"))
        #expect(string.contains("sourceApp=\(CieIDBridge.returnScheme)"))
        // The original URL must survive intact, unescaped.
        #expect(string.contains("https://ios.idserver.servizicie.interno.gov.it/idp/Authn/SSO"))
        #expect(string.contains("nextUrl=abc"))
    }

    @Test("A query-less URL still gets a well-formed sourceApp")
    func handoffWithoutExistingQuery() throws {
        let idp = try #require(URL(string:
            "https://idserver.servizicie.interno.gov.it/idp/livello2"))
        let handoff = try #require(CieIDBridge.handoffURL(for: idp))
        // '?' not '&', or the parameter is lost.
        #expect(handoff.absoluteString.contains("?sourceApp="))
        #expect(handoff.absoluteString.contains("&sourceApp=") == false)
    }

    // MARK: - Inbound

    @Test("The https URL is recovered from the return")
    func parsesReturn() throws {
        let url = try #require(URL(string:
            "one.wape.PoliVerse://https://idserver.servizicie.interno.gov.it/idp/x?codice=1"))
        let recovered = try #require(CieIDBridge.returnURL(from: url))

        #expect(recovered.scheme == "https")
        #expect(recovered.host == "idserver.servizicie.interno.gov.it")
        #expect(recovered.absoluteString.contains("codice=1"))
    }

    /// CieID sometimes returns `https//` with a single slash. The official SDK
    /// patches exactly this before parsing, so a regression here would break
    /// real logins while every well-formed test still passed.
    @Test("A mangled https// return is repaired")
    func repairsMangledScheme() throws {
        let url = try #require(URL(string:
            "one.wape.PoliVerse://https//idserver.servizicie.interno.gov.it/idp/x"))
        let recovered = try #require(CieIDBridge.returnURL(from: url))

        #expect(recovered.scheme == "https")
        #expect(recovered.host == "idserver.servizicie.interno.gov.it")
    }

    @Test("Other schemes are not treated as a CieID return")
    func rejectsOtherSchemes() throws {
        // The Moodle token redirect shares the app but not this handler.
        let moodle = try #require(URL(string: "poliverse://token=abc"))
        #expect(CieIDBridge.returnURL(from: moodle) == nil)

        let https = try #require(URL(string: "https://idserver.servizicie.interno.gov.it/x"))
        #expect(CieIDBridge.returnURL(from: https) == nil)
    }

    @Test("A return with no embedded https URL yields nil")
    func rejectsPayloadWithoutURL() throws {
        let url = try #require(URL(string: "one.wape.PoliVerse://something-else"))
        #expect(CieIDBridge.returnURL(from: url) == nil)
    }

    @Test("An error reported by CieID is surfaced")
    func extractsErrorMessage() throws {
        let url = try #require(URL(string:
            "one.wape.PoliVerse://https://idserver.servizicie.interno.gov.it/x?cieid_error_message=Operazione%20annullata"))
        let recovered = try #require(CieIDBridge.returnURL(from: url))
        #expect(CieIDBridge.errorMessage(in: recovered) == "Operazione annullata")
    }

    @Test("A clean return reports no error")
    func noErrorOnSuccess() throws {
        let url = try #require(URL(string:
            "one.wape.PoliVerse://https://idserver.servizicie.interno.gov.it/x?codice=1"))
        let recovered = try #require(CieIDBridge.returnURL(from: url))
        #expect(CieIDBridge.errorMessage(in: recovered) == nil)
    }

    // MARK: - Router

    @Test("The router hands a valid return on, and ignores the rest")
    func routerRoutes() throws {
        let router = CieIDRouter()

        #expect(router.handle(try #require(URL(string: "poliverse://token=x"))) == false)
        #expect(router.pendingURL == nil)

        let ok = router.handle(try #require(URL(string:
            "one.wape.PoliVerse://https://idserver.servizicie.interno.gov.it/idp/x")))
        #expect(ok)
        #expect(router.pendingURL != nil)

        // Consuming clears it, so a later redraw cannot reload the same URL.
        #expect(router.consume() != nil)
        #expect(router.pendingURL == nil)
        #expect(router.consume() == nil)
    }

    @Test("An error return sets the message and no pending URL")
    func routerSurfacesError() throws {
        let router = CieIDRouter()
        let handled = router.handle(try #require(URL(string:
            "one.wape.PoliVerse://https://idserver.servizicie.interno.gov.it/x?cieid_error_message=Annullato")))

        #expect(handled)
        #expect(router.errorMessage == "Annullato")
        #expect(router.pendingURL == nil)
    }
}
