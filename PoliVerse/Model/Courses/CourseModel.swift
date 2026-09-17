import Foundation
import Observation
import OSLog

/// Loads the student's enrolled teachings.
@Observable
final class CourseModel {
    private(set) var courses: [Course] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var age: TimeInterval?
    /// Keyed by matricola. Under a global name — which is how this was written
    /// before the career switcher existed — the triennale's courses appeared
    /// under the magistrale: a leak between two records belonging to the same
    /// person.
    private var slot = CachedSlot<[Course]>(name: "courses")
    /// Where a change goes when it cannot be sent now. Assigned by the app,
    /// because the queue needs the session and this service is built first.
    var pending: PendingChanges?
    /// Fills in teaching codes from the student's plan. Assigned by the app.
    var programme: StudyProgrammeModel?
    /// Changes the user made that have not reached WeBeep yet.
    ///
    /// A third state between the cache and the server: newer than both,
    /// because the user just made it, and dropped the moment the queue
    /// delivers it so the server is the truth again.
    private var optimistic = OptimisticFlags()

    private func restoreCache() {
        guard let cached = slot.restore(for: session.student?.matricola) else { return }
        courses = applyFavourites(cached)
        age = slot.age
    }

    private let session: Session
    private let weBeep: WeBeepModel
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "courses")
    /// Fifteen minutes: the enrolled-course list changes at most once a
    /// semester.
    private var window = LoadWindow(interval: 900)

    /// Identifies the data currently held, so a change of account — or of the
    /// sample-data toggle — always reloads instead of waiting out the window.
    private var source: String {
        session.useMockData ? "mock" : (session.student?.matricola ?? "anonymous")
    }

    /// Local flags, used only for courses with no WeBeep counterpart. WeBeep
    /// itself is the source of truth for everything it knows about.
    private var favourites: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "favouriteCourses") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "favouriteCourses") }
    }

    private var hiddenCourses: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "hiddenCourses") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "hiddenCourses") }
    }

    /// Courses shown in the normal list: neither hidden nor filtered out.
    var visibleCourses: [Course] { courses.filter { !$0.isHidden } }
    var favouriteCourses: [Course] { visibleCourses.filter(\.isFavourite) }
    var hiddenOnly: [Course] { courses.filter(\.isHidden) }

    /// Academic years present, most recent first, for the year filter.
    var academicYears: [String] {
        Array(Set(visibleCourses.map(\.academicYear).filter { $0 != "—" })).sorted(by: >)
    }

    func courses(in year: String?) -> [Course] {
        guard let year else { return visibleCourses }
        return visibleCourses.filter { $0.academicYear == year }
    }

    init(session: Session, weBeep: WeBeepModel) {
        self.session = session
        self.weBeep = weBeep
        // Show last known courses immediately; `load()` refreshes behind them.
        // Restored in `load()`, not here: the matricola is not known while
        // the App's initialiser is still running.
    }

    /// - Parameter force: set by pull-to-refresh; see ``LoadWindow``.
    func load(force: Bool = false) async {
        guard !isLoading, window.shouldLoad(force: force, source: source) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        restoreCache()

        if session.useMockData {
            courses = applyFavourites(MockData.courses)
            window.markLoaded(source: source)
            return
        }

        // WeBeep is the better source for "which courses am I taking".
        //
        // `/v1/insegn` is the *exam registration* endpoint — `iae` is
        // iscrizione appelli esami — so it lists teachings that still have
        // sittings to sit. A student who has passed everything gets an empty
        // array from it, which is correct for exams and useless as a course
        // list. WeBeep lists actual enrolments and keeps them after the exam is
        // passed.
        await weBeep.loadCourses()
        if !weBeep.courses.isEmpty {
            let loaded = weBeep.courses.map(Course.init(moodle:))
            log.notice("WeBeep provided \(loaded.count, privacy: .public) enrolled courses")
            courses = applyFavourites(loaded)
            slot.save(loaded, for: session.useMockData ? nil : session.student?.matricola)
            age = slot.age
            window.markLoaded(source: source)
            await fillCodes()
            return
        }

        do {
            // Fall back to the teachings list: better than nothing when WeBeep
            // is not connected, and the only source that carries exam sittings.
            let response = try await session.api.send(
                APIRequest(
                    host: .iae,
                    path: "/v1/insegn",
                    query: [.init(name: "lang", value: PoliMiLanguage.current.rawValue)]
                ),
                as: TeachingsResponse.self
            )
            let loaded = response.teachings.compactMap { $0.toCourse() }
            log.notice("insegn returned \(response.teachings.count, privacy: .public) teachings, \(loaded.count, privacy: .public) usable")
            courses = applyFavourites(loaded)
            slot.save(loaded, for: session.useMockData ? nil : session.student?.matricola)
            age = slot.age
            window.markLoaded(source: source)
        } catch {
            errorMessage = userFacingMessage(error)
            // Never substitute mock data for a failed real request. The user
            // turned sample data off; showing invented courses as if they were
            // theirs is worse than showing nothing. Cached real courses are
            // fine to keep — they were genuinely theirs once.
        }
    }

    /// Teaching codes for WeBeep pages titled with a name only, from the plan
    /// of each course's year — so their scheda, sittings and study-plan label
    /// work like those of any other course. Applied by id, over whatever the
    /// list holds by the time the plan pages arrive.
    private func fillCodes() async {
        guard let programme else { return }
        programme.enrolledCodes = Dictionary(grouping: courses.filter { $0.teachingCode != nil },
                                             by: { $0.academicYearStart ?? "" })
            .mapValues { Set($0.compactMap(\.teachingCode)) }
        let codes = await programme.codes(for: courses)
        guard !codes.isEmpty else { return }
        courses = courses.map { course in
            guard course.code == nil || course.teachingCode == nil, let code = codes[course.id] else { return course }
            var copy = course
            copy.code = code
            return copy
        }
        log.notice("study plan gave codes to \(codes.count, privacy: .public) WeBeep courses")
    }

    /// Toggles the favourite flag, writing it to WeBeep when the course came
    /// from there so the change shows up on the web too.
    func toggleFavourite(_ course: Course) {
        let wanted = !course.isFavourite
        apply(to: course) { $0.isFavourite = wanted }

        guard let moodleID = course.moodleID else {
            // A course with no WeBeep counterpart keeps the flag locally.
            var current = favourites
            if wanted { current.insert(course.id) } else { current.remove(course.id) }
            favourites = current
            return
        }

        Task {
            // Offline, or the request failed: queue it rather than silently
            // undoing the tap. Reverting was the old behaviour and it is
            // indistinguishable, from the user's side, from the app ignoring
            // them.
            if await weBeep.setFavourite(wanted, moodleID: moodleID) {
                // Accepted: the server is the truth again.
                optimistic.clear(favouriteFor: course.id)
            } else {
                // Recorded before queueing, so a relaunch before the queue
                // drains still shows what the user chose.
                optimistic.set(favourite: wanted, for: course.id)
                pending?.record(.courseFavourite(moodleID: moodleID, value: wanted))
            }
        }
    }

    /// Hides a course, mirroring WeBeep's "Remove from view".
    func toggleHidden(_ course: Course) {
        let wanted = !course.isHidden
        apply(to: course) { $0.isHidden = wanted }

        guard let moodleID = course.moodleID else {
            var current = hiddenCourses
            if wanted { current.insert(course.id) } else { current.remove(course.id) }
            hiddenCourses = current
            return
        }

        Task {
            if await weBeep.setHidden(wanted, moodleID: moodleID) {
                optimistic.clear(hiddenFor: course.id)
            } else {
                optimistic.set(hidden: wanted, for: course.id)
                pending?.record(.courseHidden(moodleID: moodleID, value: wanted))
            }
        }
    }

    private func apply(to course: Course, _ change: (inout Course) -> Void) {
        guard let index = courses.firstIndex(where: { $0.id == course.id }) else { return }
        change(&courses[index])
        courses = sortCourses(courses)
    }

    /// Applies the locally-held flags, which matter only for courses WeBeep
    /// does not know about — for the rest, WeBeep's own values already arrived
    /// on the course and must not be overwritten.
    /// Called by ``PendingChanges`` once a queued change reaches WeBeep.
    ///
    /// Dropping the override is the point: keeping it would make the app
    /// ignore a favourite removed later from the web, forever.
    func confirmDelivered(_ action: PendingAction) {
        guard let course = courses.first(where: {
            switch action {
            case .courseFavourite(let id, _), .courseHidden(let id, _):
                return $0.moodleID == id
            default:
                return false
            }
        }) else { return }

        switch action {
        case .courseFavourite: optimistic.clear(favouriteFor: course.id)
        case .courseHidden: optimistic.clear(hiddenFor: course.id)
        default: break
        }
    }

    private func applyFavourites(_ input: [Course]) -> [Course] {
        let favs = favourites
        let hidden = hiddenCourses
        let withLocal = input.map { course -> Course in
            // WeBeep owns these flags for the courses it knows; the local sets
            // are only for courses it does not.
            guard course.moodleID == nil else { return course }
            var copy = course
            copy.isFavourite = favs.contains(course.id)
            copy.isHidden = hidden.contains(course.id)
            return copy
        }
        // Unsent changes go on top of everything, WeBeep courses included.
        // Without this a star tapped offline came back off after a relaunch
        // while the queue still intended to turn it on.
        return sortCourses(optimistic.apply(to: withLocal))
    }

    /// Favourites first, then most recent year, then by name.
    private func sortCourses(_ input: [Course]) -> [Course] {
        input.sorted { lhs, rhs in
            if lhs.isFavourite != rhs.isFavourite { return lhs.isFavourite }
            if lhs.academicYear != rhs.academicYear { return lhs.academicYear > rhs.academicYear }
            return lhs.name < rhs.name
        }
    }
}
