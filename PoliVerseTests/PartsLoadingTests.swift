import Foundation
import Testing
@testable import PoliVerse

/// Loading by parts, end to end: a resource whose answers the test scripts goes
/// through the real ``Loader``, ``Query`` and ``OfflineStore``. The parts answer in
/// the order and with the outcome each test sets, and a part can be held back until
/// the test lets it go. Test names carry the id of the requirement they check
/// (docs/rasd).
@Suite("Caricamento per parti", .tags(.timing))
@MainActor
struct PartsLoadingTests {
    private nonisolated struct Boom: Error {}

    private nonisolated enum Letter: String, Hashable, Sendable, CaseIterable { case a, b, c }

    /// What the server does, as the test wrote it.
    private actor Script {
        nonisolated enum Outcome: Sendable { case value(Int), fail, crash }

        /// The parts each fetch was asked for, in order.
        private(set) var asked: [Set<Letter>] = []
        private var order: [Letter] = [.a, .b, .c]
        private var outcomes: [Letter: Outcome] = [.a: .value(1), .b: .value(1), .c: .value(1)]
        private var held: Set<Letter> = []

        func set(_ part: Letter, _ outcome: Outcome) { outcomes[part] = outcome }
        func answer(in order: [Letter]) { self.order = order }
        func hold(_ parts: Letter...) { held.formUnion(parts) }
        func release(_ parts: Letter...) { held.subtract(parts) }

        private func note(_ parts: Set<Letter>) { asked.append(parts) }
        private func isHeld(_ part: Letter) -> Bool { held.contains(part) }
        private func outcome(_ part: Letter) -> Outcome { outcomes[part] ?? .fail }
        private func sequence() -> [Letter] { order }

        /// One fetch: the parts asked for answer one after another, each reported
        /// as it does.
        nonisolated func run<R: Resource>(
            parts: Set<Letter>, over base: [String: Int]?, progress: LoadProgress<R>
        ) async throws -> LoadProgress<R>.Snapshot where R.Part == Letter, R.Value == [String: Int] {
            await note(parts)
            var value = base ?? [:]
            var arrived: Set<Letter> = []
            var failed: Set<Letter> = []
            for part in await sequence() where parts.contains(part) {
                while await isHeld(part) { try await Task.sleep(for: .milliseconds(2)) }
                switch await outcome(part) {
                case .value(let number):
                    value[part.rawValue] = number
                    arrived.insert(part)
                case .fail:
                    failed.insert(part)
                case .crash:
                    throw Boom()
                }
                progress.report(value, arrived: arrived, failed: failed)
            }
            guard !arrived.isEmpty else { throw Boom() }
            return .init(value: value, arrived: arrived, failed: failed)
        }
    }

    /// Three parts with the same age.
    private nonisolated struct Lettered: Resource {
        typealias Part = Letter
        static let id = "lettered"
        static let ttl: TimeInterval = 900
        let script: Script

        @concurrent
        func fetch(_ key: Whole, env: Env, previous: [String: Int]?) async throws -> [String: Int] {
            try await script.run(parts: Set(Letter.allCases), over: previous, progress: LoadProgress<Lettered>()).value
        }

        @concurrent
        func fetch(_ key: Whole, env: Env, parts: Set<Letter>, over held: [String: Int]?,
                   progress: LoadProgress<Lettered>) async throws -> LoadProgress<Lettered>.Snapshot {
            try await script.run(parts: parts, over: held, progress: progress)
        }
    }

