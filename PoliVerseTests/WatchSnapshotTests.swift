import Foundation
import Testing
@testable import PoliVerse

/// What the phone decides is worth a wrist.
@Suite("Watch snapshot")
struct WatchSnapshotTests {
    /// Rome, which is the calendar the day is measured in.
    private let calendar = PoliMiDate.romeCalendar
    /// A fixed midday, so "today" is not the machine's clock.
    private let noon = Date(timeIntervalSince1970: 1_800_000_000)

    /// An agenda entry at an offset from noon.
    private func event(_ id: Int, _ hours: Double, kind: EventKind = .lecture,
                       lasting: TimeInterval = 7200) -> AgendaEvent {
        let start = noon.addingTimeInterval(hours * 3600)
        return AgendaEvent(id: id, title: "Corso \(id)", start: start,
                           end: start.addingTimeInterval(lasting), kind: kind, room: "3.0.1")
    }

    /// A sitting at an offset from noon.
    private func exam(_ id: Int, _ hours: Double?, status: ExamStatus = .open) -> ExamSession {
        ExamSession(id: id, courseName: "Esame \(id)", courseCode: "0\(id)", teacher: nil,
                    date: hours.map { noon.addingTimeInterval($0 * 3600) }, room: nil,
                    enrolmentOpens: nil, enrolmentCloses: nil, enrolledCount: nil,
                    kind: nil, status: status)
    }

    @Test("Only lectures and exams: a deadline is an instant with nowhere to sit on a day")
    func kinds() {
        let snapshot = WatchSnapshotBuilder.build(
            events: [event(1, 1), event(2, 2, kind: .exam), event(3, 3, kind: .deadline),
                     event(4, 4, kind: .news), event(5, 5, kind: .custom)],
            exams: [], day: noon, calendar: calendar)
        #expect(snapshot.entries.map(\.id) == [1, 2])
        #expect(snapshot.entries.map(\.isExam) == [false, true])
    }

    @Test("Entries overlapping the days sent are on them, in order")
    func day() {
        let snapshot = WatchSnapshotBuilder.build(
            // Yesterday, this morning, this evening, tomorrow, in four days.
            events: [event(1, -30), event(2, 2), event(3, -3), event(4, 30), event(5, 96)],
            exams: [], day: noon, calendar: calendar)
        #expect(snapshot.entries.map(\.id) == [3, 2, 4])
        #expect(snapshot.entries(on: noon, calendar: calendar).map(\.id) == [3, 2])
        #expect(snapshot.covers(noon, calendar: calendar))
    }

    @Test("The days ahead are grouped, with today's finished entries left out")
    func days() {
        let snapshot = WatchSnapshotBuilder.build(
            events: [event(1, -3), event(2, 2), event(3, 24)],
            exams: [], day: noon, calendar: calendar)
        let days = snapshot.days(from: noon, calendar: calendar)
        #expect(days.map { $0.entries.map(\.id) } == [[2], [3]])
    }

    @Test("A lecture already under way at midnight still belongs to the day it runs into")
    func overlapping() {
        let midnight = calendar.startOfDay(for: noon)
        let overnight = AgendaEvent(id: 9, title: "Lab", start: midnight.addingTimeInterval(-3600),
                                    end: midnight.addingTimeInterval(3600), kind: .lecture)
        let snapshot = WatchSnapshotBuilder.build(events: [overnight], exams: [], day: noon,
                                                  calendar: calendar)
        #expect(snapshot.entries.map(\.id) == [9])
    }

    @Test("The next exam is the soonest ungraded one from the day on")
    func nextExam() {
        let snapshot = WatchSnapshotBuilder.build(
            events: [],
            exams: [exam(1, 200), exam(2, -50), exam(3, nil),
                    exam(4, 100, status: .graded(ExamGrade(value: 28, text: "28", passed: true, refusable: false))),
                    exam(5, 150)],
            day: noon, calendar: calendar)
        #expect(snapshot.nextExam?.name == "Esame 5")
        #expect(snapshot.exams.map(\.id) == [5, 1])
    }

