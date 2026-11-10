import Foundation
import Testing
@testable import PoliVerse

@Suite("WeBeep course loading")
struct WeBeepCoursesTests {
    @Test @MainActor
    func preservesMoodleFailureForLoginHandling() async {
        let loader = Loader(WeBeepCourses(fetchCourses: {
            throw WeBeepAPI.Failure.moodle(code: "invalidtoken", message: "Expired")
        }))
        let env = Env(http: FixtureHTTP(), matricola: "111", isSample: false)
        do {
            _ = try await loader.value(Whole(), env: env)
            Issue.record("Expected the Moodle authentication failure")
        } catch let failure as WeBeepAPI.Failure {
            #expect(failure.isAuthFailure)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test @MainActor
    func forcedRefreshDoesNotServeHeldCourses() async throws {
        var calls = 0
        let loader = Loader(WeBeepCourses(fetchCourses: {
            calls += 1
            return []
        }))
        // Anonymous avoids writing a real student's offline cache in this test.
        let env = Env.public(FixtureHTTP())
        _ = try await loader.value(Whole(), env: env, force: true)
        _ = try await loader.value(Whole(), env: env, force: true)
        #expect(calls == 2)
    }
}
