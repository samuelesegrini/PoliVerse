import Foundation
import Observation
import OSLog

/// Loads the student's enrolled teachings.
@Observable
final class CourseService {
    private(set) var courses: [Course] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let session: Session
    private let weBeep: WeBeepService
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "courses")
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

    init(session: Session, weBeep: WeBeepService) {
        self.session = session
        self.weBeep = weBeep
        // Show last known courses immediately; `load()` refreshes behind them.
        if let cached = DiskCache.load([Course].self, as: "courses") {
            courses = applyFavourites(cached.value)
        }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if session.useMockData {
            courses = applyFavourites(MockData.courses)
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
            DiskCache.save(loaded, as: "courses")
            return
        }

        do {
            // Fall back to the teachings list: better than nothing when WeBeep
            // is not connected, and the only source that carries exam sittings.
            let response = try await session.api.send(
                APIRequest(
                    host: .iae,
                    path: "/v1/insegn",
                    query: [.init(name: "lang", value: "IT")]
                ),
                as: TeachingsResponse.self
            )
            let loaded = response.teachings.compactMap { $0.toCourse() }
            log.notice("insegn returned \(response.teachings.count, privacy: .public) teachings, \(loaded.count, privacy: .public) usable")
            courses = applyFavourites(loaded)
            DiskCache.save(loaded, as: "courses")
        } catch {
            errorMessage = error.localizedDescription
            // Never substitute mock data for a failed real request. The user
            // turned sample data off; showing invented courses as if they were
            // theirs is worse than showing nothing. Cached real courses are
            // fine to keep — they were genuinely theirs once.
        }
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
            if await !weBeep.setFavourite(wanted, moodleID: moodleID) {
                // The server disagreed; do not leave the UI claiming otherwise.
                apply(to: course) { $0.isFavourite = !wanted }
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
            if await !weBeep.setHidden(wanted, moodleID: moodleID) {
                apply(to: course) { $0.isHidden = !wanted }
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
    private func applyFavourites(_ input: [Course]) -> [Course] {
        let favs = favourites
        let hidden = hiddenCourses
        return sortCourses(input.map { course in
            guard course.moodleID == nil else { return course }
            var copy = course
            copy.isFavourite = favs.contains(course.id)
            copy.isHidden = hidden.contains(course.id)
            return copy
        })
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
