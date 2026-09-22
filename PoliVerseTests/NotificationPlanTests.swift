import Foundation
import Testing
@testable import PoliVerse

/// What gets scheduled, and when.
///
/// iOS keeps at most **64** pending local notifications per app and silently
/// drops the rest, so the planner cannot simply emit one per event: it has to
/// choose. Everything here is pure — the scheduling itself is a thin wrapper
/// over the list this produces.
@Suite("Notification plan")
struct NotificationPlanTests {
    private let now = Date(timeIntervalSince1970: 1_772_000_000)   // 2026-02-25 08:53 UTC

    private func event(_ minutes: Int, title: String = "Analisi",
                       kind: EventKind = .lecture) -> AgendaEvent {
        let start = now.addingTimeInterval(TimeInterval(minutes * 60))
        return AgendaEvent(
            id: minutes * 1000 + abs(title.hashValue % 1000), title: title,
            start: start, end: start.addingTimeInterval(7200),
            kind: kind, room: "3.0.1")
    }

    private func exam(_ days: Int, closes: Int? = nil) -> ExamSession {
        ExamSession(
            id: days, courseName: "Fisica", courseCode: "F1", teacher: nil,
            date: now.addingTimeInterval(TimeInterval(days * 86400)),
            room: "2.0.1", enrolmentOpens: nil,
            enrolmentCloses: closes.map { now.addingTimeInterval(TimeInterval($0 * 86400)) },
            enrolledCount: nil, kind: nil, status: .open)
    }

    private var preferences: NotificationPreferences {
        NotificationPreferences(lectures: true, deadlines: true, exams: true,
                                enrolments: true, leadMinutes: 15)
    }

    /// The timetable names a room twice, and only one of the two is signposted
    /// anywhere a student will stand: `"005A"` is the ateneo's own code and is
    /// printed on no door, while `"5.1.1"` is building, floor and room. A
    /// reminder that names the room the student cannot find has not told them
    /// where to go.
    @Test("A lecture reminder names the room by its door code, not the internal one")
    func lectureNamesDoorCode() {
        let start = now.addingTimeInterval(120 * 60)
        let lecture = AgendaEvent(
            id: 1, title: "Analisi", start: start, end: start.addingTimeInterval(7200),
            kind: .lecture, room: "005A", roomAcronym: "5.1.1")
        let plan = NotificationPlan.build(
            events: [lecture], exams: [], preferences: preferences, now: now)
        let reminder = plan.first { $0.kind == .lecture }
        #expect(reminder?.body.contains("Aula 5.1.1") == true)
        #expect(reminder?.body.contains("005A") == false)
    }

    /// Named halls keep their names even when a door code is available: Rogers
    /// and De Donato are what students are told and what they ask for, and
    /// `"R.0.1"` in their place is a step backwards. The name already says
    /// "Aula", so the word is not added a second time.
    @Test("A lecture in a named hall is announced by the hall's name")
    func lectureKeepsHallName() {
        let start = now.addingTimeInterval(120 * 60)
        let lecture = AgendaEvent(
            id: 2, title: "Analisi", start: start, end: start.addingTimeInterval(7200),
            kind: .lecture, room: "Aula Rogers", roomAcronym: "R.0.1")
        let plan = NotificationPlan.build(
            events: [lecture], exams: [], preferences: preferences, now: now)
        let body = plan.first { $0.kind == .lecture }?.body
        #expect(body?.contains("Aula Rogers") == true)
        #expect(body?.contains("Aula Aula") == false)
    }

    @Test("A lecture is announced the chosen number of minutes before")
    func lectureLead() {
        let plan = NotificationPlan.build(
            events: [event(120)], exams: [], preferences: preferences, now: now)
        let lecture = plan.first { $0.kind == .lecture }
        #expect(lecture != nil)
        #expect(lecture!.fireDate == event(120).start.addingTimeInterval(-15 * 60))
    }

    /// A lecture starting sooner than the lead time cannot be announced before
    /// it starts, and firing it late is worse than not firing.
    @Test("A lecture too close to now is skipped")
    func tooSoon() {
        let plan = NotificationPlan.build(
            events: [event(5)], exams: [], preferences: preferences, now: now)
        #expect(plan.isEmpty)
    }

    @Test("Anything already past is skipped")
    func past() {
        let plan = NotificationPlan.build(
            events: [event(-120)], exams: [], preferences: preferences, now: now)
        #expect(plan.isEmpty)
    }

