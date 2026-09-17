import Foundation
import Testing
@testable import PoliVerse

/// What the exam sheet shows around a sitting, from data already loaded.
@Suite("Exam context")
struct ExamContextTests {
    private let now = Date(timeIntervalSince1970: 1_772_000_000)

    private func day(_ offset: Double) -> Date { now.addingTimeInterval(offset * 86400) }

    private func sitting(_ id: Int, at offset: Double, status: ExamStatus = .open) -> ExamSession {
        ExamSession(id: id, courseName: "Fisica", courseCode: "F1", teacher: nil, date: day(offset), room: nil,
                    enrolmentOpens: nil, enrolmentCloses: nil, enrolledCount: nil, kind: nil, status: status)
    }

    private func mark(_ value: Int, passed: Bool = true) -> ExamStatus {
        .graded(ExamGrade(value: value, text: String(value), passed: passed, refusable: true))
    }

    private func row(_ id: String, _ name: String, grade: Int?, cfu: Int, passed: Bool) -> LibrettoExam {
        LibrettoExam(id: id, name: name, grade: grade, hasLode: false, cfu: cfu, date: nil,
                     statusText: nil, isPassed: passed)
    }

    /// The libretto row is found by the sitting's code, or by its name where
    /// the codes disagree. A row whose id is blank — the libretto has no
    /// course code of its own, so an id can fall back to nothing — used to be
    /// handed to any sitting that also had none, which put a stranger's mark
    /// on the exam sheet.
    @Test("La riga di libretto è quella di questo esame, non la prima senza codice")
    func librettoRowIsNotTheFirstBlankOne() {
        let blank = row("", "Analisi", grade: 18, cfu: 10, passed: true)
        let mine = row("F1", "Fisica", grade: 28, cfu: 10, passed: true)
        let exam = ExamSession(id: 1, courseName: "Fisica", courseCode: "", teacher: nil,
                               date: day(-3), room: nil, enrolmentOpens: nil, enrolmentCloses: nil,
                               enrolledCount: nil, kind: nil, status: .open)

        let context = ExamContext(exam: exam, sittings: [], libretto: [blank, mine], now: now)
        #expect(context.librettoEntry?.name == "Fisica", "L’esame ha preso la riga sbagliata")
    }

    @Test("An unrecorded pass moves the CFU-weighted mean")
    func impact() throws {
        let libretto = [row("A", "Analisi", grade: 24, cfu: 10, passed: true),
                        row("F1", "Fisica", grade: nil, cfu: 10, passed: false)]
        let context = ExamContext(exam: sitting(1, at: -3, status: mark(30)), sittings: [], libretto: libretto, now: now)
        let impact = try #require(context.meanImpact)
        #expect(impact.before == 24)
        #expect(impact.after == 27)
    }

    @Test("A recorded mark or a fail has no impact to show")
    func noImpact() {
        let recorded = [row("A", "Analisi", grade: 24, cfu: 10, passed: true),
                        row("F1", "Fisica", grade: 30, cfu: 10, passed: true)]
        #expect(ExamContext(exam: sitting(1, at: -3, status: mark(30)), sittings: [], libretto: recorded, now: now)
            .meanImpact == nil)
        let pending = [row("A", "Analisi", grade: 24, cfu: 10, passed: true),
                       row("F1", "Fisica", grade: nil, cfu: 10, passed: false)]
        #expect(ExamContext(exam: sitting(1, at: -3, status: mark(15, passed: false)), sittings: [],
                            libretto: pending, now: now).meanImpact == nil)
    }

    @Test("Other sittings split into earlier attempts and ones ahead")
    func sittings() {
        let exam = sitting(1, at: 5)
        let all = [exam, sitting(2, at: -30, status: mark(15, passed: false)), sitting(3, at: 40), sitting(4, at: 20)]
        let context = ExamContext(exam: exam, sittings: all, libretto: [], now: now)
        #expect(context.previousAttempts.map(\.id) == [2])
        #expect(context.otherUpcoming.map(\.id) == [4, 3])
    }
}
