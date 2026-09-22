import Foundation

/// Which reminders and which news the student wants, and how far ahead.
///
/// Persisted in `UserDefaults` under ``key``, and decoded key by key so that a build
/// adding a preference cannot make the stored ones unreadable and silently reset every
/// choice.
nonisolated struct NotificationPreferences: Sendable, Equatable, Codable {
    /// Whether to remind before a lecture.
    var lectures = true
    /// Whether to remind before a deadline or a WeBeep hand-in.
    var deadlines = true
    /// Whether to remind the evening before a sitting.
    var exams = true
    /// Whether to remind on the last day of an enrolment window.
    var enrolments = true
    /// How many minutes before a lecture to remind. A lecture nearer than this is skipped
    /// rather than reminded about late.
    var leadMinutes = 15
    /// Whether a change to an exam — a mark, a room, a moved sitting — is pushed. See
    /// ``ExamUpdatePolicy``.
    var examUpdates = true
    /// Whether the app may open a newly posted results file to look for the student's own
    /// matricola.
    ///
    /// Off until the student turns it on, because such a file lists other students too. See
    /// ``ResultsFileReader``.
    var readResultsFiles = false
    /// The Rome hour quiet hours begin at.
    var quietFrom = 23
    /// The Rome hour quiet hours end at. Equal to ``quietFrom`` means no quiet hours at
    /// all.
    var quietUntil = 7
    /// Whether news read from WeBeep — files, announcements, hand-ins — is pushed. Off keeps
    /// it in the feed only.
    var weBeepUpdates = true
    /// Categories switched off, by raw value — strings, so a renamed category cannot make
    /// stored preferences unreadable.
    var disabledCategories: [String] = []
    /// The Rome hour of the evening summary.
    var digestHour = 18

    /// Whether a category of news is switched on.
    ///
    /// - Parameter category: The category to check.
    /// - Returns: `true` unless it has been switched off.
    func isEnabled(_ category: UpdateCategory) -> Bool { !disabledCategories.contains(category.rawValue) }

    /// Switches a category of news on or off.
    ///
    /// - Parameters:
    ///   - category: The category to change.
    ///   - enabled: Whether it should notify.
    mutating func setCategory(_ category: UpdateCategory, enabled: Bool) {
        disabledCategories.removeAll { $0 == category.rawValue }
        if !enabled { disabledCategories.append(category.rawValue) }
    }

    /// Whether an hour falls inside quiet hours.
    ///
    /// Handles a window that crosses midnight, and treats equal bounds as no quiet hours.
    ///
    /// - Parameter hour: The Rome hour to test.
    /// - Returns: `true` when only urgent news should go out.
    func isQuiet(hour: Int) -> Bool {
        guard quietFrom != quietUntil else { return false }
        return quietFrom < quietUntil
            ? (quietFrom..<quietUntil).contains(hour)
            : hour >= quietFrom || hour < quietUntil
    }

    /// Courses whose news stays in the app and never notifies, reminders included.
    var mutedCourses: [MutedCourse] = []

    /// Whether a course is muted.
    ///
    /// Matched by code or by normalised name: the exam services, the libretto and WeBeep do
    /// not share a code for the same teaching, but all normalise its name the same way.
    ///
    /// - Parameters:
    ///   - code: The teaching code as the source spells it.
    ///   - name: The teaching's name.
    /// - Returns: `true` when the course is muted.
    func isMuted(code: String, name: String) -> Bool {
        let target = MutedCourse.key(name)
        return mutedCourses.contains { $0.code == code || MutedCourse.key($0.name) == target }
    }

    /// Mutes or unmutes a course, by both of its identities.
    ///
    /// - Parameters:
    ///   - muted: Whether it should be silent.
    ///   - code: The teaching code.
    ///   - name: The teaching's name.
    mutating func setMuted(_ muted: Bool, code: String, name: String) {
        mutedCourses.removeAll { $0.code == code || MutedCourse.key($0.name) == MutedCourse.key(name) }
        if muted { mutedCourses.append(MutedCourse(code: code, name: name)) }
    }

    /// The defaults key the preferences are stored under.
    static let key = "notificationPreferences"

    /// The stored preferences, or the defaults when nothing is stored or it will not
    /// decode.
    static var stored: NotificationPreferences {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode(Self.self, from: data)
        else { return NotificationPreferences() }
        return decoded
    }

    /// Writes the preferences to `UserDefaults`. Failures are ignored.
    func store() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

/// Lenient decoding, so a new preference cannot reset the stored ones.
extension NotificationPreferences {
    /// One key per stored preference.
    private enum CodingKeys: String, CodingKey {
        case lectures, deadlines, exams, enrolments, leadMinutes, examUpdates, readResultsFiles, mutedCourses
        case quietFrom, quietUntil, weBeepUpdates, disabledCategories, digestHour
    }

    /// Decodes each preference independently, falling back to its default when the key is
    /// absent.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Only when the body is not a keyed container at all.
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
    /// The teaching code as the source that produced the news spells it.
    let code: String
    /// The teaching's name, which is what matches across sources.
    let name: String

    /// A teaching name reduced to its comparable form: title-cased, folded and lower-cased.
    ///
    /// - Parameter name: The name as its source spells it.
    /// - Returns: The comparable form.
    static func key(_ name: String) -> String {
        Course.normalise(name).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }
}

/// One notification, decided but not yet scheduled.
nonisolated struct PlannedNotification: Sendable, Equatable, Identifiable {
    /// What a notification is about, which also decides the screen tapping it opens — see
    /// ``NotificationModel/destination(for:)``.
    nonisolated enum Kind: String, Sendable {
        /// A lecture starting, a deadline or hand-in due, a sitting tomorrow, or an enrolment
        /// window closing.
        case lecture, deadline, exam, enrolment
        /// Something changed about an exam. See ``ExamUpdate``.
        case update
    }

    /// Stable across rebuilds, so rescheduling replaces a notification rather than adding a
    /// second copy of it.
    let id: String
    /// What the notification is about.
    let kind: Kind
    /// The notification's title.
    let title: String
    /// The notification's body.
    let body: String
    /// When it should be delivered.
    let fireDate: Date
    /// Whether it may pierce Focus.
    ///
    /// A lecture starting shortly earns that; a deadline tomorrow does not. Treating
    /// everything as urgent is how an app has its notifications switched off entirely.
    let isTimeSensitive: Bool
    /// Groups related notifications in Notification Centre. Defaults to the kind.
    var thread: String? = nil
    /// Which notification leads a summary on the Lock Screen, from 0 to 1. `nil` keeps the
    /// system default.
    var relevance: Double? = nil
}

/// Decides what to schedule.
///
/// Pure, and tested as such: ``NotificationModel`` is a thin wrapper that hands the
/// result to the system. Lectures, deadlines and sittings come from the agenda; sittings
/// and enrolment windows from the exam services; hand-ins from WeBeep; and the evening
/// summaries from ``ExamUpdatePolicy/digests(from:now:preferences:)``.
///
/// A muted course contributes nothing, reminders included.
nonisolated enum NotificationPlan {
    /// How many notifications the plan may contain.
    ///
    /// iOS keeps at most this many pending local notifications per app and silently discards
    /// the rest, so the planner chooses rather than emitting and hoping.
    static let limit = 64

    /// The Rome hour a reminder for a whole-day thing goes out the evening before, while
    /// there is still an evening in which to act.
    static let eveningHour = 18

    /// Builds the whole plan.
    ///
    /// A reminder whose moment has already passed is dropped rather than fired late. The
    /// result is deduplicated, ordered soonest first and capped at ``limit`` by
    /// ``prune(_:)``.
    ///
    /// Summaries are filtered by the student's preferences here as well as when the updates
    /// were decided, so muting a course or switching a category off also silences a summary
    /// it had already been queued for.
    ///
    /// - Parameters:
    ///   - events: The agenda entries.
    ///   - exams: The exam sittings.
    ///   - assignments: The WeBeep hand-ins still ahead.
    ///   - updates: Every recorded update, for the summaries.
    ///   - preferences: What the student has asked for.
    ///   - now: The moment to plan from.
    /// - Returns: The notifications to schedule.
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
                    body: [event.roomLabel.map(RoomNaming.sentence),
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
                    body: [event.title, event.roomLabel.map(RoomNaming.sentence)]
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
                    body: [exam.courseName, exam.room.map(RoomNaming.sentence)]
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

    /// ``eveningHour`` in Rome on the day before a date.
    ///
    /// - Parameters:
    ///   - date: What the reminder is about.
    ///   - now: The moment to plan from.
    /// - Returns: The moment to fire at, or `nil` when it has already passed and no useful
    ///   moment is left.
    private static func eveningBefore(_ date: Date, now: Date) -> Date? {
        let calendar = PoliMiDate.romeCalendar
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: date) else {
            return nil
        }
        let fire = PoliMiDate.time(eveningHour, on: dayBefore)
        return fire > now ? fire : nil
    }

    /// Deduplicates, orders and caps the plan.
    ///
    /// A sitting appears both in the agenda and in the sittings list, and two notifications
    /// for it in the same minute reads as a bug, so one of each kind, minute and body is
    /// kept. Ordered soonest first, since the cap cuts from the far end and a reminder three
    /// weeks out is worth less than one tomorrow.
    ///
    /// - Parameter planned: The notifications to prune.
    /// - Returns: At most ``limit`` notifications, soonest first.
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
