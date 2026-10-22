import Foundation
import Testing
@testable import PoliVerse

/// The link a SPID provider's page uses to open its app has to reach the app,
/// and the page that is waiting for the approval has to stay put.
@Suite("Identity app hand-off")
struct IdentityAppHandoffTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    /// The address PosteID's login script builds on a phone, as read off the
    /// live page on 2026-10-22.
    @Test("PosteID's quick sign-in link is a hand-off")
    func posteIDLink() {
        let route = IdentityAppHandoff.route(for: url(
            "https://appregistry-posteid.mobile.poste.it/jod-login-schema/btcs/pid/access/v1/?tranId=abc123"))
        #expect(route?.appName == "PosteID")
        #expect(IdentityAppHandoff.route(for: url(
            "https://appregistry-posteid.mobile.poste.it/jod-securelogin-schema/btcs/pid/access/v1/?tranId=x")) != nil)
    }

    @Test("The provider's own pages and its QR paths are not hand-offs")
    func ordinaryPages() {
        for candidate in [
            "https://posteid.poste.it/jod-login-schema/login.jsp",
            "https://appregistry-posteid.mobile.poste.it/jod-login-schema/qrcs/pid/access/v1/?x=1",
            "http://appregistry-posteid.mobile.poste.it/jod-login-schema/btcs/pid/access/v1/",
            "https://aunicalogin.polimi.it/aunicalogin/aunicalogin.jsp",
        ] {
            #expect(IdentityAppHandoff.route(for: url(candidate)) == nil, "\(candidate)")
        }
    }

    @Test("A provider's own scheme is for another app")
    func externalSchemes() {
        #expect(IdentityAppHandoff.isExternalScheme(url("mysielteid://auth?x=1")))
        #expect(IdentityAppHandoff.isExternalScheme(url("itms-apps://apps.apple.com/app/id1")))
    }

    /// The schemes the sign-in catches for itself must reach their own handlers,
    /// not be given away to the system.
    @Test("Web schemes and the sign-in's own schemes stay in the web view")
    func ownSchemes() {
        for candidate in [
            "https://posteid.poste.it/", "about:blank", "javascript:void(0)",
            "poliverse://token=abc", "moodlemobile://token=abc",
            "segrini.samuele.PoliVerse://https://idserver.servizicie.interno.gov.it/x",
            "CIEID://https://ios.idserver.servizicie.interno.gov.it/x",
        ] {
            #expect(!IdentityAppHandoff.isExternalScheme(url(candidate)), "\(candidate)")
        }
    }
}
