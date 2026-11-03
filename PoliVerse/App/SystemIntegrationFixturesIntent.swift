#if DEBUG
import AppIntents
import Foundation

/// Following Apple's test-only intent pattern: never included in Release.
struct SystemIntegrationFixturesIntent: AppIntent {
    static let title: LocalizedStringResource = "Prepare system integration tests"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: "Cleanup", default: false) var cleanup: Bool

    @MainActor private static var previousAccount: String?
    @MainActor private static var prepared = false
    private static let account = "__system-integration-tests__"

    @MainActor func perform() async throws -> some IntentResult {
        guard CommandLine.arguments.contains("-SystemIntegrationTests"),
              UserDefaults.standard.bool(forKey: "useMockData") else {
            throw FixtureError.requiresSampleTestLaunch
        }
        let store = OfflineStore.shared
        if cleanup {
            if Self.prepared { SharedAccount.matricola = Self.previousAccount }
            store.clear(account: Self.account)
            await store.flushed()
            Self.prepared = false
            return .result()
        }
        if !Self.prepared { Self.previousAccount = SharedAccount.matricola }
        Self.prepared = true
        let now = Date.now
        let index = EntityIndex(
            courses: [
                .init(id: "test-analysis", name: "Analisi dei sistemi WWDC", code: "T101", teacher: "Docente di esempio", cfu: 10, academicYear: "2026/27"),
                .init(id: "test-physics", name: "Fisica WWDC", code: "T102", teacher: nil, cfu: 5, academicYear: "2026/27")
            ],
            exams: [
                .init(id: 99100, courseName: "Appello passato WWDC", courseCode: "T100", date: now.addingTimeInterval(-172800), room: nil, enrolmentCloses: nil, grade: nil),
                .init(id: 99102, courseName: "Fisica WWDC", courseCode: "T102", date: now.addingTimeInterval(172800), room: "B.2.1", enrolmentCloses: nil, grade: nil),
                .init(id: 99101, courseName: "Analisi WWDC", courseCode: "T101", date: now.addingTimeInterval(86400), room: "A.1.1", enrolmentCloses: nil, grade: nil)
            ],
            rooms: [.init(id: "test-room", name: "Aula WWDC", building: "Edificio di esempio", campus: "Campus di esempio", seats: 40)]
        )
        store.save(index, as: EntityIndex.cacheName, account: Self.account)
        store.save(FreeRoomsSnapshot(day: now, campus: "Campus di esempio", rooms: [
            .init(id: "test-room", name: "Aula WWDC", building: "Edificio di esempio", seats: 40, busy: [])
        ]), as: FreeRoomsSnapshot.cacheName, account: Self.account)
        await store.flushed()
        SharedAccount.matricola = Self.account
        return .result()
    }

    private enum FixtureError: Error { case requiresSampleTestLaunch }
}
#endif
