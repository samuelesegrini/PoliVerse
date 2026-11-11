import Foundation
import Testing
@testable import PoliVerse

/// The pieces of the November 2026 performance pass that are plain logic:
/// how the career is laid over the one on screen while its six calls land,
/// which reads time out sooner, and the switch that brings Oggi's old drawing back.
@Suite("Performance pass")
struct PerformancePlanTests {
    // MARK: - Career, part by part

    /// One instant for every sample, so two builds of them compare equal.
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private static var shown: CareerSource.Payload {
        var payload = CareerSource.Payload(gradeBook: .sample(now: now), sessions: ExamSession.samples(now: now),
                                           libretto: LibrettoExam.samples(now: now))
        payload.gradeBook.examsGiven = 7
        payload.gradeBook.examsSubscribed = 9
        payload.gradeBook.examsPlanned = 20
        payload.officialTarget = 27
        return payload
    }

    @Test("A part not back yet keeps what was shown")
    func partialKeepsTheRest() {
        var parts = CareerSource.Parts()
        parts.add(.libretto([]))

        let partial = parts.payload(over: Self.shown)

        #expect(partial.libretto.isEmpty)
        #expect(partial.sessions == Self.shown.sessions)
        #expect(partial.gradeBook == Self.shown.gradeBook)
        #expect(partial.officialTarget == 27)
        #expect(!parts.isComplete)
    }

    /// The gradebook no longer carries exam counts; until the counters call
    /// answers, the counts on screen must not drop to zero.
    @Test("A new gradebook keeps the counts until the counters answer")
    func gradebookKeepsCounts() {
        var book = GradeBook.sample(now: Self.now)
        book.examsGiven = 0
        book.examsSubscribed = 0
        book.examsPlanned = 0
        var parts = CareerSource.Parts()
        parts.add(.book(book))

        let partial = parts.payload(over: Self.shown)

        #expect(partial.gradeBook.examsGiven == 7)
        #expect(partial.gradeBook.examsSubscribed == 9)
        #expect(partial.gradeBook.examsPlanned == 20)
    }

    /// Over an empty base the parts make exactly the career the six calls
    /// made together before: nothing from a previous career leaks into it.
    @Test("All six over an empty career make the whole record")
    func wholeOverEmpty() {
        var parts = CareerSource.Parts()
        parts.add(.book(.sample(now: Self.now)))
        parts.add(.counters(nil))
        parts.add(.sessions(ExamSession.samples(now: Self.now)))
        parts.add(.libretto(LibrettoExam.samples(now: Self.now)))
        parts.add(.target(nil))
        parts.add(.header(nil))

        let whole = parts.payload(over: CareerSource.Payload())

        #expect(parts.isComplete)
        #expect(whole.gradeBook.mean == GradeBook.sample(now: Self.now).mean)
        #expect(whole.sessions == ExamSession.samples(now: Self.now))
        #expect(whole.officialTarget == nil)
        #expect(whole.planHeader == nil)
        #expect(whole.gradeBook.examsPlanned > 0)
    }

    // MARK: - Timeouts

    @Test("Reads time out sooner than writes")
    func readTimeout() {
        #expect(PoliMiAPI.timeout(for: APIRequest(host: .app, path: "/v1/x")) == 15)
        #expect(PoliMiAPI.timeout(for: APIRequest(host: .app, path: "/v1/x", method: "PUT")) == 30)
    }

    // MARK: - Oggi's old drawing

    @Test("The legacy switch reads a list, all, or nothing")
    func legacySwitch() {
        #expect(TodayRendering.legacy(in: ["app"]).isEmpty)
        #expect(TodayRendering.legacy(in: ["app", "-TodayLegacy", "all"])
                == Set(TodayRendering.Piece.allCases))
        #expect(TodayRendering.legacy(in: ["app", "-TodayLegacy", "shadow,sheen,nonsense"])
                == [.shadow, .sheen])
        #expect(TodayRendering.legacy(in: ["app", "-TodayLegacy"]).isEmpty)
    }
}
