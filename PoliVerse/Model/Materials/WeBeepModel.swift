import Foundation
import Observation
import OSLog

/// Course materials from WeBeep, through Moodle's web services.
///
/// The token comes from ``WeBeepAuth``'s launch handshake and is kept in the Keychain
/// beside — but separate from — the Politecnico OAuth token: two independent
/// credentials with independent lifetimes, so one can be alive while the other is
/// dead.
///
/// ## What it does
///
/// - ``loadCourses()`` fetches the enrolled course list, which also serves
///   ``CourseEnrolments``.
/// - ``loadMaterials(for:)`` fetches one course's files, serving the cached listing
///   first so downloaded files are still findable offline.
/// - ``checkForUpdates(force:until:)`` reads this year's course pages for new results,
///   solutions, notices, announcements and assignments, and records what it finds in
///   ``UpdateFeed``.
/// - ``setFavourite(_:moodleID:)`` and ``setHidden(_:moodleID:)`` mirror the two flags
///   back to WeBeep.
///
/// A Moodle refusal that means the token is dead signs WeBeep out, so the interface
/// offers a fresh sign-in rather than retrying a credential that will never work.
@Observable
final class WeBeepModel {
    /// Where the WeBeep connection stands.
    enum State: Equatable {
        /// No usable token; the interface offers a WeBeep sign-in.
        case needsLogin
        /// A load is in flight.
        case loading
        /// Connected, with whatever has been loaded.
        case ready
        /// The last load did not complete, with a sentence explaining why.
        case failed(String)
    }

    /// Where the connection stands.
    private(set) var state: State = .needsLogin
    /// The enrolled courses as Moodle knows them, with their two flags.
    private(set) var courses: [MoodleCourse] = []
    /// The listing for the course last loaded by ``loadMaterials(for:)``. Sections with no
    /// files are omitted.
    private(set) var sections: [WeBeepSection] = []
    /// One offline slot per course's listing.
    ///
    /// Downloaded files stay on disk, but without the listing they cannot be found — which
    /// would make downloading for a train journey pointless. Cached per course, since one
    /// course's materials say nothing about another's.
    private var materialSlots: [String: CachedSlot<[WeBeepSection]>] = [:]
    /// `true` while a materials load is in flight.
    private(set) var isLoadingMaterials = false

    /// Supplies the signed-in student, whose matricola keys the caches, and the
    /// sample-data flag.
    private let session: Session
    /// Where the update sweep records what it notices.
    private let feed: UpdateFeed
    /// Suppresses repeated update sweeps within an hour. A course page changes when a
    /// lecturer uploads, and every sweep is one request per course.
    private var updatesWindow = LoadWindow(interval: 3600)
    /// How many course pages one sweep reads. The cap is what lets a sweep fit in a
    /// background refresh, which has about thirty seconds for everything.
    static let watchLimit = 6
    /// How many sweeps have run, so courses past ``watchLimit`` take turns.
    ///
    /// Persisted, because a background refresh usually starts the app from cold.
    private var watchPass: Int {
        get { UserDefaults.standard.integer(forKey: "webeepWatchPass") }
        set { UserDefaults.standard.set(newValue, forKey: "webeepWatchPass") }
    }
    /// Diagnostic log for this type, under the `webeep` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "webeep")
    /// The Keychain account the WeBeep token is filed under.
    private let keychainAccount = "webeep"

    /// The Moodle client, built from the stored token. `nil` when WeBeep is not connected.
    private var api: WeBeepAPI?
    /// The signed-in user's Moodle id, learned by ``loadCourses()``.
    private var userID: Int?
    /// Moodle course id per ``Course/id``, remembered once a course has been matched by
    /// code or name.
    private var courseIDByCode: [String: Int] = [:]

    /// Builds the Moodle client from the stored token, if there is one.
    ///
    /// - Parameters:
    ///   - session: Supplies the signed-in student and the sample-data flag.
    ///   - feed: Where the update sweep records what it notices.
    init(session: Session, feed: UpdateFeed) {
        self.session = session
        self.feed = feed
        if let token = storedToken() {
            api = WeBeepAPI(token: token)
        }
    }

