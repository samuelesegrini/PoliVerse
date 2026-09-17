import Foundation
import Testing
@testable import PoliVerse

/// Turning the personal timetable into weekly repeating events.
///
/// The arithmetic here is the part that goes wrong quietly: a lesson that
/// starts on the wrong week, a recurrence that stops a day early and drops the
/// last lesson, a hidden teaching that comes back in the student's calendar.
/// `CalendarExporter` itself is not tested — it needs EventKit and the
/// student's permission — but everything it writes comes from here.
/// `PersonalTimetableTests` walks one whole draft end to end; these take the
/// edges apart one at a time.
@Suite("Esportazione nel calendario")
struct CalendarExportTests {
    private let calendar = PoliMiDate.romeCalendar

    /// A Monday, the first day of lessons in the fixtures the parser tests use.
    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            timeZone: TimeZone(identifier: "Europe/Rome"),
            year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func slot(
        weekday: Int, from start: Int, to end: Int, room: String? = "3.1.4",
        address: String? = "Piazza Leonardo da Vinci 32"
    ) -> PersonalTimetable.Slot {
        .init(weekday: weekday, startMinutes: start, endMinutes: end,
              room: room, roomID: "46", address: address)
    }

    private func entry(
        code: String = "052496", title: String = "Algorithms and Parallel Computing",
        teacher: String? = "Rossi Matteo", start: Date?, end: Date?,
        slots: [PersonalTimetable.Slot]
    ) -> PersonalTimetable.Entry {
        .init(code: code, title: title, teacher: teacher, semester: 1,
              lessonsStart: start, lessonsEnd: end, slots: slots)
    }

    private func timetable(
        _ entries: [PersonalTimetable.Entry], hiding hidden: Set<String> = []
    ) -> PersonalTimetable {
        PersonalTimetable(name: "Primo semestre", yearCode: "2026", entries: entries,
                          builtAt: day(2026, 9, 1), hiddenCodes: hidden)
    }

    /// Monday 14 September 2026 to Wednesday 23 December, lessons on Monday
    /// 08:15–10:15: the shape the parser produces from the live page.
    private var oneTeaching: PersonalTimetable {
        timetable([entry(
            start: day(2026, 9, 14), end: day(2026, 12, 23),
            slots: [slot(weekday: 2, from: 8 * 60 + 15, to: 10 * 60 + 15)])])
    }

    @Test("Una fascia diventa un evento che parte dal primo giorno utile")
    func firstOccurrence() throws {
        let draft = try #require(CalendarExport.drafts(for: oneTeaching).first)

        #expect(calendar.component(.weekday, from: draft.start) == 2, "L’evento non cade di lunedì")
        #expect(draft.start == day(2026, 9, 14, hour: 8, minute: 15))
        #expect(draft.end == day(2026, 9, 14, hour: 10, minute: 15))
        #expect(draft.title == "Algorithms and Parallel Computing")
    }

    /// The first lesson of a Thursday slot is the Thursday *after* the term
    /// starts on a Monday, not the term's first day.
    @Test("Una fascia in un altro giorno parte dalla sua prima ricorrenza")
    func laterWeekday() throws {
        let timetable = timetable([entry(
            start: day(2026, 9, 14), end: day(2026, 12, 23),
            slots: [slot(weekday: 5, from: 10 * 60 + 15, to: 13 * 60 + 15)])])
        let draft = try #require(CalendarExport.drafts(for: timetable).first)

        #expect(draft.start == day(2026, 9, 17, hour: 10, minute: 15))
    }

    /// The recurrence ends the day *after* the last day of lessons, so a
    /// lesson on that last day is still inside it whatever time it starts.
    @Test("La ricorrenza finisce il giorno dopo l’ultima lezione")
    func repeatsUntil() throws {
        let draft = try #require(CalendarExport.drafts(for: oneTeaching).first)
        #expect(draft.repeatsUntil == day(2026, 12, 24))
        #expect(draft.repeatsUntil > day(2026, 12, 23, hour: 23, minute: 59))
    }

