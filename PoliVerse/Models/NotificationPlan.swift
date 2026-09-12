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

/// One reminder, decided but not yet scheduled.
nonisolated struct PlannedNotification: Sendable, Equatable, Identifiable {
    nonisolated enum Kind: String, Sendable {
        case lecture, deadline, exam, enrolment
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

        for exam in exams {
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
