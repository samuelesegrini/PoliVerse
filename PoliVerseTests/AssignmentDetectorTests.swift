import Foundation
import Testing
@testable import PoliVerse

/// Assignments on WeBeep: new ones, moved deadlines, and the reminder the
/// evening before.
@Suite("Assignment detector")
struct AssignmentDetectorTests {
    private let now = PoliMiDate.time(10, on: Date(timeIntervalSince1970: 1_772_000_000))
    private let course = MaterialCourse(moodleID: 55, code: "097785", name: "Basi di Dati")

    private func assignment(_ id: Int, _ name: String = "Progetto", dueInDays days: Double?) -> MoodleAssignment {
        MoodleAssignment(id: id, name: name,
                         duedate: days.map { Int(now.addingTimeInterval($0 * 86400).timeIntervalSince1970) } ?? 0)
    }

    private var later: Date { now.addingTimeInterval(3600) }

    private func detect(_ previous: MaterialSnapshot?, _ assignments: [MoodleAssignment],
                        at time: Date? = nil) -> AssignmentDetector.Result {
        AssignmentDetector.detect(previous: previous, assignments: assignments, course: course, now: time ?? now)
    }

    @Test("The first reading is silent but already knows the deadlines")
    func baseline() {
        let result = detect(nil, [assignment(1, dueInDays: 5), assignment(2, dueInDays: nil)])
        #expect(result.updates.isEmpty)
        #expect(result.deadlines.map(\.id) == [1])   // no due date, nothing to remind
    }

    @Test("A new assignment with a deadline ahead is news")
    func added() {
        let base = detect(nil, [assignment(1, dueInDays: 5)])
        let result = detect(base.snapshot, [assignment(1, dueInDays: 5), assignment(2, "Relazione", dueInDays: 12)], at: later)
        #expect(result.updates.map(\.kind) == [.assignmentAdded])
        #expect(result.updates.first?.newValue == "Relazione")
        #expect(result.updates.first?.examDate == assignment(2, dueInDays: 12).due)
    }

    @Test("A new assignment already past its deadline is not")
    func addedPast() {
        let base = detect(nil, [assignment(1, dueInDays: 5)])
        #expect(detect(base.snapshot, [assignment(1, dueInDays: 5), assignment(2, dueInDays: -2)], at: later).updates.isEmpty)
    }

    @Test("A moved deadline is recorded with both dates, and again if it moves again")
    func moved() {
        let base = detect(nil, [assignment(1, dueInDays: 5)])
        let first = detect(base.snapshot, [assignment(1, dueInDays: 7)], at: later)
        #expect(first.updates.map(\.kind) == [.deadlineChanged])
        #expect(first.updates.first?.examDate == assignment(1, dueInDays: 7).due)
        let second = detect(first.snapshot, [assignment(1, dueInDays: 9)], at: later.addingTimeInterval(60))
        #expect(second.updates.first?.id != first.updates.first?.id)
    }

    @Test("An empty answer keeps what was known")
    func empty() {
        let base = detect(nil, [assignment(1, dueInDays: 5)])
        let result = detect(base.snapshot, [], at: later)
        #expect(result.updates.isEmpty)
        #expect(result.snapshot.versions == base.snapshot.versions)
    }

    @Test("A deadline moved into the past is not news")
    func movedPast() {
        let base = detect(nil, [assignment(1, dueInDays: 5)])
        #expect(detect(base.snapshot, [assignment(1, dueInDays: -1)], at: later).updates.isEmpty)
    }

    @Test("A stale snapshot with an empty answer keeps what it knew")
    func staleEmpty() {
        let base = detect(nil, [assignment(1, dueInDays: 30)])
        let stale = now.addingTimeInterval(MaterialChangeDetector.staleAfter + 60)
        let result = detect(base.snapshot, [], at: stale)
        #expect(result.snapshot.versions == base.snapshot.versions)
    }

    /// A new `assign` module is reported once, with its deadline.
    @Test("A new assignment module is not also counted as a new file")
    func notAFile() {
        let course = MaterialCourse(moodleID: 55, code: "097785", name: "Basi di Dati")
        func listing(_ modules: [MoodleModule]) -> [MaterialItem] {
            MaterialItem.items(from: [MoodleSection(id: 1, name: "Consegne", modules: modules)])
        }
        let lecture = MoodleModule(id: 1, name: "Lezione 1", modname: "resource", contents: [
            MoodleContent(type: "file", filename: "l1.pdf", filesize: 1, fileurl: nil, timemodified: 1, mimetype: nil)])
        let assign = MoodleModule(id: 2, name: "Consegna progetto", modname: "assign", contents: nil)
        let base = MaterialChangeDetector.detect(previous: nil, current: listing([lecture]), course: course,
                                                 context: .none, now: now)
        let result = MaterialChangeDetector.detect(previous: base.snapshot, current: listing([lecture, assign]),
                                                   course: course, context: .none, now: later)
        #expect(result.updates.isEmpty)
    }
}

