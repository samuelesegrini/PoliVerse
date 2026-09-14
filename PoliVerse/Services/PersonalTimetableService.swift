import Foundation
import Observation
import OSLog

/// Builds the personalised timetable natively and keeps it on the phone.
///
/// The Politecnico's cart is only the calculator: the app sets the name,
/// adds each teaching, reads the "orario testuale" back, and from then on the
/// timetable is a local file. The student never sees the manifesto's pages.
@Observable
final class PersonalTimetableService {
    enum Progress: Equatable {
        case idle
        case settingName
        case adding(done: Int, total: Int)
        case reading
        case finished
        case failed(String)
    }

    private(set) var timetable: PersonalTimetable?
    /// Teachings chosen for the next build, in the order they were picked.
    private(set) var selection: [ManifestoTeaching] = []
    private(set) var progress: Progress = .idle
    /// Teachings the service refused, with its reason when it gave one.
    private(set) var refused: [(teaching: ManifestoTeaching, reason: String?)] = []

    /// The service's own cap.
    static let capacity = 15
    private static let cacheName = "personal-timetable"

    private let manifesti: ManifestiService
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "manifesti")

    init(manifesti: ManifestiService, preview: PersonalTimetable? = nil) {
        self.manifesti = manifesti
        timetable = preview ?? DiskCache.load(PersonalTimetable.self, as: Self.cacheName)?.value
        selection = timetable?.sources.map(\.teaching) ?? []
    }

    var isBuilding: Bool {
        switch progress {
        case .settingName, .adding, .reading: true
        default: false
        }
    }

    // MARK: - Selection

    func isSelected(_ teaching: ManifestoTeaching) -> Bool {
        selection.contains { $0.code == teaching.code }
    }

    func toggle(_ teaching: ManifestoTeaching) {
        if let index = selection.firstIndex(where: { $0.code == teaching.code }) {
            selection.remove(at: index)
        } else if selection.count < Self.capacity {
            selection.append(teaching)
        }
    }

    // MARK: - Building

    /// Recreates the cart from the selection and reads the timetable back.
    func build(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !selection.isEmpty, !isBuilding else { return }
        refused = []
        let teachings = selection

        progress = .settingName
        // Cleared first: the cart outlives the app on the server's session,
        // and a leftover teaching would reappear in the result.
        await manifesti.clearTimetable()
        await manifesti.setName(trimmed)

        // One at a time: the service serialises a session's requests anyway,
        // and the cart's count is only meaningful in order.
        var added = 0
        for (index, teaching) in teachings.enumerated() {
            guard !Task.isCancelled else { break }
            progress = .adding(done: index, total: teachings.count)
            let link = await manifesti.cartLink(for: teaching)
            switch await manifesti.addToTimetable(teaching, link: link) {
            case .added: added += 1
            case .refused(let reason): refused.append((teaching, reason))
            }
        }
        // Closed mid-build: a timetable missing the rest would pass for complete.
        guard !Task.isCancelled else {
            progress = .idle
            return
        }
        guard added > 0 else {
            progress = .failed(String(localized: "Il Politecnico non ha accettato nessun insegnamento."))
            return
        }

        progress = .reading
        var entries: [PersonalTimetable.Entry] = []
        var readAny = false
        for semester in [1, 2] {
            guard let html = await manifesti.textTimetable(semester: semester) else { continue }
            readAny = true
            for entry in PersonalTimetableParser.entries(html) where !entries.contains(where: { $0.code == entry.code }) {
                entries.append(entry)
            }
        }
        guard readAny else {
            progress = .failed(String(localized: "Il Politecnico non ha risposto. Riprova tra poco."))
            return
        }

        var built = PersonalTimetable(name: trimmed, yearCode: manifesti.year.code, entries: entries, builtAt: .now)
        built.sources = teachings.map(PersonalTimetable.Source.init)
        // A rebuild keeps what the student decided about each teaching.
        built.hiddenCodes = timetable?.hiddenCodes.intersection(entries.map(\.code)) ?? []
        save(built)
        log.notice("personal timetable: \(added, privacy: .public) added, \(entries.count, privacy: .public) read, \(entries.reduce(0) { $0 + $1.slots.count }, privacy: .public) slots")
        progress = .finished
    }

    func resetProgress() {
        if !isBuilding { progress = .idle }
    }

    // MARK: - Decisions

    func setHidden(_ hidden: Bool, code: String) {
        guard var current = timetable else { return }
        if hidden { current.hiddenCodes.insert(code) } else { current.hiddenCodes.remove(code) }
        save(current)
    }

    /// Hands over to the official agenda, keeping the file in case it is
    /// needed again.
    func retire(_ retired: Bool) {
        guard var current = timetable else { return }
        current.retiredAt = retired ? .now : nil
        save(current)
    }

    func delete() {
        timetable = nil
        selection = []
        progress = .idle
        // An empty entry, which no longer decodes as a timetable.
        DiskCache.save(Optional<PersonalTimetable>.none, as: Self.cacheName)
    }

    private func save(_ value: PersonalTimetable) {
        timetable = value
        DiskCache.save(value, as: Self.cacheName)
    }
}
