import Foundation
import Synchronization
import Testing
@testable import PoliVerse

/// A part that is slow and a service that stops answering: the deadline after
/// which a stored copy stands in, and the pause a host gets after two timeouts.
@Suite("Parti lente e servizi che non rispondono")
struct SlowPartsPolicyTests {
    private let start = ContinuousClock.now

    @Test("R17: prima di 4 s si aspetta, dopo si mostra la copia salvata")
    func test_R17_deadline() {
        let policy = DeadlinePolicy()
        #expect(policy.decision(waited: .seconds(3.9), hasStoredCopy: true) == .wait)
        #expect(policy.decision(waited: .seconds(4), hasStoredCopy: true) == .showStored)
        #expect(policy.decision(waited: .seconds(60), hasStoredCopy: true) == .showStored)
    }

    @Test("R17: senza una copia salvata si continua ad aspettare")
    func test_R17_nothingToShowInstead() {
        #expect(DeadlinePolicy().decision(waited: .seconds(60), hasStoredCopy: false) == .wait)
    }

    @Test("R17: l'etichetta dice l'età della copia")
    func test_R17_lateLabelSaysTheAge() {
        #expect(LateLabel.text(age: 20).contains("poco fa"))
        #expect(LateLabel.text(age: 600).contains("10 min"))
        #expect(LateLabel.text(age: 3 * 3600).contains("3 ore"))
        #expect(LateLabel.text(age: 3 * 86_400).contains("3 giorni"))
    }

    @Test("R18: due timeout di fila fermano il servizio per 30 s, uno solo no")
    func test_R18_twoTimeoutsPause() {
        var breaker = HostBreaker()
        #expect(breaker.note(.timedOut, host: "iae", at: start) == nil)
        #expect(!breaker.isPaused("iae", at: start))
        #expect(breaker.note(.timedOut, host: "iae", at: start) == .paused(.seconds(30)))
        #expect(breaker.isPaused("iae", at: start.advanced(by: .seconds(29))))
        #expect(!breaker.isPaused("iae", at: start.advanced(by: .seconds(30))))
    }

    @Test("R18: una risposta in mezzo azzera il conto, anche se è un errore")
    func test_R18_anAnswerResetsTheCount() {
        var breaker = HostBreaker()
        _ = breaker.note(.timedOut, host: "iae", at: start)
        #expect(breaker.note(.failed, host: "iae", at: start) == .resumed)
        #expect(breaker.note(.timedOut, host: "iae", at: start) == nil)
        #expect(!breaker.isPaused("iae", at: start))
        _ = breaker.note(.timedOut, host: "iae", at: start)
        #expect(breaker.note(.ok, host: "iae", at: start) == .resumed)
        #expect(!breaker.isPaused("iae", at: start))
    }

    @Test("R18: la pausa è del servizio che non risponde, non degli altri")
    func test_R18_pauseIsPerHost() {
        var breaker = HostBreaker()
        _ = breaker.note(.timedOut, host: "iae", at: start)
        _ = breaker.note(.timedOut, host: "iae", at: start)
        #expect(breaker.isPaused("iae", at: start))
        #expect(!breaker.isPaused("agenda", at: start))
        #expect(breaker.note(.ok, host: "agenda", at: start) == nil)
    }

    @Test("R18: una richiesta annullata non dice niente del servizio")
    func test_R18_cancellationIsNotATimeout() {
        var breaker = HostBreaker()
        _ = breaker.note(.timedOut, host: "iae", at: start)
        #expect(breaker.note(.cancelled, host: "iae", at: start) == nil)
        #expect(breaker.note(.timedOut, host: "iae", at: start) == .paused(.seconds(30)))
    }

    @Test("R18: dopo la pausa, un altro timeout ferma di nuovo il servizio subito")
    func test_R18_pausedAgainAfterAnotherTimeout() {
        var breaker = HostBreaker()
        _ = breaker.note(.timedOut, host: "iae", at: start)
        _ = breaker.note(.timedOut, host: "iae", at: start)
        let later = start.advanced(by: .seconds(31))
        #expect(!breaker.isPaused("iae", at: later))
        #expect(breaker.note(.timedOut, host: "iae", at: later) == .paused(.seconds(30)))
        #expect(breaker.isPaused("iae", at: later.advanced(by: .seconds(1))))
    }
}

/// The gate with a server that does not answer.
@Suite("Varco: servizio in pausa", .tags(.timing))
struct SlowHostGateTests {
    /// What the gate told about pauses, and the clock it reads.
    private nonisolated final class Recorder: Sendable {
        let changes = Mutex<[String]>([])
        let offset = Mutex<Duration>(.zero)
        let sent = Mutex(0)
        let start = ContinuousClock.now

        var now: @Sendable () -> ContinuousClock.Instant {
            { [self] in start.advanced(by: offset.withLock { $0 }) }
        }
        var note: @Sendable (String, Duration?) -> Void {
            { [self] host, pause in changes.withLock { $0.append(pause == nil ? "\(host) resumed" : "\(host) paused") } }
        }
        func advance(by duration: Duration) { offset.withLock { $0 += duration } }
    }

