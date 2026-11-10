import Foundation
import Testing
@testable import PoliVerse

@Suite("Public resource persistence")
struct PublicResourceTests {
    private actor Fetches {
        var count = 0
        func next() -> Int { count += 1; return count }
    }

    private nonisolated struct PublicValue: Resource {
        typealias Value = Int
        static let id = "public-test"
        static let persistence = Persistence.publicDisk
        static let ttl = TimeInterval.infinity
        let name: String
        let fetches: Fetches
        func storageName(for key: Whole) -> String { name }
        @concurrent
        func fetch(_ key: Whole, env: Env, previous: Int?) async throws -> Int {
            await fetches.next()
        }
    }

    @Test func restoresWithoutStudentAndKeepsFreshness() async throws {
        let name = "test-public-\(UUID().uuidString)"
        defer { remove(name) }
        let resource = PublicValue(name: name, fetches: Fetches())
        let env = Env.public(FixtureHTTP())
        let first = Loader(resource)
        _ = try await first.value(Whole(), env: env)
        let second = Loader(resource)
        let restored = await second.restore(Whole(), env: env)
        #expect(restored?.value == 1)
        #expect(await second.isDue(Whole(), env: env) == false)
        #expect(await second.isHeld(Whole(), env: env))
        #expect(try await second.value(Whole(), env: env).value == 1)
    }

    @Test func forcedRefreshReplacesRestoredPublicCopy() async throws {
        let name = "test-public-\(UUID().uuidString)"
        defer { remove(name) }
        DiskCache.save(42, as: name)
        let resource = PublicValue(name: name, fetches: Fetches())
        let env = Env.public(FixtureHTTP())
        let loader = Loader(resource)
        _ = await loader.restore(Whole(), env: env)
        #expect(await loader.cached(Whole(), env: env)?.value == 42)
        #expect(try await loader.value(Whole(), env: env, force: true).value == 1)
    }

    private nonisolated func remove(_ name: String) {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.removeItem(at: base.appendingPathComponent("PoliVerseCache/\(name).json"))
    }
}