    @Test("At most three sittings, and enrolment is carried")
    func examLimit() {
        let snapshot = WatchSnapshotBuilder.build(
            events: [],
            exams: [exam(1, 10), exam(2, 20, status: .enrolled), exam(3, 30), exam(4, 40)],
            day: noon, calendar: calendar)
        #expect(snapshot.exams.map(\.id) == [1, 2, 3])
        #expect(snapshot.exams.map(\.isEnrolled) == [false, true, false])
    }

    @Test("No results yet is no average, not a confident zero")
    func emptyCareer() {
        let empty = CareerSnapshot(mean: 0, earnedCFU: 0, plannedCFU: 180, examsGiven: 0,
                                   examsPlanned: 20, nextExamName: nil, nextExamDate: nil)
        let snapshot = WatchSnapshotBuilder.build(events: [], exams: [], day: noon,
                                                  career: empty, calendar: calendar)
        #expect(snapshot.mean == nil)

        let some = CareerSnapshot(mean: 27.4, earnedCFU: 60, plannedCFU: 180, examsGiven: 6,
                                  examsPlanned: 20, nextExamName: nil, nextExamDate: nil)
        #expect(WatchSnapshotBuilder.build(events: [], exams: [], day: noon,
                                           career: some, calendar: calendar).mean == 27.4)
    }

    @Test("A snapshot from beyond the days it was sent for says so")
    func staleDay() {
        let snapshot = WatchSnapshotBuilder.build(events: [], exams: [], day: noon,
                                                  calendar: calendar)
        #expect(snapshot.covers(noon.addingTimeInterval(48 * 3600), calendar: calendar))
        #expect(snapshot.covers(noon.addingTimeInterval(72 * 3600), calendar: calendar) == false)
    }

    @Test("The current entry is the one under way, or the next one")
    func current() {
        let snapshot = WatchSnapshotBuilder.build(
            events: [event(1, -1), event(2, 4)], exams: [], day: noon, calendar: calendar)
        // Entry 1 runs from an hour before noon for two hours: it is on now.
        #expect(snapshot.current(at: noon)?.id == 1)
        // Once it is over, the next one.
        #expect(snapshot.current(at: noon.addingTimeInterval(2 * 3600))?.id == 2)
        // Past everything, nothing.
        #expect(snapshot.current(at: noon.addingTimeInterval(20 * 3600)) == nil)
    }

    @Test("A complication's timeline changes at every start and end still ahead")
    func changes() {
        let snapshot = WatchSnapshotBuilder.build(
            events: [event(1, -1), event(2, 1, lasting: 3600), event(3, 2)],
            exams: [], day: noon, calendar: calendar)
        let hour: TimeInterval = 3600
        // Entry 1 ends as entry 2 starts: one change, not two.
        #expect(snapshot.changes(after: noon) == [1, 2, 4].map { noon.addingTimeInterval($0 * hour) })
    }

    @Test("A complication's address names its entry and nothing else")
    func url() throws {
        let entry = try #require(WatchSnapshotBuilder.build(
            events: [event(42, 1)], exams: [], day: noon, calendar: calendar).entries.first)
        #expect(WatchSnapshot.Entry.id(from: entry.url) == 42)
        #expect(WatchSnapshot.Entry.id(from: URL(string: "poliverse://entry/42")!) == nil)
    }

    @Test("A payload from an older phone still decodes, without the new fields")
    func legacy() throws {
        let json = #"{"day":0,"entries":[],"nextExamName":"Fisica","earnedCFU":12,"sentAt":0}"#
        let snapshot = try JSONDecoder().decode(WatchSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.exams.isEmpty)
        #expect(snapshot.earnedCFU == 12)
        #expect(snapshot.plannedCFU == 0)
    }

    @Test("The Watch asks again after half an hour, or once the days sent have run out")
    func staleness() {
        let snapshot = WatchSnapshot(day: calendar.startOfDay(for: noon), entries: [], sentAt: noon)
        #expect(snapshot.needsRefresh(at: noon.addingTimeInterval(10 * 60)) == false)
        #expect(snapshot.needsRefresh(at: noon.addingTimeInterval(31 * 60)))
        let later = WatchSnapshot(day: calendar.startOfDay(for: noon), entries: [],
                                  sentAt: noon.addingTimeInterval(80 * 3600))
        #expect(later.needsRefresh(at: noon.addingTimeInterval(80 * 3600)))
    }
}
