import Foundation
import Synchronization
import Testing
@testable import PoliVerse

/// When the offline pack runs and what it stores next. Values in, decision out.
@Suite("Pacchetto offline: quando e cosa")
struct OfflinePackPlanTests {
    private let calendar = PoliMiDate.romeCalendar
    /// Wednesday 11 November 2026, 22:00 in Rome.
    private var evening: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 22))!
    }

    private func state(_ items: [OfflineItem], at date: Date, account: String = "111") -> OfflinePackState {
        OfflinePackState(account: account, stored: Dictionary(uniqueKeysWithValues: items.map { ($0, date) }))
    }

    @Test("R21: senza account o con dati di esempio il pacchetto non parte")
    func test_R21_needsAnAccount() {
        #expect(OfflinePackPlan.refusal(enabled: true, account: nil, metered: false, byHand: true,
                                        state: .init(), now: evening) == .noAccount)
    }

    @Test("R21: da solo parte solo se è acceso e la rete non è a consumo")
    func test_R21_automaticRunNeedsSwitchAndUnmeteredNetwork() {
        #expect(OfflinePackPlan.refusal(enabled: false, account: "111", metered: false, byHand: false,
                                        state: .init(), now: evening) == .off)
        #expect(OfflinePackPlan.refusal(enabled: true, account: "111", metered: true, byHand: false,
                                        state: .init(), now: evening) == .metered)
        #expect(OfflinePackPlan.refusal(enabled: true, account: "111", metered: false, byHand: false,
                                        state: .init(), now: evening) == nil)
    }

    @Test("R21: al massimo una volta al giorno")
    func test_R21_atMostOnceADay() {
        let done = state(OfflineItem.allCases, at: evening.addingTimeInterval(-3600))
        #expect(OfflinePackPlan.refusal(enabled: true, account: "111", metered: false, byHand: false,
                                        state: done, now: evening) == .done)
        let tomorrow = evening.addingTimeInterval(4 * 3600)
        #expect(OfflinePackPlan.refusal(enabled: true, account: "111", metered: false, byHand: false,
                                        state: done, now: tomorrow) == nil)
    }

    @Test("R22: a mano parte anche spento, con la rete a consumo e dopo averlo già fatto oggi")
    func test_R22_byHandAlwaysRuns() {
        let done = state(OfflineItem.allCases, at: evening)
        #expect(OfflinePackPlan.refusal(enabled: false, account: "111", metered: true, byHand: true,
                                        state: done, now: evening) == nil)
    }

    @Test("P9: riprende da ciò che manca oggi, nell'ordine del pacchetto")
    func test_P9_resumesFromWhatIsMissing() {
        let half = state([.timetable, .floorPlans], at: evening)
        #expect(OfflinePackPlan.due(state: half, account: "111", now: evening) == [.rooms, .courses])
        let yesterday = state([.timetable], at: evening.addingTimeInterval(-86_400))
        #expect(OfflinePackPlan.due(state: yesterday, account: "111", now: evening) == OfflineItem.allCases)
    }

    @Test("R40: ciò che è stato salvato per un altro account non conta")
    func test_R40_anotherAccountCountsAsNothing() {
        let theirs = state(OfflineItem.allCases, at: evening, account: "222")
        #expect(OfflinePackPlan.due(state: theirs, account: "111", now: evening) == OfflineItem.allCases)
    }

    @Test("R21: le aule di domani, ma di oggi se il pacchetto parte di notte")
    func test_R21_roomsDay() {
        let night = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 3))!
        #expect(calendar.isDate(OfflinePlan.roomsDay(now: night), inSameDayAs: night))
        let tomorrow = OfflinePlan.roomsDay(now: evening)
        #expect(calendar.component(.day, from: tomorrow) == 12)
    }
}

/// A run of the pack with work the test scripts.
@Suite("Pacchetto offline: esecuzione", .tags(.timing))
@MainActor
struct OfflinePackRunTests {
    /// What the items do, as the test wrote it.
    @MainActor
    private final class Script {
        var ran: [OfflineItem] = []
        var outcome: [OfflineItem: Bool] = [:]
        var held: OfflineItem?
        var isHeld = false
        var account: String? = "111"
        var metered = false
        var modes: [OfflinePackContext.Mode?] = []

