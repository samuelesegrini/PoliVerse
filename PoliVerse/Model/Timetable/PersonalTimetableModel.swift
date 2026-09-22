import Foundation
import Observation
import OSLog

/// Builds the personalised timetable and keeps it on the device.
///
/// The Politecnico's cart is used only as a calculator: the app sets a name on the
/// session, adds each chosen teaching, reads the orario testuale back, and from then
/// on the timetable is a local file. The student never sees the service's own pages.
///
/// ## Building
///
/// ``build(name:surname:)`` recreates the cart from ``selection`` and reads the
/// result. Because setting a name empties the cart, teachings whose alphabetical
/// bracket differs from the student's are added in separate runs — see
/// ``CartBatches`` — and the entries from each run are merged.
///
/// ## Sections
///
/// Most teachings are bracketed by surname, but some are offered in sections the
/// student picks. Those raise a ``SectionQuestion``, which the builder answers
/// through ``choose(_:for:link:)``.
///
/// ## Refreshing
///
/// ``refreshIfStale(now:)`` rebuilds quietly once a timetable is a week old, since
/// rooms move in the first weeks of term and nothing announces it.
@Observable
final class PersonalTimetableModel {
    /// How far a build has got.
    enum Progress: Equatable {
        /// No build is running, and none has just finished.
        case idle
        /// Setting the name on the service and clearing the cart.
        case settingName
        /// Adding teachings, with how many of how many have been attempted.
        case adding(done: Int, total: Int)
        /// Reading the orario testuale back.
        case reading
        /// The build produced a timetable.
        case finished
        /// The build produced nothing, with a sentence explaining why.
        case failed(String)
    }

    /// The built timetable, restored from disk at init. `nil` when none has been built.
    private(set) var timetable: PersonalTimetable?
    /// Teachings chosen for the next build, in the order they were picked. Capped at
    /// ``capacity``.
    private(set) var selection: [ManifestoTeaching] = []
    /// How far the current or last build got.
    private(set) var progress: Progress = .idle
    /// Teachings the service refused during the last build, with its reason where it gave
    /// one.
    private(set) var refused: [(teaching: ManifestoTeaching, reason: String?)] = []

    /// A section the student picked, with the link it was picked through.
    typealias SectionChoice = PersonalTimetable.SectionChoice

    /// A teaching offered in sections, waiting for the student's choice.
    struct SectionQuestion: Sendable {
        /// The teaching being asked about.
        let teaching: ManifestoTeaching
        /// The link its sections were listed from.
        let link: PersonalTimetableParser.SectionsLink
        /// The sections on offer.
        let options: [PersonalTimetableParser.SectionOption]
    }

    /// Sections chosen so far, by teaching code.
    private(set) var sectionChoices: [String: SectionChoice] = [:]
    /// Alphabetical brackets chosen so far, by teaching code, where not the student's own.
    private(set) var bracketChoices: [String: BracketChoice] = [:]
    /// The year of course each picked teaching is listed under, by teaching code. Known
    /// only for teachings picked from a plan page.
    private(set) var yearsOfCourse: [String: String] = [:]
    /// Where the student last was in the manifesto, so the picker reopens there.
    var catalogue: CatalogueSelection?
    /// Outstanding section questions, in the order the teachings were picked.
    private(set) var sectionQuestions: [SectionQuestion] = []
    /// The question the sheet should ask, or `nil` when there is none.
    var pendingSections: SectionQuestion? { sectionQuestions.first }

    /// The service's own cap on how many teachings a cart may hold.
    static let capacity = 15
    /// The ``DiskCache`` record the timetable is stored under.
    private static let cacheName = "personal-timetable"

    /// The cart half of the timetable service: naming, adding and reading back. The
    /// catalogue half is ``ManifestiModel``'s.
    private let cart: TimetableCart
    /// Where a built timetable is published, so the agenda merges its lessons.
    private let agenda: (any TimetablePublishing)?
    /// Diagnostic log for this type, under the `manifesti` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "manifesti")

    /// Restores the stored timetable and everything derived from it, then publishes it to
    /// the agenda.
    ///
    /// - Parameters:
    ///   - cart: The cart half of the timetable service.
    ///   - agenda: Where a built timetable is published.
    ///   - preview: A timetable to use instead of the stored one, for previews.
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

