import Foundation
import OSLog

/// How the Politecnico's HTML-only sites are read.
///
/// The manifesti and scheda services answer pages rather than JSON, so they cannot go
/// through ``HTTP``, which is shaped around a REST request and returns bytes a decoder
/// will read. This returns markup, because the caller's next move is always a parse.
///
/// Two methods, which is the whole of the traffic. ``ScrapedSite`` is the live adapter
/// and ``FixturePages`` serves tests and previews.
nonisolated protocol PageFetching: Sendable {
    /// Fetches a page.
    ///
    /// - Parameter url: The page to fetch.
    /// - Returns: The markup, or `nil` on any failure or a non-200 status.
    func page(_ url: URL) async -> String?
    /// Posts a form and returns the page that comes back.
    ///
    /// - Parameters:
    ///   - url: Where to post.
    ///   - form: The form fields.
    /// - Returns: The markup, or `nil` on any failure or a non-200 status.
    func post(_ url: URL, form: [String: String]) async -> String?
}

/// The live adapter: one `URLSession`, configured for what the site is.
///
/// The two configurations answer one question — does this site keep state for me? — and
/// sit beside each other so the contrast is visible. See ``stateless()`` and
/// ``stateful(cookieGroup:)``.
nonisolated final class ScrapedSite: PageFetching {
    /// The session pages are fetched through.
    private let session: URLSession
    /// Diagnostic log for this type, under the `pages` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "pages")

    /// Wraps a session.
    ///
    /// - Parameter session: The session to fetch through. Use ``stateless()`` or
    ///   ``stateful(cookieGroup:)`` rather than configuring one by hand.
    init(session: URLSession) {
        self.session = session
    }

    /// A site whose reads keep nothing: no cookies at all, and caching allowed.
    ///
    /// The service serialises requests sharing a session cookie, so several parallel detail
    /// pages on a cookie-bearing session take as long as the same number in sequence.
    ///
    /// - Returns: The adapter.
    static func stateless() -> ScrapedSite {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        return ScrapedSite(session: URLSession(configuration: configuration))
    }

    /// A site the app holds a conversation with: it keeps state against a cookie.
    ///
    /// Its own cookie jar, so it cannot touch the authenticated session, and never served
    /// from a cache — every page here is the state at this moment, and a cached request would
    /// turn emptying the cart into a no-op.
    ///
    /// - Parameter cookieGroup: The app-group container the cookie jar lives in.
    /// - Returns: The adapter.
    static func stateful(cookieGroup: String) -> ScrapedSite {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.sharedCookieStorage(
            forGroupContainerIdentifier: cookieGroup)
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return ScrapedSite(session: URLSession(configuration: configuration))
    }

    /// Fetches a page, asking for the interface's current language.
    ///
    /// - Parameter url: The page to fetch.
    /// - Returns: The markup, or `nil` on any failure or a non-200 status.
    func page(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        // The service varies its output by language, and asks in Italian by
        // default only when told to.
        request.setValue(PoliMiLanguage.current.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        return await send(request, describing: url)
    }

    /// Posts a form-encoded body and returns the page that comes back.
    ///
    /// - Parameters:
    ///   - url: Where to post.
    ///   - form: The form fields.
    /// - Returns: The markup, or `nil` on any failure or a non-200 status.
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

    /// Sends a request and decodes its body.
    ///
    /// A cancellation is not logged: it means the view that asked went away.
    ///
    /// - Parameters:
    ///   - request: The prepared request.
    ///   - url: The page, for the log.
    /// - Returns: The markup, or `nil` on any failure or a non-200 status.
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

    /// Decodes a page's bytes.
    ///
    /// The pages declare UTF-8 and mostly mean it, but some are ISO-8859-1, and a wrong
    /// guess turns every accented letter into a replacement character across a page that is
    /// almost entirely prose — so UTF-8 is used only when it produces none.
    ///
    /// - Parameter data: The response body.
    /// - Returns: The markup, or `nil` when neither encoding reads.
    static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.contains("\u{FFFD}") {
            return utf8
        }
        return String(data: data, encoding: .isoLatin1)
    }
}

/// Canned markup, for tests and previews.
///
/// Fixtures are matched on a substring of the URL rather than the whole of it: these
/// URLs carry a dozen query parameters whose order is not guaranteed, and pinning all of
/// them would assert the encoder rather than the caller.
///
/// An actor, so it can record what was asked of it without a lock.
actor FixturePages: PageFetching {
    /// The canned pages, keyed by a fragment of the URL.
    private let pages: [String: String]
    /// Every page fetched, in order, for assertions.
    private(set) var requested: [URL] = []
    /// Every form posted, in order, for assertions.
    private(set) var posted: [(url: URL, form: [String: String])] = []

    /// Creates the adapter.
    ///
    /// - Parameter pages: Canned markup, keyed by a distinctive fragment of the URL.
    init(_ pages: [String: String] = [:]) {
        self.pages = pages
    }

    /// The fixture for a URL, most specific first.
    ///
    /// Longest key first rather than the dictionary's own order, which is undefined — so two
    /// keys that both match cannot answer differently between runs.
    ///
    /// - Parameter url: The URL being asked for.
    /// - Returns: The markup, or `nil` when no key matches.
    private func match(_ url: URL) -> String? {
        let whole = url.absoluteString
        return pages
            .sorted { $0.key.count > $1.key.count }
            .first { whole.contains($0.key) }?.value
    }

    /// Records the request and answers it from the fixtures.
    ///
    /// - Parameter url: The page to fetch.
    /// - Returns: The markup, or `nil` when no fixture matches.
    func page(_ url: URL) async -> String? {
        requested.append(url)
        return match(url)
    }

    /// Records the post and answers it from the fixtures.
    ///
    /// - Parameters:
    ///   - url: Where the form was posted.
    ///   - form: The form fields.
    /// - Returns: The markup, or `nil` when no fixture matches.
    func post(_ url: URL, form: [String: String]) async -> String? {
        posted.append((url, form))
        return match(url)
    }
}
