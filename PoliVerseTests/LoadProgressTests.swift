import Foundation
import Testing
@testable import PoliVerse

/// The typed progress handle and the parts a resource declares. Test names carry
/// the id of the requirement they check (docs/rasd).
@Suite("Avanzamento per parti")
struct LoadProgressTests {
    private nonisolated struct Career: Resource {
        enum Part: Hashable, Sendable, CaseIterable { case libretto, sittings, header }
        static let id = "test-career"
        static let ttl: TimeInterval = 900
        static func maxAge(of part: Part) -> TimeInterval { part == .header ? 86_400 : ttl }
        @concurrent
        func fetch(_ key: Whole, env: Env, previous: [String]?) async throws -> [String] { [] }
    }

    private nonisolated struct Single: Resource {
        static let id = "test-single"
        @concurrent
        func fetch(_ key: Whole, env: Env, previous: String?) async throws -> String { "" }
    }

    @Test("R4: tra due letture resta solo l’istantanea più recente")
    func test_R4_newestSnapshotOnly() async {
        let progress = LoadProgress<Career>()
        progress.report(["a"], arrived: [.libretto])
        progress.report(["a", "b"], arrived: [.libretto, .sittings])
        progress.report(["a", "b", "c"], arrived: [.libretto, .sittings, .header], failed: [])
        progress.finish()

        var seen: [LoadProgress<Career>.Snapshot] = []
        for await snapshot in progress.snapshots { seen.append(snapshot) }
        #expect(seen.count == 1)
        #expect(seen.first?.value == ["a", "b", "c"])
        #expect(seen.first?.arrived == [.libretto, .sittings, .header])
    }

    @Test("R1: un’istantanea letta subito porta le parti arrivate e quelle fallite")
    func test_R1_snapshotCarriesArrivedAndFailed() async {
        let progress = LoadProgress<Career>()
        var iterator = progress.snapshots.makeAsyncIterator()

        progress.report(["a"], arrived: [.libretto], failed: [.sittings])
        let first = await iterator.next()
        #expect(first?.arrived == [.libretto])
        #expect(first?.failed == [.sittings])

        progress.report(["a", "b"], arrived: [.libretto, .header])
        let second = await iterator.next()
        #expect(second?.arrived == [.libretto, .header])
        #expect(second?.failed.isEmpty == true)
    }

    @Test("R15: ogni parte ha la sua età massima; senza dichiararla vale il ttl")
    func test_R15_maxAgePerPart() {
        #expect(Career.maxAge(of: .libretto) == 900)
        #expect(Career.maxAge(of: .header) == 86_400)
        #expect(Single.maxAge(of: Whole()) == Single.ttl)
    }

    @Test("Una risorsa senza parti ne ha una sola: Whole")
    func resourceWithoutPartsHasOne() {
        #expect(Single.Part.allCases == [Whole()])
        #expect(Career.Part.allCases.count == 3)
    }

    @Test("R2: lo stato vuoto si può mostrare solo dopo la risposta")
    func test_R2_emptyOnlyAfterAnswer() {
        #expect(LoadPhase.empty.mayShowEmptyState)
        #expect(!LoadPhase.waiting(since: .seconds(5)).mayShowEmptyState)
        #expect(!LoadPhase.failed("x").mayShowEmptyState)
        #expect(!LoadPhase.held(age: 60).mayShowEmptyState)
        #expect(LoadPhase.held(age: 60).showsContent)
        #expect(LoadPhase.arrived.showsContent)
        #expect(!LoadPhase.waiting(since: .zero).showsContent)
    }
}
