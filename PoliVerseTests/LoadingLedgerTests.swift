import Foundation
import Testing
@testable import PoliVerse

/// The loading ledger: what it records about a request and a screen, what its
/// report says, and what it must never hold. Test names carry the id of the
/// requirement they check (docs/rasd).
@Suite("Registro dei caricamenti")
struct LoadingLedgerTests {
    private struct Boom: Error {}

    private let noon = Date(timeIntervalSince1970: 1_790_000_000)

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("loading-ledger.json")
    }

    /// Waits for the gate's fire-and-forget notes to land.
    private func requests(in ledger: LoadingLedger, count: Int) async -> [LedgerRequest] {
        for _ in 0..<400 {
            let held = await ledger.snapshot().requests
            if held.count >= count { return held }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await ledger.snapshot().requests
    }

    private func request(_ part: String = "career", host: String = "iae", ms: Int,
                         outcome: LedgerRequest.Outcome = .ok, daysAgo: Double = 0) -> LedgerRequest {
        LedgerRequest(part: part, host: host, start: noon.addingTimeInterval(-daysAgo * 86_400),
                      milliseconds: ms, outcome: outcome, speculative: false)
    }

    // MARK: - R34: every request is recorded

    @Test("R34: il varco registra parte, servizio, durata, esito e se era anticipata")
    func test_R34_gateRecordsWhatARequestWasFor() async throws {
        let ledger = LoadingLedger(file: nil)
        let gate = RequestGate(ledger: ledger)

        let value = try await LoadContext.$current.withValue(.init(part: "career", speculative: true)) {
            try await gate.run(host: "iae") {
                try await Task.sleep(for: .milliseconds(20))
                return 7
            }
        }
        #expect(value == 7)

        let noted = await requests(in: ledger, count: 1)
        let entry = try #require(noted.first)
        #expect(entry.part == "career")
        #expect(entry.host == "iae")
        #expect(entry.outcome == .ok)
        #expect(entry.speculative)
        #expect(entry.milliseconds >= 15)
    }

    @Test("R34: una richiesta fuori da un caricamento resta senza attribuzione, e l’errore passa invariato")
    func test_R34_unattributedRequestAndErrorPassThrough() async {
        let ledger = LoadingLedger(file: nil)
        let gate = RequestGate(ledger: ledger)

        await #expect(throws: Boom.self) {
            try await gate.run(host: "agenda") { throw Boom() }
        }

        let noted = await requests(in: ledger, count: 1)
        #expect(noted.first?.part == LoadContext.unattributed)
        #expect(noted.first?.outcome == .failed)
        #expect(noted.first?.speculative == false)
    }

    @Test("R34: scadenza, annullamento e guasto sono esiti distinti")
    func test_R34_outcomes() {
        #expect(RequestGate.outcome(of: URLError(.timedOut)) == .timedOut)
        #expect(RequestGate.outcome(of: APIError.transport(URLError(.timedOut))) == .timedOut)
        #expect(RequestGate.outcome(of: CancellationError()) == .cancelled)
        #expect(RequestGate.outcome(of: APIError.cancelled) == .cancelled)
        #expect(RequestGate.outcome(of: URLError(.cancelled)) == .cancelled)
        #expect(RequestGate.outcome(of: APIError.endpointGone("/x")) == .failed)
        #expect(RequestGate.outcome(of: URLError(.notConnectedToInternet)) == .failed)
    }

    // MARK: - R35, R37: screens and the report

    @Test("R35, R37: per schermata, mediana e 90° percentile di primo contenuto e completamento")
    func test_R35_R37_screenSpread() {
        var contents = LedgerContents()
        for value in 1...20 {
            contents.screens.append(.init(screen: "Carriera", opened: noon,
                                          firstContent: value * 10, complete: value * 100))
        }
        contents.screens.append(.init(screen: "Aule libere", opened: noon, firstContent: nil, complete: nil))

        let report = LedgerReport(contents, now: noon)
        let career = report.screens.first { $0.name == "Carriera" }
        #expect(career?.openings == 20)
        #expect(career?.isEnough == true)
        #expect(career?.firstContent == .init(median: 100, p90: 180))
        #expect(career?.complete == .init(median: 1000, p90: 1800))

        let rooms = report.screens.first { $0.name == "Aule libere" }
        #expect(rooms?.openings == 1)
        #expect(rooms?.isEnough == false)
        #expect(rooms?.firstContent == nil)
    }

    @Test("R37: per tipo di dato, tempi delle richieste riuscite e quota di fallite; le annullate non contano")
    func test_R37_partStatistics() {
        var contents = LedgerContents()
        contents.requests = [
            request(ms: 100), request(ms: 300), request(ms: 200),
            request(ms: 15_000, outcome: .timedOut),
            request(ms: 5, outcome: .cancelled),
            request("occupancy", host: "wsAule", ms: 40),
        ]

        let report = LedgerReport(contents, now: noon)
        let career = report.parts.first { $0.part == "career" }
        #expect(career?.count == 4)
        #expect(career?.duration == .init(median: 200, p90: 300))
        #expect(career?.failureShare == 0.25)
        #expect(career?.timeouts == 1)
        #expect(report.parts.map(\.part) == ["career", "occupancy"])
    }

    @Test("R37: conta solo gli ultimi 14 giorni")
    func test_R37_onlyTheLastFourteenDays() {
        var contents = LedgerContents()
        contents.requests = [request(ms: 100, daysAgo: 13), request(ms: 900, daysAgo: 15)]
        let report = LedgerReport(contents, now: noon)
        #expect(report.parts.first?.count == 1)
        #expect(report.parts.first?.duration?.median == 100)
    }

    @Test("R37: mediana e percentile per rango, anche con un solo valore")
    func test_R37_nearestRank() {
        #expect(LedgerReport.spread([]) == nil)
        #expect(LedgerReport.spread([42]) == .init(median: 42, p90: 42))
        #expect(LedgerReport.spread([4, 1, 3, 2]) == .init(median: 2, p90: 4))
    }

    // MARK: - R36: warm-ups used

    @Test("R36: la quota di richieste anticipate poi usate")
    func test_R36_speculativeShare() async {
        let ledger = LoadingLedger(file: nil, now: { Date(timeIntervalSince1970: 1_790_000_000) })
        await ledger.recordSpeculation(part: "occupancy", sent: 8, used: 0)
        await ledger.recordSpeculation(part: "occupancy", sent: 0, used: 2)

        let report = await ledger.report()
        #expect(report.speculativeSent == 8)
        #expect(report.speculativeUsed == 2)
        #expect(report.speculativeUsedShare == 0.25)
    }

    @Test("R36: senza richieste anticipate non c’è una quota")
    func test_R36_noShareWithoutWarmUps() {
        #expect(LedgerReport(LedgerContents(), now: noon).speculativeUsedShare == nil)
    }

    // MARK: - R38: nothing personal

    @Test("R38: una voce contiene solo i campi previsti, mai percorsi o matricole")
    func test_R38_entryHoldsNoContent() throws {
        let data = try JSONEncoder().encode(request(ms: 120))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["part", "host", "start", "milliseconds", "outcome", "speculative"])

        let screen = try JSONEncoder().encode(LedgerScreen(screen: "Carriera", opened: noon,
                                                           firstContent: 10, complete: 20))
        let screenObject = try #require(try JSONSerialization.jsonObject(with: screen) as? [String: Any])
        #expect(Set(screenObject.keys) == ["screen", "opened", "firstContent", "complete"])
    }

    // MARK: - R39, R40: kept on the phone, erased at sign-out

    @Test("R39: il registro sopravvive a un riavvio dell’app")
    func test_R39_persistsAcrossLaunches() async {
        let file = temporaryFile()
        let now: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_790_000_000) }
        let first = LoadingLedger(file: file, now: now)
        await first.record(request(ms: 120))
        await first.flush()

        let second = LoadingLedger(file: file, now: now)
        #expect(await second.snapshot().requests == [request(ms: 120)])
    }

    @Test("R40: all’uscita il registro è vuoto e il file non c’è più")
    func test_R40_eraseRemovesEverything() async {
        let file = temporaryFile()
        let ledger = LoadingLedger(file: file, now: { Date(timeIntervalSince1970: 1_790_000_000) })
        await ledger.record(LedgerScreen(screen: "Carriera", opened: noon, firstContent: 1, complete: 2))
        #expect(FileManager.default.fileExists(atPath: file.path))

        await ledger.erase()
        #expect(await ledger.snapshot().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - P8: bounded

    @Test("P8: il registro tiene al più le voci più recenti entro i limiti")
    func test_P8_capped() {
        var contents = LedgerContents()
        contents.requests = (0..<(LoadingLedger.requestCap + 50)).map { request(ms: $0) }
        contents.trim(now: noon)
        #expect(contents.requests.count == LoadingLedger.requestCap)
        #expect(contents.requests.last?.milliseconds == LoadingLedger.requestCap + 49)
    }

    // MARK: - The diagnostics report

    @Test("R37: il rapporto di diagnostica porta la sezione Caricamento")
    func test_R37_diagnosticsReportSection() {
        var contents = LedgerContents()
        contents.requests = [request(ms: 100), request(ms: 300)]
        contents.screens = [.init(screen: "Carriera", opened: noon, firstContent: 80, complete: 2700)]
        contents.speculation = [.init(part: "occupancy", at: noon, sent: 4, used: 3)]
        let text = Self.reportText(loading: LedgerReport(contents, now: noon))

        #expect(text.contains("## Caricamento (ultimi 14 giorni)"))
        #expect(text.contains("Schermata Carriera: 1 aperture (campione troppo piccolo)"))
        #expect(text.contains("primo contenuto: mediana 80 ms, p90 80 ms"))
        #expect(text.contains("career su iae: 2 richieste, mediana 100 ms, p90 300 ms, 0% fallite, 0 scadute"))
        #expect(text.contains("Richieste anticipate: 4, usate 75%"))
    }

    @Test("Senza dati la sezione Caricamento non compare")
    func emptyLedgerAddsNoSection() {
        #expect(!Self.reportText(loading: LedgerReport(LedgerContents(), now: noon)).contains("Caricamento"))
        #expect(!Self.reportText(loading: nil).contains("Caricamento"))
    }

    private static func reportText(loading: LedgerReport?) -> String {
        var snapshot = DiagnosticsSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_790_000_000),
            device: .init(appVersion: "2.4 (318)", system: "iOS 27.0", model: "iPhone17,1",
                          language: "it", lowPowerMode: false, sharedContainer: true,
                          online: true, expensive: false),
            account: .init(state: "Collegato", loginMethod: "SPID", matricola: "10712345",
                           tokenExpiresAt: nil, scopes: nil, profile: 1, authorised: true, cieError: nil),
            weBeep: .init(connected: true, courses: 6, failure: nil),
            services: [],
            addressesFromPolitecnico: true,
            probes: [],
            pending: .init(queued: 0, abandoned: []),
            background: .init(refreshPermission: "Consentito", lastRun: nil, notifications: "Consentite",
                              scheduledReminders: 3, nextReminder: nil, liveActivities: true,
                              widgetsKnowAccount: true, lastWidgetReload: nil,
                              spotlightItems: nil, spotlightIndexedAt: nil),
            performance: .init(metricReports: 2, diagnosticReports: 0, latest: nil))
        snapshot.loading = loading
        return DiagnosticsReport(snapshot, includesMatricola: false).text
    }
}
