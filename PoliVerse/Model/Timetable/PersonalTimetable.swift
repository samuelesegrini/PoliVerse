import Foundation

/// A personalised timetable, built from the Politecnico's orario testuale and then
/// kept on the device.
///
/// Independent of the service once built: that service's cart lives on a cookie that
/// expires, so a timetable tied to it would disappear with the session. ``sources``,
/// ``sections``, ``brackets`` and ``catalogue`` record enough to rebuild it — rooms
/// change in the first weeks of term — without searching again.
///
/// ``lessons(in:)`` expands the weekly slots into dated lessons, and ``TimetableMerge``
/// folds them into the official agenda until ``TimetableHandover`` confirms the
/// agenda has taken over.
nonisolated struct PersonalTimetable: Codable, Sendable, Equatable {
    /// What the student called this timetable.
    var name: String
    /// The academic year it was built for, as the manifesto codes it.
    var yearCode: String
    /// The teachings in it, hidden ones included.
    var entries: [Entry]
    /// When it was last built or rebuilt.
    var builtAt: Date
    /// Teachings the student chose not to see, because the official agenda already has
    /// them or they were added only to look.
    var hiddenCodes: Set<String> = []
    /// When the student retired this timetable in favour of the official agenda, or `nil`
    /// while it is still in use. A retired timetable is not merged into the agenda.
    var retiredAt: Date?
    /// The catalogue rows it was built from, so it can be rebuilt without searching.
    var sources: [Source] = []
    /// Sections chosen for teachings offered in sections, by teaching code, so a rebuild
    /// keeps them.
    var sections: [String: SectionChoice] = [:]
    /// Alphabetical brackets chosen for teachings, by code, where not the student's own.
    var brackets: [String: BracketChoice] = [:]
    /// Where in the manifesto the teachings were picked, so the picker can reopen there.
    var catalogue: CatalogueSelection?
    /// The surname the brackets were resolved against, for deciding which chosen brackets
    /// are the student's own. Absent in timetables built before it was recorded.
    var surname: String?

    /// A section the student picked, with the link it was picked through.
    struct SectionChoice: Sendable, Equatable, Codable {
        /// The link the sections were listed from.
        let link: PersonalTimetableParser.SectionsLink
        /// The section chosen.
        let option: PersonalTimetableParser.SectionOption
    }

    /// A ``ManifestoTeaching`` in the shape this timetable stores it, so a rebuild needs
    /// no catalogue search.
    struct Source: Codable, Sendable, Hashable, Identifiable {
        /// The degree course, the teaching and the plan together, which identify the row.
        var id: String { "\(courseCode)-\(code)-\(planCode ?? "")" }
        /// The six-digit teaching code.
        let code: String
        /// The teaching's name.
        let name: String
        /// The degree course the teaching is offered under.
        let courseCode: String
        /// The study plan within that degree course.
        let planCode: String?
        /// The offering's identifier, which the sections picker needs.
        let idItemOfferta: String?
        /// The catalogue row's identifier.
        let idRiga: String?
        /// The semester the teaching runs in.
        let semester: String?
        /// The academic year of the offering.
        let year: String?
        /// The degree course's name, as the catalogue spells it.
        let degreeCourse: String?
        /// The year of course the plan lists the teaching under, which the cart needs.
        var yearOfCourse: String?

        /// Captures a catalogue teaching for storage.
        ///
        /// - Parameters:
        ///   - teaching: The catalogue row.
        ///   - yearOfCourse: The year of course the plan lists it under.
        init(_ teaching: ManifestoTeaching, yearOfCourse: String? = nil) {
            code = teaching.code; name = teaching.name; courseCode = teaching.courseCode
            planCode = teaching.planCode; idItemOfferta = teaching.idItemOfferta; idRiga = teaching.idRiga
            semester = teaching.semester; year = teaching.year; degreeCourse = teaching.degreeCourse
            self.yearOfCourse = yearOfCourse
        }

        /// The stored row back as a ``ManifestoTeaching``. Credits and school are not stored
        /// and come back `nil`.
        var teaching: ManifestoTeaching {
            ManifestoTeaching(code: code, name: name, courseCode: courseCode, planCode: planCode,
                              idItemOfferta: idItemOfferta, idRiga: idRiga, semester: semester, year: year,
                              credits: nil, school: nil, degreeCourse: degreeCourse)
        }
    }

    /// One teaching in the timetable, with its weekly slots.
    struct Entry: Codable, Sendable, Hashable, Identifiable {
        /// The teaching code.
        var id: String { code }
        /// The six-digit teaching code.
        let code: String
        /// The teaching's name, as the orario testuale prints it.
        let title: String
        /// The lecturer, where the page names one.
        let teacher: String?
        /// The semester, 1 or 2, where the page says.
        let semester: Int?
        /// The first day of lessons, which bounds ``PersonalTimetable/lessons(in:)``.
        let lessonsStart: Date?
        /// The last day of lessons.
        let lessonsEnd: Date?
        /// The weekly slots this teaching occupies.
        let slots: [Slot]
    }

    /// One weekly slot: a weekday, a span of minutes, and where it is held.
    struct Slot: Codable, Sendable, Hashable {
        /// The weekday in `Calendar` numbering: 1 is Sunday, 2 Monday.
        let weekday: Int
        /// Minutes from midnight at which the slot starts.
        let startMinutes: Int
        /// Minutes from midnight at which it ends.
        let endMinutes: Int
        /// The room's name, where the page links one.
        let room: String?
        /// The room's `idaula`, the key the room services take.
        let roomID: String?
        /// The building's address, where the page gives one.
        let address: String?

        /// Whether two slots fall on the same weekday at overlapping times.
        ///
        /// - Parameter other: The slot to compare against.
        /// - Returns: `true` when they clash. Slots that merely touch do not.
        func overlaps(_ other: Slot) -> Bool {
            weekday == other.weekday && startMinutes < other.endMinutes && other.startMinutes < endMinutes
        }
    }

    /// One dated occurrence of a slot.
    struct Lesson: Identifiable, Sendable, Hashable {
        /// The teaching and the start time.
        var id: String { "\(entry.code)-\(start.timeIntervalSince1970)" }
        /// The teaching this lesson belongs to.
        let entry: Entry
        /// The weekly slot it came from.
        let slot: Slot
        /// When this occurrence starts.
        let start: Date
        /// When it ends.
        let end: Date
    }

    /// The teachings not hidden by ``hiddenCodes``.
    var visibleEntries: [Entry] { entries.filter { !hiddenCodes.contains($0.code) } }

    /// Every lesson of the visible teachings falling in an interval.
    ///
    /// Each day in the interval is tested against every visible teaching's slots, bounded
    /// by that teaching's ``Entry/lessonsStart`` and ``Entry/lessonsEnd``. Days are taken
    /// in Rome.
    ///
    /// - Parameter interval: The span to expand.
    /// - Returns: The lessons, in time order, ties broken by teaching code.
    func lessons(in interval: DateInterval) -> [Lesson] {
        let calendar = PoliMiDate.romeCalendar
        var lessons: [Lesson] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            let weekday = calendar.component(.weekday, from: day)
            for entry in visibleEntries {
                if let first = entry.lessonsStart, day < calendar.startOfDay(for: first) { continue }
                if let last = entry.lessonsEnd, day > calendar.startOfDay(for: last) { continue }
                for slot in entry.slots where slot.weekday == weekday {
                    guard let start = calendar.date(byAdding: .minute, value: slot.startMinutes, to: day),
                          let end = calendar.date(byAdding: .minute, value: slot.endMinutes, to: day),
                          interval.contains(start) else { continue }
                    lessons.append(Lesson(entry: entry, slot: slot, start: start, end: end))
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return lessons.sorted { ($0.start, $0.entry.code) < ($1.start, $1.entry.code) }
    }

    /// Pairs of visible teachings whose weekly slots overlap.
    ///
    /// Teachings in different semesters do not clash, and a teaching with no recorded
    /// semester is compared against everything.
    ///
    /// Each element is a pair.
    var clashes: [[Entry]] {
        let visible = visibleEntries
        var found: [[Entry]] = []
        for (index, entry) in visible.enumerated() {
            for other in visible[(index + 1)...] where entry.semester == other.semester || entry.semester == nil || other.semester == nil {
                if entry.slots.contains(where: { slot in other.slots.contains(where: slot.overlaps) }) {
                    found.append([entry, other])
                }
            }
        }
        return found
    }
}

/// Reads the timetable service's pages: the orario testuale, a teaching's add link,
/// the sections fragment and the cart's XML replies.
///
/// Regular expressions over template-generated markup, like ``HTMLScraper``, and not
/// an HTML parser.
nonisolated enum PersonalTimetableParser {
    /// Reads every teaching out of an orario testuale page.
    ///
    /// Teachings are separated by a background-colour marker in the markup.
    ///
    /// - Parameter html: The page.
    /// - Returns: The teachings. Blocks that yield no header are skipped.
    static func entries(_ html: String) -> [PersonalTimetable.Entry] {
        let marker = "background-color:#f3f3ee"
        let blocks = html.components(separatedBy: marker).dropFirst()
        return blocks.compactMap(entry)
    }

    /// Reads one teaching out of its block: code and name from the bold header, the
    /// lecturer from the parenthesis after it, the semester, the two lesson dates, and a
    /// slot per list item.
    ///
    /// - Parameter block: One teaching's markup.
    /// - Returns: The teaching, or `nil` without a code-and-name header.
    private static func entry(_ block: String) -> PersonalTimetable.Entry? {
        guard let header = groups(#"<b>\s*([0-9]{6})\s*-\s*(.*?)</b>"#, in: block).first,
              header.count == 2 else { return nil }
        let teacher = groups(#"</b>\s*(?:&nbsp;)?\s*\(\s*<b>[^<]*</b>\s*([^)<]*?)\s*\)"#, in: block).first?.first
            .map(clean).flatMap { $0.isEmpty ? nil : $0 }
        let semester = groups(#"([12])\s*(?:°|st|nd)\s*semest"#, in: block).first?.first.flatMap { Int($0) }
        let dates = groups(#"([0-9]{2}/[0-9]{2}/[0-9]{4})"#, in: block).compactMap { $0.first.flatMap(date) }
        let slots = groups(#"<li[^>]*>(.*?)</li>"#, in: block).compactMap { $0.first.flatMap(slot) }
        return PersonalTimetable.Entry(
            code: header[0], title: clean(header[1]), teacher: teacher, semester: semester,
            lessonsStart: dates.first, lessonsEnd: dates.dropFirst().first, slots: slots)
    }

    /// Reads one weekly slot out of a list item.
    ///
    /// The weekday is matched against ``weekdays`` on the folded text, the times are the
    /// first two `HH:mm` values, and the room and its `idaula` come from the anchor.
    ///
    /// - Parameter item: The list item's markup.
    /// - Returns: The slot, or `nil` without a recognised weekday or two times.
    private static func slot(_ item: String) -> PersonalTimetable.Slot? {
        let text = clean(item.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        guard let weekday = weekdays.first(where: { folded.hasPrefix($0.key) })?.value else { return nil }
        let times = groups(#"([0-9]{1,2}):([0-9]{2})"#, in: text).compactMap { parts -> Int? in
            guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
            return hour * 60 + minute
        }
        guard times.count >= 2 else { return nil }
        let anchor = groups(#"<a[^>]*href="[^"]*idaula=([0-9]+)[^"]*"[^>]*>(.*?)</a>"#, in: item).first
        let address = groups(#"</a>\s*\((.*)\)\s*$"#, in: item).first?.first.map(clean)
        return PersonalTimetable.Slot(
            weekday: weekday, startMinutes: times[0], endMinutes: times[1],
            room: anchor.flatMap { $0.count == 2 ? clean($0[1]) : nil },
            roomID: anchor?.first, address: address)
    }

    /// Italian and English weekday names, folded and lower-cased, mapped to `Calendar`
    /// numbering.
    private static let weekdays: [String: Int] = [
        "lunedi": 2, "martedi": 3, "mercoledi": 4, "giovedi": 5, "venerdi": 6, "sabato": 7, "domenica": 1,
        "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7, "sunday": 1,
    ]

    /// Where a teaching's page offers to add it to the cart, for the student's own
    /// alphabetical bracket.
    struct CartLink: Sendable, Equatable {
        /// The degree course, `k_corso_la`.
        let courseCode: String
        /// The study plan, `k_indir`.
        let planCode: String
        /// The semester.
        let semester: String
        /// The year of course, defaulting to `"0"` when the link omits it.
        let yearOfCourse: String
    }

    /// Finds the add-to-cart link for one teaching on a timetable page.
    ///
    /// - Parameters:
    ///   - html: The page.
    ///   - code: The teaching code to match on `codDescr`.
    /// - Returns: The link, or `nil` when the page carries none for that teaching.
    static func cartLink(in html: String, code: String) -> CartLink? {
        for match in groups(#"href="([^"]*ORARIO_IN_CARRELLO[^"]*)""#, in: html) {
            let url = match[0].replacingOccurrences(of: "&amp;", with: "&")
            guard HTMLScraper.queryValue("codDescr", in: url) == code,
                  let course = HTMLScraper.queryValue("k_corso_la", in: url) else { continue }
            return CartLink(courseCode: course, planCode: HTMLScraper.queryValue("k_indir", in: url) ?? "",
                            semester: HTMLScraper.queryValue("semestre", in: url) ?? "",
                            yearOfCourse: HTMLScraper.queryValue("anno_corso", in: url) ?? "0")
        }
        return nil
    }

    /// Where a teaching offered in sections lists them, for teachings the student picks a
    /// section of rather than being assigned by bracket.
    struct SectionsLink: Sendable, Equatable, Codable {
        /// The degree course, `k_corso_la`.
        let courseCode: String
        /// The study plan, `k_indir`.
        let planCode: String
        /// The year of course.
        let yearOfCourse: String
        /// The offering's identifier.
        let idItemOfferta: String
        /// The section group's identifier.
        let idGruppo: String
        /// The catalogue row's identifier.
        let idRiga: String
    }

    /// Finds the sections link for one teaching on a timetable page.
    ///
    /// - Parameters:
    ///   - html: The page.
    ///   - code: The teaching code to match on `codDescr`.
    /// - Returns: The link, or `nil` when the teaching is not offered in sections.
    static func sectionsLink(in html: String, code: String) -> SectionsLink? {
        for match in groups(#"orario_td con_sezioni[^>]*>\s*<a[^>]*href="([^"]*)""#, in: html) {
            let url = match[0].replacingOccurrences(of: "&amp;", with: "&")
            guard HTMLScraper.queryValue("codDescr", in: url) == code,
                  let course = HTMLScraper.queryValue("k_corso_la", in: url) else { continue }
            func value(_ name: String) -> String { HTMLScraper.queryValue(name, in: url) ?? "" }
            return SectionsLink(courseCode: course, planCode: value("k_indir"), yearOfCourse: value("anno_corso"),
                                idItemOfferta: value("idItemOfferta"), idGruppo: value("idGruppo"), idRiga: value("idRiga"))
        }
        return nil
    }

    /// One section the student may pick.
    struct SectionOption: Sendable, Hashable, Identifiable, Codable {
        /// The semester and the section name, as the radio's value spells them.
        var id: String { "\(semester)_\(name)" }
        /// The semester this section runs in.
        let semester: String
        /// The section's name.
        let name: String
        /// The row's own text, falling back to ``name`` when the row has none.
        let label: String
        /// Whether the page already had this section selected.
        let isPreselected: Bool
    }

    /// Reads the sections out of the `evn_showsezioni` fragment, one per radio button.
    ///
    /// - Parameter html: The fragment.
    /// - Returns: The sections, in page order.
    static func sections(_ html: String) -> [SectionOption] {
        groups(#"<input([^>]*name="sel_sezione"[^>]*)>(.*?)</tr>"#, in: html).compactMap { match in
            guard let value = HTMLScraper.firstMatch(#"value="([^"]*)""#, in: match[0], group: 1),
                  let separator = value.firstIndex(of: "_") else { return nil }
            let label = clean(match[1].replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
            let name = String(value[value.index(after: separator)...])
            return SectionOption(semester: String(value[..<separator]), name: name,
                                 label: label.isEmpty ? name : label, isPreselected: match[0].contains("checked"))
        }
    }

    /// What the cart answered to an add.
    enum CartReply: Sendable, Equatable {
        /// The teaching was added, with how many are now in the cart.
        case added(count: Int)
        /// The add was refused, with the service's own message where it gave one.
        case refused(String?)
    }

    /// Reads the cart's XML reply.
    ///
    /// - Parameter xml: The reply body.
    /// - Returns: ``CartReply/added(count:)`` on a success carrying a count, and
    ///   ``CartReply/refused(_:)`` otherwise.
    static func cartReply(_ xml: String) -> CartReply {
        if xml.contains("<success>"),
           let count = HTMLScraper.firstMatch("<num-ins-cart>([0-9]+)</num-ins-cart>", in: xml, group: 1).flatMap({ Int($0) }) {
            return .added(count: count)
        }
        return .refused(HTMLScraper.firstMatch("<desc-error>(.*?)</desc-error>", in: xml, group: 1).map(clean))
    }

    // MARK: Plumbing

    /// Every match of a pattern, each as its capture groups.
    ///
    /// Group zero is omitted, and a group that did not participate comes back as the empty
    /// string rather than being dropped — so a caller may index positionally.
    ///
    /// - Parameters:
    ///   - pattern: The ICU pattern, matched case-insensitively with `.` spanning line
    ///     separators.
    ///   - text: The markup to search.
    /// - Returns: One array of captures per match.
    private static func groups(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = RegexCache.regex(pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    /// Strips markup, collapses whitespace and trims.
    ///
    /// - Parameter text: The markup fragment.
    /// - Returns: The readable text.
    private static func clean(_ text: String) -> String {
        HTMLText.plain(text).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses a `dd/MM/yyyy` date in Rome.
    ///
    /// - Parameter text: The date as the page prints it.
    /// - Returns: The date, or `nil` when it has not three components.
    private static func date(_ text: String) -> Date? {
        let parts = text.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return PoliMiDate.romeCalendar.date(from: DateComponents(year: parts[2], month: parts[1], day: parts[0]))
    }
}

/// Decides when the official agenda has taken over from a personal timetable.
///
/// The agenda carries no teaching code, so a teaching counts as present when its title
/// matches an agenda lecture and at least ``lessonsNeeded`` lessons fall on its own
/// weekly slots, within ``tolerance``.
nonisolated enum TimetableHandover {
    /// Whether a teaching is still the personal timetable's to show.
    enum Status: Sendable, Equatable {
        /// `personalOnly` while the agenda does not carry the teaching; `confirmed` once it
        /// does, at which point ``TimetableMerge`` stops adding it.
        case personalOnly, confirmed
    }

    /// How far an agenda lecture's start may fall from a slot's and still count as it, in
    /// seconds.
    static let tolerance = 15 * 60
    /// How many distinct days must match before a teaching counts as confirmed.
    static let lessonsNeeded = 2

    /// Whether the agenda now carries a teaching.
    ///
    /// - Parameters:
    ///   - entry: The teaching to check.
    ///   - agenda: The official agenda entries.
    /// - Returns: ``Status/confirmed`` when at least ``lessonsNeeded`` distinct days
    ///   match, ``Status/personalOnly`` otherwise.
    static func status(of entry: PersonalTimetable.Entry, agenda: [AgendaEvent]) -> Status {
        let calendar = PoliMiDate.romeCalendar
        let title = key(entry.title)
        let matching = agenda.filter { event in
            guard event.kind == .lecture else { return false }
            let other = key(event.title)
            guard !other.isEmpty, other.contains(title) || title.contains(other) else { return false }
            let weekday = calendar.component(.weekday, from: event.start)
            let minutes = calendar.component(.hour, from: event.start) * 60 + calendar.component(.minute, from: event.start)
            return entry.slots.contains { $0.weekday == weekday && abs($0.startMinutes - minutes) * 60 <= tolerance }
        }
        return Set(matching.map { calendar.startOfDay(for: $0.start) }).count >= lessonsNeeded ? .confirmed : .personalOnly
    }

    /// Whether enough teachings are confirmed to offer retiring the timetable.
    ///
    /// Four in five, since a teaching or two may never match by name.
    ///
    /// - Parameters:
    ///   - confirmed: How many teachings the agenda now carries.
    ///   - total: How many the timetable holds.
    /// - Returns: `true` at or above four fifths. Always `false` for an empty timetable.
    static func suggestsRetiring(confirmed: Int, of total: Int) -> Bool {
        total > 0 && Double(confirmed) / Double(total) >= 0.8
    }

    /// A title reduced to its comparable form: folded, lower-cased, non-alphanumerics
    /// collapsed to spaces.
    ///
    /// - Parameter title: The title as its source spells it.
    /// - Returns: The comparable form.
    private static func key(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Matches a career's degree course against a catalogue row, whose labels carry
/// level, ordinance and code alongside the name.
nonisolated enum DegreeCourseMatch {
    /// Whether a catalogue row names the student's degree course.
    ///
    /// - Parameters:
    ///   - degreeCourse: The catalogue row's degree-course name.
    ///   - plan: The degree course as the career names it.
    /// - Returns: `true` when the row's name contains the career's. `false` when either
    ///   is missing or the career's name is empty once folded.
    static func matches(_ degreeCourse: String?, plan: String?) -> Bool {
        guard let degreeCourse, let plan else { return false }
        let wanted = key(plan)
        return !wanted.isEmpty && key(degreeCourse).contains(wanted)
    }

    /// The best catalogue option for a degree course among a school's.
    ///
    /// An exact name match — or one at the end of a longer label — wins over a label that
    /// merely contains the name, so “Ingegneria Informatica” is not answered with
    /// “Ingegneria Informatica Online”. Among equals, the option whose group matches the
    /// career's level wins.
    ///
    /// - Parameters:
    ///   - options: The school's options.
    ///   - name: The degree course as the career names it.
    ///   - kind: The career's level, for example “Laurea Magistrale”.
    /// - Returns: The option, or `nil` when the name is empty or nothing matches.
    static func best(_ options: [CatalogueOption], name: String, kind: String?) -> CatalogueOption? {
        let wanted = key(name)
        guard !wanted.isEmpty else { return nil }
        let label = { (option: CatalogueOption) in
            key(option.label.replacingOccurrences(of: #"\([0-9]+\)\s*$"#, with: "", options: .regularExpression))
        }
        let exact = options.filter { label($0) == wanted || label($0).hasSuffix(" " + wanted) }
        let candidates = exact.isEmpty ? options.filter { key($0.label).contains(wanted) } : exact
        let master = kind.map { key($0).contains("magistrale") || key($0).contains("master") }
        if let master, let byLevel = candidates.first(where: { option in
            let group = key(option.group ?? "")
            return (group.contains("magistrale") || group.contains("master")) == master
        }) {
            return byLevel
        }
        return candidates.first
    }

    /// Text reduced to its comparable form: folded, lower-cased, non-alphanumerics
    /// collapsed to spaces.
    ///
    /// - Parameter text: The text as written.
    /// - Returns: The comparable form.
    private static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Folds a personal timetable's lessons into the official agenda.
///
/// A teaching the agenda already confirms is left to the agenda, so nothing appears
/// twice; one it lacks is added carrying ``tag``, which the calendar badges and which
/// tells a personal lesson from one the server sent.
nonisolated enum TimetableMerge {
    /// The ``AgendaEvent/tags`` entry every merged-in lesson carries.
    static let tag = "orario-personalizzato"

    /// Merges personal lessons into the official agenda for an interval.
    ///
    /// - Parameters:
    ///   - official: The agenda as the server sent it.
    ///   - timetable: The personal timetable, or `nil` when there is none.
    ///   - interval: The span being shown.
    /// - Returns: The two sets in time order, or `official` unchanged when there is no
    ///   timetable, it has been retired, or every teaching is already confirmed.
    static func merge(official: [AgendaEvent], timetable: PersonalTimetable?, in interval: DateInterval) -> [AgendaEvent] {
        guard let timetable, timetable.retiredAt == nil else { return official }
        let confirmed = Set(timetable.entries.filter {
            TimetableHandover.status(of: $0, agenda: official) == .confirmed
        }.map(\.code))
        var remaining = timetable
        remaining.hiddenCodes.formUnion(confirmed)
        let personal = remaining.lessons(in: interval).map { lesson in
            AgendaEvent(id: id(code: lesson.entry.code, start: lesson.start), title: lesson.entry.title,
                        start: lesson.start, end: lesson.end, kind: .lecture, room: lesson.slot.room,
                        roomAcronym: lesson.slot.room, calendarName: String(localized: "Orario personalizzato"),
                        details: lesson.slot.address, tags: [tag])
        }
        guard !personal.isEmpty else { return official }
        return (official + personal).sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    /// Whether a lecture should be marked as coming from the Politecnico.
    ///
    /// Only while personal lessons share the agenda, where the two need telling apart.
    ///
    /// - Parameters:
    ///   - event: The agenda entry.
    ///   - timetable: The personal timetable, or `nil` when there is none.
    /// - Returns: `true` for an official lecture while a live timetable is merged in.
    static func marksOfficial(_ event: AgendaEvent, timetable: PersonalTimetable?) -> Bool {
        guard let timetable, timetable.retiredAt == nil else { return false }
        return event.kind == .lecture && !event.tags.contains(tag)
    }

    /// The entries that came from the server, dropping the merged-in personal lessons.
    ///
    /// - Parameter events: The merged agenda.
    /// - Returns: The official entries.
    static func officialOnly(_ events: [AgendaEvent]) -> [AgendaEvent] {
        events.filter { !$0.tags.contains(tag) }
    }

    /// A stable identifier for a merged-in lesson.
    ///
    /// Negative, so it can never collide with an agenda id, and computed with FNV-1a
    /// rather than `hashValue`, which changes between launches.
    ///
    /// - Parameters:
    ///   - code: The teaching code.
    ///   - start: When the lesson starts.
    /// - Returns: The identifier.
    static func id(code: String, start: Date) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(code)|\(Int(start.timeIntervalSince1970))".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return -Int(hash % UInt64(Int32.max)) - 1
    }
}