    private func gate(_ recorder: Recorder) -> RequestGate {
        RequestGate(ledger: LoadingLedger(file: nil), now: recorder.now, pauseChanged: recorder.note)
    }

    /// A request to a server that never answers within the timeout.
    private func timeOut(_ gate: RequestGate, _ recorder: Recorder, host: String = "iae") async {
        _ = try? await gate.run(host: host) { () async throws -> Int in
            recorder.sent.withLock { $0 += 1 }
            throw URLError(.timedOut)
        }
    }

    @Test("R18: dopo due timeout le richieste al servizio falliscono subito, senza partire")
    func test_R18_pausedHostIsNotAsked() async {
        let recorder = Recorder()
        let gate = gate(recorder)
        await timeOut(gate, recorder)
        await timeOut(gate, recorder)
        #expect(recorder.sent.withLock { $0 } == 2)
        #expect(recorder.changes.withLock { $0 } == ["iae paused"])

        await #expect(throws: HostPaused(host: "iae")) {
            try await gate.run(host: "iae") { () async throws -> Int in
                recorder.sent.withLock { $0 += 1 }
                return 1
            }
        }
        #expect(recorder.sent.withLock { $0 } == 2)
        // Another service is asked as usual.
        let other = try? await gate.run(host: "agenda") { 7 }
        #expect(other == 7)
    }

    @Test("R18: passati 30 s il servizio è chiesto di nuovo, e una risposta lo riapre")
    func test_R18_askedAgainAfterThePause() async throws {
        let recorder = Recorder()
        let gate = gate(recorder)
        await timeOut(gate, recorder)
        await timeOut(gate, recorder)
        recorder.advance(by: .seconds(29))
        #expect(await gate.isPaused("iae"))
        recorder.advance(by: .seconds(1))
        #expect(!(await gate.isPaused("iae")))

        let value = try await gate.run(host: "iae") { 3 }
        #expect(value == 3)
        #expect(recorder.changes.withLock { $0 } == ["iae paused", "iae resumed"])
    }

    @Test("R18: quello che fa lo studente parte anche con il servizio in pausa")
    func test_R18_actionsAreAlwaysSent() async throws {
        let recorder = Recorder()
        let gate = gate(recorder)
        await timeOut(gate, recorder)
        await timeOut(gate, recorder)
        let value = try await gate.run(host: "iae", pausable: false) { 5 }
        #expect(value == 5)
    }

    @Test("R18: l'errore di un servizio in pausa lo nomina come lo conosce lo studente")
    func test_R18_errorNamesTheService() {
        #expect(HostPaused(host: "agenda").localizedDescription.contains(HostPauses.name(of: "agenda")))
        #expect(HostPauses.name(of: "sconosciuto") == "sconosciuto")
    }
}

/// The services named on screen while they are paused.
@Suite("Servizi in pausa sullo schermo", .tags(.timing))
@MainActor
struct HostPausesTests {
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("R18: la riga di stato dice quale servizio non risponde, e smette quando risponde")
    func test_R18_statusNamesTheService() {
        let pauses = HostPauses()
        let status = DataStatus(session: Session(), network: NetworkMonitor(), pauses: pauses)
        #expect(status.state == .idle)

        pauses.set("agenda", pausedFor: .seconds(30))
        #expect(status.state == .notResponding([HostPauses.name(of: "agenda")]))
        #expect(!status.isQuiet)
        #expect(status.badge == nil)

        pauses.set("agenda", pausedFor: nil)
        #expect(status.state == .idle)
    }

    @Test("R18: due servizi con lo stesso nome sullo schermo sono detti una volta")
    func test_R18_namesAreSaidOnce() {
        let pauses = HostPauses()
        pauses.set("maps", pausedFor: .seconds(30))
        pauses.set("wsAule", pausedFor: .seconds(30))
        pauses.set("iae", pausedFor: .seconds(30))
        #expect(pauses.names == [HostPauses.name(of: "maps"), HostPauses.name(of: "iae")].sorted())
    }

    @Test("R18: la pausa finisce da sola quando il suo tempo è passato")
    func test_R18_pauseEndsByItself() async {
        let pauses = HostPauses()
        pauses.set("iae", pausedFor: .milliseconds(40))
        #expect(pauses.hosts == ["iae"])
        await until { pauses.hosts.isEmpty }
        #expect(pauses.hosts.isEmpty)
    }
}
