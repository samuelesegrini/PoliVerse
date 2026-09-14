import Foundation

/// A personalised timetable, kept on the phone.
///
/// Built once from the Politecnico's "orario testuale" and then independent of
/// it: the service's cart lives on a cookie that expires, and a timetable that
/// vanished with it — or asked for the student's name again — was the problem.
nonisolated struct PersonalTimetable: Codable, Sendable, Equatable {
    var name: String
    var yearCode: String
    var entries: [Entry]
    var builtAt: Date
    /// Teachings the student chose not to see: the official agenda has them,
    /// or they were added only to look.
    var hiddenCodes: Set<String> = []
    /// Set when the student retires the timetable for the official agenda.
    var retiredAt: Date?
    /// The catalogue rows it was built from, so it can be rebuilt — rooms
    /// change in the first weeks — without searching again.
    var sources: [Source] = []
    /// Sections chosen for teachings offered in sections, by teaching code,
    /// so a rebuild keeps them.
    var sections: [String: SectionChoice] = [:]

    struct SectionChoice: Sendable, Equatable, Codable {
        let link: PersonalTimetableParser.SectionsLink
        let option: PersonalTimetableParser.SectionOption
    }

    /// A ``ManifestoTeaching`` as it is kept on disk.
    struct Source: Codable, Sendable, Hashable, Identifiable {
        var id: String { "\(courseCode)-\(code)-\(planCode ?? "")" }
        let code: String
        let name: String
        let courseCode: String
        let planCode: String?
        let idItemOfferta: String?
        let idRiga: String?
        let semester: String?
        let year: String?
        let degreeCourse: String?

        init(_ teaching: ManifestoTeaching) {
            code = teaching.code; name = teaching.name; courseCode = teaching.courseCode
            planCode = teaching.planCode; idItemOfferta = teaching.idItemOfferta; idRiga = teaching.idRiga
            semester = teaching.semester; year = teaching.year; degreeCourse = teaching.degreeCourse
        }

        var teaching: ManifestoTeaching {
            ManifestoTeaching(code: code, name: name, courseCode: courseCode, planCode: planCode,
                              idItemOfferta: idItemOfferta, idRiga: idRiga, semester: semester, year: year,
                              credits: nil, school: nil, degreeCourse: degreeCourse)
        }
    }

    struct Entry: Codable, Sendable, Hashable, Identifiable {
        var id: String { code }
        let code: String
        let title: String
        let teacher: String?
        let semester: Int?
        let lessonsStart: Date?
        let lessonsEnd: Date?
        let slots: [Slot]
    }

    struct Slot: Codable, Sendable, Hashable {
        /// `Calendar` numbering: 1 is Sunday, 2 Monday.
        let weekday: Int
        let startMinutes: Int
        let endMinutes: Int
        let room: String?
        /// `idaula`, the key the room services take.
        let roomID: String?
        let address: String?

        func overlaps(_ other: Slot) -> Bool {
            weekday == other.weekday && startMinutes < other.endMinutes && other.startMinutes < endMinutes
        }
    }

    struct Lesson: Identifiable, Sendable, Hashable {
        var id: String { "\(entry.code)-\(start.timeIntervalSince1970)" }
        let entry: Entry
        let slot: Slot
        let start: Date
        let end: Date
    }

    var visibleEntries: [Entry] { entries.filter { !hiddenCodes.contains($0.code) } }

    /// Every lesson in an interval, in time order.
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

    /// Pairs of teachings whose weekly slots overlap in the same semester.
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

/// Reads the service's pages: the orario testuale, a teaching's add link, and
/// the cart's XML replies.
nonisolated enum PersonalTimetableParser {
    static func entries(_ html: String) -> [PersonalTimetable.Entry] {
        let marker = "background-color:#f3f3ee"
        let blocks = html.components(separatedBy: marker).dropFirst()
        return blocks.compactMap(entry)
    }

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

    private static let weekdays: [String: Int] = [
        "lunedi": 2, "martedi": 3, "mercoledi": 4, "giovedi": 5, "venerdi": 6, "sabato": 7, "domenica": 1,
        "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7, "sunday": 1,
    ]

    /// Where a teaching's page offers to add it: the student's own bracket,
    /// once a name is set on the session.
    struct CartLink: Sendable, Equatable {
        let courseCode: String
        let planCode: String
        let semester: String
        let yearOfCourse: String
    }

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

    /// A teaching offered in sections the student picks, rather than by bracket.
    struct SectionsLink: Sendable, Equatable, Codable {
        let courseCode: String
        let planCode: String
        let yearOfCourse: String
        let idItemOfferta: String
        let idGruppo: String
        let idRiga: String
    }

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

    struct SectionOption: Sendable, Hashable, Identifiable, Codable {
        var id: String { "\(semester)_\(name)" }
        let semester: String
        let name: String
        let label: String
        let isPreselected: Bool
    }

    /// The `evn_showsezioni` fragment: one radio per section.
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

    enum CartReply: Sendable, Equatable {
        case added(count: Int)
        /// The service's own message, when it gave one.
        case refused(String?)
    }

    static func cartReply(_ xml: String) -> CartReply {
        if xml.contains("<success>"),
           let count = HTMLScraper.firstMatch("<num-ins-cart>([0-9]+)</num-ins-cart>", in: xml, group: 1).flatMap({ Int($0) }) {
            return .added(count: count)
        }
        return .refused(HTMLScraper.firstMatch("<desc-error>(.*?)</desc-error>", in: xml, group: 1).map(clean))
    }

    // MARK: Plumbing

    private static func groups(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = RegexCache.regex(pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    private static func clean(_ text: String) -> String {
        HTMLText.plain(text).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func date(_ text: String) -> Date? {
        let parts = text.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return PoliMiDate.romeCalendar.date(from: DateComponents(year: parts[2], month: parts[1], day: parts[0]))
    }
}

/// When the official agenda takes over from the personal timetable.
///
/// The agenda carries no teaching code, so a teaching counts as there when
/// its title matches and at least two lessons fall on its own weekly slots.
nonisolated enum TimetableHandover {
    enum Status: Sendable, Equatable {
        case personalOnly, confirmed
    }

    static let tolerance = 15 * 60
    static let lessonsNeeded = 2

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

    /// Four in five: a teaching or two may never match by name.
    static func suggestsRetiring(confirmed: Int, of total: Int) -> Bool {
        total > 0 && Double(confirmed) / Double(total) >= 0.8
    }

    private static func key(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Whether a catalogue row is the student's degree course, by name: the
/// career gives "Ingegneria Energetica", the catalogue
/// "(1 liv.)(ord. 270) - BV (352) Ingegneria Energetica".
nonisolated enum DegreeCourseMatch {
    static func matches(_ degreeCourse: String?, plan: String?) -> Bool {
        guard let degreeCourse, let plan else { return false }
        let wanted = key(plan)
        return !wanted.isEmpty && key(degreeCourse).contains(wanted)
    }

    private static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Personal lessons in the agenda, alongside the official ones.
///
/// A teaching the agenda already confirms is left to the agenda, so nothing
/// shows twice; one it lacks is added with ``tag``, which the calendar badges
/// and which lets a cached agenda be told apart from what the server sent.
nonisolated enum TimetableMerge {
    static let tag = "orario-personalizzato"

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

    static func officialOnly(_ events: [AgendaEvent]) -> [AgendaEvent] {
        events.filter { !$0.tags.contains(tag) }
    }

    /// Negative, so it can never collide with the agenda's own ids; FNV-1a,
    /// because `hashValue` changes between launches.
    static func id(code: String, start: Date) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(code)|\(Int(start.timeIntervalSince1970))".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return -Int(hash % UInt64(Int32.max)) - 1
    }
}
