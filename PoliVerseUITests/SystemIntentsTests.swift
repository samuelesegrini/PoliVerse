#if DEBUG
import AppIntentsTesting
import XCTest

/// Out-of-process tests of the real entity queries and intent dispatch.
nonisolated final class SystemIntentsTests: XCTestCase {
    private let definitions = IntentDefinitions(bundleIdentifier: "segrini.samuele.PoliVerse")
    private var app: XCUIApplication!

    @MainActor override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-useMockData", "<true/>", "-hasCompletedOnboarding", "<true/>",
                               "-lastSeenReleaseVersion", "999", "-SystemIntegrationTests",
                               "-AppleLanguages", "(it)", "-AppleLocale", "it_IT"]
        app.launch()
        _ = try await definitions.intents["SystemIntegrationFixturesIntent"].makeIntent().run()
    }

    @MainActor override func tearDown() async throws {
        defer { app?.terminate() }
        _ = try await definitions.intents["SystemIntegrationFixturesIntent"].makeIntent(cleanup: true).run()
    }

    func testCourseResolutionByNameCodeAndIdentity() async throws {
        let courses = definitions.entities["CourseEntity"]
        let expected = courses.makeReference(identifier: "test-analysis").identifier
        let byName = try await courses.entities(matching: "sistemi WWDC")
        let byCode = try await courses.entities(matching: "T101")
        let byID = try await courses.entities(identifiers: ["test-analysis"])
        XCTAssertEqual(byName.map(\.identifier), [expected])
        XCTAssertEqual(byCode.map(\.identifier), [expected])
        XCTAssertEqual(byID.map(\.identifier), [expected])
        let missing = try await courses.entities(matching: "corso inesistente WWDC")
        XCTAssertTrue(missing.isEmpty)
    }

    func testSuggestedExamsExcludePastAndAreSoonestFirst() async throws {
        let exams = definitions.entities["ExamEntity"]
        let suggested = try await exams.suggestedEntities()
        XCTAssertEqual(suggested.map(\.identifier), [
            exams.makeReference(identifier: "99101").identifier,
            exams.makeReference(identifier: "99102").identifier
        ])
        let first = try XCTUnwrap(suggested.first)
        let result = try await definitions.intents["ExamDateIntent"].makeIntent(exam: first).run()
        let returned: AnyAppEntity = try result.value
        XCTAssertEqual(returned.identifier, first.identifier)
    }

    /// Dispatch and parameter resolution, not an assertion about the spoken wording.
    func testRoomResolvesAndCanBePassedToAvailabilityIntent() async throws {
        let rooms = definitions.entities["RoomEntity"]
        let found = try await rooms.entities(matching: "Aula WWDC")
        XCTAssertEqual(found.map(\.identifier), [rooms.makeReference(identifier: "test-room").identifier])
        let room = try XCTUnwrap(found.first)
        _ = try await definitions.intents["RoomFreeIntent"].makeIntent(room: room).run()
    }
}

#endif