    /// `true` while a build is running.
    var isBuilding: Bool {
        switch progress {
        case .settingName, .adding, .reading: true
        default: false
        }
    }

    // MARK: - Selection

    /// Whether a teaching is in ``selection``.
    ///
    /// - Parameter teaching: The teaching to check.
    /// - Returns: `true` when it is chosen, matched by code.
    func isSelected(_ teaching: ManifestoTeaching) -> Bool {
        selection.contains { $0.code == teaching.code }
    }

    /// Adds or removes a teaching picked from a plan page, recording the year of course
    /// the page lists it under.
    ///
    /// - Parameter row: The plan row that was tapped.
    func toggle(_ row: PlanTeaching) {
        if let year = row.yearOfCourse { yearsOfCourse[row.teaching.code] = year }
        toggle(row.teaching)
    }

    /// Records the bracket to add a teaching under.
    ///
    /// - Parameters:
    ///   - bracket: The bracket to use, or `nil` to use the one the student's surname
    ///     falls in.
    ///   - teaching: The teaching it applies to.
    func choose(bracket: BracketChoice?, for teaching: ManifestoTeaching) {
        bracketChoices[teaching.code] = bracket
    }

    /// Adds or removes a teaching from ``selection``.
    ///
    /// Adding is refused once ``capacity`` is reached. A newly added teaching is checked
    /// for sections, which only a named session can see — before the name is set,
    /// ``prepare(name:)`` asks instead.
    ///
    /// - Parameter teaching: The teaching that was tapped.
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

    /// Raises a ``SectionQuestion`` when a teaching is offered in sections.
    ///
    /// Does nothing when a section is already chosen, a question is already outstanding,
    /// the teaching is not offered in sections, or it has been deselected while the
    /// service was being asked.
    ///
    /// - Parameter teaching: The teaching to check.
    private func askForSections(_ teaching: ManifestoTeaching) async {
        guard sectionChoices[teaching.code] == nil, !sectionQuestions.contains(where: { $0.teaching.code == teaching.code }),
              let found = await cart.sections(for: teaching), isSelected(teaching) else { return }
        sectionQuestions.append(SectionQuestion(teaching: teaching, link: found.link, options: found.options))
    }

    /// Answers a section question and clears it.
    ///
    /// - Parameters:
    ///   - option: The section chosen, or `nil` to leave the teaching unsectioned.
    ///   - teaching: The teaching it applies to.
    ///   - link: The link the sections were listed from.
    func choose(_ option: PersonalTimetableParser.SectionOption?, for teaching: ManifestoTeaching,
                link: PersonalTimetableParser.SectionsLink) {
        sectionChoices[teaching.code] = option.map { SectionChoice(link: link, option: $0) }
        sectionQuestions.removeAll { $0.teaching.code == teaching.code }
    }

    /// Sets the name on the service ahead of a build, then asks about the sections of
    /// every already-chosen teaching.
    ///
    /// Teachings kept from a previous build were picked before a name was set, so their
    /// sections can only be discovered now.
    ///
    /// - Parameter name: The name to set on the session.
    func prepare(name: String) async {
        await cart.setName(name)
        // Teachings kept from the last build were picked before the name was
        // set: ask about their sections now.
        for teaching in selection { await askForSections(teaching) }
    }

    // MARK: - Building

    /// Builds the timetable from ``selection``, in the catalogue's year or the cart's.
    ///
    /// - Parameters:
    ///   - name: The name to set on the service, and the timetable's own name.
    ///   - surname: The surname the alphabetical brackets are resolved against.
    func build(name: String, surname: String) async {
        await build(name: name, surname: surname, teachings: selection,
                    yearCode: catalogue?.year ?? cart.year.code)
    }

    /// How old a timetable may get before ``refreshIfStale(now:)`` rebuilds it: a week,
    /// because rooms move in the first weeks of term and nothing announces it.
    static let refreshInterval: TimeInterval = 7 * 86400