        func work() -> [OfflineItem: OfflinePack.Work] {
            var work: [OfflineItem: OfflinePack.Work] = [:]
            for item in OfflineItem.allCases {
                work[item] = { @MainActor [unowned self] in
                    self.ran.append(item)
                    self.modes.append(OfflinePackContext.mode)
                    if self.held == item {
                        self.isHeld = true
                        while self.isHeld { try? await Task.sleep(for: .milliseconds(2)) }
                    }
                    return self.outcome[item] ?? true
                }
            }
            return work
        }
    }

    private func pack(_ script: Script, defaults: UserDefaults) -> OfflinePack {
        OfflinePack(work: script.work(), account: { script.account }, metered: { script.metered },
                    defaults: defaults)
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "offline-\(UUID().uuidString)")!
    }

    private func until(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("R21: gli elementi sono salvati uno dopo l'altro, ognuno con la sua data")
    func test_R21_storesEachItemInOrder() async {
        let script = Script()
        let pack = pack(script, defaults: defaults())
        await pack.run()
        #expect(script.ran == OfflineItem.allCases)
        #expect(OfflineItem.allCases.allSatisfy { pack.storedAt($0) != nil })
        #expect(script.modes.allSatisfy { $0 == .automatic })
        #expect(!pack.isRunning)
        #expect(pack.stopped == nil)
    }

    @Test("R21: una seconda volta nello stesso giorno non scarica niente")
    func test_R21_secondRunTheSameDayDoesNothing() async {
        let script = Script()
        let pack = pack(script, defaults: defaults())
        await pack.run()
        script.ran = []
        await pack.run()
        #expect(script.ran.isEmpty)
    }

    @Test("R21: con la rete a consumo non parte da solo, a mano sì")
    func test_R21_meteredNetwork() async {
        let script = Script()
        script.metered = true
        let pack = pack(script, defaults: defaults())
        await pack.run()
        #expect(script.ran.isEmpty)
        await pack.run(byHand: true)
        #expect(script.ran == OfflineItem.allCases)
        #expect(script.modes.allSatisfy { $0 == .byHand })
    }

    @Test("R22: spento non parte da solo, e l'interruttore resta salvato")
    func test_R22_switchIsKept() async {
        let script = Script()
        let store = defaults()
        let pack = pack(script, defaults: store)
        #expect(pack.isEnabled)
        pack.isEnabled = false
        await pack.run()
        #expect(script.ran.isEmpty)
        #expect(!self.pack(script, defaults: store).isEnabled)
    }

    @Test("R22: un elemento non completo resta da fare e il motivo è detto, gli altri vanno avanti")
    func test_R22_incompleteItemStaysDue() async {
        let script = Script()
        script.outcome[.rooms] = false
        let pack = pack(script, defaults: defaults())
        await pack.run()
        #expect(script.ran == OfflineItem.allCases)
        #expect(pack.storedAt(.rooms) == nil)
        #expect(pack.storedAt(.courses) != nil)
        #expect(pack.stopped != nil)
        script.ran = []
        await pack.run()
        #expect(script.ran == [.rooms])
    }

    @Test("P9: interrotto da iOS, riprende dall'elemento dopo l'ultimo salvato")
    func test_P9_resumesAfterBeingStopped() async {
        let script = Script()
        script.held = .rooms
        let store = defaults()
        let pack = pack(script, defaults: store)
        let run = Task { await pack.run() }
        await until { script.isHeld }
        #expect(pack.current == .rooms)
        pack.cancel()
        script.isHeld = false
        await run.value
        #expect(script.ran == [.timetable, .rooms])
        #expect(pack.stopped != nil)

        // The next launch reads what was stored.
        script.ran = []
        script.held = nil
        await self.pack(script, defaults: store).run()
        #expect(script.ran == [.floorPlans, .courses])
    }

    @Test("R40: cambiando account a metà, il pacchetto si ferma e non registra niente per il nuovo")
    func test_R40_accountChangeStopsTheRun() async {
        let script = Script()
        script.held = .rooms
        let pack = pack(script, defaults: defaults())
        let run = Task { await pack.run() }
        await until { script.isHeld }
        script.account = "222"
        script.isHeld = false
        await run.value
        #expect(script.ran == [.timetable, .rooms])
        #expect(pack.storedAt(.timetable) == nil)
        #expect(pack.storedAt(.rooms) == nil)
    }

    @Test("R40: all'uscita il pacchetto dimentica ciò che ha salvato")
    func test_R40_forget() async {
        let script = Script()
        let store = defaults()
        let pack = pack(script, defaults: store)
        await pack.run()
        pack.forget()
        #expect(pack.storedAt(.timetable) == nil)
        #expect(store.data(forKey: OfflinePackState.key) == nil)
    }
}

