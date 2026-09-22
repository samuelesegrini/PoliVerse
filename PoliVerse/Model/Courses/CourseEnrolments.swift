import Foundation

/// What the course list needs from WeBeep, and nothing else.
///
/// ``CourseModel`` used to take the whole ``WeBeepModel`` — 496 lines holding a
/// Moodle token, a file cache, a forum reader and an update watcher — in order
/// to use three of its methods. That is what made the course list impossible to
/// stand up in a test: constructing WeBeep means constructing a ``Session``,
/// which means the Keychain.
///
/// Three methods, because that is genuinely the whole of the traffic between
/// them: which courses am I enrolled in, and mirror these two flags to the web.
@MainActor
protocol CourseEnrolments: AnyObject, Sendable {
    /// The enrolled teachings as WeBeep knows them, refreshing first.
    func enrolledCourses() async -> [Course]
    /// Returns false when the change could not be delivered, so the caller can
    /// queue it rather than silently undoing the user's tap.
    func setFavourite(_ favourite: Bool, moodleID: Int) async -> Bool
    func setHidden(_ hidden: Bool, moodleID: Int) async -> Bool
}

