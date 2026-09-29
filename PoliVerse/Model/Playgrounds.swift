#if DEBUG
import Foundation
import Playgrounds

// Playgrounds for the pure planners, run from Xcode's canvas (Editor ▸ Canvas,
// then pick one). Change `now` or the inputs and the results update beside the
// code, without launching the app. Start here when a reminder, a row in Oggi
// or a payload looks wrong, then pin what you find in a test.
//
// Debug only, so none of this reaches a Release build.

/// A Monday morning in term, in Rome. Move it to try a weekend, the night
/// before an exam, or either daylight-saving change.
private let now = PoliMiDate.romeCalendar.date(
    from: DateComponents(year: 2026, month: 10, day: 26, hour: 8, minute: 50))!

#Playground("Reminders for the sample week") {
    let plan = NotificationPlan.build(
        events: AgendaEvent.samples(around: now),
        exams: ExamSession.samples(now: now),
        assignments: AssignmentDeadline.samples(now: now),
        updates: ExamUpdate.samples(now: now),
        preferences: NotificationPreferences(),
        now: now)
    let rome = Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: PoliMiDate.romeCalendar.timeZone)
    let rows = plan.map { "\($0.fireDate.formatted(rome))  \($0.kind)  \($0.title)" }
    let beforeNow = plan.filter { $0.fireDate < now }
}

#Playground("Oggi: In arrivo") {
    let items = TodayDigest.upcoming(
        events: AgendaEvent.samples(around: now),
        deadlines: AssignmentDeadline.samples(now: now),
        exams: ExamSession.samples(now: now),
        now: now, limit: 5)
    let rows = items.map { "\($0.date.formatted())  \($0.source)  \($0.title)" }
}

#Playground("Agenda payload") {
    // Paste a row from a recorded response.
    let json = """
    [{"event_id": 1, "date_start": "2026-10-25T02:30:00", "date_end": "2026-10-25T03:30:00",
      "event_type": {"typeId": 1}, "title": {"it": "Lezione nell'ora ripetuta"}},
     {"date_start": "2026-10-26T09:15:00", "date_end": "2026-10-26T11:15:00",
      "title": {"it": "Senza id"}}]
    """
    let events = try JSONDecoder().decode([AgendaEventDTO].self, from: Data(json.utf8)).map { $0.toEvent() }
}
#endif
