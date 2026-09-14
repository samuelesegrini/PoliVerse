import Foundation

/// Which reminders the student wants, and how far ahead.
nonisolated struct NotificationPreferences: Sendable, Equatable, Codable {
    var lectures = true
    var deadlines = true
    var exams = true
    var enrolments = true
    /// Minutes before a lecture. Anything nearer than this is skipped rather
    /// than fired late.
    var leadMinutes = 15
    /// Pushes when something changes about an exam — a mark, a room, a moved
    /// sitting. See ``ExamUpdatePolicy``.
    var examUpdates = true
    /// Let the app open a newly posted results file to look for the
    /// student's own matricola. Off until the student turns it on: the file
    /// lists other students too. See ``ResultsFileReader``.
    var readResultsFiles = false
    /// Rome hours between which only urgent news goes out. Equal hours mean
    /// no quiet hours at all.
    var quietFrom = 23
    var quietUntil = 7
    /// News read from WeBeep — files, announcements, assignments — as
    /// notifications. Off keeps it in the feed only.
    var weBeepUpdates = true
    /// Categories switched off, by raw value — strings, so a renamed
    /// category can never make stored preferences unreadable.
    var disabledCategories: [String] = []
    /// Rome hour of the daily summary.
    var digestHour = 18

    func isEnabled(_ category: UpdateCategory) -> Bool { !disabledCategories.contains(category.rawValue) }

    mutating func setCategory(_ category: UpdateCategory, enabled: Bool) {
        disabledCategories.removeAll { $0 == category.rawValue }
        if !enabled { disabledCategories.append(category.rawValue) }
    }

    func isQuiet(hour: Int) -> Bool {
        guard quietFrom != quietUntil else { return false }
        return quietFrom < quietUntil
            ? (quietFrom..<quietUntil).contains(hour)
            : hour >= quietFrom || hour < quietUntil
    }

    /// Courses whose news stays in the app and never notifies (§11.1).
    var mutedCourses: [MutedCourse] = []

    /// Whether a course is muted, matched by code or by name: the exam
    /// services, the libretto and WeBeep do not share a code for the same
    /// teaching (§3), but all normalise its name the same way.
    func isMuted(code: String, name: String) -> Bool {
        let target = MutedCourse.key(name)
        return mutedCourses.contains { $0.code == code || MutedCourse.key($0.name) == target }
    }

    mutating func setMuted(_ muted: Bool, code: String, name: String) {
        mutedCourses.removeAll { $0.code == code || MutedCourse.key($0.name) == MutedCourse.key(name) }
        if muted { mutedCourses.append(MutedCourse(code: code, name: name)) }
    }

    static let key = "notificationPreferences"

    static var stored: NotificationPreferences {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode(Self.self, from: data)
        else { return NotificationPreferences() }
        return decoded
    }

    func store() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

extension NotificationPreferences {
    private enum CodingKeys: String, CodingKey {
        case lectures, deadlines, exams, enrolments, leadMinutes, examUpdates, readResultsFiles, mutedCourses
        case quietFrom, quietUntil, weBeepUpdates, disabledCategories, digestHour
    }

    /// Lenient, key by key: a build that adds a preference must not make the
    /// stored ones unreadable, which would silently reset every choice.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = NotificationPreferences()
        lectures = try container.decodeIfPresent(Bool.self, forKey: .lectures) ?? defaults.lectures
        deadlines = try container.decodeIfPresent(Bool.self, forKey: .deadlines) ?? defaults.deadlines
        exams = try container.decodeIfPresent(Bool.self, forKey: .exams) ?? defaults.exams
        enrolments = try container.decodeIfPresent(Bool.self, forKey: .enrolments) ?? defaults.enrolments
        leadMinutes = try container.decodeIfPresent(Int.self, forKey: .leadMinutes) ?? defaults.leadMinutes
        examUpdates = try container.decodeIfPresent(Bool.self, forKey: .examUpdates) ?? defaults.examUpdates
        readResultsFiles = try container.decodeIfPresent(Bool.self, forKey: .readResultsFiles)
            ?? defaults.readResultsFiles
        mutedCourses = try container.decodeIfPresent([MutedCourse].self, forKey: .mutedCourses)
            ?? defaults.mutedCourses
        quietFrom = try container.decodeIfPresent(Int.self, forKey: .quietFrom) ?? defaults.quietFrom
        quietUntil = try container.decodeIfPresent(Int.self, forKey: .quietUntil) ?? defaults.quietUntil
        weBeepUpdates = try container.decodeIfPresent(Bool.self, forKey: .weBeepUpdates) ?? defaults.weBeepUpdates
        disabledCategories = try container.decodeIfPresent([String].self, forKey: .disabledCategories)
            ?? defaults.disabledCategories
        digestHour = try container.decodeIfPresent(Int.self, forKey: .digestHour) ?? defaults.digestHour
    }
}