    /// Deadlines are not "in 15 minutes" things — they are announced the
    /// evening before, when there is still time to act.
    @Test("A deadline is announced the evening before")
    func deadlineEvening() {
        let deadline = event(60 * 40, title: "Consegna", kind: .deadline)
        let plan = NotificationPlan.build(
            events: [deadline], exams: [], preferences: preferences, now: now)
        let item = plan.first { $0.kind == .deadline }
        #expect(item != nil)
        let calendar = PoliMiDate.romeCalendar
        #expect(calendar.component(.hour, from: item!.fireDate) == 18)
        #expect(item!.fireDate < deadline.start)
    }

    @Test("An exam is announced the evening before as well")
    func examEvening() {
        let plan = NotificationPlan.build(
            events: [], exams: [exam(3)], preferences: preferences, now: now)
        #expect(plan.contains { $0.kind == .exam })
    }

    /// The one nobody forgives missing: enrolment closing.
    @Test("An enrolment window closing is announced a day ahead")
    func enrolmentClosing() {
        let plan = NotificationPlan.build(
            events: [], exams: [exam(20, closes: 5)], preferences: preferences, now: now)
        let item = plan.first { $0.kind == .enrolment }
        #expect(item != nil)
        #expect(item!.fireDate < exam(20, closes: 5).enrolmentCloses!)
    }

    @Test("Each kind can be switched off on its own")
    func preferencesRespected() {
        var prefs = preferences
        prefs.lectures = false
        let plan = NotificationPlan.build(
            events: [event(120), event(60 * 40, title: "C", kind: .deadline)],
            exams: [exam(3)], preferences: prefs, now: now)
        #expect(!plan.contains { $0.kind == .lecture })
        #expect(plan.contains { $0.kind == .deadline })
    }

    /// The cap. Soonest first, because a reminder three weeks out is worth
    /// less than one tomorrow.
    @Test("The plan never exceeds the system limit")
    func respectsLimit() {
        let many = (1...200).map { event($0 * 60, title: "Lezione \($0)") }
        let plan = NotificationPlan.build(
            events: many, exams: [], preferences: preferences, now: now)
        #expect(plan.count <= NotificationPlan.limit)
        #expect(plan.count == NotificationPlan.limit)
    }

    @Test("What survives the cap is the soonest")
    func keepsSoonest() {
        let many = (1...200).map { event($0 * 60, title: "Lezione \($0)") }
        let plan = NotificationPlan.build(
            events: many, exams: [], preferences: preferences, now: now)
        #expect(plan.first?.fireDate == plan.map(\.fireDate).min())
        let latestKept = plan.map(\.fireDate).max()!
        #expect(latestKept < many.last!.start)
    }

    /// An exam appears both in the agenda and in the sittings list; announcing
    /// it twice at the same minute is a bug the user experiences as noise.
    @Test("The same thing is not announced twice")
    func deduplicates() {
        let sitting = exam(3)
        let asEvent = AgendaEvent(
            id: 90_000 + sitting.id, title: "Fisica",
            start: sitting.date!, end: sitting.date!.addingTimeInterval(3600),
            kind: .exam, room: "2.0.1")
        let plan = NotificationPlan.build(
            events: [asEvent], exams: [sitting], preferences: preferences, now: now)
        #expect(plan.filter { $0.kind == .exam }.count == 1)
    }

    @Test("Identifiers are stable, so rescheduling replaces rather than piles up")
    func stableIdentifiers() {
        let first = NotificationPlan.build(
            events: [event(120)], exams: [], preferences: preferences, now: now)
        let second = NotificationPlan.build(
            events: [event(120)], exams: [], preferences: preferences, now: now)
        #expect(first.map(\.id) == second.map(\.id))
    }

    /// A lecture about to start is time-sensitive; a deadline tomorrow is not.
    @Test("Only imminent lectures are time-sensitive")
    func interruptionLevels() {
        let plan = NotificationPlan.build(
            events: [event(120), event(60 * 40, title: "C", kind: .deadline)],
            exams: [], preferences: preferences, now: now)
        #expect(plan.first { $0.kind == .lecture }?.isTimeSensitive == true)
        #expect(plan.first { $0.kind == .deadline }?.isTimeSensitive == false)
    }

    @Test("With everything off nothing is scheduled")
    func allOff() {
        let prefs = NotificationPreferences(lectures: false, deadlines: false,
                                            exams: false, enrolments: false,
                                            leadMinutes: 15)
        let plan = NotificationPlan.build(
            events: [event(120)], exams: [exam(3, closes: 2)],
            preferences: prefs, now: now)
        #expect(plan.isEmpty)
    }
}
