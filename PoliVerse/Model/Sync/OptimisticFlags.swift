import Foundation

/// Course flags the user has changed but the Politecnico has not accepted yet.
///
/// ## Why this is needed
///
/// `Course.isFavourite` is deliberately not persisted: it is WeBeep's to own,
/// and reapplying it from the server on every load is what stops a stale cache
/// resurrecting a favourite the user removed on the web. That is right, and it
/// left a hole — a star tapped offline flipped an in-memory flag and queued
/// the change, but a relaunch showed the star **off** while the queue still
/// intended to turn it on. The app contradicted itself, and `isHidden`
/// behaved differently again because that one *is* encoded.
///
/// An override is a third state between "cached" and "server": newer than
/// both, because the user just made it, and temporary — it is dropped the
/// moment the change reaches the Politecnico, so the server goes back to being
/// the truth.
/// Not `Sendable`: it holds a `UserDefaults`, and the flags are only ever
/// touched from the main actor where the course list lives.
nonisolated struct OptimisticFlags {
    private let defaults: UserDefaults
    private let favouriteKey = "optimisticFavourites"
    private let hiddenKey = "optimisticHidden"

    private var favourites: [String: Bool]
    private var hidden: [String: Bool]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favourites = defaults.dictionary(forKey: favouriteKey) as? [String: Bool] ?? [:]
        hidden = defaults.dictionary(forKey: hiddenKey) as? [String: Bool] ?? [:]
    }

    /// Nil means "no unsent change"; false is a change, not an absence —
    /// turning something off is as much a decision as turning it on.
    func favourite(for id: String) -> Bool? { favourites[id] }
    func hidden(for id: String) -> Bool? { hidden[id] }

    mutating func set(favourite: Bool, for id: String) {
        favourites[id] = favourite
        defaults.set(favourites, forKey: favouriteKey)
    }

    mutating func set(hidden value: Bool, for id: String) {
        hidden[id] = value
        defaults.set(hidden, forKey: hiddenKey)
    }

    mutating func clear(favouriteFor id: String) {
        favourites[id] = nil
        defaults.set(favourites, forKey: favouriteKey)
    }

    mutating func clear(hiddenFor id: String) {
        hidden[id] = nil
        defaults.set(hidden, forKey: hiddenKey)
    }

    var isEmpty: Bool { favourites.isEmpty && hidden.isEmpty }

    /// Applies every unsent change over whatever the server or the cache said.
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