    /// Whether a timetable is worth rebuilding.
    ///
    /// - Parameters:
    ///   - timetable: The timetable to judge.
    ///   - now: The moment to measure against.
    /// - Returns: `true` only for a live timetable, older than ``refreshInterval``, that
    ///   knows what it was built from and still has lessons to come.
    static func needsRefresh(_ timetable: PersonalTimetable, now: Date) -> Bool {
        guard timetable.retiredAt == nil, !timetable.sources.isEmpty,
              now.timeIntervalSince(timetable.builtAt) >= refreshInterval else { return false }
        // Nothing left to attend: a rebuild would only cost requests.
        return timetable.entries.contains { ($0.lessonsEnd ?? .distantFuture) >= now }
    }

    /// Rebuilds a week-old timetable quietly, from what it was built from.
    ///
    /// Runs in the timetable's own academic year, whatever the catalogue is browsing. A
    /// timetable already synced to the Calendar app follows the rebuild. The outcome is
    /// not left on ``progress``: a background rebuild that fails keeps the timetable it
    /// had and reports nothing to the builder.
    ///
    /// - Parameter now: The moment to measure staleness against.
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

    /// Recreates the cart from a set of teachings and reads the timetable back.
    ///
    /// The cart is cleared first, since it outlives the app on the server's session and a
    /// leftover teaching would reappear in the result. Teachings are then added in
    /// ``CartBatches`` runs — one per bracket, because setting a name empties the cart —
    /// one at a time within a run, and both semesters' pages are read after each run that
    /// added anything.
    ///
    /// Cancellation mid-build leaves ``progress`` at ``Progress/idle`` and saves nothing,
    /// so a partial timetable cannot pass for a complete one. A build that adds nothing,
    /// or that the service never answers, ends in ``Progress/failed(_:)``.
    ///
    /// A successful build keeps the hidden teachings that still exist, and records the
    /// sources, brackets, sections, catalogue position and surname needed to rebuild.
    ///
    /// - Parameters:
    ///   - name: The name to set, and the timetable's own name.
    ///   - surname: The surname the brackets are resolved against.
    ///   - teachings: What to add.
    ///   - yearCode: The academic year to build in.
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

    /// Adds one teaching to the cart.
    ///
    /// Uses the chosen section's link where there is one, then the plan page's own year of
    /// course, and otherwise the link on the teaching's detail page.
    ///
    /// - Parameter teaching: The teaching to add.
    /// - Returns: What the cart answered.
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

    /// Returns ``progress`` to ``Progress/idle`` once a build is over, so a finished or
    /// failed build stops being reported.
    func resetProgress() {
        if !isBuilding { progress = .idle }
    }

    // MARK: - Decisions

    /// Hides or reveals one teaching, and follows the change into a synced calendar.
    ///
    /// - Parameters:
    ///   - hidden: Whether to hide it.
    ///   - code: The teaching code.
    func setHidden(_ hidden: Bool, code: String) {
        guard var current = timetable else { return }
        if hidden { current.hiddenCodes.insert(code) } else { current.hiddenCodes.remove(code) }
        save(current)
        // A hidden teaching leaves the synced calendar as well.
        if CalendarExporter.canSyncQuietly {
            Task { _ = await CalendarExporter.sync(CalendarExport.drafts(for: current)) }
        }
    }

    /// Hands over to the official agenda, or takes the timetable back.
    ///
    /// The file is kept either way. Retiring removes the timetable's lessons from the
    /// synced calendar as well.
    ///
    /// - Parameter retired: `true` to hand over, `false` to resume.
    func retire(_ retired: Bool) {
        guard var current = timetable else { return }
        // Archived for the official agenda: its lessons leave the calendar too.
        if retired { CalendarExporter.remove() }
        current.retiredAt = retired ? .now : nil
        save(current)
    }

    /// Discards the timetable, its selection and its stored file, and removes its lessons
    /// from the synced calendar.
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

    /// Stores a timetable, publishes it to the agenda and writes it to disk.
    ///
    /// - Parameter value: The timetable to keep.
    private func save(_ value: PersonalTimetable) {
        timetable = value
        agenda?.personalTimetable = value
        DiskCache.save(value, as: Self.cacheName)
    }
}
