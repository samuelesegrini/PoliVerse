import Foundation
import Testing
@testable import PoliVerse

/// One sitting's story: what the app noticed, and the dates still ahead.
@Suite("Exam timeline")
struct ExamTimelineTests {
    private let now = Date(timeIntervalSince1970: 1_772_000_000)

    private func day(_ offset: Double) -> Date { now.addingTimeInterval(offset * 86400) }

    private var exam: ExamSession {
        ExamSession(
            id: 7, courseName: "Fisica", courseCode: "F1", teacher: nil,
            date: day(10), room: "B.3.2", enrolmentOpens: day(-5), enrolmentCloses: day(3),
            enrolledCount: nil, kind: nil, status: .enrolled)
    }

    private func update(_ kind: ExamUpdate.Kind, exam id: Int? = 7, course: String = "F1",
                        name: String = "Fisica", at offset: Double) -> ExamUpdate {
        ExamUpdate(kind: kind, examID: id, courseCode: course, courseName: name,
                   detectedAt: day(offset), source: .exams, evidence: "test",
                   wasEnrolled: true, examDate: day(10))
    }

    @Test("Updates and official dates are merged in order, future ones flagged")
    func merged() {
        let entries = ExamTimeline.entries(
            for: exam, sittings: [exam],
            updates: [update(.roomPublished, at: -1), update(.enrolled, at: -4)], now: now)
        #expect(entries.map(\.title) == [
            String(localized: "Apertura iscrizioni"),
            ExamUpdate(kind: .enrolled, examID: 7, courseCode: "F1", courseName: "", detectedAt: now,
                       source: .exams, evidence: "", wasEnrolled: true, examDate: nil).title,
            ExamUpdate(kind: .roomPublished, examID: 7, courseCode: "F1", courseName: "", detectedAt: now,
                       source: .exams, evidence: "", wasEnrolled: true, examDate: nil).title,
            String(localized: "Chiusura iscrizioni"),
            String(localized: "Esame"),
        ])
        #expect(entries.map(\.isFuture) == [false, false, false, true, true])
    }

    @Test("Other sittings' updates are left out")
    func filtered() {
        let entries = ExamTimeline.entries(
            for: exam, sittings: [exam], updates: [update(.roomPublished, exam: 8, at: -1)], now: now)
        #expect(entries.allSatisfy { $0.update == nil })
    }

    /// The libretto knows teachings, not sittings: its mark belongs to the
    /// sitting of that course that came before it.
    @Test("A recorded grade for the course after the sitting joins its timeline")
    func librettoGrade() {
        let after = update(.gradeRecorded, exam: nil, at: 15)
        let before = update(.gradeRecorded, exam: nil, at: -20)
        let other = update(.gradeRecorded, exam: nil, course: "X9", name: "Chimica", at: 15)
        let entries = ExamTimeline.entries(
            for: exam, sittings: [exam], updates: [after, before, other], now: day(16))
        #expect(entries.compactMap(\.update?.id) == [after.id])
    }

    /// Failed in January, passed in February: the February mark is not the
    /// January sitting's.
    @Test("A recorded grade belongs only to the latest sitting before it")
    func latestSittingOnly() {
        let later = ExamSession(
            id: 8, courseName: "Fisica", courseCode: "F1", teacher: nil, date: day(14),
            room: nil, enrolmentOpens: nil, enrolmentCloses: nil, enrolledCount: nil,
            kind: nil, status: .enrolled)
        let recorded = update(.gradeRecorded, exam: nil, at: 15)
        let first = ExamTimeline.entries(for: exam, sittings: [exam, later], updates: [recorded], now: day(16))
        let second = ExamTimeline.entries(for: later, sittings: [exam, later], updates: [recorded], now: day(16))
        #expect(first.allSatisfy { $0.update == nil })
        #expect(second.compactMap(\.update?.id) == [recorded.id])
    }
}
