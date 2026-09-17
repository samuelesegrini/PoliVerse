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
    /// How a service says, after a load, whether that load got anywhere.
    /// Nil for the ones that have no error to report.
    typealias Failure = @MainActor () -> String?
    /// How a service says how old the data it is holding is.
    typealias Age = @MainActor () -> TimeInterval?

    /// One service as Impostazioni shows it: what it is called, how old what
    /// it holds is, and what went wrong last time, if anything.
    struct ServiceStatus: Identifiable, Equatable {
        let id: String
        let title: String
        let age: TimeInterval?
        let failure: String?
    }

    private struct Registration {
        let name: String
        /// The service's name on screen, for the status line. Nil means the
        /// service is not worth naming to the student.
        let title: LocalizedStringResource?
        let failure: Failure?
        let age: Age?
        let run: Load
    }

    private var loads: [Registration] = []
    /// What the app tells the student about its data. Assigned by the app;
    /// nil in tests and in the few previews that build a bare coordinator.
    var status: DataStatus?
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
        courses: CourseModel,
        agenda: AgendaModel,
        career: CareerModel,
        notices: NoticeModel,
        news: NewsModel,
        weBeep: WeBeepModel
    ) -> FreshnessCoordinator {
        let coordinator = FreshnessCoordinator()
        coordinator.register("courses", title: "Corsi", failure: { courses.errorMessage }, age: { courses.age }) {
            await courses.load(force: $0)
        }
        coordinator.register("agenda", title: "Orario", failure: { agenda.errorMessage }, age: { agenda.age }) {
            await agenda.load(around: .now, force: $0)
        }
        coordinator.register("career", title: "Carriera", failure: { career.errorMessage }, age: { career.age }) {
            await career.load(force: $0)
        }
        // Last, as on Home: the bell is the least urgent thing on the screen,
        // and an endpoint whose shape is still unconfirmed should not delay
        // the content that is known to work.
        coordinator.register("notices", title: "Avvisi", failure: { notices.errorMessage }, age: { notices.age }) {
            await notices.load(force: $0)
        }
        coordinator.register("news", title: "Notizie", failure: { news.errorMessage }, age: { news.age }) {
            await news.load(force: $0)
        }
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
    /// - Parameters:
    ///   - title: how the service is named on screen, when a failed load has
    ///     to be reported. Omitted for work with nothing to show for itself.
    ///   - failure: read after each load; a non-nil message means that load
    ///     did not get what it went for.
    func register(_ name: String, title: LocalizedStringResource? = nil,
                  failure: Failure? = nil, age: Age? = nil, _ run: @escaping Load) {
        loads.append(Registration(name: name, title: title, failure: failure, age: age, run: run))
    }

    /// Every named service, read as they are now rather than as they were at
    /// the end of the last pass: a screen opened between passes should show
    /// what each service is actually holding, not a snapshot that has since
    /// gone stale. Reading the services here — inside a view's `body` — is
    /// also what keeps the list updating as loads land.
    var services: [ServiceStatus] {
        loads.compactMap { load in
            guard let title = load.title else { return nil }
            return ServiceStatus(id: load.name, title: String(localized: title),
                                 age: load.age?(), failure: load.failure?())
        }
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
        // `loads`, `status` and `log` by value, as before: the run belongs to
        // the app's data rather than to this object's lifetime.
        let task = Task { @MainActor [loads, status, log] in
            await previous?.value
            // Inside the chain, after the previous run: passes never overlap
            // here, which a same-named signpost requires.
            let interval = PerfSignpost.begin(.freshnessRevalidate)
            defer { PerfSignpost.end(interval) }
            status?.refreshBegan()
            var failed: [String] = []
            for load in loads {
                await load.run(force)
                // Read after the load, not inside it: a service clears its own
                // error when a load starts, so asking before would report the
                // previous pass.
                guard let message = load.failure?(), !message.isEmpty else { continue }
                log.notice("\(load.name, privacy: .public) failed: \(message, privacy: .private)")
                if let title = load.title { failed.append(String(localized: title)) }
            }
            status?.refreshEnded(failures: failed)
        }
        inFlight = task
        await task.value
        // Only if nothing has chained behind us: a later caller owns the slot
        // now, and clearing it would let a third caller start a parallel run.
        if inFlight == task { inFlight = nil }
        log.debug("revalidated \(self.loads.map(\.name).joined(separator: ", "), privacy: .public), force \(force, privacy: .public)")
    }
}
