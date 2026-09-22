import Foundation

/// Per-course flags the student has changed but the Politecnico has not accepted
/// yet, persisted in `UserDefaults`.
///
/// `Course.isFavourite` and `Course.isHidden` belong to WeBeep and are reapplied
/// from the server on every load, so a stale cache cannot resurrect a favourite
/// removed on the web. An override is a third state, newer than both the cache
/// and the server, and it survives relaunch: ``apply(to:)`` layers it over
/// whatever arrived.
///
/// An override is temporary. It is cleared the moment ``ActionQueue`` gets the
/// matching change to the Politecnico, at which point the server is the truth
/// again.
///
/// Not `Sendable`: it holds a `UserDefaults`, and the flags are only touched from
/// the main actor, where the course list lives.
nonisolated struct OptimisticFlags {
    /// Where the overrides are persisted.
    private let defaults: UserDefaults
    /// Defaults key for the favourite overrides.
    private let favouriteKey = "optimisticFavourites"
    /// Defaults key for the hidden overrides.
    private let hiddenKey = "optimisticHidden"

    /// Favourite overrides by ``Course/id``.
    private var favourites: [String: Bool]
    /// Hidden overrides by ``Course/id``.
    private var hidden: [String: Bool]

    /// Reads the stored overrides.
    ///
    /// - Parameter defaults: Where the overrides are persisted.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favourites = defaults.dictionary(forKey: favouriteKey) as? [String: Bool] ?? [:]
        hidden = defaults.dictionary(forKey: hiddenKey) as? [String: Bool] ?? [:]
    }

    /// The unsent favourite value for a course.
    ///
    /// - Parameter id: The ``Course/id``.
    /// - Returns: The overriding value, or `nil` when there is no unsent change.
    ///   `false` is a change, not an absence.
    func favourite(for id: String) -> Bool? { favourites[id] }
    /// The unsent hidden value for a course.
    ///
    /// - Parameter id: The ``Course/id``.
    /// - Returns: The overriding value, or `nil` when there is no unsent change.
    func hidden(for id: String) -> Bool? { hidden[id] }

    /// Records an unsent favourite change and persists it.
    ///
    /// - Parameters:
    ///   - favourite: The value the student chose.
    ///   - id: The ``Course/id``.
    mutating func set(favourite: Bool, for id: String) {
        favourites[id] = favourite
        defaults.set(favourites, forKey: favouriteKey)
    }

    /// Records an unsent hidden change and persists it.
    ///
    /// - Parameters:
    ///   - value: The value the student chose.
    ///   - id: The ``Course/id``.
    mutating func set(hidden value: Bool, for id: String) {
        hidden[id] = value
        defaults.set(hidden, forKey: hiddenKey)
    }

    /// Drops the favourite override for a course, once the change has reached the
    /// Politecnico.
    ///
    /// - Parameter id: The ``Course/id``.
    mutating func clear(favouriteFor id: String) {
        favourites[id] = nil
        defaults.set(favourites, forKey: favouriteKey)
    }

    /// Drops the hidden override for a course, once the change has reached the
    /// Politecnico.
    ///
    /// - Parameter id: The ``Course/id``.
    mutating func clear(hiddenFor id: String) {
        hidden[id] = nil
        defaults.set(hidden, forKey: hiddenKey)
    }

    /// `true` when there are no unsent changes of either kind.
    var isEmpty: Bool { favourites.isEmpty && hidden.isEmpty }

    /// Layers every unsent change over the courses as they arrived.
    ///
    /// - Parameter courses: Courses from the network, the offline copy or the sample
    ///   set.
    /// - Returns: The same courses with overridden flags. The input is returned
    ///   unchanged when there are no overrides.
    func apply(to courses: [Course]) -> [Course] {
        guard !isEmpty else { return courses }
        return courses.map { course in
            var copy = course
            if let value = favourites[course.id] { copy.isFavourite = value }
            if let value = hidden[course.id] { copy.isHidden = value }
            return copy
        }
    }
}
