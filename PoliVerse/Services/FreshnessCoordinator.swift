import Foundation
import OSLog

/// The one place that knows what "refresh everything" means.
///
/// The app used to spell that list out three times — the pull-to-refresh
/// handler and the `.task` on `HomeView`, and the background task's closure in
/// `PoliVerseApp` — and each copy drifted a little from the others. Worse, two
/// moments that obviously deserve fresh data triggered nothing at all: coming
/// back to the app after lunch showed the lectures from before lunch, and
/// walking out of a basement left the screen as stale as it was underground.
/// Both are fixed by having somewhere to hang them.
///
/// The coordinator holds no opinion about *when*; it only owns the list and
/// the guarantee that one revalidation is in flight at a time. Whether a given
/// load actually reaches the network is still `LoadWindow`'s decision, which is
/// why foregrounding can call this on every return from the app switcher
/// without costing a request.
@MainActor
@Observable
final class FreshnessCoordinator {
    /// One service's load, as the coordinator sees it: take a `force` flag,
    /// come back when the data is in.
    typealias Load = @MainActor (_ force: Bool) async -> Void

    private var loads: [(name: String, run: Load)] = []
    /// The revalidation currently in flight, if any. New runs chain behind it
    /// rather than racing it.
    private var inFlight: Task<Void, Never>?
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "freshness")

    /// Everything the app shows, in the order `HomeView` wants it.
    ///
    /// A factory rather than five `register` calls at each site, because the
    /// duplication this class exists to remove would otherwise simply move:
    /// the app and the preview environment both need the same list, and a list
    /// written twice is a list that drifts.
    static func standard(
        courses: CourseService,
        agenda: AgendaService,
        career: CareerService,
        notices: NoticeService,
        news: NewsService,
        weBeep: WeBeepService
    ) -> FreshnessCoordinator {
        let coordinator = FreshnessCoordinator()
        coordinator.register("courses") { await courses.load(force: $0) }
        coordinator.register("agenda") { await agenda.load(around: .now, force: $0) }
        coordinator.register("career") { await career.load(force: $0) }
        // Last, as on Home: the bell is the least urgent thing on the screen,
        // and an endpoint whose shape is still unconfirmed should not delay
        // the content that is known to work.
        coordinator.register("notices") { await notices.load(force: $0) }
        coordinator.register("news") { await news.load(force: $0) }
        // After everything on screen: it reads several course pages, and
        // what it finds lands in the feed rather than on any open screen.
        coordinator.register("webeep-updates") { await weBeep.checkForUpdates(force: $0) }
        return coordinator
    }

    /// Adds a load to the set, to run after everything registered before it.
    ///
    /// The closure captures its service strongly, deliberately. Every service
    /// is held by `PoliVerseApp` for the whole life of the process, so there
    /// is nothing to release and nothing to leak: no service holds the
    /// coordinator, so there is no cycle either. Weak captures here would only
    /// add a silent failure mode where a load stops running and nothing says
    /// so.
    ///
    /// The name is for the log: "revalidated 5 services" says nothing when one
    /// of them is hanging, and the names say which.
    func register(_ name: String, _ run: @escaping Load) {
        loads.append((name, run))
    }

    /// Runs every registered load, in order, and returns when the last one is
    /// done.
    ///
    /// Callers may overlap freely — unlocking the phone in a lift foregrounds
    /// the app and restores signal within a frame of each other. A gentle run
    /// arriving while another is in flight simply waits for it instead of
    /// putting a second copy of every request on the wire. A **forced** run
    /// always gets a pass of its own, chained behind whatever is running: it
    /// is a promise of data fetched *after this moment*, and a run already
    /// halfway through its list cannot keep that promise.
    ///
    /// The work runs in an unstructured `Task` on purpose. The caller is
    /// usually a view's `.task`, which is cancelled the moment the view goes
    /// away; a revalidation triggered by foregrounding or by reconnection is
    /// about the app's data, not that view's lifetime, and should finish
    /// writing what it fetched rather than abandon it half-applied. Individual
    /// requests still surface `APIError.cancelled` normally if the session
    /// tears down underneath them.
    func revalidate(force: Bool = false) async {
        if !force, let inFlight {
            log.debug("revalidation already in flight, joining it")
            await inFlight.value
            return
        }
        let previous = inFlight
        let task = Task { @MainActor [loads] in
            await previous?.value
            for load in loads {
                await load.run(force)
            }
        }
        inFlight = task
        await task.value
        // Only if nothing has chained behind us: a later caller owns the slot
        // now, and clearing it would let a third caller start a parallel run.
        if inFlight == task { inFlight = nil }
        log.debug("revalidated \(self.loads.map(\.name).joined(separator: ", "), privacy: .public), force \(force, privacy: .public)")
    }
}
