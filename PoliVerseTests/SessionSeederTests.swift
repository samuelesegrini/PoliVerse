import Foundation
import Testing
@testable import PoliVerse

/// One sign-in, three sessions: the WeBeep walk has to follow the redirects an
/// identity provider answers from its cookie, and stop the moment a page wants
/// the student — a hidden web view waiting on a password nobody can see is the
/// failure this guards against.
@Suite("Session seeding")
struct SessionSeederTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    private func step(_ string: String, launched: Bool = false) -> SessionSeeder.WeBeepStep {
        SessionSeeder.weBeepStep(for: url(string), launched: launched)
    }

    @Test("The token redirect is read, under either scheme")
    func tokenRedirect() {
        #expect(step("poliverse://token=abc", launched: true) == .token)
        #expect(step("moodlemobile://token=abc", launched: true) == .token)
    }

    @Test("The dashboard asks launch.php for the token, once")
    func dashboardLaunches() {
        #expect(step("https://webeep.polimi.it/my/") == .launch)
        #expect(step("https://webeep.polimi.it/my/", launched: true) == .follow)
    }

    /// aunicalogin and Shibboleth either answer from the cookie, often by a page
    /// that submits itself, or show the chooser; only waiting tells which.
    @Test("The Politecnico's sign-in pages are hops to watch")
    func signInHops() {
        #expect(step("https://aunicalogin.polimi.it/aunicalogin/aunicalogin.jsp?id_servizio=1") == .signInHop)
        #expect(step("https://shibidp.polimi.it/idp/profile/SAML2/Redirect/SSO?execution=e1s1") == .signInHop)
    }

    @Test("The redirects in between are followed")
    func followsRedirects() {
        #expect(step("https://webeep.polimi.it/auth/shibboleth/index.php") == .follow)
        #expect(step("https://webeep.polimi.it/Shibboleth.sso/SAML2/POST") == .follow)
        #expect(step("about:blank") == .follow)
    }

    /// A provider's page means the cookie did not carry the student through,
    /// and Moodle's own login page means it has no session after all.
    @Test("A page that wants the student stops the walk")
    func stopsForStudent() {
        #expect(step("https://posteid.poste.it/jod-login-schema/login.jsp") == .needsStudent)
        #expect(step("https://idserver.servizicie.interno.gov.it/idp/login/livello2") == .needsStudent)
        #expect(step("https://webeep.polimi.it/login/index.php", launched: true) == .needsStudent)
        #expect(step("tel:0223991") == .needsStudent)
    }

    @Test("Only the single sign-on hosts' cookies are carried over")
    func ssoDomains() {
        #expect(SessionSeeder.isSSODomain("aunicalogin.polimi.it"))
        #expect(SessionSeeder.isSSODomain(".aunicalogin.polimi.it"))
        #expect(SessionSeeder.isSSODomain("shibidp.polimi.it"))
        #expect(!SessionSeeder.isSSODomain("polimiapp.polimi.it"))
        #expect(!SessionSeeder.isSSODomain("webeep.polimi.it"))
        #expect(!SessionSeeder.isSSODomain("posteid.poste.it"))
    }
}
