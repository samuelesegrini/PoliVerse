import Foundation
import Observation

/// Loads the student's enrolled teachings.
@Observable
final class CourseService {
    private(set) var courses: [Course] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let session: Session
    private var favourites: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "favouriteCourses") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "favouriteCourses") }
    }

    init(session: Session) {
        self.session = session
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

        do {
            // `/rest/v1/insegn` lives on the exams host but takes the same
            // bearer token as the app host.
            let response = try await session.api.send(
                APIRequest(
                    host: .exams,
                    path: "/rest/v1/insegn",
                    query: [.init(name: "lang", value: "IT")]
                ),
                as: TeachingsResponse.self
            )
            let loaded = response.INSEGN.map { $0.toCourse() }
            courses = applyFavourites(loaded)
            DiskCache.save(loaded, as: "courses")
        } catch {
            errorMessage = error.localizedDescription
            // Falling back keeps the screen useful rather than blank while the
            // endpoint shapes are still being verified against a real account.
            if courses.isEmpty { courses = applyFavourites(MockData.courses) }
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
