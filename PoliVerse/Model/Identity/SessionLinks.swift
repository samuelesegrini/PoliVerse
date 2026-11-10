import Foundation
import Observation

/// Three independently verified connections. Work belongs to the account, not to
/// the screen watching it, and never holds up restoring the app at launch.
@MainActor
@Observable
final class SessionLinks {
    enum Connection: String, CaseIterable, Identifiable, Sendable {
        case university, weBeep, recordings
        var id: String { rawValue }
    }

    enum Status: Equatable, Sendable {
        case idle, connecting, connected, needsSignIn, unavailable, offline
    }

    /// Completed milestones, not an estimate of network time remaining.
    enum Milestone: Int, Sendable {
        case started = 1, sessionReady, accessVerified, ready
        var fraction: Double { Double(rawValue) / 4 }
    }
    typealias Report = @MainActor @Sendable (Milestone) -> Void

    private(set) var milestones: [Connection: Milestone] = [:]
    private(set) var statuses: [Connection: Status] = [:]
    private let check: @MainActor (Connection, Bool, @escaping Report) async -> Status
    private let finishLogin: @MainActor () async -> Void
    @ObservationIgnored private var tasks: [Connection: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var reporting: [Connection: UUID] = [:]
    private var freshLogin = false

    init(check: @escaping @MainActor (Connection, Bool, @escaping Report) async -> Status,
         finishLogin: @escaping @MainActor () async -> Void = {}) {
        self.check = check
        self.finishLogin = finishLogin
    }

    subscript(_ connection: Connection) -> Status { statuses[connection] ?? .idle }

    func progress(for connection: Connection) -> Double {
        self[connection] == .connected ? 1 : (milestones[connection]?.fraction ?? 0)
    }

    /// Mark the handoff before the account is read back, so a screen cannot offer
    /// a second sign-in while the first one is still being adopted.
    func prepareForLogin() {
        reset()
        statuses = [.university: .connecting, .weBeep: .connecting, .recordings: .connecting]
        milestones = Dictionary(uniqueKeysWithValues: Connection.allCases.map { ($0, .started) })
    }

    /// The university has accepted its credential. The other connections verify
    /// independently; a caller never has to await them.
    func connect(freshLogin: Bool = false) {
        guard tasks.isEmpty else { return }
        self.freshLogin = freshLogin
        statuses[.university] = .connected
        milestones[.university] = .ready
        for connection in [Connection.weBeep, .recordings] { launch(connection) }
    }

    /// Retries one connection without restarting any of the others.
    func retry(_ connection: Connection) {
        guard connection != .university, tasks[connection] == nil else { return }
        launch(connection)
    }

    func needsSignIn(_ connection: Connection) {
        guard tasks[connection] == nil else { return }
        statuses[connection] = .needsSignIn
    }

    /// Cancellation invalidates even an operation that ignores task cancellation.
    /// Credential adapters must also check cancellation before persisting results.
    func reset() {
        generation += 1
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        statuses.removeAll()
        milestones.removeAll()
        reporting.removeAll()
        freshLogin = false
    }

    func stop() async {
        let running = Array(tasks.values)
        reset()
        for task in running { await task.value }
    }

    /// Joins current work for tests and callers that explicitly need a result.
    /// Launch and onboarding deliberately do not call this.
    func settle(_ connection: Connection? = nil) async {
        let running = connection.map { tasks[$0].map { [$0] } ?? [] } ?? Array(tasks.values)
        for task in running { await task.value }
    }

    private func launch(_ connection: Connection) {
        statuses[connection] = .connecting
        milestones[connection] = .started
        let reportID = UUID()
        reporting[connection] = reportID
        let current = generation
        let fresh = freshLogin
        tasks[connection] = Task { [self] in
            let result = await check(connection, fresh) { [weak self] milestone in
                guard let self, self.generation == current,
                      self.reporting[connection] == reportID,
                      milestone.rawValue > (self.milestones[connection]?.rawValue ?? 0) else { return }
                self.milestones[connection] = milestone
            }
            guard !Task.isCancelled, generation == current else { return }
            reporting[connection] = nil
            if result == .connected { milestones[connection] = .ready }
            statuses[connection] = result
            tasks[connection] = nil
            if tasks.isEmpty, freshLogin {
                freshLogin = false
                await finishLogin()
            }
        }
    }
}
