import OSLog
@preconcurrency import WebKit

/// A web view nobody sees, walking recman on ``RecordingsWebKit``'s session.
///
/// Recman's URLs carry per-session workflow tokens (`jaf_currentWFID`, `__pj1`), and
/// the way in passes through aunicalogin pages that sign on by submitting forms from
/// script. A `URLSession` would have to replay all of that by hand; a web view
/// simply follows it, the way the student's browser does.
///
/// One operation at a time: ``RecordingsModel`` is the only caller and serialises
/// them.
@MainActor
final class RecmanBrowser: NSObject, WKNavigationDelegate {
    /// What opening the archive came to.
    enum Outcome: Equatable {
        /// The archive's list page.
        case archive(String)
        /// The walk stopped on a sign-in page: the SSO session is missing or expired.
        case signInNeeded
        /// Anything else, with a sentence for the log.
        case failed(String)

        /// The outcome in a few words for the log, without the page.
        var summary: String {
            switch self {
            case .archive(let html): "archive, \(RecmanParser.rows(in: html).count) rows"
            case .signInNeeded: "sign-in needed"
            case .failed(let reason): "failed: \(reason)"
            }
        }
    }

    /// Diagnostic log for this type, under the `recordings` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "recordings")
    /// The web view doing the walking.
    private let webView: WKWebView

    /// Receives the outcome of the walk in progress.
    private var archiveWaiter: CheckedContinuation<Outcome, Never>?
    /// Receives the Webex address a play link leads to.
    private var linkWaiter: CheckedContinuation<URL?, Never>?
    /// Counts navigations, so a delayed check can tell whether the page moved on.
    private var navigations = 0
    /// Whether the archive's search has been submitted in this walk.
    private var searched = false
    /// Whether a link towards the list has been followed in this walk.
    private var followedToList = false
    /// Counts operations, so a timeout left over from an earlier one cannot end the
    /// current one.
    private var operation = 0
    /// The course the archive's search is narrowed to in this walk, by teaching code.
    private var course: String?

    /// How long a sign-in page is given to move on by itself — an SSO page with a
    /// valid cookie submits itself within a moment — before it counts as asking the
    /// student.
    private let signInGrace: Duration = .seconds(3)
    /// How long a whole walk may take.
    private let timeout: Duration = .seconds(30)

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = RecordingsWebKit.dataStore
        // Recman's pages are read, never shown; nothing needs to play.
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    // MARK: - Operations

    /// Walks from a starting address to a list of recordings.
    ///
    /// - Parameters:
    ///   - start: A course's WeBeep link, a ``RecmanJump`` address, or
    ///     ``RecordingsWebKit/entry``.
    ///   - course: The teaching code to narrow the archive's search to. A course's own
    ///     page needs none.
    /// - Returns: The list page, or why it could not be reached.
    func openArchive(from start: URL, course: String? = nil) async -> Outcome {
        self.course = course
        searched = false
        followedToList = false
        operation += 1
        let current = operation
        return await withCheckedContinuation { continuation in
            archiveWaiter = continuation
            webView.load(URLRequest(url: start))
            Task { [timeout] in
                try? await Task.sleep(for: timeout)
                guard self.operation == current else { return }
                self.finishArchive(.failed("timeout at \(self.webView.url?.host ?? "?")"))
            }
        }
    }

    /// Follows a play link as far as the Webex address it redirects to.
    ///
    /// The link is only valid in the session that served the list, so this runs on
    /// the same web view, straight after ``openArchive(from:)``.
    ///
    /// - Parameter link: A row's play link.
    /// - Returns: The Webex recording address, or `nil` when the link led elsewhere.
    func webexAddress(for link: URL) async -> URL? {
        operation += 1
        let current = operation
        return await withCheckedContinuation { continuation in
            linkWaiter = continuation
            webView.load(URLRequest(url: link))
            Task {
                try? await Task.sleep(for: .seconds(15))
                guard self.operation == current else { return }
                self.finishLink(nil)
            }
        }
    }

    // MARK: - Finishing