/// The gate with the pack's requests.
@Suite("Varco: richieste del pacchetto offline")
struct OfflinePackGateTests {
    private func gate(device: SpeculativeBudget.Device = .init(), enabled: Bool,
                      allowMetered: Bool = false) -> RequestGate {
        var settings = SpeculativeBudget.Settings()
        settings.enabled = enabled
        settings.allowMetered = allowMetered
        let chosen = settings
        return RequestGate(ledger: LoadingLedger(file: nil), device: { device }, settings: { chosen },
                           counts: .memory())
    }

    @Test("R33: il pacchetto ha il suo interruttore, non quello della preparazione in anticipo")
    func test_R33_packIgnoresThePrefetchSwitch() async {
        let gate = gate(enabled: false)
        #expect(await gate.refusal() == .off)
        #expect(await gate.refusal(pack: .automatic) == nil)
    }

    @Test("R21: da solo mai con la rete a consumo, a mano sì; con Dati ridotti mai")
    func test_R21_meteredAndLowData() async {
        let metered = gate(device: .init(metered: true), enabled: true)
        #expect(await metered.refusal(pack: .automatic) == .metered)
        #expect(await metered.refusal(pack: .byHand) == nil)
        let lowData = gate(device: .init(lowData: true), enabled: true)
        #expect(await lowData.refusal(pack: .byHand) == .lowData)
    }

    @Test("R33: il limite del giorno ferma anche il pacchetto")
    func test_R33_dailyLimitStopsThePack() async throws {
        let gate = gate(enabled: true)
        let limit = SpeculativeBudget.Settings().dailyLimit
        let speculative = Task.detached(priority: .utility) {
            try await LoadContext.$current.withValue(.init(part: "test", speculative: true)) {
                try await OfflinePackContext.$mode.withValue(.automatic) {
                    for _ in 0..<limit { _ = try await gate.run(host: "maps") { 1 } }
                }
            }
        }
        try await speculative.value
        #expect(await gate.refusal(pack: .byHand) == .limitReached)
    }

    @Test("R33: una richiesta del pacchetto va nella corsia anticipata anche con la preparazione spenta")
    func test_R33_packRequestRunsWithPrefetchOff() async throws {
        let gate = gate(enabled: false)
        let value = try await Task.detached(priority: .utility) {
            try await LoadContext.$current.withValue(.init(part: "test", speculative: true)) {
                try await OfflinePackContext.$mode.withValue(.automatic) {
                    try await gate.run(host: "maps") { 7 }
                }
            }
        }.value
        #expect(value == 7)
        #expect(await gate.sentToday() == 1)
        await #expect(throws: SpeculationRefused.self) {
            try await Task.detached(priority: .utility) {
                try await LoadContext.$current.withValue(.init(part: "test", speculative: true)) {
                    try await gate.run(host: "maps") { 7 }
                }
            }.value
        }
    }
}

/// Rooms, plans and listings kept on disk, and shown from there.
@Suite("Pacchetto offline: copie su disco", .tags(.network))
@MainActor
struct OfflineCopiesTests {
    private let day = PoliMiDate.time(12, on: Date(timeIntervalSince1970: 1_772_000_000))

