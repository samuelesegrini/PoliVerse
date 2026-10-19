#if DEBUG
import RealityKit
import XCTest
@testable import PoliVerse

/// What loading the 3D walk costs on the device the tests run on: time, CPU and memory.
///
/// The cloud bench (`prototypes/trifoglio-3d-PROTOTYPE/banco/misura.py`) counts bytes,
/// triangles and draw calls; only a phone can say what those become in seconds and
/// megabytes. The goals each test is held to are in `banco/README.md`.
///
/// Off by default: a run reads 50 MB of models several times over. Turn on with
/// `TRIFOGLIO3D_BENCH=1` in the test action's environment (or
/// `TEST_RUNNER_TRIFOGLIO3D_BENCH=1 xcodebuild test …`), on a phone rather than the
/// simulator, whose GPU and disk say nothing about an iPhone's. Set a baseline per device in
/// Xcode's test report to catch a regression.
///
/// The models live in Preview Content, which only Debug builds carry, so these run in the
/// ordinary Debug test action rather than the Release-built PoliVersePerformance scheme.
nonisolated final class Trifoglio3DLoadTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TRIFOGLIO3D_BENCH"] == "1",
                          "Banco 3D spento: TRIFOGLIO3D_BENCH=1 per farlo girare")
    }

    /// Five runs each, as the app's other performance tests.
    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }

    /// Runs async work to the end from inside a `measure` block, which is synchronous.
    @MainActor private func run(_ work: @escaping @MainActor () async -> Void) {
        let done = expectation(description: "caricato")
        Task { @MainActor in
            await work()
            done.fulfill()
        }
        wait(for: [done], timeout: 120)
    }

    /// Everything before the first frame: `campus.usdz` and the plan files.
    /// Goal: under 1 s on an iPhone 15, under 250 MB of memory.
    @MainActor func testBeforeFirstFrame() {
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            let scene = Trifoglio3DScene()
            run { await scene.loadCampus() }
            XCTAssertNil(scene.failure)
        }
    }

    /// The campus file alone, read by RealityKit: the floor under every other number.
    @MainActor func testCampusFile() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "campus", withExtension: "usdz"))
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            run { _ = try? await Entity(contentsOf: url) }
        }
    }

    /// The largest building's floors, with the exact tap shapes of its rooms: what the
    /// flight to a building has to hide. Goal: under 300 ms, shorter than the 1.3 s flight.
    @MainActor func testOneBuilding() {
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            let scene = Trifoglio3DScene()
            run { _ = await scene.loadBuilding("MIA0201") }
            XCTAssertNotNil(scene.models["MIA0201"])
        }
    }

    /// Ten buildings visited one after another: memory must stay flat, because only
    /// ``Trifoglio3DScene/keptBuildings`` of them stay loaded.
    @MainActor func testWalkAcrossTenBuildings() {
        let walk = Array(Trifoglio3DScene.buildings.prefix(10))
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            let scene = Trifoglio3DScene()
            run { for csie in walk { await scene.loadBuilding(csie) } }
            XCTAssertLessThanOrEqual(scene.models.count, Trifoglio3DScene.keptBuildings)
        }
    }

    /// What the walk used to read before its first frame: the campus and all 36 buildings.
    /// Kept as the reference the progressive load is compared against.
    @MainActor func testEverythingAtOnce() throws {
        let urls = try (["campus", "giuriati"] + Trifoglio3DScene.buildings).map {
            try XCTUnwrap(Bundle.main.url(forResource: $0, withExtension: "usdz"), $0)
        }
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            run {
                var entities: [Entity] = []
                for url in urls { if let entity = try? await Entity(contentsOf: url) { entities.append(entity) } }
                XCTAssertEqual(entities.count, urls.count)
            }
        }
    }
}
#endif
