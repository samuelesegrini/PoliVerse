import Foundation
import Observation
import OSLog

/// Course materials from WeBeep, via Moodle's web services.
///
/// The token is obtained by ``WeBeepAuth``'s launch handshake and kept in the
/// Keychain alongside — but separate from — the PoliMi OAuth token. They are
/// independent credentials with independent lifetimes: the PoliMi session can
/// be alive while the WeBeep one is dead, and vice versa.
@Observable
final class WeBeepService {
    enum State: Equatable {
        case needsLogin
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .needsLogin
    private(set) var courses: [MoodleCourse] = []
    private(set) var sections: [WeBeepSection] = []
    /// Materials listings kept per course.
    ///
    /// Files already downloaded stay on disk, but without the listing they
    /// cannot be found: the screen that shows them was empty offline, which
    /// makes downloading for a train journey pointless. Cached per course,
    /// since one course's materials say nothing about another's.
    private var materialSlots: [String: CachedSlot<[WeBeepSection]>] = [:]
    private(set) var isLoadingMaterials = false

    private let session: Session
    private let feed: UpdateFeed
    /// An hour: a course page changes when a teacher uploads, and every check
    /// is one request per course.
    private var updatesWindow = LoadWindow(interval: 3600)
    /// Course pages checked per pass. A background refresh has about thirty
    /// seconds for everything, and the career comes first.
    static let watchLimit = 6
    /// Counts passes, so courses past the cap take turns. Kept across
    /// launches: a background refresh usually starts the app from cold.
    private var watchPass: Int {
        get { UserDefaults.standard.integer(forKey: "webeepWatchPass") }
        set { UserDefaults.standard.set(newValue, forKey: "webeepWatchPass") }
    }
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "webeep")
    private let keychainAccount = "webeep"

    private var api: WeBeepAPI?
    private var userID: Int?
    /// Course id per PoliMi course code, learned by matching names once.
    private var courseIDByCode: [String: Int] = [:]

    init(session: Session, feed: UpdateFeed) {
        self.session = session
        self.feed = feed
        if let token = storedToken() {
            api = WeBeepAPI(token: token)
        }
    }

    var isAuthenticated: Bool { api != nil }

    // MARK: - Token

