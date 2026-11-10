import Foundation
import Testing
@testable import PoliVerse

/// The section kit's decisions: what a section draws while its part is on its way,
/// how a reveal is timed, and the heights it remembers. Test names carry the id of
/// the requirement they check (docs/rasd).
@Suite("Sezioni in arrivo")
@MainActor
struct SectionKitTests {
    // MARK: - R5, R6, R2: what a section without rows draws

    @Test("R5: nei primi 300 ms niente, poi la riga d’attesa, dopo 3 s anche il passo in corso")
    func test_R5_waitingStages() {
        func stage(_ milliseconds: Int) -> SectionStage {
            SectionStage(.waiting(since: .milliseconds(milliseconds)), hasRows: false)
        }
        #expect(stage(0) == .quiet)
        #expect(stage(299) == .quiet)
        #expect(stage(300) == .waiting(showsStep: false))
        #expect(stage(2999) == .waiting(showsStep: false))
        #expect(stage(3000) == .waiting(showsStep: true))
        #expect(stage(60_000) == .waiting(showsStep: true))
    }

    @Test("R5: conta l’attesa più lunga tra quella della parte e quella della sezione sullo schermo")
    func test_R5_longestWaitCounts() {
        #expect(SectionStage(.waiting(since: .zero), hasRows: false, waited: .milliseconds(400))
                == .waiting(showsStep: false))
        #expect(SectionStage(.waiting(since: .seconds(4)), hasRows: false, waited: .zero)
                == .waiting(showsStep: true))
    }

    @Test("R5: l’attesa cambia aspetto a 300 ms e a 3 s, poi non più")
    func test_R5_nextChange() {
        #expect(SectionStage.nextChange(after: .zero) == .milliseconds(300))
        #expect(SectionStage.nextChange(after: .milliseconds(100)) == .milliseconds(200))
        #expect(SectionStage.nextChange(after: .milliseconds(300)) == .milliseconds(2700))
        #expect(SectionStage.nextChange(after: .seconds(3)) == nil)
    }

    @Test("R2: lo stato vuoto solo per una parte che ha risposto o ha una copia; mai durante l’attesa")
    func test_R2_emptyOnlyAfterAnswer() {
        #expect(SectionStage(.empty, hasRows: false) == .empty)
        #expect(SectionStage(.arrived, hasRows: false) == .empty)
        #expect(SectionStage(.held(age: 60), hasRows: false) == .empty)
        #expect(SectionStage(.waiting(since: .seconds(30)), hasRows: false) != .empty)
        #expect(SectionStage(.failed("x"), hasRows: false) != .empty)
    }

    @Test("R6: una parte fallita senza righe mostra il guasto; con righe già sullo schermo restano quelle")
    func test_R6_failureOnlyWithoutRows() {
        #expect(SectionStage(.failed("giù"), hasRows: false) == .failed("giù"))
        #expect(SectionStage(.failed("giù"), hasRows: true) == .content)
        #expect(SectionStage(.waiting(since: .seconds(10)), hasRows: true) == .content)
    }

    // MARK: - R8: the reveal's timing

    @Test("R8: qualunque sia il numero di righe, la comparsa finisce entro 0,6 s")
    func test_R8_revealEndsInTime() {
        for order in [0, 1, 5, 6, 7, 40, 1000] {
            #expect(RevealPlan.delay(order: order) + RevealPlan.item <= RevealPlan.total + 0.0001)
        }
        #expect(RevealPlan.delay(order: 0) == 0)
        #expect(RevealPlan.delay(order: 2) > RevealPlan.delay(order: 1))
        #expect(RevealPlan.delay(order: -3) == 0)
        #expect(RevealPlan.total == 0.6)
        #expect(RevealPlan.reduced == 0.2)
    }

    @Test("R8: i pezzi di un testo partono uno dopo l’altro e alla fine sono tutti al loro posto")
    func test_R8_textUnits() {
        let count = 12
        #expect(RevealPlan.progress(ofUnit: 0, of: count, at: 0) == 0)
        for index in 0..<count {
            #expect(RevealPlan.progress(ofUnit: index, of: count, at: 1) == 1)
        }
        // Half way, the first is in place and the last has not started.
        #expect(RevealPlan.progress(ofUnit: 0, of: count, at: 0.5) == 1)
        #expect(RevealPlan.progress(ofUnit: count - 1, of: count, at: 0.5) == 0)
        // Never ahead of the piece before it.
        for index in 1..<count {
            #expect(RevealPlan.progress(ofUnit: index, of: count, at: 0.6)
                    <= RevealPlan.progress(ofUnit: index - 1, of: count, at: 0.6))
        }
        #expect(RevealPlan.progress(ofUnit: 0, of: 1, at: 0.3) == 0.3)
    }

    // MARK: - R11: remembered heights

    @Test("R11: l’altezza di una sezione è ricordata tra un avvio e l’altro, e dimenticata all’uscita")
    func test_R11_heightIsRememberedAndForgotten() throws {
        let suite = "shape-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let memory = ShapeMemory(defaults: defaults)
        #expect(memory.height(for: "carriera.libretto") == nil)
        memory.remember(412.4, for: "carriera.libretto")
        memory.remember(0, for: "oggi.timetable")
        #expect(memory.height(for: "carriera.libretto") == 412)
        #expect(memory.height(for: "oggi.timetable") == nil)
        memory.write()

        let relaunched = ShapeMemory(defaults: defaults)
        #expect(relaunched.height(for: "carriera.libretto") == 412)

        relaunched.forget()
        #expect(relaunched.height(for: "carriera.libretto") == nil)
        #expect(ShapeMemory(defaults: defaults).height(for: "carriera.libretto") == nil)
    }

    // MARK: - Oggi: the timetable's phase

    @Test("R2: prima di qualsiasi risposta l’orario non può dirsi vuoto")
    func test_R2_agendaBeforeAnyAnswer() {
        let agenda = AgendaModel(account: StubAccount(matricola: String(Int.random(in: 10_000_000...99_999_999))))
        #expect(!SectionStage(agenda.phase(on: .now, isEmpty: true), hasRows: false, waited: .seconds(1))
            .isEmptyState)
    }

    @Test("R1, R2: la settimana che ha risposto è arrivata, e se non ha lezioni è vuota")
    func test_R1_R2_agendaAnsweredWeek() async {
        let agenda = AgendaModel(account: StubAccount(isSample: true))
        await agenda.load(around: .now)
        #expect(agenda.phase(on: .now, isEmpty: false) == .arrived)
        #expect(agenda.phase(on: .now, isEmpty: true) == .empty)
    }

    @Test("R6: se l’orario non arriva e non c’è una copia, la sezione dice il guasto")
    func test_R6_agendaFailure() async {
        let http = FixtureHTTP.failing(APIError.badStatus(500, body: "down"))
        let agenda = AgendaModel(account: StubAccount(matricola: String(Int.random(in: 10_000_000...99_999_999)),
                                                      http: http))
        await agenda.load(around: .now)
        guard case .failed = agenda.phase(on: .now, isEmpty: true) else {
            Issue.record("expected a failure, got \(agenda.phase(on: .now, isEmpty: true))")
            return
        }
    }
}

private extension SectionStage {
    var isEmptyState: Bool { self == .empty }
}
