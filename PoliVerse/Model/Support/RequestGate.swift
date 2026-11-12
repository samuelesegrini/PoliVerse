import Foundation
import Synchronization

/// The one place every request to the Politecnico passes through.
///
/// It times each request and notes it in the ``LoadingLedger`` with what
/// ``LoadContext`` says it was for, and it keeps the ``HostBreaker``: a host that
/// timed out twice in a row is not asked for half a minute, and requests to it
/// throw ``HostPaused`` at once, so a screen shows its stored copy without
/// waiting.
///
/// Requests run in two lanes. A request for something on screen goes at once. A
/// speculative one — a warm-up nobody is waiting for yet — goes only when the
/// ``SpeculativeBudget`` allows it, counts towards today's limit, runs at most
/// ``speculativePerHost`` at a time per host, and waits while a request for the
/// screen is in flight to the same host. A warm-up that someone joined runs at
/// their priority and so in the screen's lane.
actor RequestGate {
    /// The lane a request runs in.
    enum Lane: Equatable, Sendable {
        /// For a section on screen, or something the student did.
        case onScreen
        /// Ahead of the student: sent only within the budget, and after the screen.
        case speculative
    }

    /// Where today's count of speculative requests is kept.
    struct CountStore: Sendable {
        /// Reads the count last written.
        var load: @Sendable () -> SpeculativeCount?
        /// Writes the count.
        var save: @Sendable (SpeculativeCount) -> Void

        /// The user defaults.
        static let defaults = CountStore(load: { SpeculativeCount.stored }, save: { $0.store() })

        /// Memory only, for tests.
        static func memory() -> CountStore {
            let box = Mutex<SpeculativeCount?>(nil)
            return CountStore(load: { box.withLock { $0 } }, save: { count in box.withLock { $0 = count } })
        }
    }

    /// How many speculative requests may run at once to one host.
    static let speculativePerHost = 2

    /// The app's gate, noting into the app's ledger.
    nonisolated static let shared = RequestGate(ledger: .shared)

    private let ledger: LoadingLedger
    private var breaker: HostBreaker
    private let now: @Sendable () -> ContinuousClock.Instant
    private let pauseChanged: @Sendable (String, Duration?) -> Void
    private let device: @Sendable () -> SpeculativeBudget.Device
    private let settings: @Sendable () -> SpeculativeBudget.Settings
    private let counts: CountStore
    private let today: @Sendable () -> Date

    /// Requests for the screen in flight, per host.
    private var onScreen: [String: Int] = [:]
    /// Speculative requests in flight, per host.
    private var speculative: [String: Int] = [:]
    /// Speculative requests waiting for their turn, per host, oldest first.
    private var waiting: [String: [(id: UUID, pack: OfflinePackContext.Mode?,
                                    turn: CheckedContinuation<Void, any Error>)]] = [:]

    /// Creates a gate.
    ///
    /// - Parameters:
    ///   - ledger: Where requests are noted.
    ///   - breaker: Decides when a host is paused.
    ///   - now: The clock the pauses run on.
    ///   - pauseChanged: Told the host and for how long it is paused, or `nil`
    ///     when it answers again. The app's gate writes to ``HostPauses/shared``.
    ///   - device: The state of the phone, for the speculative budget.
    ///   - settings: What the student allowed, for the speculative budget.
    ///   - counts: Where today's count of speculative requests is kept.
    ///   - today: The calendar moment the count's day is read from.
    init(ledger: LoadingLedger, breaker: HostBreaker = HostBreaker(),
         now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
         pauseChanged: @escaping @Sendable (String, Duration?) -> Void = { host, pause in
             Task { @MainActor in HostPauses.shared.set(host, pausedFor: pause) }
         },
         device: @escaping @Sendable () -> SpeculativeBudget.Device = { .current },
         settings: @escaping @Sendable () -> SpeculativeBudget.Settings = { .stored },
         counts: CountStore = .defaults,
         today: @escaping @Sendable () -> Date = { .now }) {
        self.ledger = ledger
        self.breaker = breaker
        self.now = now
        self.pauseChanged = pauseChanged
        self.device = device
        self.settings = settings
        self.counts = counts
        self.today = today
    }

    // MARK: - The speculative budget

    /// How many speculative requests went out today.
    func sentToday() -> Int {
        SpeculativeCount.today(at: today(), stored: counts.load()).sent
    }

    /// How many of some wanted speculative requests the budget allows now.
    ///
    /// - Parameter count: How many are wanted.
    func allowance(for count: Int) -> Int {
        SpeculativeBudget.allows(count, device: device(), settings: settings(), sentToday: sentToday())
    }

    /// Why no speculative request may go out now, or `nil` when one may.
    ///
    /// - Parameter pack: The offline pack's run the request belongs to. The pack
    ///   has a switch of its own, so "Prepara in anticipo" does not apply to it,
    ///   and a run the student started by hand may use a metered network.
    func refusal(pack: OfflinePackContext.Mode? = nil) -> SpeculativeBudget.Refusal? {
        var chosen = settings()
        if let pack {
            chosen.enabled = true
            if pack == .byHand { chosen.allowMetered = true }
        }
        return SpeculativeBudget.refusal(device: device(), settings: chosen, sentToday: sentToday())
    }

    // MARK: - Lanes

    /// Lets a request in: one for the screen at once, a speculative one when the
    /// budget and its host allow.
    private func admit(host: String, lane: Lane) async throws {
        guard lane == .speculative else {
            onScreen[host, default: 0] += 1
            return
        }
        let pack = OfflinePackContext.mode
        if let reason = refusal(pack: pack) { throw SpeculationRefused(reason: reason) }
        if waiting[host, default: []].isEmpty, hasRoom(host) {
            begin(host)
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { turn in
                waiting[host, default: []].append((id, pack, turn))
            }
        } onCancel: {
            Task { await self.abandon(host: host, id: id) }
        }
    }

    /// A request is over: its place goes to the next speculative one, if any.
    private func release(host: String, lane: Lane) {
        switch lane {
        case .onScreen: onScreen[host] = max(0, (onScreen[host] ?? 0) - 1)
        case .speculative: speculative[host] = max(0, (speculative[host] ?? 0) - 1)
        }
        pump(host)
    }

    /// Whether a speculative request to a host may start now.
    private func hasRoom(_ host: String) -> Bool {
        (onScreen[host] ?? 0) == 0 && (speculative[host] ?? 0) < Self.speculativePerHost
    }

    /// Starts a speculative request: one more in flight, one more today.
    private func begin(_ host: String) {
        speculative[host, default: 0] += 1
        var count = SpeculativeCount.today(at: today(), stored: counts.load())
        count.sent += 1
        counts.save(count)
    }

    /// Lets in the speculative requests waiting for a host, as far as there is room.
    /// One that the budget now refuses is told so rather than left waiting.
    private func pump(_ host: String) {
        while hasRoom(host), var queue = waiting[host], !queue.isEmpty {
            let next = queue.removeFirst()
            waiting[host] = queue.isEmpty ? nil : queue
            if let reason = refusal(pack: next.pack) {
                next.turn.resume(throwing: SpeculationRefused(reason: reason))
            } else {
                begin(host)
                next.turn.resume()
            }
        }
    }

    /// A waiting request whose caller went away.
    private func abandon(host: String, id: UUID) {
        guard let index = waiting[host]?.firstIndex(where: { $0.id == id }),
              let entry = waiting[host]?.remove(at: index) else { return }
        if waiting[host]?.isEmpty == true { waiting[host] = nil }
        entry.turn.resume(throwing: CancellationError())
    }

    /// How many speculative requests to a host are in flight and waiting, for tests.
    func speculativeLoad(_ host: String) -> (running: Int, waiting: Int) {
        (speculative[host] ?? 0, waiting[host]?.count ?? 0)
    }

    /// Whether requests to a host are being answered without being sent.
    ///
    /// - Parameter host: The service, by name.
    func isPaused(_ host: String) -> Bool {
        breaker.isPaused(host, at: now())
    }

    /// Tells the breaker how a request ended.
    private func record(_ outcome: LedgerRequest.Outcome, host: String) {
        switch breaker.note(outcome, host: host, at: now()) {
        case .paused(let pause): pauseChanged(host, pause)
        case .resumed: pauseChanged(host, nil)
        case nil: break
        }
    }

    /// Runs a request and notes how long it took and how it ended.
    ///
    /// - Parameters:
    ///   - host: The service asked, by name. Never a URL.
    ///   - pausable: Whether the request may be answered with ``HostPaused``
    ///     while its host is paused. `false` for what the student did, such as
    ///     enrolling in an exam: that is always sent.
    ///   - request: The request itself.
    /// - Returns: What the request returned.
    /// - Throws: What the request threw, unchanged, or ``HostPaused`` without
    ///   sending it.
    nonisolated func run<T: Sendable>(
        host: String, pausable: Bool = true, _ request: @Sendable () async throws -> T
    ) async throws -> T {
        if pausable, await isPaused(host) { throw HostPaused(host: host) }
        let context = LoadContext.current
        // A warm-up someone joined has been raised to their priority: it is
        // for the screen now.
        let lane: Lane = context?.speculative == true && Task.currentPriority <= .utility
            ? .speculative : .onScreen
        try await admit(host: host, lane: lane)
        let start = Date.now
        let clock = ContinuousClock()
        let began = clock.now
        func note(_ outcome: LedgerRequest.Outcome) {
            let elapsed = clock.now - began
            let milliseconds = Int(elapsed.components.seconds) * 1000
                + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
            ledger.note(LedgerRequest(
                part: context?.part ?? LoadContext.unattributed, host: host, start: start,
                milliseconds: milliseconds, outcome: outcome,
                speculative: context?.speculative ?? false))
        }
        do {
            let value = try await request()
            note(.ok)
            await record(.ok, host: host)
            await release(host: host, lane: lane)
            return value
        } catch {
            let outcome = Self.outcome(of: error)
            note(outcome)
            await record(outcome, host: host)
            await release(host: host, lane: lane)
            throw error
        }
    }

    /// How a request that threw `error` ended.
    ///
    /// - Parameter error: What the request threw.
    /// - Returns: ``LedgerRequest/Outcome/cancelled`` for a caller that went away,
    ///   ``LedgerRequest/Outcome/timedOut`` for a timeout, otherwise
    ///   ``LedgerRequest/Outcome/failed``.
    nonisolated static func outcome(of error: any Error) -> LedgerRequest.Outcome {
        var underlying = error
        if let api = error as? APIError {
            switch api {
            case .cancelled: return .cancelled
            case .transport(let inner): underlying = inner
            default: break
            }
        }
        if PoliMiAPI.isCancellation(underlying) { return .cancelled }
        let nsError = underlying as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut { return .timedOut }
        return .failed
    }
}
