import Foundation
import Observation
import OSLog

/// The lecture recordings, read from recman on the student's own web session, one
/// course at a time.
///
/// A course is read through its WeBeep "Registrazioni" link, which lands on that
/// course's recordings and nothing else. The archive (service 2314) is the fallback
/// for a course without that link, searched by course: unsearched, it is not the
/// student's list but a page of the latest hundred recordings of the whole
/// Politecnico. Both need the Politecnico's web sign-in, kept by
/// ``RecordingsWebKit``; ``RecmanJump`` would avoid it, but the Politecnico refuses
/// the jump for these services.
///
/// What is read is kept as an offline copy per account. Opening a recording goes
/// through recman's play link, which is only valid in the session that served the
/// list, so ``webexAddress(for:)`` reads the course again when the list it holds is
/// from an earlier session. The Webex address it arrives at does not expire and is
/// remembered. See `docs/recordings.md`.
@Observable
@MainActor
final class RecordingsModel {
    /// Where loading stands.
    enum Phase: Equatable {
        /// Nothing in flight.
        case idle
        /// Walking recman.
        case loading
        /// The Politecnico's sign-in is needed before recman can be read.
        case needsSignIn
        /// Recman could not be read, with a sentence fit to show.
        case unavailable(String)
    }

    /// Every recording read so far, of every course, newest first.
    private(set) var recordings: [Recording] = []
    /// Where loading stands.
    private(set) var phase: Phase = .idle

    /// Who is signed in.
    private let account: any Account
    /// Where the offline copy lives.
    private let offline: OfflineStore
    /// Diagnostic log for this type, under the `recordings` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "recordings")
    /// The hidden browser, created on first use and kept for the play links.
    private var browser: RecmanBrowser?
    /// The hidden Webex page, created on first play.
    private var playback: WebexPlayback?
    /// The play links read, valid while the session that served them lasts.
    private var playLinks: [Int: URL] = [:]
    /// When each course's play links were read, by teaching code.
    private var readAt: [String: Date] = [:]
    /// Webex addresses already found, by `transfer_id`.
    private var webexAddresses: [Int: URL] = [:]
    /// The WeBeep links already found, by teaching code: stable, unlike recman's own.
    private var courseEntries: [String: URL] = [:]
    /// The account the held data belongs to.
    private var heldFor: String?
    /// Whether an operation is walking recman, so a second waits its turn.
    private var busy = false
    /// Set once the Politecnico has refused the jump for this service, so it is not
    /// asked again until the next launch.
    private var jumpRefused = false

    /// How long a read of a course stands before the next visit reads it again.
    private let ttl: TimeInterval = 30 * 60
    /// How long recman's play links are trusted before the course is read again.
    private let linkLifetime: TimeInterval = 10 * 60

    /// Name of the offline record.
    private static let recordName = "recordings"
    /// Name of the offline record of Webex addresses.
    private static let addressesName = "recordings-webex"

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - account: Who is signed in.
    ///   - offline: Where the offline copy lives.
    init(account: any Account, offline: OfflineStore = .shared) {
        self.account = account
        self.offline = offline
    }

    /// One course's recordings, newest first. See ``Recording/of(_:in:)``.
    ///
    /// - Parameter course: The course.
    /// - Returns: Its recordings.
    func recordings(for course: Course) -> [Recording] {
        Recording.of(course, in: recordings)
    }

    // MARK: - Loading

    /// Brings one course's recordings up to date, unless they were read within the
    /// last half hour.
    ///
    /// - Parameters:
    ///   - course: The course.
    ///   - force: Reads recman whatever the age of what is held.
    ///   - entry: The course's WeBeep "Registrazioni" link, asked for only when recman
    ///     is to be read.
    func load(_ course: Course, force: Bool = false, entry: () async -> URL?) async {
        restoreIfNeeded()
        if account.isSample {
            recordings = Self.samples()
            phase = .idle
            return
        }
        guard account.matricola != nil, let code = course.teachingCode, !busy else { return }
        if !force, phase != .needsSignIn, let at = readAt[code], Date.now.timeIntervalSince(at) < ttl { return }

        busy = true
        defer { busy = false }
        phase = .loading
        if let url = await entry() { courseEntries[code] = url }
        await read(code)
    }