    /// Hands the walk's outcome over, once.
    private func finishArchive(_ outcome: Outcome) {
        guard let waiter = archiveWaiter else { return }
        archiveWaiter = nil
        if case .failed(let reason) = outcome { log.error("Recman walk failed: \(reason, privacy: .public)") }
        webView.stopLoading()
        waiter.resume(returning: outcome)
    }

    /// Hands a play link's destination over, once.
    private func finishLink(_ url: URL?) {
        guard let waiter = linkWaiter else { return }
        linkWaiter = nil
        webView.stopLoading()
        waiter.resume(returning: url)
    }

    // MARK: - Navigation

    /// Stops at Webex while resolving a play link; lets everything else through.
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        navigations += 1
        guard let url = navigationAction.request.url else { return .allow }
        if linkWaiter != nil, url.host?.hasSuffix("webex.com") == true {
            finishLink(url)
            return .cancel
        }
        return .allow
    }

    /// Looks at each page the walk settles on.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        Task { await settled(on: url) }
    }

    /// A navigation that failed before any page came back ends the walk.
    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        let code = (error as NSError).code
        // A cancel is this type's own doing, or the page moving on.
        guard code != NSURLErrorCancelled, code != 102 else { return }
        finishArchive(.failed("navigation \((error as NSError).domain) \(code)"))
        finishLink(nil)
    }

    /// Decides what a settled page means for the operation in progress.
    private func settled(on url: URL) async {
        if linkWaiter != nil {
            // The older answer to a play link: a page that moves on by script.
            if RecmanParser.isRecman(url), let html = await html(),
               let target = RecmanParser.scriptedRedirect(in: html), target.host?.hasSuffix("webex.com") == true {
                finishLink(target)
            }
            return
        }
        guard archiveWaiter != nil else { return }

        if RecordingsWebKit.isSignIn(url) {
            // Either an SSO hop that will submit itself, or the sign-in itself.
            let seen = navigations
            try? await Task.sleep(for: signInGrace)
            if navigations == seen, archiveWaiter != nil { finishArchive(.signInNeeded) }
            return
        }

        guard RecmanParser.isRecman(url), let html = await html() else { return }
        if RecmanParser.isArchive(html) {
            if RecmanParser.rows(in: html).isEmpty, !searched {
                let year = await submitSearch(course: course)
                log.info("Recman list empty; search \(year.map { "submitted for year \($0), course \(course ?? "any")" } ?? "not found", privacy: .public)")
                if year != nil {
                    searched = true
                    return
                }
            }
            if RecmanParser.rows(in: html).isEmpty {
                log.info("Recman list read no rows: \(Self.diagnosis(of: html), privacy: .public)")
            } else {
                log.info("Recman list: \(Self.overview(of: html), privacy: .public)")
            }
            finishArchive(.archive(html))
        } else if !followedToList, let next = listLink(in: html) {
            followedToList = true
            webView.load(URLRequest(url: next))
        } else {
            finishArchive(.failed("recman page without a list: \(url.path) — \(Self.gist(of: html))"))
        }
    }

    // MARK: - Page access

    /// Why a list page read no rows, for the log: its structure, how many play links
    /// it carries, and the first row's cells — a recording's course, date and topic,
    /// which say nothing about the student.
    static func diagnosis(of html: String) -> String {
        let links = html.components(separatedBy: "transfer_id=").count - 1
        var firstRow = ""
        if let link = html.range(of: "transfer_id="),
           let open = html.range(of: "<tr", options: [.backwards, .caseInsensitive], range: html.startIndex..<link.lowerBound),
           let close = html.range(of: "</tr>", options: .caseInsensitive, range: link.upperBound..<html.endIndex) {
            firstRow = HTMLScraper.matches("<td[^>]*>(.*?)</td>", in: String(html[open.lowerBound..<close.upperBound]))
                .compactMap(\.first).map { HTMLScraper.text($0) }.joined(separator: " ¦ ")
        }
        let events = Set(HTMLScraper.matches(#"(evn_[a-z_]+)="#, in: html).compactMap(\.first)).sorted()
        return "\(gist(of: html)) | transfer_id links: \(links) | events: \(events.joined(separator: ", ")) | first row: \(firstRow)"
    }

    /// What a list that did read holds, for the log: rows per academic year, the
    /// span of dates, and anything that looks like paging — a page of exactly the
    /// page size with more behind it is a list cut short.
    static func overview(of html: String) -> String {
        let recordings = RecmanParser.rows(in: html).map(\.recording)
        let years = Dictionary(grouping: recordings, by: \.academicYear)
            .map { "\($0.key): \($0.value.count)" }.sorted().joined(separator: ", ")
        let dates = recordings.map(\.recordedAt)
        let span = [dates.min(), dates.max()].compactMap { $0?.formatted(.iso8601.year().month().day()) }
            .joined(separator: " … ")
        let paging = Set(HTMLScraper.matches(#"(?i)((?:evn_|jaf_)[a-z_]*(?:pagin|page|next|succ|prec)[a-z_]*)"#, in: html)
            .compactMap(\.first)).sorted()
        return "\(recordings.count) rows | years: \(years) | dates: \(span) | paging: \(paging.isEmpty ? "none seen" : paging.joined(separator: ", "))"
    }

    /// A page's structure in a few words fit for the log: its title, its column
    /// headers and its form fields' names.
    ///
    /// Structure only, never the page's text: the header of every recman page names
    /// the student.
    static func gist(of html: String) -> String {
        let title = HTMLScraper.firstMatch("<title[^>]*>(.*?)</title>", in: html, group: 1).map(HTMLScraper.text) ?? ""
        let headers = HTMLScraper.matches("<th[^>]*>(.*?)</th>", in: html)
            .compactMap(\.first).map(HTMLScraper.text).filter { !$0.isEmpty }
        let fields = Set(HTMLScraper.matches(#"name="([A-Za-z_]+)""#, in: html).compactMap(\.first)).sorted()
        return "\(title) | headers: \(headers.joined(separator: ", ")) | fields: \(fields.joined(separator: ", "))"
    }

    /// The current page's markup.
    private func html() async -> String? {
        try? await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String
    }

    /// Submits the archive's search for one course in the latest academic year.
    ///
    /// The list opens empty until searched, and a search is not narrowed to the
    /// student: it returns the whole Politecnico's recordings, a hundred at most.
    /// So the course goes in the Corso field (`contesto`), and the year is the latest
    /// one, the option with the highest value.
    ///
    /// - Parameter course: The teaching code to search for, or `nil` for none.
    /// - Returns: The year option chosen, as the page labels it — empty when the page
    ///   has no year choice — or `nil` when there was no search button to press.
    private func submitSearch(course: String?) async -> String? {
        // The body of an async function; `course` arrives as an argument, so the
        // teaching code is never spliced into the source.
        let body = """
        var field = document.querySelector('[name="contesto"]');
        if (field && course) { field.value = course; }
        var year = document.querySelector('select[name="aa"]');
        if (year) {
          var best = -1, bestValue = -1;
          for (var i = 0; i < year.options.length; i++) {
            var value = parseInt(year.options[i].value, 10);
            if (!isNaN(value) && value > bestValue) { best = i; bestValue = value; }
          }
          if (best >= 0) { year.selectedIndex = best; }
        }
        var button = document.querySelector('[name="EVN_SEARCH"]');
        if (!button) { return null; }
        var chosen = year && year.selectedIndex >= 0 ? year.options[year.selectedIndex].text.trim() : '';
        button.click();
        return chosen;
        """
        return try? await webView.callAsyncJavaScript(
            body, arguments: ["course": course ?? ""], contentWorld: .page) as? String
    }

    /// A link on a recman page towards the archive's list, for a walk that lands on
    /// a page in front of it.
    private func listLink(in html: String) -> URL? {
        let hrefs = HTMLScraper.matches(#"href\s*=\s*"([^"]+)""#, in: html).compactMap(\.first)
        let target = hrefs.first { $0.contains("ArchivioListActivity") || $0.contains("action=plen_0") }
        return target.flatMap {
            URL(string: $0.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: webView.url)?.absoluteURL
        }
    }
}
