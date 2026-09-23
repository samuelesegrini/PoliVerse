import Foundation

/// Reads the recman archive page, `ArchivioListActivity.do`.
///
/// The archive is a JAF page like the Manifesti ones: a template-generated table,
/// so ``HTMLScraper``'s regular expressions are enough. Each recording is a row with
/// a play link, `evn_preview_link=evento&transfer_id=<n>`, and the cells Anno
/// Accademico, Data, Corso, Forma didattica, Argomento, Ospiti and Durata — the
/// last reading "135 min / 198 MB". Every cell writes its column's name above its
/// value, which is how fields are found; the column's position is the fallback.
/// See `docs/recordings.md`.
nonisolated enum RecmanParser {
    /// Where the archive's relative links are resolved against.
    static let base = URL(string: "https://onlineservices.polimi.it")!

    /// A parsed row: the recording, and the link that opens it in this session.
    struct Row: Sendable {
        /// The recording.
        let recording: Recording
        /// The play link, valid only in the session that served the page.
        let playLink: URL?
    }

    /// Every recording on the page, in the page's order.
    ///
    /// A row that does not read — no date, no teaching code — is skipped rather than
    /// guessed at.
    ///
    /// - Parameters:
    ///   - html: The archive page, or one course's page.
    ///   - fallbackCode: The teaching code to file a row under when its course cell
    ///     names none — a course's own page, reached from WeBeep, may leave it out.
    /// - Returns: The rows. Empty for a page with no recordings, or one that is not
    ///   the archive.
    static func rows(in html: String, fallbackCode: String? = nil) -> [Row] {
        let columns = Columns(headers: headers(in: html))
        var seen: Set<Int> = []
        return rowFragments(in: html).compactMap { fragment in
            guard let row = row(fragment, columns: columns, fallbackCode: fallbackCode),
                  seen.insert(row.recording.transferID).inserted
            else { return nil }
            return row
        }
    }

    /// Whether the page is the archive's list, even an empty one.
    ///
    /// Recognised by a play link, by the list's date header in either language, or by
    /// the search form posting back to the list — which is all an empty list, before
    /// its search, carries.
    ///
    /// - Parameter html: A page from recman.
    /// - Returns: `true` for the list page, filled or empty.
    static func isArchive(_ html: String) -> Bool {
        if html.localizedCaseInsensitiveContains("evn_preview_link") || html.contains("transfer_id=") { return true }
        let dateHeaders = Label.date
        if headers(in: html).contains(where: { header in
            dateHeaders.contains { header.caseInsensitiveCompare($0) == .orderedSame } }) { return true }
        return html.contains("ArchivioListActivity") && html.localizedCaseInsensitiveContains("EVN_SEARCH")
    }

    /// Whether a URL is one of recman's own pages.
    ///
    /// - Parameter url: The URL to test.
    /// - Returns: `true` for `onlineservices.polimi.it/recman_frontend/…`.
    static func isRecman(_ url: URL) -> Bool {
        url.host == base.host && url.path.hasPrefix("/recman_frontend")
    }

    /// The address a page sends the browser on to with a script, when it does.
    ///
    /// The play link answers with a redirect today; earlier versions answered with a
    /// page that set `location.href`, and third-party tools still read it that way.
    ///
    /// - Parameter html: The page.
    /// - Returns: The target, or `nil`.
    static func scriptedRedirect(in html: String) -> URL? {
        HTMLScraper.firstMatch(#"location\.href\s*=\s*['"]([^'"]+)['"]"#, in: html, group: 1)
            .flatMap { URL(string: $0.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL }
    }

    /// A course's own way into recman: the "Registrazioni" link on its WeBeep page.
    ///
    /// A URL module pointing at aunicalogin's "Registrazioni del corso" service with
    /// the course's `c_classe_webeep`. Asked for in Italian, like the archive.
    ///
    /// - Parameter sections: The course page, from `core_course_get_contents`.
    /// - Returns: The link, or `nil` when the page has none.
    static func courseEntry(in sections: [MoodleSection]) -> URL? {
        let links = sections
            .flatMap { $0.modules ?? [] }
            .filter { $0.modname == "url" }
            .flatMap { $0.contents ?? [] }
            .compactMap(\.fileurl)
        guard let link = links.first(where: {
            $0.contains("aunicalogin.polimi.it") && $0.contains("getservizio") && $0.contains("c_classe_webeep")
        }), var components = URLComponents(string: link) else { return nil }
        if !(components.queryItems ?? []).contains(where: { $0.name == "lang" }) {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "lang", value: "IT")]
        }
        return components.url
    }

    // MARK: - Rows

    /// The markup of each row carrying a play link.
    ///
    /// Found from the link outwards — back to the row's opening tag, on to its
    /// closing one — rather than by matching `<tr>…</tr>` across the page, which
    /// would pair a layout table's opening tag with the first closing tag inside the
    /// list and swallow a row.
    private static func rowFragments(in html: String) -> [Substring] {
        var fragments: [Substring] = []
        var cursor = html.startIndex
        while let link = html.range(of: "transfer_id=", range: cursor..<html.endIndex) {
            guard let open = html.range(of: "<tr", options: [.backwards, .caseInsensitive],
                                        range: html.startIndex..<link.lowerBound),
                  let close = html.range(of: "</tr>", options: .caseInsensitive,
                                         range: link.upperBound..<html.endIndex)
            else { break }
            fragments.append(html[open.lowerBound..<close.upperBound])
            cursor = close.upperBound
        }
        return fragments
    }

    /// Reads one row.
    ///
    /// Each cell is read by the label it carries where it carries one — the page
    /// writes "Data", "Corso" and so on inside every cell, above the value — and by
    /// the column's position where it does not.
    private static func row(_ fragment: Substring, columns: Columns, fallbackCode: String?) -> Row? {
        let raw = String(fragment)
        guard let link = playLink(in: raw),
              let transfer = HTMLScraper.queryValue("transfer_id", in: link.absoluteString).flatMap(Int.init)
        else { return nil }

        let cells = HTMLScraper.matches("<td[^>]*>(.*?)</td>", in: raw).compactMap(\.first).map(Cell.init(html:))
        let labelled = Dictionary(cells.compactMap { cell in cell.label.map { ($0.lowercased(), cell.value) } },
                                  uniquingKeysWith: { first, _ in first })
        func field(_ index: Int, _ names: [String]) -> String? {
            if let value = names.lazy.compactMap({ labelled[$0.lowercased()] }).first { return value.nonEmpty }
            guard cells.indices.contains(index), cells[index].label == nil else { return nil }
            return cells[index].value.nonEmpty
        }

        guard let dateText = field(columns.date, Label.date), let date = parseDate(dateText) else { return nil }
        let courseText = field(columns.course, Label.course)
        guard let course = courseText.flatMap(parseCourse)
                ?? fallbackCode.map({ (code: $0, title: courseText ?? $0, lecturer: nil) })
        else { return nil }
        // "168 min / 649 MB": the length and the size share a cell on the current page.
        let duration = field(columns.duration, Label.duration)
        let size = field(columns.size, Label.size) ?? duration

        let recording = Recording(
            transferID: transfer,
            academicYear: field(columns.year, Label.year).map(normaliseYear) ?? Course.academicYearLabel(for: date),
            recordedAt: date,
            teachingCode: course.code,
            courseTitle: course.title,
            lecturer: course.lecturer,
            form: Recording.Form(label: field(columns.form, Label.form) ?? ""),
            topic: field(columns.topic, Label.topic),
            minutes: duration.flatMap(leadingNumber),
            megabytes: size.flatMap(parseMegabytes))
        return Row(recording: recording, playLink: link)
    }

    /// One cell: the label the page writes above its value, when it writes one, and
    /// the value.
    struct Cell {
        let label: String?
        let value: String

        /// Splits a cell's text into its lines; a first line that is a known column
        /// name is the label.
        init(html: String) {
            let lines = HTMLScraper.text(html)
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if lines.count >= 2, Label.all.contains(where: { $0.caseInsensitiveCompare(lines[0]) == .orderedSame }) {
                label = lines[0]
                value = RecmanParser.clean(lines.dropFirst().joined(separator: " "))
            } else {
                label = nil
                value = RecmanParser.clean(lines.joined(separator: " "))
            }
        }
    }

    /// The names each column goes by, in Italian and English.
    enum Label {
        static let year = ["Anno Accademico", "Academic Year"]
        static let date = ["Data Registrazione", "Data", "Recording Date", "Registration Date", "Date"]
        static let course = ["Corso", "Course"]
        static let form = ["Forma didattica", "Teaching Form", "Teaching Type", "Type"]
        static let topic = ["Argomento", "Topic", "Subject"]
        static let guests = ["Ospiti", "Guests"]
        static let duration = ["Durata", "Duration"]
        static let size = ["Dimensione", "Size"]
        static let play = ["Riproduci", "Play"]
        static let all = year + date + course + form + topic + guests + duration + size + play
    }

    /// The row's play link, absolute and with its entities decoded.
    private static func playLink(in row: String) -> URL? {
        let hrefs = HTMLScraper.matches(#"href\s*=\s*"([^"]*transfer_id=[^"]*)""#, in: row).compactMap(\.first)
        guard let href = hrefs.first else { return nil }
        return URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL
    }

    // MARK: - Columns

    /// The page's column headers as text, in order.
    private static func headers(in html: String) -> [String] {
        HTMLScraper.matches("<th[^>]*>(.*?)</th>", in: html)
            .compactMap(\.first)
            .map { clean(HTMLScraper.text($0)) }
    }

    /// Where each field sits in a row.
    struct Columns: Equatable {
        var year = 1, date = 2, course = 3, form = 4, topic = 5, duration = 7, size = 8

        /// Places the fields by header, keeping the default order for any header the
        /// page does not have.
        ///
        /// Italian and English labels are both looked for, since the page follows
        /// the account's language.
        ///
        /// - Parameter headers: The header texts, in order.
        init(headers: [String] = []) {
            // The list's own headers begin at "Riproduci"; anything before is a
            // layout table's.
            let start = headers.firstIndex { Label.play.contains($0) }
                ?? headers.firstIndex { Label.year.contains($0) || Label.date.contains($0) } ?? 0
            let list = Array(headers[start...])
            func index(_ names: [String]) -> Int? {
                list.firstIndex { header in names.contains { header.caseInsensitiveCompare($0) == .orderedSame } }
            }
            year = index(Label.year) ?? year
            date = index(Label.date) ?? date
            course = index(Label.course) ?? course
            form = index(Label.form) ?? form
            topic = index(Label.topic) ?? topic
            duration = index(Label.duration) ?? duration
            size = index(Label.size) ?? size
        }
    }

    // MARK: - Fields

    /// `"21/09/2026 13:34"`, in Rome's time.
    static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = PoliMiDate.romeCalendar.timeZone
        for format in ["dd/MM/yyyy HH:mm", "dd/MM/yyyy HH:mm:ss", "dd/MM/yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// `"090950 - DISTRIBUTED SYSTEMS (CUGOLA GIANPAOLO SAVERIO)"` as code, title and
    /// lecturer.
    ///
    /// The lecturer is the last bracketed group at the end; a title with brackets of
    /// its own keeps them.
    static func parseCourse(_ text: String) -> (code: String, title: String, lecturer: String?)? {
        guard let code = HTMLScraper.firstMatch(#"^\s*([0-9]{6})\b"#, in: text, group: 1),
              let codeEnd = text.range(of: code)?.upperBound else { return nil }
        // What follows the code, less the " - " between them.
        var rest = String(text[codeEnd...]).trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("-") { rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces) }

        var lecturer: String?
        if rest.hasSuffix(")"), let open = rest.range(of: "(", options: .backwards) {
            lecturer = String(rest[open.upperBound..<rest.index(before: rest.endIndex)])
                .trimmingCharacters(in: .whitespaces).nonEmpty
            rest = String(rest[..<open.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return (code, rest.isEmpty ? code : rest, lecturer)
    }

    /// `"2026 / 27"` as `"2026/27"`.
    static func normaliseYear(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "")
    }

    /// The number a cell such as `"135 min"` or `"198 MB"` starts with.
    static func leadingNumber(_ text: String) -> Int? {
        HTMLScraper.firstMatch(#"^\s*([0-9]+)"#, in: text, group: 1).flatMap(Int.init)
    }

    /// The size in a cell such as `"198 MB"`, `"168 min / 649 MB"` or `"1,2 GB"`, in
    /// megabytes.
    static func parseMegabytes(_ text: String) -> Int? {
        let groups = HTMLScraper.matches(#"([0-9]+(?:[.,][0-9]+)?)\s*(MB|GB)"#, in: text).first
        guard let groups, groups.count == 2,
              let number = Double(groups[0].replacingOccurrences(of: ",", with: ".")) else { return nil }
        return Int((groups[1].uppercased() == "GB" ? number * 1024 : number).rounded())
    }

    /// Whitespace, including the non-breaking kind, collapsed to single spaces.
    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
