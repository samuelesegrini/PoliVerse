import Foundation
import Observation

/// The student's enrolled teachings, as the screens read them.
///
/// ## What changed when this moved onto ``Store``
///
/// The list used to be a stored property that four separate paths wrote to —
/// the load, the favourite toggle, the hidden toggle, and the study-plan pass
/// that fills in teaching codes. Each wrote the *whole* list back after
/// re-applying the local flags, so the order of those writes mattered and
/// getting it wrong lost a flag. There is now one stored fact per source of
/// truth — what the service returned (in the store), what this device
/// remembers, what has not reached WeBeep yet, and the codes the plan supplied
/// — and ``courses`` derives from them. Nothing to sequence, nothing to
/// overwrite.
///
/// The derivation sorts on read rather than on write, which the timetable
/// deliberately does not do. The difference is size: a student has on the order
/// of ten enrolled courses, not the 350 rooms that made ``AgendaModel`` index
/// eagerly.
@Observable
@MainActor
final class CourseModel {
    private let store: Store<CourseSource>
    private let enrolments: any CourseEnrolments

    /// Where a change goes when it cannot be sent now.
    private let pending: PendingChanges?
    /// Fills in teaching codes from the student's plan.
    private let programme: StudyProgrammeModel?

    /// Local flags, used only for courses with no WeBeep counterpart — WeBeep
    /// itself is the source of truth for everything it knows about.
    ///
    /// Held here as observed state rather than read from `UserDefaults` at the
    /// point of use, because ``courses`` derives from them: a toggle has to
    /// invalidate the list, and a bare `UserDefaults` read cannot say that it
    /// changed.
    private var favourites: Set<String>
    private var hiddenCourses: Set<String>

    /// Where the local flags live. Injected so a test — and two tests in the
    /// same run — cannot see each other's, which `UserDefaults.standard` made
    /// unavoidable.
    private let defaults: UserDefaults

    /// Changes the user made that have not reached WeBeep yet: a third state
    /// between the cache and the server, newer than both, dropped the moment
    /// the queue delivers it so the server is the truth again.
    private var optimistic: OptimisticFlags

    /// Teaching codes the study plan supplied for WeBeep pages titled with a
    /// name only, keyed by course id.
    private var planCodes: [String: String] = [:]

    init(account: any Account, enrolments: any CourseEnrolments,
         pending: PendingChanges? = nil, programme: StudyProgrammeModel? = nil,
         defaults: UserDefaults = .standard) {
        self.enrolments = enrolments
        self.pending = pending
        self.programme = programme
        self.defaults = defaults
        self.favourites = Set(defaults.stringArray(forKey: "favouriteCourses") ?? [])
        self.hiddenCourses = Set(defaults.stringArray(forKey: "hiddenCourses") ?? [])
        self.optimistic = OptimisticFlags(defaults: defaults)
        self.store = Store(
            CourseSource(enrolled: { [weak enrolments] in
                await enrolments?.enrolledCourses() ?? []
            }),
            account: account
        )
    }

    // MARK: - What the screens read

    /// Every enrolled course, with this device's flags, any unsent change and
    /// any code the study plan supplied applied over what the service returned.
    var courses: [Course] {
        let loaded = store.value ?? []
        let withLocal = loaded.map { course -> Course in
            var copy = course
            if let code = planCodes[course.id], course.code == nil || course.teachingCode == nil {
                copy.code = code
            }
            // WeBeep owns these flags for the courses it knows; the local sets
            // are only for the courses it does not.
            guard course.moodleID == nil else { return copy }
            copy.isFavourite = favourites.contains(course.id)
            copy.isHidden = hiddenCourses.contains(course.id)
            return copy
        }
        // Unsent changes go on top of everything, WeBeep courses included.
        // Without this a star tapped offline came back off after a relaunch
        // while the queue still intended to turn it on.
        return sortCourses(optimistic.apply(to: withLocal))
    }

    var isLoading: Bool { store.isLoading }
    var errorMessage: String? { store.errorMessage }
    var age: TimeInterval? { store.age }

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

    // MARK: - Loading

    func load(force: Bool = false) async {
        await store.load(force: force)
        await fillCodes()
    }

    /// Teaching codes for WeBeep pages titled with a name only, from the plan
    /// of each course's year — so their scheda, sittings and study-plan label
    /// work like those of any other course.
    private func fillCodes() async {
        guard let programme else { return }
        let current = courses
        programme.enrolledCodes = Dictionary(
            grouping: current.filter { $0.teachingCode != nil },
            by: { $0.academicYearStart ?? "" }
        ).mapValues { Set($0.compactMap(\.teachingCode)) }
        let codes = await programme.codes(for: current)
        guard !codes.isEmpty else { return }
        planCodes = codes
    }

    // MARK: - Changes the user makes

    /// Toggles the favourite flag, writing it to WeBeep when the course came
    /// from there so the change shows up on the web too.
    func toggleFavourite(_ course: Course) {
        let wanted = !course.isFavourite

        guard let moodleID = course.moodleID else {
            // A course with no WeBeep counterpart keeps the flag locally.
            if wanted { favourites.insert(course.id) } else { favourites.remove(course.id) }
            defaults.set(Array(favourites), forKey: "favouriteCourses")
            return
        }

        // Recorded before the request, so the list shows the tap immediately
        // and a relaunch before the queue drains still shows what was chosen.
        optimistic.set(favourite: wanted, for: course.id)
        Task {
            // Offline, or the request failed: queue it rather than silently
            // undoing the tap. Reverting was the old behaviour and it is
            // indistinguishable, from the user's side, from the app ignoring
            // them.
            if await enrolments.setFavourite(wanted, moodleID: moodleID) {
                // Accepted: the server is the truth again.
                optimistic.clear(favouriteFor: course.id)
            } else {
                pending?.record(.courseFavourite(moodleID: moodleID, value: wanted))
            }
        }
    }

    /// Hides a course, mirroring WeBeep's "Remove from view".
    func toggleHidden(_ course: Course) {
        let wanted = !course.isHidden

        guard let moodleID = course.moodleID else {
            if wanted { hiddenCourses.insert(course.id) } else { hiddenCourses.remove(course.id) }
            defaults.set(Array(hiddenCourses), forKey: "hiddenCourses")
            return
        }

        optimistic.set(hidden: wanted, for: course.id)
        Task {
            if await enrolments.setHidden(wanted, moodleID: moodleID) {
                optimistic.clear(hiddenFor: course.id)
            } else {
                pending?.record(.courseHidden(moodleID: moodleID, value: wanted))
            }
        }
    }

    /// Called by ``PendingChanges`` once a queued change reaches WeBeep.
    ///
    /// Dropping the override is the point: keeping it would make the app ignore
    /// a favourite removed later from the web, forever.
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

    /// Favourites first, then most recent year, then by name.
    private func sortCourses(_ input: [Course]) -> [Course] {
        input.sorted { lhs, rhs in
            if lhs.isFavourite != rhs.isFavourite { return lhs.isFavourite }
            if lhs.academicYear != rhs.academicYear { return lhs.academicYear > rhs.academicYear }
            return lhs.name < rhs.name
        }
    }
}
