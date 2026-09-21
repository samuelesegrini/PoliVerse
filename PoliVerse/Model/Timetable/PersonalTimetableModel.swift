import Foundation
import Observation
import OSLog

/// Builds the personalised timetable natively and keeps it on the phone.
///
/// The Politecnico's cart is only the calculator: the app sets the name,
/// adds each teaching, reads the "orario testuale" back, and from then on the
/// timetable is a local file. The student never sees the manifesto's pages.
@Observable
final class PersonalTimetableModel {
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

    typealias SectionChoice = PersonalTimetable.SectionChoice

    /// A teaching offered in sections, waiting for the student's choice.
    struct SectionQuestion: Sendable {
        let teaching: ManifestoTeaching
        let link: PersonalTimetableParser.SectionsLink
        let options: [PersonalTimetableParser.SectionOption]
    }

    /// Chosen sections, by teaching code.
    private(set) var sectionChoices: [String: SectionChoice] = [:]
    /// Chosen brackets, by teaching code, when not the student's own.
    private(set) var bracketChoices: [String: BracketChoice] = [:]
    /// The year of course each picked teaching is listed under.
    private(set) var yearsOfCourse: [String: String] = [:]
    /// Where the student last was in the manifesto.
    var catalogue: CatalogueSelection?
    /// Questions in the order teachings were picked; the sheet shows the first.
    private(set) var sectionQuestions: [SectionQuestion] = []
    var pendingSections: SectionQuestion? { sectionQuestions.first }

    /// The service's own cap.
    static let capacity = 15
    private static let cacheName = "personal-timetable"

