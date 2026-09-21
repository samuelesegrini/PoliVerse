import Foundation

/// What changed in a version of PoliVerse, in the student's words.
///
/// ## Editing this before a release
///
/// ``ReleaseNotes/all`` is the list, newest first. Before shipping, add one
/// `ReleaseNote` whose `version` is exactly the `CFBundleShortVersionString`
/// of the build going out — the two are matched by string, so "2.1" here and
/// "2.1" in the target's settings, not "2.1.0".
///
/// Keep it to three or four items. This screen is shown once per update, in
/// front of someone who opened the app to check a room, and a list of fifteen
/// bullet points is a list nobody reads. Say what the student can now *do*,
/// not what was refactored.
///
/// Nothing else needs touching: the app works out who has seen what, and a
/// version with no note here simply shows nothing.
nonisolated struct ReleaseNote: Identifiable, Equatable, Sendable {
    /// Matched against `CFBundleShortVersionString`, exactly.
    let version: String
    /// One line above the items, saying what the release is about.
    let headline: LocalizedStringResource
    let items: [Item]

    var id: String { version }

    nonisolated struct Item: Identifiable, Equatable, Sendable {
        let symbol: String
        let title: LocalizedStringResource
        let detail: LocalizedStringResource

        var id: String { symbol + String(localized: title) }

        init(symbol: String, title: LocalizedStringResource, detail: LocalizedStringResource) {
            self.symbol = symbol
            self.title = title
            self.detail = detail
        }
    }

    init(version: String, headline: LocalizedStringResource, items: [Item]) {
        self.version = version
        self.headline = headline
        self.items = items
    }
}

nonisolated enum ReleaseNotes {
    /// The notes, newest first. **This is the list to edit before a release.**
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

    /// The note for one version, if there is one.
    static func note(for version: String) -> ReleaseNote? {
        all.first { $0.version == version }
    }

    /// What to show someone opening `current` who last saw `lastSeen`.
    ///
    /// - `lastSeen` nil means the app has been used before this screen existed:
    ///   there is no history to replay, so it shows the release they have just
    ///   landed on and nothing older.
    /// - Otherwise every note between the two, newest first — a student who
    ///   skipped two updates is told about both.
    /// - A version with no note shows nothing, which is how a bug-fix release
    ///   ships without a screen.
    static func unseen(since lastSeen: String?, upTo current: String) -> [ReleaseNote] {
        unseen(in: all, since: lastSeen, upTo: current)
    }

    /// The same, over a given list — how the rule is tested without the tests
    /// depending on what happens to be written for the next release.
    static func unseen(in notes: [ReleaseNote], since lastSeen: String?, upTo current: String) -> [ReleaseNote] {
        guard let lastSeen else {
            return notes.filter { $0.version == current }
        }
        guard isOlder(lastSeen, than: current) else { return [] }
        return notes.filter { isOlder(lastSeen, than: $0.version) && !isOlder(current, than: $0.version) }
    }

    /// Version strings compared component by component, numerically.
    ///
    /// "2.10" is after "2.9", which a string comparison gets backwards, and a
    /// missing component counts as zero so "2" and "2.0" are the same release.
    static func isOlder(_ lhs: String, than rhs: String) -> Bool {
        let left = components(lhs), right = components(rhs)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}