/// A course the student silenced, remembered by both of its identities.
nonisolated struct MutedCourse: Sendable, Equatable, Hashable, Codable {
    let code: String
    let name: String

    static func key(_ name: String) -> String {
        Course.normalise(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }
}

/// One reminder, decided but not yet scheduled.
nonisolated struct PlannedNotification: Sendable, Equatable, Identifiable {
    nonisolated enum Kind: String, Sendable {
        case lecture, deadline, exam, enrolment
        /// Something changed about an exam — see ``ExamUpdate``.
        case update
    }

    /// Stable across rebuilds, so rescheduling replaces a reminder rather than
    /// adding a second copy of it.
    let id: String
    let kind: Kind
    let title: String
    let body: String
    let fireDate: Date
    /// Time-sensitive notifications pierce Focus. A lecture starting shortly
    /// earns that; a deadline tomorrow does not, and treating everything as
    /// urgent is how an app gets its notifications turned off entirely.
    let isTimeSensitive: Bool
    /// Groups related notifications in Notification Centre. Defaults to the
    /// kind.
    var thread: String? = nil
    /// Which notification leads a summary on the lock screen, 0…1. Nil keeps
    /// the system default.
    var relevance: Double? = nil
}

/// Decides what to schedule.
///
/// Pure, and tested as such: the scheduler around it is a thin wrapper that
/// hands this list to `UNUserNotificationCenter`.
nonisolated enum NotificationPlan {
    /// iOS keeps at most 64 pending local notifications per app and silently
    /// discards the rest — so the planner chooses rather than emits.
    static let limit = 64

    /// Reminders for a whole-day thing go out the evening before, when there
    /// is still an evening in which to act.
    static let eveningHour = 18

    static func build(
        events: [AgendaEvent],
        exams: [ExamSession],
        assignments: [AssignmentDeadline] = [],
        updates: [ExamUpdate] = [],
        preferences: NotificationPreferences,
        now: Date = .now
    ) -> [PlannedNotification] {
        var planned: [PlannedNotification] = []

        for event in events {
            switch event.kind {
            case .lecture where preferences.lectures:
                let fire = event.start.addingTimeInterval(
                    TimeInterval(-preferences.leadMinutes * 60))
                // Nearer than the lead time: firing now would be late, and a
                // late reminder is worse than none.
                guard fire > now else { continue }
                planned.append(PlannedNotification(
                    id: "lecture-\(event.id)",
                    kind: .lecture,
                    title: event.title,
                    body: [event.room.map { "Aula \($0)" },
                           "Inizia alle \(RoomBooking.clock.string(from: event.start))"]
                        .compactMap { $0 }.joined(separator: " · "),
                    fireDate: fire,
                    isTimeSensitive: true))

            case .deadline where preferences.deadlines:
                guard let fire = eveningBefore(event.start, now: now) else { continue }
                planned.append(PlannedNotification(
                    id: "deadline-\(event.id)",
                    kind: .deadline,
                    title: "Scadenza domani",
                    body: event.title,
                    fireDate: fire,
                    isTimeSensitive: false))

            case .exam where preferences.exams:
                guard let fire = eveningBefore(event.start, now: now) else { continue }
                planned.append(PlannedNotification(
                    id: "exam-event-\(event.id)",
                    kind: .exam,
                    title: "Esame domani",
                    body: [event.title, event.room.map { "Aula \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "),
                    fireDate: fire,
                    isTimeSensitive: false))

            default:
                continue
            }
        }

        // A muted course sends nothing (§11.2), reminders included.
        for exam in exams where !preferences.isMuted(code: exam.courseCode, name: exam.courseName) {
            if preferences.exams, let date = exam.date,
               let fire = eveningBefore(date, now: now) {
                planned.append(PlannedNotification(
                    id: "exam-\(exam.id)",
                    kind: .exam,
                    title: "Esame domani",
                    body: [exam.courseName, exam.room.map { "Aula \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "),
                    fireDate: fire,
                    isTimeSensitive: false))
            }

            if preferences.enrolments, let closes = exam.enrolmentCloses,
               let fire = eveningBefore(closes, now: now) {
                planned.append(PlannedNotification(
                    id: "enrolment-\(exam.id)",
                    kind: .enrolment,
                    title: "Iscrizioni in chiusura",
                    body: "\(exam.courseName): ultimo giorno per iscriverti all'appello.",
                    fireDate: fire,
                    isTimeSensitive: false))
            }
        }

        for assignment in assignments
        where preferences.deadlines && !preferences.isMuted(code: assignment.courseCode, name: assignment.courseName) {
            let day = AssignmentDetector.reminderDay(for: assignment.due)
            let fire = PoliMiDate.time(eveningHour, on: day)
            guard fire > now else { continue }
            planned.append(PlannedNotification(
                id: "assignment-\(assignment.id)",
                kind: .deadline,
                title: String(localized: "Consegna domani"),
                body: "\(assignment.courseName): \(assignment.name)",
                fireDate: fire,
                isTimeSensitive: false))
        }

        // Evening summaries of exam updates that did not deserve a push of
        // their own. Rebuilt from the log each time, like everything else here.
        if preferences.examUpdates {
            // Filtered here, not only when decided: muting a course, or
            // switching a kind of news off, also silences the summary it had
            // already been queued for.
            planned += ExamUpdatePolicy.digests(
                from: updates.filter {
                    !preferences.isMuted(code: $0.courseCode, name: $0.courseName)
                        && preferences.isEnabled($0.kind.category)
                        && (preferences.weBeepUpdates || $0.source != .webeep)
                },
                now: now, preferences: preferences)
        }

        return prune(planned)
    }

    /// 18:00 Rome the day before, unless that is already past — in which case
    /// there is no useful moment left and the reminder is dropped.
    private static func eveningBefore(_ date: Date, now: Date) -> Date? {
        let calendar = PoliMiDate.romeCalendar
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: date) else {
            return nil
        }
        let fire = PoliMiDate.time(eveningHour, on: dayBefore)
        return fire > now ? fire : nil
    }

    /// Deduplicates, orders and caps.
    ///
    /// An exam appears both in the agenda and in the sittings list, and two
    /// notifications for it in the same minute is noise the user experiences
    /// as a bug. Soonest first, because a reminder three weeks out is worth
    /// less than one tomorrow — and the cap cuts from the far end.
    private static func prune(_ planned: [PlannedNotification]) -> [PlannedNotification] {
        var seen: Set<String> = []
        let deduped = planned
            .sorted { $0.fireDate < $1.fireDate }
            .filter { item in
                // Same kind at the same minute about the same thing: keep one.
                let fingerprint = "\(item.kind.rawValue)-\(Int(item.fireDate.timeIntervalSince1970 / 60))-\(item.body)"
                return seen.insert(fingerprint).inserted
            }
        return Array(deduped.prefix(limit))
    }
}