    private func storedToken() -> String? {
        guard let data = KeychainStore.load(account: keychainAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func store(_ token: WeBeepAuth.MoodleToken) {
        try? KeychainStore.save(Data(token.token.utf8), account: keychainAccount)
        api = WeBeepAPI(token: token.token)
        state = .ready
    }

    func signOut() {
        KeychainStore.delete(account: keychainAccount)
        api = nil
        userID = nil
        courses = []
        sections = []
        courseIDByCode = [:]
        state = .needsLogin
    }

    /// Marks a course favourite on WeBeep.
    ///
    /// - Returns: whether it stuck. The caller updates optimistically and
    ///   reverts on false, so a failed write does not leave the UI claiming
    ///   something the server disagrees with.
    @discardableResult
    func setFavourite(_ favourite: Bool, moodleID: Int) async -> Bool {
        guard let api else { return false }
        do {
            try await api.setFavourite(courseID: moodleID, favourite: favourite)
            if let index = courses.firstIndex(where: { $0.id == moodleID }) {
                courses[index] = courses[index].withFavourite(favourite)
            }
            return true
        } catch {
            log.error("Could not set favourite: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func setHidden(_ hidden: Bool, moodleID: Int) async -> Bool {
        guard let api else { return false }
        do {
            try await api.setHidden(courseID: moodleID, hidden: hidden)
            if let index = courses.firstIndex(where: { $0.id == moodleID }) {
                courses[index] = courses[index].withHidden(hidden)
            }
            return true
        } catch {
            log.error("Could not set hidden: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Loading

    /// Fetches the enrolled course list, establishing the user id on the way.
    func loadCourses() async {
        if session.useMockData {
            state = .ready
            return
        }
        guard let api else {
            state = .needsLogin
            return
        }

        state = .loading
        do {
            let info = try await api.siteInfo()
            userID = info.userid
            courses = try await api.courses(userID: info.userid)
            state = .ready
        } catch let error as WeBeepAPI.Failure {
            handle(error)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMaterials(for course: Course) async {
        guard !isLoadingMaterials else { return }
        isLoadingMaterials = true
        defer { isLoadingMaterials = false }

        // Last known listing first, so the screen has content before the
        // request and keeps it if the request fails.
        restoreMaterials(for: course)

        if session.useMockData || api == nil {
            sections = MockData.weBeepSections(for: course)
            if api == nil && !session.useMockData { state = .needsLogin }
            return
        }

        guard let api else { return }

        do {
            if courses.isEmpty { await loadCourses() }
            guard let moodleID = moodleCourseID(for: course) else {
                sections = []
                state = .failed("Corso non trovato su WeBeep.")
                return
            }

            let raw = try await api.contents(courseID: moodleID)
            // The listing is already here; noticing what is new costs nothing.
            // Only for a page the background pass would read anyway — this
            // year's, linked by id — so opening an old course never announces
            // its old results as news.
            if let account = session.student?.matricola,
               Self.isWatchable(course, now: .now), let watched = MaterialCourse(course) {
                feed.show(account: account)
                await feed.recordMaterials(
                    course: watched, sections: raw, account: account, inspect: resultsInspector())
            }
            sections = raw.compactMap { section in
                let files = (section.modules ?? []).flatMap { module in
                    (module.contents ?? []).compactMap { content -> WeBeepFile? in
                        // Modules carry more than files — `url` entries point
                        // offsite, labels carry none at all.
                        guard content.type == "file",
                              let name = content.filename,
                              let fileURL = content.fileurl else { return nil }
                        return WeBeepFile(
                            id: "\(module.id)-\(name)",
                            name: name,
                            courseID: course.id,
                            sectionName: section.name,
                            sizeBytes: content.filesize ?? 0,
                            modifiedAt: content.timemodified.map {
                                Date(timeIntervalSince1970: TimeInterval($0))
                            } ?? .now,
                            downloadURL: api.authenticatedFileURL(fileURL)
                        )
                    }
                }
                guard !files.isEmpty else { return nil }
                return WeBeepSection(id: String(section.id), name: section.name, files: files)
            }
            // Logged in the same shape as the other services, so a device run
            // shows plainly whether the materials path ran — this one went
            // unverified longest precisely because it said nothing.
            log.notice("WeBeep course \(moodleID, privacy: .public): \(raw.count, privacy: .public) sections, \(self.sections.count, privacy: .public) with files, \(self.sections.reduce(0) { $0 + $1.files.count }, privacy: .public) files")
            state = .ready
            saveMaterials(for: course)
        } catch let error as WeBeepAPI.Failure {
            handle(error)
            // Kept, not cleared: a cached listing is how a downloaded file is
            // found again without signal.
        } catch {
            state = .failed(userFacingMessage(error) ?? "")
        }
    }

    /// Reads this academic year's course pages for new items — results,
    /// solutions, notices — without the student opening each one.
    ///
    /// Favourites first, capped at ``watchLimit``: the cap is what lets it
    /// fit in a background refresh, and a favourite is the student saying
    /// which pages they care about. Every failure is quiet; the next pass
    /// tries again.
    func checkForUpdates(force: Bool = false) async {
        guard !session.useMockData, api != nil, let account = session.student?.matricola,
              updatesWindow.shouldLoad(force: force, source: account) else { return }

        if courses.isEmpty { await loadCourses() }
        guard let api else { return }
        feed.show(account: account)

        let watched = Self.watched(courses.map(Course.init(moodle:)), now: .now, pass: watchPass)
        watchPass += 1
        var checked = 0
        for course in watched {
            // A sign-out or a career switch mid-pass ends it: the rest would
            // be weighed against somebody else's sittings.
            guard !Task.isCancelled, session.student?.matricola == account,
                  let target = MaterialCourse(course) else { break }
            do {
                let raw = try await api.contents(courseID: target.moodleID)
                await feed.recordMaterials(
                    course: target, sections: raw, account: account, inspect: resultsInspector())
                checked += 1
            } catch let error as WeBeepAPI.Failure where error.isAuthFailure {
                handle(error)
                return
            } catch {
                log.error("Update check for course \(target.moodleID, privacy: .public) failed: \(error.localizedDescription)")
            }
        }
        log.notice("Checked \(checked, privacy: .public) of \(watched.count, privacy: .public) course pages for updates")
        // A pass that read nothing is retried next time, like any failed load.
        if checked > 0 { updatesWindow.markLoaded(source: account) }
    }

    /// Reads a new results file for the student's own line, if they turned
    /// that on; nil otherwise, so nothing is downloaded.
    ///
    /// The file is fetched into memory, read, and dropped. Only the lookup —
    /// found or not, and the student's own mark — outlives the call; the
    /// URL with its token is never logged or stored.
    private func resultsInspector() -> (@MainActor (ResultsFileRef) async -> ResultsLookup?)? {
        let preferences = NotificationPreferences.stored
        guard preferences.examUpdates, preferences.readResultsFiles,
              let api, let student = session.student else { return nil }
        let identifiers = [student.matricola, student.personCode]
        return { file in
            // Checked before downloading, from the listing's own size.
            guard (file.size ?? 0) <= ResultsFileReader.maximumBytes,
                  let url = api.authenticatedFileURL(file.fileURL) else { return nil }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            // Ephemeral: the shared session's cache would write the file —
            // other students' marks — to disk.
            let session = URLSession(configuration: .ephemeral)
            defer { session.finishTasksAndInvalidate() }
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200
            else { return nil }
            return await ResultsFileReader.read(
                data, mimetype: file.mimetype, fileName: file.name, identifiers: identifiers)
        }
    }

    /// The course pages worth checking: this academic year's, not hidden.
    ///
    /// Favourites every pass; the rest of the ``watchLimit`` rotates through
    /// the other courses, so a seventh course is read every few passes rather
    /// than never.
    static func watched(_ courses: [Course], now: Date, pass: Int = 0) -> [Course] {
        let eligible = courses
            .filter { isWatchable($0, now: now) }
            .sorted { ($0.moodleID ?? 0) < ($1.moodleID ?? 0) }
        let favourites = Array(eligible.filter(\.isFavourite).prefix(watchLimit))
        let others = eligible.filter { !$0.isFavourite }
        let room = watchLimit - favourites.count
        guard room > 0, !others.isEmpty else { return favourites }
        let start = (pass * room) % others.count
        let rotated = Array(others[start...] + others[..<start])
        return favourites + rotated.prefix(room)
    }

    /// This academic year's, visible, and linked to WeBeep by id.
    static func isWatchable(_ course: Course, now: Date) -> Bool {
        !course.isHidden && course.moodleID != nil
            && startYear(of: course.academicYear) == startYear(of: Course.academicYearLabel(for: now))
    }

    /// `2025/26`, `2025-26` and `2025-2026` all start in 2025.
    private static func startYear(of label: String) -> Int? {
        Int(label.prefix(4))
    }

    private func slotName(for course: Course) -> String { "materials-\(course.id)" }

    private func restoreMaterials(for course: Course) {
        var slot = materialSlots[course.id]
            ?? CachedSlot<[WeBeepSection]>(name: slotName(for: course))
        if let cached = slot.restore(for: session.student?.matricola) {
            sections = cached
        }
        materialSlots[course.id] = slot
    }

    private func saveMaterials(for course: Course) {
        var slot = materialSlots[course.id]
            ?? CachedSlot<[WeBeepSection]>(name: slotName(for: course))
        slot.save(sections, for: session.useMockData ? nil : session.student?.matricola)
        materialSlots[course.id] = slot
    }

    /// Matches a PoliMi course to its Moodle counterpart.
    ///
    /// The two systems share no identifier — Moodle has its own numeric course
    /// id and a free-text `fullname`, while PoliMi uses `c_insegn_piano`. The
    /// course code often appears inside the Moodle title (WeBeep names courses
    /// like "097785 - BASI DI DATI"), so try that first and fall back to
    /// comparing normalised names.
    private func moodleCourseID(for course: Course) -> Int? {
        // A course sourced from WeBeep already knows its Moodle id; no matching
        // required, and no chance of matching wrongly.
        if let direct = course.moodleID { return direct }
        if let cached = courseIDByCode[course.id] { return cached }

        let searchCode = course.code ?? course.id
        if let byCode = courses.first(where: {
            $0.fullname.contains(searchCode) || ($0.shortname ?? "").contains(searchCode)
        }) {
            courseIDByCode[course.id] = byCode.id
            return byCode.id
        }

        let target = course.name.lowercased()
        if let byName = courses.first(where: {
            let full = Course.normalise($0.fullname).lowercased()
            return full.contains(target) || target.contains(full)
        }) {
            courseIDByCode[course.id] = byName.id
            return byName.id
        }

        log.warning("No WeBeep course matched \(course.id) \(course.name)")
        return nil
    }

    private func handle(_ error: WeBeepAPI.Failure) {
        if error.isAuthFailure {
            // The token is dead; drop it so the UI offers login rather than
            // retrying against a credential that will never work again.
            signOut()
        } else {
            state = .failed(error.localizedDescription)
        }
    }
}
