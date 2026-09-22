import Foundation

/// What changed in one version of PoliVerse, in the student's words.
nonisolated struct ReleaseNote: Identifiable, Equatable, Sendable {
    /// Matched against `CFBundleShortVersionString`, exactly — `"2.1"` rather than
    /// `"2.1.0"`.
    let version: String
    /// One line above the items, saying what the release is about.
    let headline: LocalizedStringResource
    /// What the student can now do. Three or four; see ``ReleaseNotes/all``.
    let items: [Item]

    /// ``version``.
    var id: String { version }

    /// One thing a release brought.
    nonisolated struct Item: Identifiable, Equatable, Sendable {
        /// The SF Symbol shown beside it.
        let symbol: String
        /// What it is, in a few words.
        let title: LocalizedStringResource
        /// What the student can do with it.
        let detail: LocalizedStringResource

        /// The symbol and the title together.
        var id: String { symbol + String(localized: title) }

        /// Creates an item.
        ///
        /// - Parameters:
        ///   - symbol: The SF Symbol to show.
        ///   - title: What it is.
        ///   - detail: What the student can do with it.
        init(symbol: String, title: LocalizedStringResource, detail: LocalizedStringResource) {
            self.symbol = symbol
            self.title = title
            self.detail = detail
        }
    }

    /// Creates a release note.
    ///
    /// - Parameters:
    ///   - version: The build's `CFBundleShortVersionString`, exactly.
    ///   - headline: What the release is about.
    ///   - items: What it brought.
    init(version: String, headline: LocalizedStringResource, items: [Item]) {
        self.version = version
        self.headline = headline
        self.items = items
    }
}

/// The release notes, and the rules for deciding which the student has not seen.
///
/// ## Adding a note
///
/// ``all`` is the list, newest first. Add one ``ReleaseNote`` whose ``ReleaseNote/version``
/// is exactly the `CFBundleShortVersionString` of the build going out; the two are
/// matched by string.
///
/// Three or four items. The screen is shown once per update, in front of someone who
/// opened the app to check a room, so it says what the student can now do rather than
/// what changed internally.
///
/// Nothing else needs touching: ``WhatsNewState`` works out who has seen what, and a
/// version with no note here shows nothing.
nonisolated enum ReleaseNotes {
    /// The notes, newest first. This is the list to edit before a release.
    static let all: [ReleaseNote] = [
        ReleaseNote(
            version: "2.0",
            headline: "Il Politecnico come lo vuoi tu.",
            items: [
                .init(symbol: "paintbrush.fill",
                      title: "Personalizza, su tutta l'app",
                      detail: "Il colore, il carattere e il materiale che scegli per Oggi valgono adesso in ogni schermata: carriera, corsi, ricerca e impostazioni comprese."),
                .init(symbol: "calendar.badge.plus",
                      title: "Orario personalizzato",
                      detail: "Scegli gli insegnamenti che segui e l'app ne ricava l'orario della settimana, con aule e indirizzi, prima che il piano arrivi in agenda."),
                .init(symbol: "book.closed.fill",
                      title: "Il piano giusto",
                      detail: "Corso di studi e PSPA si leggono dal Manifesto anche quando il piano non è un menu, così schede e docenti sono i tuoi."),
            ]),
    ]

    /// The note for one version.
    ///
    /// - Parameter version: The `CFBundleShortVersionString` to look for.
    /// - Returns: The note, or `nil` when that version has none.
    static func note(for version: String) -> ReleaseNote? {
        all.first { $0.version == version }
    }

    /// The notes to show someone opening `current` who last saw `lastSeen`.
    ///
    /// - Parameters:
    ///   - lastSeen: The version whose notes were last read, or `nil` when the app has been
    ///     used before this screen existed — in which case only the release just landed on is
    ///     shown, since there is no history to replay.
    ///   - current: The version now running.
    /// - Returns: Every note between the two, newest first, so a student who skipped two
    ///   updates is told about both. Empty when the version has no note, which is how a
    ///   bug-fix release ships without a screen.
    static func unseen(since lastSeen: String?, upTo current: String) -> [ReleaseNote] {
        unseen(in: all, since: lastSeen, upTo: current)
    }

    /// The same rule over a given list, so it can be tested without depending on what
    /// happens to be written for the next release.
    ///
    /// - Parameters:
    ///   - notes: The notes to choose from, newest first.
    ///   - lastSeen: The version whose notes were last read, or `nil`.
    ///   - current: The version now running.
    /// - Returns: The notes to show.
    static func unseen(in notes: [ReleaseNote], since lastSeen: String?, upTo current: String) -> [ReleaseNote] {
        guard let lastSeen else {
            return notes.filter { $0.version == current }
        }
        guard isOlder(lastSeen, than: current) else { return [] }
        return notes.filter { isOlder(lastSeen, than: $0.version) && !isOlder(current, than: $0.version) }
    }

    /// Compares two version strings component by component, numerically.
    ///
    /// `"2.10"` comes after `"2.9"`, which a string comparison gets backwards, and a missing
    /// component counts as zero so `"2"` and `"2.0"` are the same release.
    ///
    /// - Parameters:
    ///   - lhs: The first version.
    ///   - rhs: The second.
    /// - Returns: `true` when the first precedes the second.
    static func isOlder(_ lhs: String, than rhs: String) -> Bool {
        let left = components(lhs), right = components(rhs)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b }
        }
        return false
    }

    /// A version string as its numeric components. Non-digits within a component are
    /// ignored.
    ///
    /// - Parameter version: The version string.
    /// - Returns: The components, in order.
    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}