    /// Whether a WeBeep token is held.
    var isAuthenticated: Bool { api != nil }

    // MARK: - Token

    /// The token from the Keychain.
    ///
    /// - Returns: The token, or `nil` when none is stored.
    private func storedToken() -> String? {
        guard let data = KeychainStore.load(account: keychainAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores a freshly obtained token and enters ``State/ready``.
    ///
    /// - Parameter token: The token from ``WeBeepAuth/token(from:passport:verifySignature:)``.
    func store(_ token: WeBeepAuth.MoodleToken) {
        try? KeychainStore.save(Data(token.token.utf8), account: keychainAccount)
        api = WeBeepAPI(token: token.token)
        state = .ready
    }

    /// Deletes the token and forgets everything loaded from WeBeep, returning to
    /// ``State/needsLogin``.
    func signOut() {
        KeychainStore.delete(account: keychainAccount)
        api = nil
        userID = nil
        courses = []
        sections = []
        courseIDByCode = [:]
        state = .needsLogin
    }

    /// Stars or unstars a course on WeBeep, updating the held course list on success.
    ///
    /// - Parameters:
    ///   - favourite: The value the student chose.
    ///   - moodleID: Moodle's course id.
    /// - Returns: `false` when WeBeep is not connected or the write failed, so the caller
    ///   can queue the change rather than leave the interface claiming something the
    ///   server disagrees with.
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

    /// Hides or reveals a course on WeBeep, updating the held course list on success.
    ///
    /// - Parameters:
    ///   - hidden: The value the student chose.
    ///   - moodleID: Moodle's course id.
    /// - Returns: `false` when WeBeep is not connected or the write failed.
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

    /// Fetches the enrolled course list, learning the Moodle user id on the way.
    ///
    /// Under sample data it only enters ``State/ready``. Without a token it enters
    /// ``State/needsLogin``.
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

    /// Fetches one course's files into ``sections``.
    ///
    /// The cached listing is restored first, so the screen has content before the request
    /// and keeps it if the request fails — which is how a downloaded file is found again
    /// without signal. Only entries that are genuinely files are listed: a module may
    /// carry links or nothing at all.
    ///
    /// A listing for a page the update sweep would read anyway is also handed to
    /// ``UpdateFeed``, since noticing what is new costs nothing once the listing is here.
    /// Opening an old course therefore never announces its old results as news.
    ///
    /// - Parameter course: The course whose materials to load.
    func loadMaterials(for course: Course) async {
        guard !isLoadingMaterials else { return }
        isLoadingMaterials = true
        defer { isLoadingMaterials = false }

        // Last known listing first, so the screen has content before the
        // request and keeps it if the request fails.
        restoreMaterials(for: course)

        if session.useMockData || api == nil {
            sections = WeBeepSection.samples(for: course)
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
            contents[moodleID] = (raw, .now)
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

    /// Reads this academic year's course pages for new items, without the student opening
    /// each one.
    ///
    /// Favourites first and capped at ``watchLimit`` — see ``watched(_:now:pass:)``. Each
    /// page yields its contents, its announcements forum where it has one, and finally
    /// every page's assignments in a single request. Everything found is recorded in
    /// ``UpdateFeed``.
    ///
    /// The sweep stops early on a sign-out or a career switch, since the rest would be
    /// weighed against somebody else's sittings, and on cancellation. A sweep that read
    /// nothing does not mark the load window, so it is retried.
    ///
    /// - Parameters:
    ///   - force: Bypasses the hourly load window.
    ///   - deadline: Stops starting new courses after this moment, so a background refresh
    ///     ends on its own terms rather than being killed mid-write.
    func checkForUpdates(force: Bool = false, until deadline: Date? = nil) async {
        guard !session.useMockData, api != nil, let account = session.student?.matricola,
              updatesWindow.shouldLoad(force: force, source: account) else { return }

        if courses.isEmpty { await loadCourses() }
        guard let api else { return }
        feed.show(account: account)

        let watched = Self.watched(courses.map(Course.init(moodle:)), now: .now, pass: watchPass)
        watchPass += 1
        var checked = 0
        var read: [MaterialCourse] = []
        for course in watched {
            // A sign-out or a career switch mid-pass ends it: the rest would
            // be weighed against somebody else's sittings.
            guard !Task.isCancelled, session.student?.matricola == account,
                  deadline.map({ Date.now < $0 }) ?? true,
                  let target = MaterialCourse(course) else { break }
            do {
                let raw = try await api.contents(courseID: target.moodleID)
                await feed.recordMaterials(
                    course: target, sections: raw, account: account, inspect: resultsInspector())
                // One more request, only where the page has an announcements
                // forum. A failure here is the forum's, not the page's.
                if let forum = AnnouncementDetector.forumInstances(in: raw).first {
                    do {
                        let posts = try await api.discussions(forumID: forum)
                        await feed.recordAnnouncements(course: target, posts: posts, account: account)
                    } catch {
                        log.error("Announcements for course \(target.moodleID, privacy: .public) failed: \(error.localizedDescription)")
                    }
                }
                checked += 1
                read.append(target)
            } catch let error as WeBeepAPI.Failure where error.isAuthFailure {
                handle(error)
                return
            } catch {
                log.error("Update check for course \(target.moodleID, privacy: .public) failed: \(error.localizedDescription)")
            }
        }
        // Assignments for every page read, in a single request.
        if !read.isEmpty, !Task.isCancelled, deadline.map({ Date.now < $0 }) ?? true,
           session.student?.matricola == account {
            do {
                let byCourse = try await api.assignments(courseIDs: read.map(\.moodleID))
                for course in read {
                    await feed.recordAssignments(course: course, assignments: byCourse[course.moodleID] ?? [],
                                                 account: account)
                }
            } catch let error as WeBeepAPI.Failure where error.isAuthFailure {
                handle(error)
                return
            } catch {
                log.error("Assignments check failed: \(error.localizedDescription)")
            }
        }
        log.notice("Checked \(checked, privacy: .public) of \(watched.count, privacy: .public) course pages for updates")
        // A pass that read nothing is retried next time, like any failed load.
        if checked > 0 { updatesWindow.markLoaded(source: account) }
    }

    /// Reads a new results file for the student's own line, if they have turned that on.
    ///
    /// The file is fetched into memory through an ephemeral session — the shared session's
    /// cache would write other students' marks to disk — read, and dropped. Only the
    /// lookup outlives the call, and the address with its token is never logged or stored.
    /// Files larger than ``ResultsFileReader/maximumBytes`` are not fetched at all, judged
    /// from the listing's own size.
    ///
    /// - Returns: The inspector, or `nil` when the student has not allowed it, WeBeep is
    ///   not connected, or nobody is signed in — in which case nothing is downloaded.
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

    /// The course pages one sweep should read.
    ///
    /// Favourites every pass, since a favourite is the student saying which pages they
    /// care about; the remaining room rotates through the other eligible courses, so a
    /// seventh course is read every few passes rather than never.
    ///
    /// - Parameters:
    ///   - courses: The enrolled courses.
    ///   - now: The moment that decides which academic year is current.
    ///   - pass: The sweep's number, which advances the rotation.
    /// - Returns: At most ``watchLimit`` courses.
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

    /// Whether a course page is worth sweeping: this academic year's, not hidden, and
    /// linked to WeBeep by id.
    ///
    /// - Parameters:
    ///   - course: The course to judge.
    ///   - now: The moment that decides which academic year is current.
    /// - Returns: `true` when the page should be read.
    static func isWatchable(_ course: Course, now: Date) -> Bool {
        !course.isHidden && course.moodleID != nil
            && startYear(of: course.academicYear) == startYear(of: Course.academicYearLabel(for: now))
    }

    /// The calendar year an academic-year label begins in.
    ///
    /// - Parameter label: `2025/26`, `2025-26` or `2025-2026`, all of which begin in 2025.
    /// - Returns: The year, or `nil` when the label does not begin with four digits.
    private static func startYear(of label: String) -> Int? {
        Int(label.prefix(4))
    }

    /// The offline record name a course's listing is stored under.
    ///
    /// - Parameter course: The course.
    /// - Returns: The record name.
    private func slotName(for course: Course) -> String { "materials-\(course.id)" }

    /// Puts a course's cached listing into ``sections``, if there is one for this account.
    ///
    /// - Parameter course: The course.
    private func restoreMaterials(for course: Course) {
        var slot = materialSlots[course.id]
            ?? CachedSlot<[WeBeepSection]>(name: slotName(for: course))
        if let cached = slot.restore(for: session.student?.matricola) {
            sections = cached
        }
        materialSlots[course.id] = slot
    }

    /// Stores the current ``sections`` as this course's listing. Nothing is written under
    /// sample data.
    ///
    /// - Parameter course: The course.
    private func saveMaterials(for course: Course) {
        var slot = materialSlots[course.id]
            ?? CachedSlot<[WeBeepSection]>(name: slotName(for: course))
        slot.save(sections, for: session.useMockData ? nil : session.student?.matricola)
        materialSlots[course.id] = slot
    }

    /// Matches a Politecnico course to its Moodle counterpart.
    ///
    /// A course sourced from WeBeep already knows its id, so no matching is needed and
    /// none can go wrong. Otherwise the teaching code is looked for inside Moodle's title
    /// and short name — WeBeep names courses like `"097785 - BASI DI DATI"` — and failing
    /// that the normalised names are compared. A match is remembered.
    ///
    /// - Parameter course: The course to match.
    /// - Returns: Moodle's course id, or `nil` when nothing matches.
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

    // MARK: - Enrolment

    /// Whether each course page takes self-enrolment, by Moodle course id. Asked once per
    /// launch and read by ``EnrolmentOrigin``.
    private(set) var selfEnrolment: [Int: Bool] = [:]

    /// Asks the pages not already asked whether they take self-enrolment.
    ///
    /// One at a time: a background nicety rather than something worth a burst of requests.
    /// Failures are ignored and retried on a later launch.
    ///
    /// - Parameter moodleIDs: The course pages to ask about.
    func loadSelfEnrolment(for moodleIDs: [Int]) async {
        guard let api, !session.useMockData else { return }
        for id in moodleIDs where selfEnrolment[id] == nil {
            guard !Task.isCancelled else { return }
            if let methods = try? await api.enrolmentMethods(courseID: id) {
                selfEnrolment[id] = MoodleEnrolmentMethod.allowsSelfEnrolment(methods)
            }
        }
    }

    /// The lecturers listed on each course page, by Moodle course id. Asked once per
    /// launch.
    private(set) var contacts: [Int: [String]] = [:]

    /// Fetches the lecturers of the pages not already asked, twenty at a time — one
    /// request carries the ids in its query string.
    ///
    /// - Parameter moodleIDs: The course pages to ask about.
    func loadContacts(for moodleIDs: [Int]) async {
        guard let api, !session.useMockData else { return }
        let missing = moodleIDs.filter { contacts[$0] == nil }
        guard !missing.isEmpty else { return }
        do {
            // Chunked: one request carries the ids in its query string.
            for start in stride(from: 0, to: missing.count, by: 20) {
                let found = try await api.contacts(courseIDs: Array(missing[start..<min(start + 20, missing.count)]))
                contacts.merge(found) { _, new in new }
            }
        } catch {
            log.error("Course contacts failed: \(error.localizedDescription)")
        }
    }

    /// The held Moodle course with a given id.
    ///
    /// - Parameter id: Moodle's course id.
    /// - Returns: The course, or `nil` when it is not in the held list.
    func moodleCourse(id: Int) -> MoodleCourse? {
        courses.first { $0.id == id }
    }

    // MARK: - Forums

    /// Course pages read recently, so the course hub's forums and the materials screen
    /// share one `core_course_get_contents`. Reused for ten minutes.
    private var contents: [Int: (sections: [MoodleSection], at: Date)] = [:]

    /// The forums on a course's page.
    ///
    /// - Parameter course: The course.
    /// - Returns: The forums, or `nil` when WeBeep is not connected, the course cannot be
    ///   matched, or the call failed — none of which is the same as a page with no forums.
    func forums(for course: Course) async -> [CourseForum]? {
        if session.useMockData { return CourseForum.samples }
        guard let api else { return nil }
        if courses.isEmpty { await loadCourses() }
        guard let moodleID = moodleCourseID(for: course) else { return nil }
        if let cached = contents[moodleID], Date.now.timeIntervalSince(cached.at) < 600 {
            return CourseForum.forums(in: cached.sections)
        }
        do {
            let raw = try await api.contents(courseID: moodleID)
            contents[moodleID] = (raw, .now)
            return CourseForum.forums(in: raw)
        } catch let error as WeBeepAPI.Failure where error.isAuthFailure {
            handle(error)
            return nil
        } catch {
            log.error("Forums for course \(moodleID, privacy: .public) failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// The "Registrazioni" link on a course's WeBeep page, which the recordings use as
    /// a way into recman when the archive will not open. See
    /// ``RecmanParser/courseEntry(in:)``.
    ///
    /// - Parameter course: The course.
    /// - Returns: The link, or `nil` when WeBeep is not connected, the course cannot be
    ///   matched, or its page has no such link.
    func recordingsEntry(for course: Course) async -> URL? {
        guard !session.useMockData, let api else { return nil }
        if courses.isEmpty { await loadCourses() }
        guard let moodleID = moodleCourseID(for: course) else { return nil }
        if let cached = contents[moodleID], Date.now.timeIntervalSince(cached.at) < 600 {
            return RecmanParser.courseEntry(in: cached.sections)
        }
        do {
            let raw = try await api.contents(courseID: moodleID)
            contents[moodleID] = (raw, .now)
            return RecmanParser.courseEntry(in: raw)
        } catch let error as WeBeepAPI.Failure where error.isAuthFailure {
            handle(error)
            return nil
        } catch {
            log.error("Recordings link for course \(moodleID, privacy: .public) failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// The discussions in one forum.
    ///
    /// - Parameter forum: The forum to read.
    /// - Returns: Up to thirty discussions, in Moodle's own order.
    /// - Throws: `URLError.userAuthenticationRequired` when WeBeep is not connected, or
    ///   ``WeBeepAPI/Failure``.
    func discussions(in forum: CourseForum) async throws -> [MoodleDiscussion] {
        if session.useMockData { return MoodleDiscussion.samples }
        // Not connected: the forum screen offers the login before asking.
        guard let api else { throw URLError(.userAuthenticationRequired) }
        return try await api.discussions(forumID: forum.id, perPage: 30)
    }

    /// The posts in one discussion, oldest first.
    ///
    /// - Parameter discussion: The discussion to read.
    /// - Returns: The posts.
    /// - Throws: `URLError.userAuthenticationRequired` when WeBeep is not connected, or
    ///   ``WeBeepAPI/Failure``.
    func posts(in discussion: MoodleDiscussion) async throws -> [MoodlePosts.Post] {
        if session.useMockData { return MoodlePosts.Post.samples(for: discussion) }
        // Not connected: the forum screen offers the login before asking.
        guard let api else { throw URLError(.userAuthenticationRequired) }
        return try await api.discussionPosts(discussionID: discussion.discussion ?? discussion.id).chronological
    }

    /// Reports a Moodle failure.
    ///
    /// A failure that means the token is dead signs WeBeep out, so the interface offers a
    /// fresh sign-in; anything else enters ``State/failed(_:)``.
    ///
    /// - Parameter error: What the call raised.
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
/// ``WeBeepModel`` satisfies ``CourseEnrolments``, with its Moodle courses
/// projected into the app's own ``Course``.
///
/// Declared here rather than beside the protocol: ``CourseEnrolments`` refines
/// `Sendable`, and a `Sendable` conformance stated in another file is
/// retroactive.
extension WeBeepModel: CourseEnrolments {
    /// The enrolled teachings, loading them first if they are not held yet.
    ///
    /// - Returns: The teachings.
    func enrolledCourses() async -> [Course] {
        await loadCourses()
        return courses.map(Course.init(moodle:))
    }
}
