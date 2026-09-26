import Foundation

/// The site the student studies at — "Milano Bovisa", "Como" — chosen in the
/// journey or in Impostazioni.
///
/// What Aule libere opens on. Kept in the defaults rather than per account: a
/// site is where someone is, not something their career says.
///
/// A site, not a campus: the service names campuses by address, and a student
/// says "Bovisa", not "Via Durando". Aule libere asks per address, so the site
/// is turned into its biggest address when it is opened.
nonisolated enum FavouriteCampus {
    /// The defaults key the site is stored under.
    static let storageKey = "favouriteCampus"

    /// The campus to show for a favourite site.
    ///
    /// - Parameters:
    ///   - favourite: The stored favourite, if any: a site, or a campus stored before
    ///     sites were offered.
    ///   - campuses: The campuses the catalogue knows.
    ///   - mainCampus: The campus of a site with the most rooms, `nil` for an unknown site.
    /// - Returns: The campus to show, or `nil` when there are none.
    static func resolve(_ favourite: String?, among campuses: [String],
                        mainCampus: (String) -> String? = { _ in nil }) -> String? {
        if let favourite {
            if let campus = mainCampus(favourite) { return campus }
            if campuses.contains(favourite) { return favourite }
        }
        return campuses.first
    }

    /// The stored favourite.
    static var stored: String? {
        let value = UserDefaults.standard.string(forKey: storageKey)
        return value?.isEmpty == false ? value : nil
    }
}