    /// The same, but `c` is old after a twentieth of a second.
    private nonisolated struct Aging: Resource {
        typealias Part = Letter
        static let id = "aging"
        static let ttl: TimeInterval = 900
        static func maxAge(of part: Letter) -> TimeInterval { part == .c ? 0.05 : ttl }
        let script: Script

        @concurrent
        func fetch(_ key: Whole, env: Env, previous: [String: Int]?) async throws -> [String: Int] {
            try await script.run(parts: Set(Letter.allCases), over: previous, progress: LoadProgress<Aging>()).value
        }

        @concurrent
        func fetch(_ key: Whole, env: Env, parts: Set<Letter>, over held: [String: Int]?,
                   progress: LoadProgress<Aging>) async throws -> LoadProgress<Aging>.Snapshot {
            try await script.run(parts: parts, over: held, progress: progress)
        }
    }

    private static let env = Env(http: FixtureHTTP(), matricola: "111", isSample: false)
    private static let other = Env(http: FixtureHTTP(), matricola: "222", isSample: false)
    private static let all: Set<Letter> = [.a, .b, .c]

    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("parts-\(UUID().uuidString)", isDirectory: true)
    }

    private func files(in folder: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    /// Waits for something the test does not control the instant of.
    private func until(_ condition: () async -> Bool) async {
        for _ in 0..<1000 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func isWaiting(_ phase: LoadPhase) -> Bool {
        if case .waiting = phase { return true }
        return false
    }

    private func isFailed(_ phase: LoadPhase) -> Bool {
        if case .failed = phase { return true }
        return false
    }

    private func isHeldCopy(_ phase: LoadPhase) -> Bool {
        if case .held = phase { return true }
        return false
    }

    // MARK: - R1, R12: a part is there as soon as it answers

    @Test("R1: una parte arrivata è consegnata mentre le altre sono ancora in viaggio")
    func test_R1_partIsFiledWhileOthersAreOnTheirWay() async throws {
        let script = Script()
        await script.hold(.b, .c)
        let loader = Loader(Lettered(script: script), offline: OfflineStore(directory: folder()))
        let updates = await loader.updates(Whole(), env: Self.env)
        var iterator = updates.makeAsyncIterator()

        async let whole = loader.value(Whole(), env: Self.env)
        let first = await iterator.next()
        #expect(first?.value == ["a": 1])
        #expect(first?.arrived == [.a])
        #expect(first.map { Set($0.parts.keys) } == [.a])
        #expect(await loader.isDue(Whole(), env: Self.env))

        await script.release(.b, .c)
        let last = try await whole
        #expect(last.value == ["a": 1, "b": 1, "c": 1])
        #expect(Set(last.parts.keys) == Self.all)
        #expect(last.failed.isEmpty)
        #expect(await script.asked == [Self.all])
    }

    @Test("R1: le parti arrivano in qualsiasi ordine e il valore finale è lo stesso")
    func test_R1_anyOrderOfArrival() async throws {
        for order: [Letter] in [[.a, .b, .c], [.c, .a, .b], [.b, .c, .a]] {
            let script = Script()
            await script.answer(in: order)
            let loader = Loader(Lettered(script: script), offline: OfflineStore(directory: folder()))
            let snapshot = try await loader.value(Whole(), env: Self.env)
            #expect(snapshot.value == ["a": 1, "b": 1, "c": 1])
            #expect(snapshot.arrived == Self.all)
            #expect(await loader.isHeld(Whole(), env: Self.env))
        }
    }

    // MARK: - R14, R16: stored one by one, asked again one by one

    @Test("R14, R16: la parte arrivata prima di un guasto è salvata, e alla ripartenza si chiedono solo le altre")
    func test_R14_R16_arrivedPartSurvivesAndOnlyTheRestIsAsked() async throws {
        let folder = folder()
        let script = Script()
        await script.set(.b, .crash)
        let store = OfflineStore(directory: folder)
        let loader = Loader(Lettered(script: script), offline: store)

        await #expect(throws: Boom.self) {
            try await loader.value(Whole(), env: Self.env)
        }
        // In memory, the part that answered is kept.
        #expect(await loader.cached(Whole(), env: Self.env)?.value == ["a": 1])
        await store.flushed()
        #expect(files(in: folder) == ["111-lettered.json", "111-lettered.parts.json"])

        // The app is started again.
        await script.set(.b, .value(2))
        let again = Loader(Lettered(script: script), offline: OfflineStore(directory: folder))
        let restored = await again.restore(Whole(), env: Self.env)
        #expect(restored?.value == ["a": 1])
        #expect(restored.map { Set($0.parts.keys) } == [.a])
        #expect(restored?.isFresh == false)
        #expect(await again.dueParts(Whole(), env: Self.env) == [.b, .c])

        let whole = try await again.value(Whole(), env: Self.env)
        #expect(whole.value == ["a": 1, "b": 2, "c": 1])
        #expect(await script.asked.last == [.b, .c])
        // Restored, not answered in this run.
        #expect(whole.arrived == [.b, .c])
    }

    @Test("R16: un caricamento interrotto riparte chiedendo solo ciò che non era arrivato")
    func test_R16_cancelledLoadResumesWithMissingParts() async throws {
        let script = Script()
        await script.hold(.b)
        let loader = Loader(Lettered(script: script), offline: OfflineStore(directory: folder()))
        let updates = await loader.updates(Whole(), env: Self.env)
        var iterator = updates.makeAsyncIterator()

        let loading = Task { try await loader.value(Whole(), env: Self.env) }
        _ = await iterator.next()
        loading.cancel()
        _ = await loading.result
        await loader.settle()

        await script.release(.b)
        let whole = try await loader.value(Whole(), env: Self.env)
        #expect(whole.value == ["a": 1, "b": 1, "c": 1])
        #expect(await script.asked == [Self.all, [.b, .c]])
    }

    // MARK: - R15: each part has its own age

    @Test("R15: un aggiornamento chiede solo le parti più vecchie della loro età massima")
    func test_R15_refreshAsksOnlyForOldParts() async throws {
        let script = Script()
        let loader = Loader(Aging(script: script), offline: OfflineStore(directory: folder()))
        _ = try await loader.value(Whole(), env: Self.env)

        try await Task.sleep(for: .milliseconds(80))
        #expect(await loader.dueParts(Whole(), env: Self.env) == [.c])
        #expect(await !loader.isHeld(Whole(), env: Self.env))

        await script.set(.a, .value(9))
        await script.set(.c, .value(2))
        let refreshed = try await loader.value(Whole(), env: Self.env)
        #expect(await script.asked == [Self.all, [.c]])
        #expect(refreshed.value == ["a": 1, "b": 1, "c": 2])
    }

    @Test("R15, R20: con tutte le parti fresche non parte nessuna richiesta")
    func test_R15_R20_freshPartsAreServedWithoutAsking() async throws {
        let script = Script()
        let loader = Loader(Lettered(script: script), offline: OfflineStore(directory: folder()))
        _ = try await loader.value(Whole(), env: Self.env)
        #expect(await loader.dueParts(Whole(), env: Self.env).isEmpty)
        #expect(await !loader.isDue(Whole(), env: Self.env))

        _ = try await loader.value(Whole(), env: Self.env)
        #expect(await script.asked.count == 1)

        // Pull to refresh asks for everything.
        _ = try await loader.value(Whole(), env: Self.env, force: true)
        #expect(await script.asked.last == Self.all)
    }

    // MARK: - R6: a failure stays in its section

    @Test("R6: una parte fallita non tocca le altre e non è richiesta di nuovo subito")
    func test_R6_failedPartLeavesTheOthersAlone() async throws {
        let script = Script()
        await script.set(.b, .fail)
        let loader = Loader(Lettered(script: script), offline: OfflineStore(directory: folder()))

        let snapshot = try await loader.value(Whole(), env: Self.env)
        #expect(snapshot.value == ["a": 1, "c": 1])
        #expect(snapshot.failed == [.b])
        #expect(Set(snapshot.parts.keys) == [.a, .c])
        #expect(await !loader.isHeld(Whole(), env: Self.env))
        // Not hammered: the failed part waits its minute.
        #expect(await loader.dueParts(Whole(), env: Self.env).isEmpty)

        // The student asks again.
        await script.set(.b, .value(3))
        let retried = try await loader.value(Whole(), env: Self.env, force: true)
        #expect(retried.value == ["a": 1, "b": 3, "c": 1])
        #expect(retried.failed.isEmpty)
        #expect(await loader.isHeld(Whole(), env: Self.env))
    }

    @Test("R6, R23: un guasto non toglie mai ciò che era già mostrato")
    func test_R6_R23_failureNeverRemovesContent() async throws {
        let script = Script()
        let loader = Loader(Lettered(script: script), offline: OfflineStore(directory: folder()))
        _ = try await loader.value(Whole(), env: Self.env)

        // One part fails on a refresh: its old content stays.
        await script.set(.a, .value(2))
        await script.set(.b, .fail)
        let partly = try await loader.value(Whole(), env: Self.env, force: true)
        #expect(partly.value == ["a": 2, "b": 1, "c": 1])
        #expect(partly.failed == [.b])
        #expect(Set(partly.parts.keys) == Self.all)

        // The whole refresh fails: everything stays.
        await script.set(.a, .crash)
        await #expect(throws: Boom.self) {
            try await loader.value(Whole(), env: Self.env, force: true)
        }
        #expect(await loader.cached(Whole(), env: Self.env)?.value == ["a": 2, "b": 1, "c": 1])
    }

    // MARK: - R40: another account, and sign-out

    @Test("R14, R40: le copie sono dell’account, e all’uscita non ne resta nessuna")
    func test_R14_R40_copiesBelongToTheAccountAndGoAtSignOut() async throws {
        let folder = folder()
        let script = Script()
        let store = OfflineStore(directory: folder)
        let loader = Loader(Lettered(script: script), offline: store)
        _ = try await loader.value(Whole(), env: Self.env)

        #expect(await loader.cached(Whole(), env: Self.other) == nil)
        #expect(await loader.dueParts(Whole(), env: Self.other) == Self.all)
        await store.flushed()
        #expect(files(in: folder) == ["111-lettered.json", "111-lettered.parts.json"])

        // Sign-out.
        await loader.clear()
        store.clear(account: "111")
        #expect(await loader.cached(Whole(), env: Self.env) == nil)
        #expect(files(in: folder).isEmpty)
        let again = Loader(Lettered(script: script), offline: OfflineStore(directory: folder))
        #expect(await again.restore(Whole(), env: Self.env) == nil)
    }

    // MARK: - R2, R3: what a section may say

    @Test("R2, R3: lo stato vuoto solo dopo la risposta, il valore calcolato solo con tutte le parti")
    func test_R2_R3_emptyStateAndComputedValueWaitForTheirParts() async {
        let script = Script()
        await script.answer(in: [.b, .a, .c])
        await script.hold(.a)
        let query = Query(Lettered(script: script), account: StubAccount(matricola: "111"),
                          offline: OfflineStore(directory: folder()))

        // Before anything was asked, nothing may be said.
        #expect(!query.phase(of: .a, isEmpty: true).mayShowEmptyState)

        let loading = Task { await query.load() }
        await until { query.has(.b) }

        #expect(query.phase(of: .b, isEmpty: true) == .empty)
        #expect(query.phase(of: .b, isEmpty: false) == .arrived)
        #expect(isWaiting(query.phase(of: .a, isEmpty: true)))
        #expect(!query.phase(of: .a, isEmpty: true).mayShowEmptyState)
        #expect(query.pending == [.a, .c])
        #expect(!query.has(.a, .b))
        #expect(query.value == ["b": 1])

        await script.release(.a)
        await loading.value
        #expect(query.phase(of: .a, isEmpty: true) == .empty)
        #expect(query.has(.a, .b, .c))
        #expect(query.pending.isEmpty)
        #expect(query.value == ["a": 1, "b": 1, "c": 1])
    }

    @Test("R6: la sezione della parte fallita dice il guasto, le altre mostrano il contenuto")
    func test_R6_sectionOfAFailedPartSaysSo() async {
        let script = Script()
        await script.set(.b, .fail)
        let query = Query(Lettered(script: script), account: StubAccount(matricola: "111"),
                          offline: OfflineStore(directory: folder()))
        await query.load()

        #expect(query.errorMessage == nil)
        #expect(query.failed == [.b])
        #expect(isFailed(query.phase(of: .b, isEmpty: true)))
        #expect(query.phase(of: .a, isEmpty: false) == .arrived)
        #expect(query.phase(of: .c, isEmpty: false) == .arrived)
    }

    @Test("R23: una copia salvata è mostrata come tale, con la sua età, senza richieste")
    func test_R23_storedCopyIsShownAsHeld() async {
        let folder = folder()
        let script = Script()
        let store = OfflineStore(directory: folder)
        let first = Query(Lettered(script: script), account: StubAccount(matricola: "111"), offline: store)
        await first.load()
        await store.flushed()

        // The app is started again within the parts' max age.
        let second = Query(Lettered(script: script), account: StubAccount(matricola: "111"),
                           offline: OfflineStore(directory: folder))
        await second.load()
        #expect(second.value == ["a": 1, "b": 1, "c": 1])
        #expect(isHeldCopy(second.phase(of: .a, isEmpty: false)))
        #expect(second.arrived.isEmpty)
        #expect(await script.asked.count == 1)
    }

    // MARK: - The career, the first resource by parts

    @Test("R1, R3, R6: carriera con il solo libretto dei voti: le altre sezioni dicono il guasto, la media dal libretto non compare")
    func test_R1_R3_R6_careerWithOnlyTheGradeBook() async throws {
        let http = FixtureHTTP(["/v1/io-e-polimi/111": Data("{\"mean\": 27.5, \"given_cfu\": 60, \"planned_cfu\": 180}".utf8)],
                               fallback: .failure(APIError.badStatus(500, body: "down")))
        let career = CareerModel(account: StubAccount(matricola: "111", http: http), feed: UpdateFeed(),
                                 offline: OfflineStore(directory: folder()))
        #expect(!career.hasAnswer)

        await career.load()

        #expect(career.hasAnswer)
        #expect(career.gradeBook.mean == 27.5)
        #expect(career.errorMessage == nil)
        #expect(isFailed(career.sittingsPhase))
        #expect(isFailed(career.librettoPhase))
        #expect(!career.sittingsPhase.mayShowEmptyState)
        #expect(career.weightedMean == nil)
        #expect(await http.requests.count == 6)

        // Opening the screen again at once does not ask the failed parts again.
        await career.load()
        #expect(await http.requests.count == 6)
    }

    @Test("R15, R16: la carriera chiede di nuovo solo le parti mancanti")
    func test_R15_R16_careerAsksOnlyForMissingParts() async throws {
        let http = FixtureHTTP(["/v1/io-e-polimi/111": Data("{\"mean\": 27.5, \"given_cfu\": 60, \"planned_cfu\": 180}".utf8)],
                               fallback: .failure(APIError.badStatus(500, body: "down")))
        let env = Env(http: http, matricola: "111", isSample: false)
        let loader = Loader(CareerSource(), offline: OfflineStore(directory: folder()))

        let snapshot = try await loader.value(Whole(), env: env)
        #expect(snapshot.arrived == [.book])
        #expect(snapshot.failed == [.counters, .sittings, .libretto, .target, .header])
        #expect(await loader.dueParts(Whole(), env: env).isEmpty)
        #expect(CareerSource.maxAge(of: .header) > CareerSource.maxAge(of: .libretto))
    }
}
