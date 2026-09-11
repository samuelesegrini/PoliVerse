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
    private var favourites: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "favouriteCourses") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "favouriteCourses") }
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

    func toggleFavourite(_ course: Course) {
        var current = favourites
        if current.contains(course.id) { current.remove(course.id) } else { current.insert(course.id) }
        favourites = current
        courses = applyFavourites(courses)
    }

    private func applyFavourites(_ input: [Course]) -> [Course] {
        let favs = favourites
        return input
            .map { course in
                var copy = course
                copy.isFavourite = favs.contains(course.id)
                return copy
            }
            .sorted { lhs, rhs in
                if lhs.isFavourite != rhs.isFavourite { return lhs.isFavourite }
                return lhs.name < rhs.name
            }
    }
}
