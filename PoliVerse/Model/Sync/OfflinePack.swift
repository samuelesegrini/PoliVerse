import Foundation
import Observation
import OSLog

/// One thing the offline pack keeps on the phone.
nonisolated enum OfflineItem: String, CaseIterable, Codable, Sendable {
    /// The timetable of this week and the next.
    case timetable
    /// Tomorrow's bookings for the favourite campus.
    case rooms
    /// The floor plans of the favourite campus's rooms.
    case floorPlans
    /// The listing of each course of this year on WeBeep.
    case courses

    /// The item's name in Impostazioni.
    var title: LocalizedStringResource {
        switch self {
        case .timetable: "Orario di questa settimana e della prossima"
        case .rooms: "Aule libere di domani"
        case .floorPlans: "Piante delle aule"
        case .courses: "Materiali dei corsi"
        }
    }
}

/// What the offline pack has stored, and for whom.
nonisolated struct OfflinePackState: Codable, Equatable, Sendable {
    /// The account the items were stored for.
    var account: String?
    /// When each item was last stored whole.
    var stored: [OfflineItem: Date] = [:]
    /// When the last run ended, whole or not.
    var lastRun: Date?

    /// The defaults key the state is kept under.
    static let key = "offlinePack"

    /// The state kept, or an empty one.
    static func load(from defaults: UserDefaults) -> OfflinePackState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(OfflinePackState.self, from: data) else { return .init() }
        return state
    }

    /// Keeps the state.
    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

/// When the pack runs and what it does next. Values in, decision out.
nonisolated enum OfflinePackPlan {
    /// Why the pack does not run now.
    enum Refusal: Equatable, Sendable {
        /// The student switched it off.
        case off
        /// Nobody is signed in, or the data is sample data.
        case noAccount
        /// The network is metered or in Low Data Mode, and the run was not asked for by hand.
        case metered
        /// Everything was stored today already.
        case done
    }

    /// Why the pack may not run, or `nil` when it may.
    ///
    /// - Parameters:
    ///   - enabled: The student's switch.
    ///   - account: Whose data, or `nil` for nobody or sample data.
    ///   - metered: Whether the network is metered or constrained.
    ///   - byHand: Started from Impostazioni: runs on any network, and again
    ///     on a day it already ran.
    ///   - state: What is stored.
    ///   - now: The current moment.
    ///   - calendar: The calendar a day is counted in.
    static func refusal(enabled: Bool, account: String?, metered: Bool, byHand: Bool,
                        state: OfflinePackState, now: Date,
                        calendar: Calendar = PoliMiDate.romeCalendar) -> Refusal? {
        guard let account else { return .noAccount }
        if byHand { return nil }
        if !enabled { return .off }
        if metered { return .metered }
        return due(state: state, account: account, now: now, calendar: calendar).isEmpty ? .done : nil
    }

    /// The items still to store today, in the order they are stored.
    ///
    /// An item stored today is not stored again, so a run that iOS stopped half
    /// way resumes at the next one. Items stored for another account count as
    /// never stored.
    ///
    /// - Parameters:
    ///   - state: What is stored.
    ///   - account: Whose data the run is for.
    ///   - now: The current moment.
    ///   - calendar: The calendar a day is counted in.
    static func due(state: OfflinePackState, account: String, now: Date,
                    calendar: Calendar = PoliMiDate.romeCalendar) -> [OfflineItem] {
        let mine = state.account == account
        return OfflineItem.allCases.filter { item in
            guard mine, let date = state.stored[item] else { return true }
            return !calendar.isDate(date, inSameDayAs: now)
        }
    }
}

