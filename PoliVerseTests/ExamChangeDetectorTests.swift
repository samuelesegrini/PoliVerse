import Foundation
import Testing
@testable import PoliVerse

/// What the app notices between two looks at the exam services.
///
/// The Politecnico sends no change feed, so every update is a comparison of
/// two snapshots. The comparison is the easy part; the rules that matter are
/// the ones about when **not** to compare — a first launch, a failed request,
/// a service that answers empty between sessions.
@Suite("Exam change detector")
struct ExamChangeDetectorTests {
    private let now = Date(timeIntervalSince1970: 1_772_000_000)   // 2026-02-25 08:53 UTC

    private func sitting(
        _ id: Int = 1, days: Int = 10, room: String? = nil,
        status: ExamStatus = .enrolled, corrections: Bool = false
    ) -> ExamSession {
        ExamSession(
            id: id, courseName: "Fisica", courseCode: "F1", teacher: nil,
            date: now.addingTimeInterval(TimeInterval(days * 86400)),
            room: room, enrolmentOpens: nil, enrolmentCloses: nil,
            enrolledCount: nil, kind: nil, status: status,
            hasCorrections: corrections)
    }

    private func grade(refusable: Bool = true) -> ExamStatus {
        .graded(ExamGrade(value: 27, text: "27", passed: true, refusable: refusable))
    }

    private func libretto(_ id: String, passed: Bool) -> LibrettoExam {
        LibrettoExam(id: id, name: "Fisica", grade: passed ? 27 : nil, hasLode: false,
                     cfu: 8, date: nil, statusText: nil, isPassed: passed)
    }

    /// The state after one look, to compare the next one against.
    private func baseline(_ sessions: [ExamSession], libretto: [LibrettoExam]? = nil) -> ExamWatchState {
        ExamChangeDetector.detect(previous: nil, sessions: sessions, libretto: libretto, now: now).state
    }

    private func kinds(_ previous: ExamWatchState?, _ sessions: [ExamSession]?,
                       libretto: [LibrettoExam]? = nil) -> [ExamUpdate.Kind] {
        ExamChangeDetector.detect(previous: previous, sessions: sessions, libretto: libretto, now: now)
            .updates.map(\.kind)
    }

    /// Otherwise the first launch announces every sitting the student has
    /// ever had as news.
    @Test("The first look is a silent baseline")
    func silentBaseline() {
        let result = ExamChangeDetector.detect(
            previous: nil, sessions: [sitting(room: "B.3.2")],
            libretto: [libretto("F1", passed: false)], now: now)
        #expect(result.updates.isEmpty)
        #expect(result.state.exams?[1] != nil)
    }

    @Test("A new sitting is discovered")
    func discovered() {
        #expect(kinds(baseline([sitting(1)]), [sitting(1), sitting(2, status: .notYetOpen)]) == [.discovered])
    }

    @Test("A room appearing is published; a different room is a change")
    func room() {
        #expect(kinds(baseline([sitting()]), [sitting(room: "B.3.2")]) == [.roomPublished])
        #expect(kinds(baseline([sitting(room: "B.3.2")]), [sitting(room: "L.26.01")]) == [.roomChanged])
    }

    @Test("A moved sitting is a date change")
    func dateChanged() {
        #expect(kinds(baseline([sitting(days: 10)]), [sitting(days: 12)]) == [.dateChanged])
    }

    @Test("Enrolment opening, and the student enrolling, are both noticed")
    func enrolment() {
        #expect(kinds(baseline([sitting(status: .notYetOpen)]), [sitting(status: .open)]) == [.enrolmentOpened])
        #expect(kinds(baseline([sitting(status: .open)]), [sitting(status: .enrolled)]) == [.enrolled])
        #expect(kinds(baseline([sitting(status: .enrolled)]), [sitting(status: .open)]) == [.unenrolled])
    }