    @Test("R23: il nome del file di una pianta dipende da piano e aula, e non ha caratteri strani")
    func test_R23_floorPlanFileName() {
        let url = URL(string: "https://onlineservices.polimi.it/maps_rest/rest/download/img/piano/MI0203-1/CO.1.1")!
        #expect(FloorPlanResource.storageName(for: url) == "floor-plan-MI0203-1-CO_1_1")
        let other = URL(string: "https://onlineservices.polimi.it/maps_rest/rest/download/img/piano/MI0203-1/CO.1.2")!
        #expect(FloorPlanResource.storageName(for: other) != FloorPlanResource.storageName(for: url))
    }

    @Test("R23: una copia delle aule torna con le prenotazioni e l'idaula del catalogo")
    func test_R23_snapshotBackToSchedules() {
        let start = day
        let snapshot = FreeRoomsSnapshot(day: day, campus: "C", rooms: [
            .init(id: "A1", name: "A1", building: "Edificio 1", seats: 40,
                  busy: [.init(start: start, end: start.addingTimeInterval(3600))]),
        ])
        let catalogue = [Classroom(id: "A1", capacity: 40, buildingCode: "B", floorCode: "0",
                                   campusName: "C", occupancyID: "9")]
        let rooms = FreeRoomsModel.schedules(from: snapshot, catalogue: catalogue)
        #expect(rooms.map(\.id) == ["A1"])
        #expect(rooms.first?.occupancyID == "9")
        #expect(rooms.first?.bookings.map(\.start) == [start])
    }

    @Test("R23: senza rete le aule libere mostrano la copia salvata con la sua età, non un errore")
    func test_R23_freeRoomsFromTheStoredCopy() async {
        let campus = "Offline \(UUID().uuidString)"
        let booked = day.addingTimeInterval(-1800)
        OfflineStore.shared.save(
            FreeRoomsSnapshot(day: day, campus: campus, rooms: [
                .init(id: "A1", name: "A1", building: nil, seats: nil,
                      busy: [.init(start: booked, end: booked.addingTimeInterval(3600))]),
            ]),
            as: FreeRoomsSnapshot.packCacheName, account: campus)
        await OfflineStore.shared.flushed()

        let model = FreeRoomsModel(
            catalogue: OfflineCatalogue([Classroom(id: "A1", capacity: 40, buildingCode: "B", floorCode: "0",
                                                   campusName: campus, occupancyID: "off-\(UUID().uuidString)")]),
            session: NoSignal.session)
        model.day = day
        model.campus = campus
        await model.load()

        #expect(model.rooms.map(\.id) == ["A1"])
        #expect(model.rooms.first?.bookings.count == 1)
        #expect(model.errorMessage == nil)
        #expect(model.hiddenRooms.isEmpty)
        #expect(model.age != nil)
    }

    @Test("R23: senza rete e senza copia le aule libere dicono il guasto")
    func test_R23_freeRoomsWithoutACopySayWhy() async {
        let campus = "Offline \(UUID().uuidString)"
        let model = FreeRoomsModel(
            catalogue: OfflineCatalogue([Classroom(id: "A1", capacity: 40, buildingCode: "B", floorCode: "0",
                                                   campusName: campus, occupancyID: "off-\(UUID().uuidString)")]),
            session: NoSignal.session)
        model.day = day
        model.campus = campus
        await model.load()

        #expect(model.rooms.isEmpty)
        #expect(model.errorMessage != nil)
    }
}

/// A fixed list of rooms.
@MainActor
private final class OfflineCatalogue: RoomCatalogue {
    let rooms: [Classroom]
    var campuses: [String] { Array(Set(rooms.compactMap(\.campusName))).sorted() }
    init(_ rooms: [Classroom]) { self.rooms = rooms }
    func load(force: Bool) async {}
}

/// A network that is not there: every request fails at once.
private nonisolated final class NoSignal: URLProtocol, @unchecked Sendable {
    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NoSignal.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
}
