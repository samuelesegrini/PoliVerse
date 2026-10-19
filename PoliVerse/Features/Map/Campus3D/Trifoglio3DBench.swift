#if DEBUG
import Darwin
import Metal
import RealityKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// PROTOTYPE — debug builds only, with ``Trifoglio3DView``.
//
// The 3D walk's bench, run on the phone itself: every number it shows is read from the
// device while the walk runs, none is estimated. "Misura" in the walk's top bar, or the
// `-Trifoglio3DBench` launch argument, runs it; the results can be shared as JSON. The goals
// the numbers are held to are in `prototypes/trifoglio-3d-PROTOTYPE/banco/README.md`.

/// What the operating system says about this process right now.
enum Trifoglio3DProbe {
    /// The app's memory as iOS counts it against its limit (`phys_footprint`), in bytes.
    static func memory() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// CPU time the whole process has used so far, every thread together, in seconds.
    static func cpuTime() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &time)
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1e9
    }

    /// Bytes the GPU driver holds for this process's Metal device, textures and meshes included.
    static func gpuMemory() -> UInt64 {
        UInt64(MTLCreateSystemDefaultDevice()?.currentAllocatedSize ?? 0)
    }

    /// The phone's model, for example `iPhone16,1`.
    static func model() -> String {
        var name = utsname()
        uname(&name)
        return withUnsafeBytes(of: &name.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// The thermal state as a word: nominal, fair, serious, critical.
    static func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    /// The battery's charge from 0 to 1, or `nil` where it cannot be read (the simulator, a Mac).
    static func battery() -> Double? {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return level < 0 ? nil : Double(level)
        #else
        return nil
        #endif
    }
}

/// Everything one run measured, as it is shown and shared.
struct Trifoglio3DBenchReport: Codable {
    /// One stretch of seconds watched frame by frame.
    struct Window: Codable {
        /// How long it lasted, in seconds.
        var seconds: Double
        /// Frames drawn per second, on average.
        var fps: Double
        /// Frame durations in milliseconds: the median, the 95th percentile and the longest.
        var frameMedianMs: Double
        var frameP95Ms: Double
        var frameMaxMs: Double
        /// Time spent late, beyond the expected frame, per second of watching (Apple: < 5 good).
        var hitchMsPerSecond: Double
        /// CPU used by the app, as a percentage of one core (above 100 means several cores).
        var cpuPercent: Double
        /// The app's memory at the end, and the most it reached, in MB.
        var memoryMB: Double
        var memoryPeakMB: Double
        /// What the GPU driver held at the end, in MB.
        var gpuMB: Double
    }

    /// Six still seconds with one piece of the scene switched off.
    struct Variant: Codable {
        /// What was switched off.
        var name: String
        var window: Window
    }

    /// One building's floors read from the bundle.
    struct Building: Codable {
        var csie: String
        var ms: Double
    }

    var device: String
    var system: String
    var date: Date
    /// From the start of the load to the campus in the scene, and to its first frame, in ms.
    var campusLoadedMs: Double?
    var firstFrameMs: Double?
    /// The app's memory at the first frame, in MB.
    var memoryAtFirstFrameMB: Double?
    /// Ten seconds looking at the still campus.
    var stillCampus: Window?
    /// Where the frame time goes: the still campus, then a building with the others
    /// see-through, each with one piece switched off, so the gap in fps is that piece's cost.
    var variants: [Variant] = []
    /// The flight from the campus to classroom T.1.2, building load included.
    var tourToClassroom: Window?
    /// Every building read cold, one at a time, slowest first.
    var buildings: [Building] = []
    /// What the walk did before this change: the campus, the Giuriati and every building
    /// read before anything showed. Time in ms, memory with all of them held, in MB.
    var everythingAtOnceMs: Double?
    var everythingAtOnceMemoryMB: Double?
    var everythingAtOnceGpuMB: Double?
    /// The still campus again at the end, to see whether memory came back down.
    var stillCampusAfter: Window?
    /// Battery charge (0–1) and thermal state at the start and at the end, and the run's length.
    var batteryStart: Double?
    var batteryEnd: Double?
    var thermalStart: String
    var thermalEnd: String?
    var totalSeconds: Double?
}

/// Runs the bench against the scene on screen.
@Observable
final class Trifoglio3DBench {
    /// What it is doing now, shown over the walk; `nil` when it is not running.
    private(set) var step: String?
    /// The last finished run.
    private(set) var report: Trifoglio3DBenchReport?

    /// Frame durations collected by the window being watched.
    @ObservationIgnored private var frames: [TimeInterval] = []

    /// Runs every measurement in turn. Takes about a minute; the walk moves by itself.
    /// - Parameter quick: Only the still campus with the simplified shells against the
    ///   detailed ones, five times each, alternated: about a minute, short enough not to heat
    ///   the phone the way the whole bench does.
    func run(on scene: Trifoglio3DScene, quick: Bool = false) async {
        guard step == nil else { return }
        let start = ContinuousClock.now
        var report = Trifoglio3DBenchReport(
            device: Trifoglio3DProbe.model(), system: ProcessInfo.processInfo.operatingSystemVersionString,
            date: .now, batteryStart: Trifoglio3DProbe.battery(), thermalStart: Trifoglio3DProbe.thermal())
        if let loadStarted = scene.loadStarted {
            report.campusLoadedMs = scene.campusLoaded.map { ms(loadStarted, $0) }
            report.firstFrameMs = scene.firstFrame.map { ms(loadStarted, $0) }
        }
        report.memoryAtFirstFrameMB = scene.memoryAtFirstFrame.map { mb($0) }

        step = "Torno al campus"
        await scene.go(to: .campus)
        scene.unloadBuildings()
        step = "Campus fermo, 10 s"
        report.stillCampus = await watch(scene) { try? await Task.sleep(for: .seconds(10)) }

        if quick {
            for round in 1...5 {
                for (name, detailed) in [("campus, tutto acceso", false), ("campus, edifici dettagliati", true)] {
                    step = "Lontano o dettagliati (\(round)/5): \(name)"
                    scene.setDistant(!detailed)
                    try? await Task.sleep(for: .seconds(1))
                    report.variants.append(.init(name: name, window: await watch(scene) { try? await Task.sleep(for: .seconds(4)) }))
                }
            }
            scene.setDistant(true)
            finish(&report, start: start)
            return
        }

        await measureVariants(&report, scene: scene)

        step = "Volo all'aula T.1.2"
        report.tourToClassroom = await watch(scene) { await scene.tour() }

        step = "Torno al campus"
        await scene.go(to: .campus)
        for (index, csie) in Trifoglio3DScene.buildings.enumerated() {
            step = "Edifici uno a uno: \(index + 1) di \(Trifoglio3DScene.buildings.count)"
            scene.unloadBuildings()
            let t0 = ContinuousClock.now
            await scene.loadBuilding(csie)
            report.buildings.append(.init(csie: csie, ms: ms(t0, .now)))
        }
        scene.unloadBuildings()
        report.buildings.sort { $0.ms > $1.ms }

        step = "Il vecchio caricamento: tutto subito"
        await everythingAtOnce(&report, scene: scene)

        step = "Campus fermo di nuovo, 10 s"
        report.stillCampusAfter = await watch(scene) { try? await Task.sleep(for: .seconds(10)) }

        finish(&report, start: start)
    }

    /// Closes the report with the battery and the heat, and saves it.
    private func finish(_ report: inout Trifoglio3DBenchReport, start: ContinuousClock.Instant) {
        report.batteryEnd = Trifoglio3DProbe.battery()
        report.thermalEnd = Trifoglio3DProbe.thermal()
        report.totalSeconds = seconds(start, .now)
        self.report = report
        step = nil
        save()
    }

    /// Where the last report is written, in the app's Documents, so a Mac can copy it off the
    /// phone without anyone touching it:
    /// `xcrun devicectl device copy from --device <id> --domain-type appDataContainer
    /// --domain-identifier segrini.samuele.PoliVerse --source Documents/trifoglio3d-bench.json
    /// --destination bench.json`
    static var reportURL: URL {
        URL.documentsDirectory.appending(path: "trifoglio3d-bench.json")
    }

    /// Writes the report to ``reportURL`` and prints it, between markers, to the console.
    private func save() {
        try? Data(json.utf8).write(to: Self.reportURL, options: .atomic)
        print("TRIFOGLIO3D_BENCH_BEGIN\n\(json)\nTRIFOGLIO3D_BENCH_END")
    }

    /// How many times each campus variant is measured.
    private static let rounds = 3

    /// The still campus and a building view, each with one piece switched off in turn.
    private func measureVariants(_ report: inout Trifoglio3DBenchReport, scene: Trifoglio3DScene) async {
        let trees = ["Chiome", "Tronchi", "Alberi_Chiome", "Alberi_Tronchi", "Filari_Chiome", "Filari_Tronchi"]
        let campusVariants: [(String, (Bool) -> Void)] = [
            ("campus, tutto acceso", { _ in }),
            ("campus, senza ombre", { scene.setShadows($0) }),
            ("campus, senza alberi", { scene.setVisible(trees, $0) }),
            ("campus, senza città intorno", { scene.setVisible(["Quartiere"], $0) }),
            ("campus, senza arredi", { scene.setVisible(["Arredi"], $0) }),
            ("campus, senza terreno", { scene.setVisible(["Terreno"], $0) }),
            ("campus, senza edifici", { scene.setVisible(["Edifici"], $0) }),
            ("campus, scena vuota", { scene.setScene($0) }),
            ("campus, edifici dettagliati", { scene.setDistant($0) }),
            ("campus, solo edifici senza ombre", {
                scene.setShadows($0); scene.setVisible(trees + ["Quartiere", "Arredi", "Terreno"], $0)
            }),
        ]
        // Three rounds, one variant after another: on an iPhone 12 Pro the campus sits so close
        // to 16.7 ms a frame that the same variant runs at 30 or 60 Hz from one try to the next.
        for round in 1...Self.rounds {
            for (name, toggle) in campusVariants {
                step = "Dove va il tempo (\(round)/\(Self.rounds)): \(name)"
                toggle(false)
                try? await Task.sleep(for: .seconds(1))     // the first frames after a change are not typical
                report.variants.append(.init(name: name, window: await watch(scene) { try? await Task.sleep(for: .seconds(4)) }))
                toggle(true)
            }
        }
        await scene.go(to: .building("MIA0203"))
        for (name, change) in [("edificio, così com'è", { }),
                               ("edificio, gli altri opachi", { scene.setExteriorsOpaque() })] as [(String, () -> Void)] {
            step = "Dove va il tempo: \(name)"
            change()
            try? await Task.sleep(for: .seconds(1))
            report.variants.append(.init(name: name, window: await watch(scene) { try? await Task.sleep(for: .seconds(6)) }))
        }
        await scene.go(to: .campus)
    }

    /// Reads every model as the walk used to before its first frame, holds them all, then
    /// lets them go.
    private func everythingAtOnce(_ report: inout Trifoglio3DBenchReport, scene: Trifoglio3DScene) async {
        let t0 = ContinuousClock.now
        var held: [Entity] = []
        for name in ["campus", "giuriati"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "usdz"),
               let entity = try? await Entity(contentsOf: url) { held.append(entity) }
        }
        for csie in Trifoglio3DScene.buildings {
            if let building = await scene.readBuilding(csie) { held.append(building) }
        }
        report.everythingAtOnceMs = ms(t0, .now)
        report.everythingAtOnceMemoryMB = mb(Trifoglio3DProbe.memory())
        report.everythingAtOnceGpuMB = mb(Trifoglio3DProbe.gpuMemory())
        withExtendedLifetime(held) {}
    }

    /// Watches the frames, the CPU and the memory while some work runs.
    private func watch(_ scene: Trifoglio3DScene, during work: () async -> Void) async -> Trifoglio3DBenchReport.Window {
        frames.removeAll()
        var peak = Trifoglio3DProbe.memory()
        scene.onFrame = { [weak self] delta in
            self?.frames.append(delta)
            if self?.frames.count.isMultiple(of: 15) == true { peak = max(peak, Trifoglio3DProbe.memory()) }
        }
        let cpu0 = Trifoglio3DProbe.cpuTime()
        let t0 = ContinuousClock.now
        await work()
        let wall = seconds(t0, .now)
        let cpu = Trifoglio3DProbe.cpuTime() - cpu0
        scene.onFrame = nil
        let memory = Trifoglio3DProbe.memory()
        peak = max(peak, memory)

        let sorted = frames.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        // A frame is late when it takes more than one and a half times the usual one; the
        // time beyond the usual one is what the eye sees as a stutter.
        let late = frames.filter { $0 > median * 1.5 }.reduce(0) { $0 + ($1 - median) }
        return .init(seconds: wall, fps: wall > 0 ? Double(frames.count) / wall : 0,
                     frameMedianMs: median * 1000, frameP95Ms: p95 * 1000, frameMaxMs: (sorted.last ?? 0) * 1000,
                     hitchMsPerSecond: wall > 0 ? late * 1000 / wall : 0,
                     cpuPercent: wall > 0 ? cpu / wall * 100 : 0,
                     memoryMB: mb(memory), memoryPeakMB: mb(peak), gpuMB: mb(Trifoglio3DProbe.gpuMemory()))
    }

    /// The report as pretty JSON, to share.
    var json: String {
        guard let report else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(report)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    private func seconds(_ a: ContinuousClock.Instant, _ b: ContinuousClock.Instant) -> Double {
        let d = b - a
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    private func ms(_ a: ContinuousClock.Instant, _ b: ContinuousClock.Instant) -> Double { seconds(a, b) * 1000 }

    private func mb(_ bytes: UInt64) -> Double { Double(bytes) / 1_048_576 }
}

/// The finished run, a line per number, with the JSON to share.
struct Trifoglio3DBenchView: View {
    let bench: Trifoglio3DBench
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let report = bench.report {
                    Section("Dispositivo") {
                        row("Modello", report.device)
                        row("Sistema", report.system)
                        row("Durata del banco", report.totalSeconds.map { String(format: "%.0f s", $0) })
                        row("Batteria", battery(report))
                        row("Temperatura", "\(report.thermalStart) → \(report.thermalEnd ?? "?")")
                    }
                    Section("Apertura") {
                        row("Campus nella scena", report.campusLoadedMs.map { String(format: "%.0f ms", $0) })
                        row("Primo frame", report.firstFrameMs.map { String(format: "%.0f ms", $0) })
                        row("Memoria al primo frame", report.memoryAtFirstFrameMB.map { String(format: "%.0f MB", $0) })
                    }
                    window("Campus fermo, 10 s", report.stillCampus)
                    if !report.variants.isEmpty {
                        Section("Dove va il tempo (fps · CPU · GPU)") {
                            ForEach(Array(report.variants.enumerated()), id: \.offset) { _, variant in
                                row(variant.name, String(format: "%.0f fps · %.0f %% · %.0f MB", variant.window.fps,
                                                         variant.window.cpuPercent, variant.window.gpuMB))
                            }
                        }
                    }
                    window("Volo all'aula T.1.2", report.tourToClassroom)
                    Section("Edifici letti uno a uno") {
                        let times = report.buildings.map(\.ms).sorted()
                        row("Mediana", times.isEmpty ? nil : String(format: "%.0f ms", times[times.count / 2]))
                        row("Totale", String(format: "%.0f ms", times.reduce(0, +)))
                        ForEach(report.buildings.prefix(5), id: \.csie) { row($0.csie, String(format: "%.0f ms", $0.ms)) }
                    }
                    Section("Il vecchio caricamento: tutto subito") {
                        row("Tempo prima di vedere il campus", report.everythingAtOnceMs.map { String(format: "%.0f ms", $0) })
                        row("Memoria con tutto caricato", report.everythingAtOnceMemoryMB.map { String(format: "%.0f MB", $0) })
                        row("GPU con tutto caricato", report.everythingAtOnceGpuMB.map { String(format: "%.0f MB", $0) })
                    }
                    window("Campus fermo, alla fine", report.stillCampusAfter)
                }
            }
            .navigationTitle("Banco 3D")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: bench.json, preview: SharePreview("Banco 3D"))
                }
            }
        }
    }

    @ViewBuilder
    private func window(_ title: String, _ window: Trifoglio3DBenchReport.Window?) -> some View {
        if let window {
            Section(title) {
                row("Frame al secondo", String(format: "%.0f", window.fps))
                row("Frame: mediana / 95° / max", String(format: "%.1f / %.1f / %.0f ms",
                                                          window.frameMedianMs, window.frameP95Ms, window.frameMaxMs))
                row("Scatti", String(format: "%.1f ms/s", window.hitchMsPerSecond))
                row("CPU", String(format: "%.0f %%", window.cpuPercent))
                row("Memoria / picco", String(format: "%.0f / %.0f MB", window.memoryMB, window.memoryPeakMB))
                row("GPU", String(format: "%.0f MB", window.gpuMB))
                row("Durata", String(format: "%.1f s", window.seconds))
            }
        }
    }

    private func row(_ title: String, _ value: String?) -> some View {
        LabeledContent(title, value: value ?? "—")
    }

    private func battery(_ report: Trifoglio3DBenchReport) -> String? {
        guard let start = report.batteryStart, let end = report.batteryEnd else { return nil }
        return String(format: "%.0f %% → %.0f %%", start * 100, end * 100)
    }
}
#endif
