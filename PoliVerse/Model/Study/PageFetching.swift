import Foundation
import OSLog

/// How the Politecnico's HTML-only sites are read.
///
/// The manifesti and scheda services answer pages, not JSON, so they cannot go
/// through ``HTTP`` — that seam is shaped around a REST request and returns
/// bytes a decoder will read. This one returns *markup*, because the caller's
/// next move is always a parse.
///
/// Two methods, which is the whole of the traffic: fetch a page, or post a
/// form and read the page that comes back.
nonisolated protocol PageFetching: Sendable {
    func page(_ url: URL) async -> String?
    func post(_ url: URL, form: [String: String]) async -> String?
}

/// The live adapter: one `URLSession`, configured for what the site is.
///
/// ## Why the two configurations are named here
///
/// The difference between them used to be two initialisers in two files, each
/// explaining itself in a comment. It is one decision — *does this site keep
/// state for me?* — and the two answers now sit next to each other where the
/// contrast is visible.
nonisolated final class ScrapedSite: PageFetching {
    private let session: URLSession
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "pages")

    init(session: URLSession) {
        self.session = session
    }

    /// Reads that keep nothing: no cookies at all, and caching allowed.
    ///
    /// The service serialises requests that share a `JSESSIONID`, so eight
    /// "parallel" detail pages on a cookie-bearing session took eight times as
    /// long as one.
    static func stateless() -> ScrapedSite {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return ScrapedSite(session: URLSession(configuration: configuration))
    }

    /// A conversation: the site keeps state against a cookie.
    ///
    /// Its own cookie jar, so it cannot touch the authenticated session. And
    /// never from a cache — every page here is the state at this moment. A
    /// cached GET turned "empty the cart" into a no-op and returned an old
    /// timetable in place of the one just built.
    static func stateful(cookieGroup: String) -> ScrapedSite {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.sharedCookieStorage(
            forGroupContainerIdentifier: cookieGroup)
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return ScrapedSite(session: URLSession(configuration: configuration))
    }

    func page(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // The service varies its output by language, and asks in Italian by
        // default only when told to.
        request.setValue(PoliMiLanguage.current.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        return await send(request, describing: url)
    }

    func post(_ url: URL, form: [String: String]) async -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(PoliMiLanguage.current.acceptLanguage, forHTTPHeaderField: "Accept-Language")

        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        return await send(request, describing: url)
    }

    private func send(_ request: URLRequest, describing url: URL) async -> String? {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return Self.decode(data)
        } catch {
            guard !PoliMiAPI.isCancellation(error) else { return nil }
            log.error("\(url.lastPathComponent, privacy: .public) fallito: \(error.localizedDescription)")
            return nil
        }
    }

    /// The pages declare UTF-8 and mostly mean it, but some are ISO-8859-1 —
    /// a wrong guess turns every accented letter into a replacement character
    /// across a page that is almost entirely prose.
    static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.contains("\u{FFFD}") {
            return utf8
        }
        return String(data: data, encoding: .isoLatin1)
    }
}

/// Canned markup, for tests and previews.
///
/// Matched on a substring of the URL rather than the whole of it: these URLs
/// carry a dozen query parameters whose order is not guaranteed, and a test
/// that pinned all of them would be asserting the encoder, not the caller.
actor FixturePages: PageFetching {
    private let pages: [String: String]
    private(set) var requested: [URL] = []
    private(set) var posted: [(url: URL, form: [String: String])] = []

    /// - Parameter pages: keyed by a distinctive fragment of the URL.
    init(_ pages: [String: String] = [:]) {
        self.pages = pages
    }

    /// The most specific fixture wins, longest key first.
    ///
    /// Not `first(where:)` over the dictionary: its order is not defined, so
    /// with two keys that both match — "ManifestoPublic.do" and the
    /// "EVN_ADDCART" page that lives at the same path — the answer would
    /// differ between runs.
    private func match(_ url: URL) -> String? {
        let whole = url.absoluteString
        return pages
            .sorted { $0.key.count > $1.key.count }
            .first { whole.contains($0.key) }?.value
    }

    func page(_ url: URL) async -> String? {
        requested.append(url)
        return match(url)
    }

    func post(_ url: URL, form: [String: String]) async -> String? {
        posted.append((url, form))
        return match(url)
    }
}
