import Foundation

/// The campus the student goes to, chosen in the journey or in Impostazioni.
///
/// What Aule libere opens on. Kept in the defaults rather than per account: a
/// campus is where someone is, not something their career says.
nonisolated enum FavouriteCampus {
    /// The defaults key the campus is stored under.
    static let storageKey = "favouriteCampus"

    /// The campus to show among the ones a catalogue knows: the favourite when
    /// it is one of them, otherwise the first.
    ///
    /// - Parameters:
    ///   - favourite: The stored favourite, if any.
    ///   - campuses: The campuses the catalogue knows.
    /// - Returns: The campus to show, or `nil` when there are none.
    static func resolve(_ favourite: String?, among campuses: [String]) -> String? {
        if let favourite, campuses.contains(favourite) { return favourite }
        return campuses.first
    }

    /// The stored favourite.
    static var stored: String? {
        let value = UserDefaults.standard.string(forKey: storageKey)
        return value?.isEmpty == false ? value : nil
    }
}
