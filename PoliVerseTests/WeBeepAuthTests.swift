import Testing
import Foundation
@testable import PoliVerse

/// Payloads here are built the way `admin/tool/mobile/launch.php` builds them:
///
/// ```php
/// $siteid = md5($CFG->wwwroot . $passport);
/// $apptoken = $siteid . ':::' . $token->token;          // + ':::' . $privatetoken
/// $location = "$urlscheme://token=" . base64_encode($apptoken);
/// ```
@Suite("WeBeep token handshake")
struct WeBeepAuthTests {
    private func redirect(
        scheme: String = "poliverse",
        siteID: String,
        token: String,
        privateToken: String? = nil,
        stripPadding: Bool = false
    ) -> URL {
        var payload = "\(siteID):::\(token)"
        if let privateToken { payload += ":::\(privateToken)" }
        var encoded = Data(payload.utf8).base64EncodedString()
        if stripPadding { encoded = encoded.replacingOccurrences(of: "=", with: "") }
        return URL(string: "\(scheme)://token=\(encoded)")!
    }

    private func validSiteID(passport: String) -> String {
        WeBeepAuth.md5Hex(WeBeepAuth.siteURL + passport)
    }

    @Test("A well-formed redirect yields the token")
    func parsesToken() throws {
        let passport = "918273"
        let url = redirect(siteID: validSiteID(passport: passport), token: "abc123token")

        let result = try WeBeepAuth.token(from: url, passport: passport)
        #expect(result.token == "abc123token")
        #expect(result.privateToken == nil)
    }

    @Test("The private token is read when present")
    func parsesPrivateToken() throws {
        let passport = "5551212"
        let url = redirect(
            siteID: validSiteID(passport: passport),
            token: "tok", privateToken: "priv"
        )

        let result = try WeBeepAuth.token(from: url, passport: passport)
        #expect(result.token == "tok")
        #expect(result.privateToken == "priv")
    }

    /// launch.php omits the private token unless the user just logged in, so a
    /// two-part payload must not be treated as malformed.
    @Test("A two-part payload is valid, not an error")
    func twoPartPayloadIsValid() throws {
        let passport = "42424242"
        let url = redirect(siteID: validSiteID(passport: passport), token: "only")
        #expect(try WeBeepAuth.token(from: url, passport: passport).token == "only")
    }

    /// `forcedurlscheme` can override the scheme we asked for, so the
    /// interceptor has to accept Moodle's default too.
    @Test("A forced moodlemobile scheme is still accepted")
    func acceptsForcedScheme() throws {
        let passport = "777000"
        let url = redirect(
            scheme: "moodlemobile",
            siteID: validSiteID(passport: passport), token: "forced"
        )
        #expect(try WeBeepAuth.token(from: url, passport: passport).token == "forced")
    }

    @Test("An unrelated scheme is rejected")
    func rejectsOtherSchemes() {
        let passport = "1"
        let url = redirect(scheme: "https", siteID: validSiteID(passport: passport), token: "x")
        #expect(throws: WeBeepAuth.TokenError.notATokenRedirect) {
            _ = try WeBeepAuth.token(from: url, passport: passport)
        }
    }

    /// The signature binds the payload to the passport we generated for this
    /// attempt; a payload minted for a different passport must not be accepted.
    @Test("A payload signed for another passport is rejected")
    func rejectsWrongPassport() {
        let url = redirect(siteID: validSiteID(passport: "1111"), token: "x")
        #expect(throws: WeBeepAuth.TokenError.signatureMismatch) {
            _ = try WeBeepAuth.token(from: url, passport: "2222")
        }
    }

    @Test("Unparseable payloads are rejected rather than guessed at")
    func rejectsGarbage() {
        let passport = "9"
        #expect(throws: (any Error).self) {
            _ = try WeBeepAuth.token(
                from: URL(string: "poliverse://token=!!!not-base64!!!")!, passport: passport)
        }
        // Base64 that decodes but has no ':::' separator.
        let noSeparator = Data("justonevalue".utf8).base64EncodedString()
        #expect(throws: WeBeepAuth.TokenError.malformedPayload) {
            _ = try WeBeepAuth.token(
                from: URL(string: "poliverse://token=\(noSeparator)")!, passport: passport)
        }
    }

    @Test("Base64 arriving without padding still decodes")
    func handlesUnpaddedBase64() throws {
        let passport = "31337"
        let url = redirect(
            siteID: validSiteID(passport: passport),
            token: "abcdefghij", stripPadding: true
        )
        #expect(try WeBeepAuth.token(from: url, passport: passport).token == "abcdefghij")
    }

    @Test("The launch URL carries what Moodle expects")
    func launchURLShape() throws {
        let components = try #require(URLComponents(
            url: WeBeepAuth.launchURL(passport: "123"), resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        func value(_ n: String) -> String? { items.first { $0.name == n }?.value }

        #expect(components.host == "webeep.polimi.it")
        #expect(components.path == "/admin/tool/mobile/launch.php")
        #expect(value("service") == "moodle_mobile_app")
        #expect(value("passport") == "123")
        #expect(value("urlscheme") == WeBeepAuth.urlScheme)
    }

    @Test("Each attempt gets its own passport")
    func passportsDiffer() {
        let passports = Set((0..<50).map { _ in WeBeepAuth.newPassport() })
        #expect(passports.count > 45)
    }

    /// Sanity-check the MD5 helper against a known vector, since the signature
    /// check is worthless if the hash is wrong.
    @Test("MD5 matches a known vector")
    func md5KnownVector() {
        #expect(WeBeepAuth.md5Hex("abc") == "900150983cd24fb0d6963f7d28e17f72")
        #expect(WeBeepAuth.md5Hex("") == "d41d8cd98f00b204e9800998ecf8427e")
    }
}

@Suite("Moodle file URLs")
struct WeBeepAPITests {
    @Test("The token is appended to file URLs")
    func appendsToken() throws {
        let api = WeBeepAPI(token: "TOK")
        let url = try #require(api.authenticatedFileURL(
            "https://webeep.polimi.it/webservice/pluginfile.php/123/mod_resource/content/1/a.pdf"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "token" }?.value == "TOK")
    }

    /// A stale token already on the URL must be replaced, not duplicated —
    /// Moodle takes the first occurrence and would reject the old one.
    @Test("An existing token is replaced, not duplicated")
    func replacesExistingToken() throws {
        let api = WeBeepAPI(token: "NEW")
        let url = try #require(api.authenticatedFileURL(
            "https://webeep.polimi.it/webservice/pluginfile.php/1/a.pdf?token=OLD&forcedownload=1"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let tokens = items.filter { $0.name == "token" }
        #expect(tokens.count == 1)
        #expect(tokens.first?.value == "NEW")
    }
}