    @Test("Ogni fascia dell’insegnamento diventa un evento")
    func oneDraftPerSlot() {
        let timetable = timetable([entry(
            start: day(2026, 9, 14), end: day(2026, 12, 23),
            slots: [
                slot(weekday: 2, from: 8 * 60 + 15, to: 10 * 60 + 15),
                slot(weekday: 3, from: 10 * 60 + 15, to: 12 * 60 + 15),
            ])])
        #expect(CalendarExport.drafts(for: timetable).count == 2)
    }

    /// A teaching the student hid — the official agenda already has it, or it
    /// was added only to look — must not reach their calendar.
    @Test("Gli insegnamenti nascosti non vengono esportati")
    func hiddenAreLeftOut() {
        let visible = entry(code: "052496", start: day(2026, 9, 14), end: day(2026, 12, 23),
                            slots: [slot(weekday: 2, from: 8 * 60 + 15, to: 10 * 60 + 15)])
        let hidden = entry(code: "059156", title: "Analisi", start: day(2026, 9, 14),
                           end: day(2026, 12, 23),
                           slots: [slot(weekday: 3, from: 8 * 60 + 15, to: 10 * 60 + 15)])
        let drafts = CalendarExport.drafts(for: timetable([visible, hidden], hiding: ["059156"]))

        #expect(drafts.count == 1)
        #expect(drafts.first?.title == "Algorithms and Parallel Computing")
    }

    /// Without both dates there is nothing to repeat between, and a guess
    /// would put lessons in the student's calendar for a term that may not be
    /// theirs.
    @Test("Senza le date delle lezioni non si esporta niente")
    func withoutDates() {
        let slots = [slot(weekday: 2, from: 8 * 60 + 15, to: 10 * 60 + 15)]
        #expect(CalendarExport.drafts(for: timetable([entry(start: nil, end: day(2026, 12, 23), slots: slots)])).isEmpty)
        #expect(CalendarExport.drafts(for: timetable([entry(start: day(2026, 9, 14), end: nil, slots: slots)])).isEmpty)
    }

    /// A term shorter than a week that never reaches the slot's weekday has no
    /// lesson in it at all.
    @Test("Una fascia che non ricorre mai nel periodo non diventa un evento")
    func slotOutsideTheTerm() {
        let timetable = timetable([entry(
            // Monday to Wednesday; the slot is on Friday.
            start: day(2026, 9, 14), end: day(2026, 9, 16),
            slots: [slot(weekday: 6, from: 8 * 60 + 15, to: 10 * 60 + 15)])])
        #expect(CalendarExport.drafts(for: timetable).isEmpty)
    }

    @Test("Aula e indirizzo finiscono nel luogo, il docente nelle note")
    func locationAndNotes() throws {
        let draft = try #require(CalendarExport.drafts(for: oneTeaching).first)
        let location = try #require(draft.location)

        let notes = try #require(draft.notes)

        #expect(location.contains("3.1.4"))
        #expect(location.contains("Piazza Leonardo da Vinci 32"))
        #expect(notes.contains("Rossi Matteo"))
    }

    /// Lecture rooms are published late and change in the first weeks; an
    /// unknown room is no reason to leave the lesson out.
    @Test("Senza aula né indirizzo il luogo resta vuoto, e l’evento c’è lo stesso")
    func withoutARoom() throws {
        let timetable = timetable([entry(
            teacher: nil, start: day(2026, 9, 14), end: day(2026, 12, 23),
            slots: [slot(weekday: 2, from: 8 * 60 + 15, to: 10 * 60 + 15, room: nil, address: nil)])])
        let draft = try #require(CalendarExport.drafts(for: timetable).first)

        #expect(draft.location == nil)
        #expect(draft.notes == nil)
    }

    /// Lessons are in Milan; a student abroad must not get them shifted.
    @Test("Gli orari sono quelli di Roma, non quelli del telefono")
    func romeNotTheDevice() throws {
        let draft = try #require(CalendarExport.drafts(for: oneTeaching).first)
        var rome = Calendar(identifier: .gregorian)
        rome.timeZone = TimeZone(identifier: "Europe/Rome")!

        #expect(rome.component(.hour, from: draft.start) == 8)
        #expect(rome.component(.minute, from: draft.start) == 15)
    }
}