    /// A mark usually arrives already refusable, and both facts matter.
    @Test("A published mark and its refusal window are separate facts")
    func grade() {
        let found = kinds(baseline([sitting()]), [sitting(status: grade())])
        #expect(found == [.gradePublished, .refusalOpened])
        #expect(kinds(baseline([sitting(status: grade(refusable: false))]),
                      [sitting(status: grade())]) == [.refusalOpened])
    }

    @Test("Corrections becoming available is noticed")
    func corrections() {
        #expect(kinds(baseline([sitting(status: grade())]),
                      [sitting(status: grade(), corrections: true)]) == [.correctionsAvailable])
    }

    @Test("The same snapshot twice says nothing")
    func idempotent() {
        let state = baseline([sitting(room: "B.3.2", status: grade())])
        #expect(kinds(state, [sitting(room: "B.3.2", status: grade())]).isEmpty)
    }

    /// A failed request is not an empty list.
    @Test("A failed load keeps the previous state and reports nothing")
    func failedLoad() {
        let state = baseline([sitting()])
        let result = ExamChangeDetector.detect(previous: state, sessions: nil, libretto: nil, now: now)
        #expect(result.updates.isEmpty)
        #expect(result.state == state)
    }

    /// "Utente non abilitato Code 6" arrives as an empty list between sessions.
    /// Reading that as every sitting withdrawn would be the worst notification
    /// this app could send.
    @Test("An empty answer is not every sitting withdrawn")
    func emptyAnswer() {
        let state = baseline([sitting(1), sitting(2)])
        let result = ExamChangeDetector.detect(previous: state, sessions: [], libretto: nil, now: now)
        #expect(result.updates.isEmpty)
        #expect(result.state.exams == state.exams)
    }

    @Test("A future sitting must be missing twice in a row to count as withdrawn")
    func withdrawnNeedsConfirmation() {
        let first = ExamChangeDetector.detect(
            previous: baseline([sitting(1), sitting(2)]), sessions: [sitting(1)], libretto: nil, now: now)
        #expect(first.updates.isEmpty)

        let second = ExamChangeDetector.detect(
            previous: first.state, sessions: [sitting(1)], libretto: nil, now: now)
        #expect(second.updates.map(\.kind) == [.withdrawn])
        #expect(second.updates.first?.examID == 2)
        #expect(second.state.exams?[2] == nil)
    }

    @Test("A sitting that comes back is not withdrawn")
    func reappears() {
        let missing = ExamChangeDetector.detect(
            previous: baseline([sitting(1), sitting(2)]), sessions: [sitting(1)], libretto: nil, now: now)
        let back = ExamChangeDetector.detect(
            previous: missing.state, sessions: [sitting(1), sitting(2)], libretto: nil, now: now)
        #expect(back.updates.isEmpty)
        let later = ExamChangeDetector.detect(
            previous: back.state, sessions: [sitting(1)], libretto: nil, now: now)
        #expect(later.updates.isEmpty)
    }

    /// Sittings leave `/v1/insegn` once they are over; that is normal.
    @Test("A past sitting disappearing is silent")
    func pastDisappears() {
        let result = ExamChangeDetector.detect(
            previous: baseline([sitting(1), sitting(2, days: -3)]), sessions: [sitting(1)],
            libretto: nil, now: now)
        #expect(result.updates.isEmpty)
        #expect(result.state.exams?[2] == nil)
    }

    @Test("A teaching moving to passed in the libretto is a recorded grade")
    func gradeRecorded() {
        let state = baseline([sitting()], libretto: [libretto("F1", passed: false)])
        let result = ExamChangeDetector.detect(
            previous: state, sessions: [sitting()], libretto: [libretto("F1", passed: true)], now: now)
        #expect(result.updates.map(\.kind) == [.gradeRecorded])
        #expect(result.updates.first?.courseCode == "F1")
    }

    @Test("An empty or failed libretto is not compared")
    func librettoDegraded() {
        let state = baseline([sitting()], libretto: [libretto("F1", passed: false)])
        #expect(kinds(state, [sitting()], libretto: []).isEmpty)
        #expect(kinds(state, [sitting()], libretto: nil).isEmpty)
        let after = ExamChangeDetector.detect(previous: state, sessions: [sitting()], libretto: nil, now: now)
        #expect(after.state.libretto == state.libretto)
    }

    /// The identifier is what stops the same change being logged twice when
    /// a foreground load and a background refresh both see it.
    @Test("Updates carry a stable identity and the context they were seen in")
    func identity() {
        let state = baseline([sitting()])
        let a = ExamChangeDetector.detect(previous: state, sessions: [sitting(room: "B.3.2")], libretto: nil, now: now)
        let b = ExamChangeDetector.detect(previous: state, sessions: [sitting(room: "B.3.2")], libretto: nil,
                                          now: now.addingTimeInterval(60))
        #expect(a.updates.first?.id == b.updates.first?.id)
        let update = a.updates.first
        #expect(update?.newValue == "B.3.2")
        #expect(update?.wasEnrolled == true)
        #expect(update?.examDate == sitting().date)
        #expect(update?.source == .exams)
    }
}