/// The day whose room bookings the pack keeps.
nonisolated enum OfflinePlan {
    /// When the campus opens: a run before it stores the day just starting.
    static let openingHour = 8

    /// The next day the student may be on campus: today when the pack runs in the
    /// night, before the campus opens, and otherwise tomorrow.
    ///
    /// - Parameters:
    ///   - now: When the pack runs.
    ///   - calendar: The calendar of Rome.
    static func roomsDay(now: Date, calendar: Calendar = PoliMiDate.romeCalendar) -> Date {
        let today = calendar.startOfDay(for: now)
        guard calendar.component(.hour, from: now) >= openingHour else { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}

/// Marks the requests of the offline pack, so the gate counts them in the daily
/// budget without asking for the "Prepara in anticipo" switch, which is about
/// lectures, not about the pack.
nonisolated enum OfflinePackContext {
    /// How the run was started.
    enum Mode: Sendable, Equatable {
        /// By the processing task: never on a metered network.
        case automatic
        /// From Impostazioni: the student chose to, on whatever network there is.
        case byHand
    }

    /// The run the current request belongs to, or `nil` outside the pack.
    @TaskLocal static var mode: Mode?
}

/// Keeps on the phone what a student needs on a train with no signal.
///
/// Once a day, on a network that is not metered and when iOS grants a processing
/// task, it stores the timetable of this week and the next, tomorrow's bookings for
/// the favourite campus, the floor plans of its rooms and the listing of each course
/// of this year. Every request but the timetable's is speculative: it counts in the
/// day's limit, and the pack stops when the limit is reached.
///
/// Items are stored one after another and each is recorded as soon as it is in,
/// so a run iOS stops half way resumes at the next item. The work for each item is
/// passed in rather than named, so the order and the resuming are tested without
/// the services.
@MainActor
@Observable
final class OfflinePack {
    /// Stores one item, and says whether it was stored whole.
    typealias Work = @MainActor () async -> Bool

    /// The key of the student's switch.
    static let enabledKey = "offlinePackEnabled"

    /// What is stored, and for whom.
    private(set) var state: OfflinePackState
    /// The item being stored now, or `nil` when the pack is not running.
    private(set) var current: OfflineItem?
    /// Why the last run did not store everything, or `nil`.
    private(set) var stopped: String?

    @ObservationIgnored private let work: [OfflineItem: Work]
    @ObservationIgnored private let account: @MainActor () -> String?
    @ObservationIgnored private let metered: @MainActor () -> Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var running: Task<Void, Never>?
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "offline")

    /// Creates the pack.
    ///
    /// - Parameters:
    ///   - work: What stores each item.
    ///   - account: The signed-in matricola, or `nil` for nobody or sample data.
    ///   - metered: Whether the network is metered or in Low Data Mode.
    ///   - defaults: Where the state and the switch are kept.
    ///   - now: The clock.
    init(work: [OfflineItem: Work], account: @escaping @MainActor () -> String?,
         metered: @escaping @MainActor () -> Bool, defaults: UserDefaults = .standard,
         now: @escaping () -> Date = { .now }) {
        self.work = work
        self.account = account
        self.metered = metered
        self.defaults = defaults
        self.now = now
        state = OfflinePackState.load(from: defaults)
    }

    /// The student's switch. On unless they turned it off.
    var isEnabled: Bool {
        get {
            access(keyPath: \.isEnabled)
            return defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.isEnabled) { defaults.set(newValue, forKey: Self.enabledKey) }
        }
    }

    /// Whether a run is in progress.
    var isRunning: Bool { current != nil }

    /// When an item was stored for the signed-in account, or `nil` if it never was.
    func storedAt(_ item: OfflineItem) -> Date? {
        guard state.account == account() else { return nil }
        return state.stored[item]
    }

    /// Stores what is due, one item after another.
    ///
    /// A second call while a run is going on joins it.
    ///
    /// - Parameter byHand: Started from Impostazioni: stores every item again,
    ///   on any network.
    func run(byHand: Bool = false) async {
        if let running {
            await running.value
            return
        }
        let task = Task(name: "offline pack") { await self.pass(byHand: byHand) }
        running = task
        await task.value
        running = nil
    }

    private func pass(byHand: Bool) async {
        let at = now()
        let who = account()
        if let refusal = OfflinePackPlan.refusal(enabled: isEnabled, account: who, metered: metered(),
                                                 byHand: byHand, state: state, now: at) {
            log.notice("offline pack: not run (\(String(describing: refusal), privacy: .public))")
            return
        }
        guard let who else { return }
        if state.account != who { state = OfflinePackState(account: who) }
        let items = byHand ? OfflineItem.allCases : OfflinePackPlan.due(state: state, account: who, now: at)
        stopped = nil
        defer {
            current = nil
            state.lastRun = now()
            state.save(to: defaults)
        }
        for item in items {
            guard !Task.isCancelled, account() == who else {
                stopped = String(localized: "Interrotto: riprende alla prossima occasione.")
                return
            }
            current = item
            let whole = await OfflinePackContext.$mode.withValue(byHand ? .byHand : .automatic) {
                await self.work[item]?() ?? false
            }
            guard account() == who else { return }
            if whole {
                state.stored[item] = now()
                state.save(to: defaults)
            } else {
                stopped = String(localized: "Non tutto è stato scaricato: riprova con il Wi‑Fi.")
            }
            log.notice("offline pack: \(item.rawValue, privacy: .public) \(whole ? "stored" : "incomplete", privacy: .public)")
        }
    }

    /// Ends a run in progress, for when iOS takes the processing task back. What is
    /// stored stays.
    func cancel() {
        running?.cancel()
    }

    /// Forgets what was stored, for sign-out. The copies themselves go with the
    /// account's offline store.
    func forget() {
        running?.cancel()
        state = OfflinePackState()
        defaults.removeObject(forKey: OfflinePackState.key)
    }
}
