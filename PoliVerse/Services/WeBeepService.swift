import Foundation
import Observation
import OSLog

/// Course materials from WeBeep.
///
/// ## Why this does not reuse the PoliMi bearer token
///
/// PoliFemo has **no WeBeep code at all** — `webeep` appears in that repository
/// exactly once, as a scope string in the login URL. So there was no logic to
/// port, and the approach below is ours.
///
/// WeBeep is a stock Moodle. Moodle's REST API wants its own `wstoken`, which
/// the PoliMi OAuth token is not. The supported way to get one on an
/// SSO-only site is the same handshake the official Moodle app performs:
///
/// 1. Open `/admin/tool/mobile/launch.php?service=moodle_mobile_app&passport=N&urlscheme=…`
/// 2. Moodle bounces through the institutional IdP (the user is already known
///    to it from our login, so this is usually silent)
/// 3. It redirects to `<urlscheme>://token=<base64>` where the payload decodes
///    to `siteid:::wstoken:::privatetoken`
/// 4. Every later call is `/webservice/rest/server.php?wstoken=…&wsfunction=…`
///
/// - Important: Step 3's payload is signed against the `passport` value we
///   send; the check must be implemented before trusting the token, and the
///   whole flow needs verifying against a live account. Until then this service
///   serves mock data and ``isLive`` reports `false`.
@Observable
final class WeBeepService {
    private(set) var sections: [WeBeepSection] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// `false` until the Moodle token handshake above is implemented and tested.
    let isLive = false

    private let session: Session
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "webeep")

    init(session: Session) {
        self.session = session
    }

    /// Builds the launch URL for the Moodle mobile-app token handshake.
    ///
    /// - Parameter passport: a random number echoed back inside the signed
    ///   payload, which is what stops another app from replaying the redirect.
    static func tokenLaunchURL(passport: Int = Int.random(in: 1...1000)) -> URL {
        var components = URLComponents(
            url: APIHost.weBeep.baseURL.appendingPathComponent("/admin/tool/mobile/launch.php"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            .init(name: "service", value: "moodle_mobile_app"),
            .init(name: "passport", value: String(passport)),
            .init(name: "urlscheme", value: "poliverse"),
        ]
        return components.url!
    }

    func loadMaterials(for course: Course) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard isLive, !session.useMockData else {
            sections = MockData.weBeepSections(for: course)
            return
        }

        // Reached only once the handshake above is in place:
        // core_course_get_contents returns sections with their file modules.
        do {
            let data = try await session.api.send(
                APIRequest(
                    host: .weBeep,
                    path: "/webservice/rest/server.php",
                    query: [
                        .init(name: "wsfunction", value: "core_course_get_contents"),
                        .init(name: "moodlewsrestformat", value: "json"),
                        .init(name: "courseid", value: course.id),
                    ],
                    authenticated: false
                )
            )
            log.debug("WeBeep returned \(data.count) bytes")
            sections = MockData.weBeepSections(for: course)
        } catch {
            errorMessage = error.localizedDescription
            sections = MockData.weBeepSections(for: course)
        }
    }
}