    /// The cart, not the catalogue: this model only ever spoke to that half —
    /// which is what made the split obvious. See ``TimetableCart``.
    private let cart: TimetableCart
    private let agenda: (any TimetablePublishing)?
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "manifesti")

    init(cart: TimetableCart, agenda: (any TimetablePublishing)? = nil, preview: PersonalTimetable? = nil) {
        self.cart = cart
        self.agenda = agenda
        timetable = preview ?? DiskCache.load(PersonalTimetable.self, as: Self.cacheName)?.value
        selection = timetable?.sources.map(\.teaching) ?? []
        sectionChoices = timetable?.sections ?? [:]
        bracketChoices = timetable?.brackets ?? [:]
        catalogue = timetable?.catalogue
        yearsOfCourse = Dictionary(timetable?.sources.compactMap { source in source.yearOfCourse.map { (source.code, $0) } } ?? [],
                                   uniquingKeysWith: { first, _ in first })
        agenda?.personalTimetable = timetable
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

    /// A teaching picked from its plan page, which knows its year of course.
    func toggle(_ row: PlanTeaching) {
        if let year = row.yearOfCourse { yearsOfCourse[row.teaching.code] = year }
        toggle(row.teaching)
    }

    /// The student's bracket choice for a teaching; nil goes back to the one
    /// their name falls in.
    func choose(bracket: BracketChoice?, for teaching: ManifestoTeaching) {
        bracketChoices[teaching.code] = bracket
    }

    func toggle(_ teaching: ManifestoTeaching) {
        if let index = selection.firstIndex(where: { $0.code == teaching.code }) {
            selection.remove(at: index)
        } else if selection.count < Self.capacity {
            selection.append(teaching)
            // Most teachings are bracketed by name; the few offered in
            // sections ask which, and only a named session can see that —
            // before the name is set, `prepare` asks instead.
            if cart.surname != nil {
                Task { await askForSections(teaching) }
            }
        }
    }

    private func askForSections(_ teaching: ManifestoTeaching) async {
        guard sectionChoices[teaching.code] == nil, !sectionQuestions.contains(where: { $0.teaching.code == teaching.code }),
              let found = await cart.sections(for: teaching), isSelected(teaching) else { return }
        sectionQuestions.append(SectionQuestion(teaching: teaching, link: found.link, options: found.options))
    }

    func choose(_ option: PersonalTimetableParser.SectionOption?, for teaching: ManifestoTeaching,
                link: PersonalTimetableParser.SectionsLink) {
        sectionChoices[teaching.code] = option.map { SectionChoice(link: link, option: $0) }
        sectionQuestions.removeAll { $0.teaching.code == teaching.code }
    }

    /// Sets the name on the service ahead of the build, so choosing teachings
    /// can find those offered in sections.
    func prepare(name: String) async {
        await cart.setName(name)
        // Teachings kept from the last build were picked before the name was
        // set: ask about their sections now.
        for teaching in selection { await askForSections(teaching) }
    }

    // MARK: - Building

    /// Recreates the cart from the selection and reads the timetable back.
    func build(name: String, surname: String) async {
        await build(name: name, surname: surname, teachings: selection,
                    yearCode: catalogue?.year ?? cart.year.code)
    }

    /// A week: rooms move in the first weeks of term, and nothing announces it.
    static let refreshInterval: TimeInterval = 7 * 86400

    static func needsRefresh(_ timetable: PersonalTimetable, now: Date) -> Bool {
        guard timetable.retiredAt == nil, !timetable.sources.isEmpty,
              now.timeIntervalSince(timetable.builtAt) >= refreshInterval else { return false }
        // Nothing left to attend: a rebuild would only cost requests.
        return timetable.entries.contains { ($0.lessonsEnd ?? .distantFuture) >= now }
    }

    /// Rebuilds a week-old timetable quietly, from what it was built from.
    func refreshIfStale(now: Date = .now) async {
        guard let current = timetable, !isBuilding, Self.needsRefresh(current, now: now) else { return }
        // In the timetable's own year, whatever the catalogue is browsing.
        await build(name: current.name,
                    surname: current.surname ?? String(current.name.split(separator: " ").first ?? ""),
                    teachings: current.sources.map(\.teaching), yearCode: current.yearCode)
        // A timetable already in the Calendar app follows the recalculation.
        if progress == .finished, CalendarExporter.canSyncQuietly, let updated = timetable {
            _ = await CalendarExporter.sync(CalendarExport.drafts(for: updated))
        }
        // Quiet: a failed background refresh keeps the timetable it had and
        // does not leave an error on the builder.
        if case .failed = progress { progress = .idle }
        if progress == .finished { progress = .idle }
    }

    private func build(name: String, surname: String, teachings: [ManifestoTeaching], yearCode: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !teachings.isEmpty, !isBuilding else { return }
        refused = []

        progress = .settingName
        // Cleared first: the cart outlives the app on the server's session,
        // and a leftover teaching would reappear in the result.
        await cart.clearTimetable(yearCode: yearCode)

        let batches = CartBatches.batches(name: trimmed, surname: surname, teachings: teachings, brackets: bracketChoices)
        var added = 0
        var done = 0
        var readAny = false
        var entries: [PersonalTimetable.Entry] = []
        for batch in batches {
            guard !Task.isCancelled else { break }
            // Setting the name empties the cart: each bracket is its own run.
            await cart.setName(batch.cartName, yearCode: yearCode)
            var addedHere = 0
            // One at a time: the service serialises a session's requests
            // anyway, and the cart's count is only meaningful in order.
            for teaching in batch.teachings {
                guard !Task.isCancelled else { break }
                progress = .adding(done: done, total: teachings.count)
                done += 1
                let reply = await add(teaching)
                log.notice("personal timetable: \(teaching.code, privacy: .public) into cart \(batch.cartName == trimmed ? "own" : batch.cartName, privacy: .public): \(String(describing: reply), privacy: .public)")
                switch reply {
                case .added: addedHere += 1
                case .refused(let reason): refused.append((teaching, reason))
                }
            }
            guard addedHere > 0, !Task.isCancelled else { continue }
            added += addedHere

            progress = .reading
            for semester in [1, 2] {
                guard let html = await cart.textTimetable(semester: semester, yearCode: yearCode) else { continue }
                readAny = true
                for entry in PersonalTimetableParser.entries(html) where !entries.contains(where: { $0.code == entry.code }) {
                    entries.append(entry)
                }
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
        guard readAny else {
            progress = .failed(String(localized: "Il Politecnico non ha risposto. Riprova tra poco."))
            return
        }
        // The name the student gave, whatever the carts were named.
        if batches.first?.cartName != trimmed { await cart.setName(trimmed, yearCode: yearCode) }

        var built = PersonalTimetable(name: trimmed, yearCode: yearCode, entries: entries, builtAt: .now)
        built.sources = teachings.map { PersonalTimetable.Source($0, yearOfCourse: yearsOfCourse[$0.code]) }
        built.brackets = bracketChoices.filter { code, _ in teachings.contains { $0.code == code } }
        built.catalogue = catalogue
        built.surname = surname
        built.sections = sectionChoices.filter { code, _ in teachings.contains { $0.code == code } }
        // A rebuild keeps what the student decided about each teaching.
        built.hiddenCodes = timetable?.hiddenCodes.intersection(entries.map(\.code)) ?? []
        save(built)
        log.notice("personal timetable: \(added, privacy: .public) added, \(entries.count, privacy: .public) read, \(entries.reduce(0) { $0 + $1.slots.count }, privacy: .public) slots")
        progress = .finished
    }

    /// One teaching into the cart: its chosen section, else the row's own
    /// link when it came from a plan page, else the link on its detail page.
    private func add(_ teaching: ManifestoTeaching) async -> PersonalTimetableParser.CartReply {
        if let choice = sectionChoices[teaching.code] {
            let link = PersonalTimetableParser.CartLink(
                courseCode: choice.link.courseCode, planCode: choice.link.planCode,
                semester: choice.option.semester, yearOfCourse: choice.link.yearOfCourse)
            return await cart.addToTimetable(teaching, link: link, section: choice.option.name)
        }
        if let year = yearsOfCourse[teaching.code] {
            let link = PersonalTimetableParser.CartLink(courseCode: teaching.courseCode, planCode: teaching.planCode ?? "",
                                                        semester: teaching.semester ?? "", yearOfCourse: year)
            return await cart.addToTimetable(teaching, link: link)
        }
        return await cart.addToTimetable(teaching, link: await cart.cartLink(for: teaching))
    }

    func resetProgress() {
        if !isBuilding { progress = .idle }
    }

    // MARK: - Decisions

    func setHidden(_ hidden: Bool, code: String) {
        guard var current = timetable else { return }
        if hidden { current.hiddenCodes.insert(code) } else { current.hiddenCodes.remove(code) }
        save(current)
        // A hidden teaching leaves the synced calendar as well.
        if CalendarExporter.canSyncQuietly {
            Task { _ = await CalendarExporter.sync(CalendarExport.drafts(for: current)) }
        }
    }

    /// Hands over to the official agenda, keeping the file in case it is
    /// needed again.
    func retire(_ retired: Bool) {
        guard var current = timetable else { return }
        // Archived for the official agenda: its lessons leave the calendar too.
        if retired { CalendarExporter.remove() }
        current.retiredAt = retired ? .now : nil
        save(current)
    }

    func delete() {
        CalendarExporter.remove()
        timetable = nil
        agenda?.personalTimetable = nil
        selection = []
        bracketChoices = [:]
        yearsOfCourse = [:]
        progress = .idle
        // An empty entry, which no longer decodes as a timetable.
        DiskCache.save(Optional<PersonalTimetable>.none, as: Self.cacheName)
    }

    private func save(_ value: PersonalTimetable) {
        timetable = value
        agenda?.personalTimetable = value
        DiskCache.save(value, as: Self.cacheName)
    }
}