    /// Where a recording plays on Webex.
    ///
    /// Remembered once found. Otherwise follows the row's play link, reading the
    /// course again first when its links may have expired.
    ///
    /// - Parameter recording: The recording to open.
    /// - Returns: The Webex address, or `nil` when it could not be found — in which
    ///   case ``phase`` says why when it is the session.
    func webexAddress(for recording: Recording) async -> URL? {
        if let known = webexAddresses[recording.transferID] { return known }
        guard !account.isSample, !busy else { return nil }
        busy = true
        defer { busy = false }

        let code = recording.teachingCode
        let fresh = readAt[code].map { Date.now.timeIntervalSince($0) < linkLifetime } ?? false
        if !fresh || playLinks[recording.transferID] == nil {
            phase = .loading
            await read(code)
        }
        guard let link = playLinks[recording.transferID], let browser else { return nil }
        guard let address = await browser.webexAddress(for: link) else {
            log.error("No Webex address for transfer \(recording.transferID, privacy: .public)")
            return nil
        }
        webexAddresses[recording.transferID] = address
        if let matricola = account.matricola {
            offline.save(webexAddresses.mapKeys(String.init), as: Self.addressesName, account: matricola)
        }
        return address
    }

    /// Where a recording streams, asked of Webex's own page.
    ///
    /// Not kept: the addresses carry a ticket that expires after ninety minutes.
    ///
    /// - Parameters:
    ///   - address: The recording's Webex address, from ``webexAddress(for:)``.
    ///   - accountEmail: The student's institutional email, given to Webex when
    ///     ``webexEmail`` has not been set.
    /// - Returns: The stream with the cookies to send along, or why there is none.
    func stream(at address: URL, accountEmail: String?) async -> (outcome: WebexPlayback.Outcome, cookies: [HTTPCookie]) {
        let playback = playback ?? WebexPlayback()
        self.playback = playback
        await RecordingsWebKit.restoreSession()
        let outcome = await playback.stream(at: address, email: webexEmail ?? accountEmail)
        switch outcome {
        case .stream(let stream):
            log.info("Webex stream: hls \(stream.hlsURL != nil, privacy: .public), download \(stream.allowsDownload, privacy: .public), disclaimer \(stream.needsDisclaimer, privacy: .public)")
            await RecordingsWebKit.saveSession()
        case .signInNeeded:
            log.info("Webex stream: sign-in needed")
        case .failed:
            break
        }
        return (outcome, await RecordingsWebKit.webexCookies())
    }

    /// The email the student gave for Webex, when the institutional one was not the
    /// account's. Kept on this device, and forgotten at sign-out.
    var webexEmail: String? {
        get { UserDefaults.standard.string(forKey: RecordingsWebKit.webexEmailKey) }
        set { UserDefaults.standard.set(newValue, forKey: RecordingsWebKit.webexEmailKey) }
    }

    /// Reads one course from recman: through its WeBeep link when it has one, and
    /// through the archive searched for the course otherwise.
    ///
    /// - Parameter code: The course's teaching code.
    private func read(_ code: String) async {
        await RecordingsWebKit.restoreSession()
        let browser = browser ?? RecmanBrowser()
        self.browser = browser

        var outcome = RecmanBrowser.Outcome.failed("no way in tried")
        if let url = courseEntries[code] {
            outcome = await browser.openArchive(from: url)
            log.info("Recman via WeBeep link: \(outcome.summary, privacy: .public)")
        }
        if case .failed = outcome {
            // The archive, searched for the course. Through the token first, which
            // the Politecnico has so far refused, then through the kept session.
            outcome = .signInNeeded
            if let jump = await jumpAddress() {
                outcome = await browser.openArchive(from: jump, course: code)
                log.info("Recman archive via linksalto: \(outcome.summary, privacy: .public)")
            }
            if outcome == .signInNeeded {
                outcome = await browser.openArchive(from: RecordingsWebKit.entry, course: code)
                log.info("Recman archive via own session: \(outcome.summary, privacy: .public)")
            }
        }

        switch outcome {
        case .archive(let html):
            take(RecmanParser.rows(in: html, fallbackCode: courseEntries[code] == nil ? nil : code), for: code)
            await RecordingsWebKit.saveSession()
        case .signInNeeded:
            phase = .needsSignIn
        case .failed:
            phase = .unavailable(String(localized: "L'archivio delle registrazioni non risponde come previsto. Puoi aprirlo dal browser."))
        }
    }

    /// Takes in one course's rows, replacing what was held for it.
    ///
    /// Rows of another course are left out: a search the archive did not narrow
    /// down must not file other courses' lectures here.
    ///
    /// - Parameters:
    ///   - rows: The rows read.
    ///   - code: The course they were read for.
    private func take(_ rows: [RecmanParser.Row], for code: String) {
        let mine = rows.filter { $0.recording.teachingCode == code }
        if mine.count < rows.count {
            log.info("Recman: \(rows.count - mine.count, privacy: .public) rows of other courses left out")
        }
        recordings = recordings.filter { $0.teachingCode != code } + mine.map(\.recording)
        recordings.sort { $0.recordedAt > $1.recordedAt }
        for row in mine {
            if let link = row.playLink { playLinks[row.recording.transferID] = link }
        }
        readAt[code] = .now
        phase = .idle
        if let matricola = account.matricola {
            offline.save(recordings, as: Self.recordName, account: matricola)
        }
        log.info("Recman: \(mine.count, privacy: .public) recordings for the course")
    }