@Suite("Assignment deadlines · policy and reminders")
struct AssignmentReminderTests {
    private let now = PoliMiDate.time(10, on: Date(timeIntervalSince1970: 1_772_000_000))

    /// §21 keeps WeBeep news Bassa, except a deadline brought forward.
    @Test("Only a deadline brought forward into the week pushes")
    func policy() {
        func decide(_ kind: ExamUpdate.Kind, dueInDays days: Double, wasInDays old: Double? = nil) -> ExamUpdate.Delivery? {
            let update = ExamUpdate(kind: kind, examID: nil, courseCode: "097785", courseName: "Basi di Dati",
                                    detectedAt: now, source: .webeep, evidence: "t",
                                    oldValue: old.map { String(Int(now.addingTimeInterval($0 * 86400).timeIntervalSince1970)) },
                                    newValue: "Progetto", wasEnrolled: false,
                                    examDate: now.addingTimeInterval(days * 86400))
            return ExamUpdatePolicy.decide([update], history: [], preferences: NotificationPreferences(), now: now)
                .first?.delivery
        }
        #expect(decide(.deadlineChanged, dueInDays: 3, wasInDays: 6) == .push)
        #expect(decide(.deadlineChanged, dueInDays: 5, wasInDays: 3) == .digest)   // later: more time
        #expect(decide(.deadlineChanged, dueInDays: 20, wasInDays: 25) == .digest)
        #expect(decide(.assignmentAdded, dueInDays: 3) == .digest)
    }

    @Test("A deadline is reminded the evening before its last day, when deadlines are on")
    func reminder() {
        let afternoon = PoliMiDate.time(15, on: now.addingTimeInterval(2 * 86400))
        let deadline = AssignmentDeadline(id: 1, courseCode: "097785", courseName: "Basi di Dati",
                                          name: "Progetto", due: afternoon)
        let plan = NotificationPlan.build(events: [], exams: [], assignments: [deadline],
                                          preferences: NotificationPreferences(), now: now)
        let reminder = plan.first { $0.id == "assignment-1" }
        #expect(reminder?.fireDate == PoliMiDate.time(18, on: now.addingTimeInterval(86400)))
        #expect(reminder?.body.contains("Progetto") == true)

        var off = NotificationPreferences()
        off.deadlines = false
        #expect(NotificationPlan.build(events: [], exams: [], assignments: [deadline], preferences: off, now: now).isEmpty)
    }

    /// Moodle's 00:00 deadline means the end of the day before.
    @Test("A midnight deadline is reminded two evenings ahead, not six hours before")
    func midnight() {
        let midnight = PoliMiDate.romeCalendar.startOfDay(for: now.addingTimeInterval(3 * 86400))
        let deadline = AssignmentDeadline(id: 2, courseCode: "097785", courseName: "Basi di Dati",
                                          name: "Relazione", due: midnight)
        let plan = NotificationPlan.build(events: [], exams: [], assignments: [deadline],
                                          preferences: NotificationPreferences(), now: now)
        #expect(plan.first?.fireDate == PoliMiDate.time(18, on: midnight.addingTimeInterval(-2 * 86400)))
    }

    @Test("Deadlines of a course not read for a fortnight are dropped from the log")
    func pruned() {
        let course = MaterialCourse(moodleID: 55, code: "097785", name: "Basi di Dati")
        let key = AssignmentDetector.courseKey(course)
        var log = ExamUpdateLog()
        log.materials = [key: MaterialSnapshot(versions: [:], notable: [:], takenAt: now)]
        log.deadlines = [key: [AssignmentDeadline(id: 1, courseCode: "097785", courseName: "Basi di Dati",
                                                  name: "Progetto", due: now.addingTimeInterval(30 * 86400))]]
        log.record([], state: ExamWatchState(), now: now.addingTimeInterval(86400))
        #expect(log.deadlines?[key]?.count == 1)
        log.record([], state: ExamWatchState(), now: now.addingTimeInterval(20 * 86400))
        #expect(log.deadlines?[key] == nil)
    }
}
