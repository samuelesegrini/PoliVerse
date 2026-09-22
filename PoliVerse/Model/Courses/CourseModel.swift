import Foundation
import Observation

/// The student's enrolled teachings, as the screens read them.
///
/// ``courses`` is derived rather than stored, from four independent facts: what the
/// service returned, held in a ``Store``; the flags this device remembers for
/// courses WeBeep does not know; the changes that have not reached WeBeep yet, held
/// in ``OptimisticFlags``; and the teaching codes the study plan supplied. Nothing
/// has to be written back in a particular order, and no path can overwrite another's
/// flag.
///
/// Sorting happens on read, which is affordable here: a student has on the order of
/// ten enrolled courses.
///
/// ## Changes
///
/// ``toggleFavourite(_:)`` and ``toggleHidden(_:)`` record the change locally at
/// once, then mirror it to WeBeep for any course that came from there. A mirror that
/// fails is queued through ``PendingChanges`` rather than being undone, and
/// ``confirmDelivered(_:)`` drops the local override once the queue delivers it.
@Observable
@MainActor
final class CourseModel {
    /// The loaded course list, with its cache and load window.
    private let store: Store<CourseSource>
    /// Reads the WeBeep enrolments and mirrors the two flags back to it.
    private let enrolments: any CourseEnrolments

    /// Where a change goes when it cannot be delivered now.
    private let pending: PendingChanges?
    /// Fills in teaching codes from the student's study plan.
    private let programme: (any TeachingCodes)?

    /// Starred courses WeBeep does not know about, by ``Course/id``.
    ///
    /// Held as observed state rather than read from `UserDefaults` at the point of use,
    /// because ``courses`` derives from it and a bare defaults read could not invalidate
    /// the list.
    private var favourites: Set<String>
    /// Hidden courses WeBeep does not know about, by ``Course/id``. Observed for the same
    /// reason as ``favourites``.
    private var hiddenCourses: Set<String>

    /// Where the local flags live. Injected so that two tests in one run cannot see each
    /// other's.
    private let defaults: UserDefaults

    /// Changes the student made that have not reached WeBeep yet. Applied over
    /// everything, WeBeep courses included.
    private var optimistic: OptimisticFlags

    /// Teaching codes the study plan supplied for WeBeep pages titled with a name only,
    /// by ``Course/id``.
    private var planCodes: [String: String] = [:]

    /// Creates the model and reads the local flags.
    ///
    /// - Parameters:
    ///   - account: Whose courses to load.
    ///   - enrolments: Reads WeBeep's enrolments and mirrors the flags. Captured weakly
    ///     by the source.
    ///   - pending: Where an undeliverable change is queued.
    ///   - programme: Supplies teaching codes from the study plan.
    ///   - defaults: Where the local flags live.
    init(account: any Account, enrolments: any CourseEnrolments,
         pending: PendingChanges? = nil, programme: (any TeachingCodes)? = nil,
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

    /// Every enrolled course, sorted, with the study plan's codes, this device's flags
    /// and any unsent change applied over what the service returned.
    ///
    /// The local flag sets apply only to courses with no ``Course/moodleID``: WeBeep owns
    /// those flags for the courses it knows. Unsent changes apply to all of them, so a
    /// star tapped offline survives a relaunch while the queue still intends to deliver
    /// it.
    ///
    /// Sorted by ``sortCourses(_:)``.
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

    /// `true` while a load is in flight.
    var isLoading: Bool { store.isLoading }
    /// The last load's error, or `nil` when it succeeded.
    var errorMessage: String? { store.errorMessage }
    /// Seconds since the course list was fetched, or `nil` if never.
    var age: TimeInterval? { store.age }

    /// The courses shown in the normal list: everything not hidden.
    var visibleCourses: [Course] { courses.filter { !$0.isHidden } }
    /// The starred courses among the visible ones.
    var favouriteCourses: [Course] { visibleCourses.filter(\.isFavourite) }
    /// The hidden courses, for the sheet that lists them.
    var hiddenOnly: [Course] { courses.filter(\.isHidden) }

    /// The academic years present among the visible courses, most recent first, for the
    /// year filter. Years recorded as `"—"` are omitted.
    var academicYears: [String] {
        Array(Set(visibleCourses.map(\.academicYear).filter { $0 != "—" })).sorted(by: >)
    }

    /// The visible courses of one academic year.
    ///
    /// - Parameter year: The year to filter by, or `nil` for every visible course.
    /// - Returns: The matching courses.
    func courses(in year: String?) -> [Course] {
        guard let year else { return visibleCourses }
        return visibleCourses.filter { $0.academicYear == year }
    }

    // MARK: - Loading

    /// Loads the course list, then fills in teaching codes from the study plan.
    ///
    /// - Parameter force: Bypasses the store's load window.
    func load(force: Bool = false) async {
        await store.load(force: force)
        await fillCodes()
    }

    /// Asks the study programme for teaching codes for the WeBeep pages titled with a
    /// name only, so their scheda, sittings and plan label work like any other course's.
    ///
    /// Tells the programme which codes are already known per year first, and leaves
    /// ``planCodes`` untouched when nothing comes back.
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

    /// Stars or unstars a course.
    ///
    /// A course with no ``Course/moodleID`` keeps the flag locally. One that came from
    /// WeBeep records an override immediately, so the tap shows at once and survives a
    /// relaunch, then mirrors the change: an accepted change clears the override, and a
    /// rejected one is queued.
    ///
    /// - Parameter course: The course whose flag to flip.
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
            // undoing the tap, which from the student's side is
            // indistinguishable from the app ignoring them.
            if await enrolments.setFavourite(wanted, moodleID: moodleID) {
                // Accepted: the server is the truth again.
                optimistic.clear(favouriteFor: course.id)
            } else {
                pending?.record(.courseFavourite(moodleID: moodleID, value: wanted))
            }
        }
    }

    /// Hides or reveals a course, mirroring Moodle's “Remove from view”.
    ///
    /// Behaves exactly as ``toggleFavourite(_:)`` does, including the override and the
    /// queue.
    ///
    /// - Parameter course: The course whose flag to flip.
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

    /// Drops the local override for a change that has now reached WeBeep.
    ///
    /// Keeping the override would make the app ignore a favourite later removed from the
    /// web. Called by ``PendingChanges`` after a successful delivery; does nothing for
    /// an action naming no known course, or for one that is not a course flag.
    ///
    /// - Parameter action: The change that was delivered.
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

    /// Orders courses: starred first, then by most recent academic year, then by name.
    ///
    /// - Parameter input: The courses to order.
    /// - Returns: The ordered courses.
    private func sortCourses(_ input: [Course]) -> [Course] {
        input.sorted { lhs, rhs in
            if lhs.isFavourite != rhs.isFavourite { return lhs.isFavourite }
            if lhs.academicYear != rhs.academicYear { return lhs.academicYear > rhs.academicYear }
            return lhs.name < rhs.name
        }
    }
}