    /// Asks the Politecnico for a signed-in address into recman, on the app's token.
    ///
    /// - Returns: The address, or `nil` when the jump is refused — logged with its
    ///   status only, since the answer may carry the student's details.
    private func jumpAddress() async -> URL? {
        guard !jumpRefused else { return nil }
        do {
            let data = try await account.http.data(for: RecmanJump.request(matricola: account.matricola))
            let answer = try JSONDecoder().decode(RecmanJump.Answer.self, from: data)
            if answer.url == nil { log.error("linksalto answered without a jump_url") }
            return answer.url
        } catch APIError.badStatus(let status, let body) {
            // The refusal names the field and the reason, and nothing about the
            // student: `{"violations":[{"field":"id_servizio","message":"Unauthorized"}]}`.
            let reasons = HTMLScraper.matches(#""field"\s*:\s*"([^"]*)"\s*,\s*"message"\s*:\s*"([^"]*)""#, in: body)
                .map { $0.joined(separator: ": ") }.joined(separator: "; ")
            log.error("linksalto refused: \(status, privacy: .public) \(reasons, privacy: .public)")
            // Not a passing failure: the service is not one the app may jump to.
            if reasons.contains("Unauthorized") { jumpRefused = true }
            return nil
        } catch {
            log.error("linksalto failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Puts the offline copy on screen once per account, and forgets another account's
    /// data.
    private func restoreIfNeeded() {
        let key = account.isSample ? "mock" : account.matricola
        guard key != heldFor else { return }
        heldFor = key
        recordings = []
        playLinks = [:]
        readAt = [:]
        webexAddresses = [:]
        courseEntries = [:]
        phase = .idle
        guard let matricola = account.matricola, !account.isSample else { return }
        if let entry = offline.load([Recording].self, as: Self.recordName, account: matricola) {
            recordings = entry.value
        }
        if let entry = offline.load([String: URL].self, as: Self.addressesName, account: matricola) {
            webexAddresses = Dictionary(entry.value.compactMap { key, value in Int(key).map { ($0, value) } },
                                        uniquingKeysWith: { first, _ in first })
        }
    }

    /// Drops the browser and everything session-bound, on sign-out.
    ///
    /// The web session itself is emptied by ``RecordingsWebKit/endSession()``.
    func reset() {
        browser = nil
        heldFor = nil
        recordings = []
        playLinks = [:]
        readAt = [:]
        webexAddresses = [:]
        courseEntries = [:]
        phase = .idle
    }
}

private extension Dictionary {
    /// The same dictionary with its keys transformed.
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        Dictionary<T, Value>(map { (transform($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Sample data

extension RecordingsModel {
    /// A term's worth of recordings for two of the sample courses.
    static func samples(now: Date = .now) -> [Recording] {
        let calendar = PoliMiDate.romeCalendar
        let year = Course.academicYearLabel(for: now)
        let courses: [(code: String, title: String, lecturer: String, topics: [String])] = [
            ("095948", "INGEGNERIA DEL SOFTWARE", "ROSSI MARIO",
             ["Introduzione al corso", "UML: diagrammi delle classi", "Design pattern creazionali",
              "Design pattern strutturali", "Testing e JUnit"]),
            ("086657", "RETI DI CALCOLATORI", "BIANCHI LUCA",
             ["Livelli e protocolli", "Il livello applicativo: HTTP", "TCP e controllo di congestione"]),
        ]
        var transfer = 160_000
        return courses.flatMap { course in
            course.topics.enumerated().map { index, topic in
                transfer += 1
                let day = calendar.date(byAdding: .day, value: -3 * (course.topics.count - index), to: now) ?? now
                let start = calendar.date(bySettingHour: 10, minute: 17, second: 0, of: day) ?? day
                return Recording(
                    transferID: transfer, academicYear: year, recordedAt: start,
                    teachingCode: course.code, courseTitle: course.title, lecturer: course.lecturer,
                    form: index == course.topics.count - 1 ? .exercise : .lecture, topic: topic,
                    minutes: 90 + index * 7, megabytes: 130 + index * 9)
            }
        }
        .sorted { $0.recordedAt > $1.recordedAt }
    }
}
