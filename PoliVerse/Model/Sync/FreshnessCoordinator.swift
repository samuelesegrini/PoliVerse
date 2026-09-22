import Foundation
import OSLog

/// The single definition of what refreshing everything means.
///
/// Services register a load with ``register(_:title:failure:age:_:)``, and
/// ``revalidate(force:)`` runs the registered loads in registration order.
/// ``standard(courses:agenda:career:notices:news:weBeep:status:)`` builds the set
/// the app and the preview environment both use.
///
/// The coordinator holds no opinion about when to refresh; callers decide that.
/// Whether a given load reaches the network remains ``LoadWindow``'s decision, so
/// calling ``revalidate(force:)`` on every return from the app switcher costs no
/// requests.
///
/// ``services`` reports each named service's age and last error for Impostazioni,
/// and ``status`` receives the begin and end of every pass.
@MainActor
@Observable
final class FreshnessCoordinator {
    /// One service's load: takes a `force` flag, returns when the data is in.
    typealias Load = @MainActor (_ force: Bool) async -> Void
    /// Reports whether the last load got what it went for. `nil` means no error to
    /// report.
    typealias Failure = @MainActor () -> String?
    /// Reports how old the data a service is holding is, in seconds.
    typealias Age = @MainActor () -> TimeInterval?

    /// One service as Impostazioni shows it: its name, the age of what it holds, and
    /// what went wrong last time.
    struct ServiceStatus: Identifiable, Equatable {
        /// The registration name, unique within the coordinator.
        let id: String
        /// The service's localised name on screen.
        let title: String
        /// Seconds since the held data was fetched, or `nil` if unknown.
        let age: TimeInterval?
        /// The last load's error message, or `nil` when the last load succeeded.
        let failure: String?
    }

    /// One registered load and everything the coordinator reports about it.
    private struct Registration {
        /// Identifies the registration in the log and in ``ServiceStatus/id``.
        let name: String
        /// The service's name on screen. `nil` for work with nothing to show the student,
        /// which is then omitted from ``services`` and never named in a failure.
        let title: LocalizedStringResource?
        /// Read after each load to detect a failure.
        let failure: Failure?
        /// Read on demand to report the age of the held data.
        let age: Age?
        /// The load itself.
        let run: Load
    }

    /// The registered loads, in the order they run.
    private var loads: [Registration] = []
    /// What the app tells the student about its data.
    ///
    /// Set by ``standard(courses:agenda:career:notices:news:weBeep:status:)`` along
    /// with the rest of the set, and optional for the tests and previews that build a
    /// bare coordinator with no status line to feed.
    var status: DataStatus?
    /// The pass currently running, if any. Later passes join it or chain behind it
    /// rather than racing it.
    private var inFlight: Task<Void, Never>?
    /// Diagnostic log for this type, under the `freshness` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "freshness")

    /// Builds the coordinator with every service the app refreshes, in the order the
    /// home screen wants them.
    ///
    /// Courses, the timetable and the career come first, as the content on screen.
    /// Notices and news follow. The WeBeep update sweep runs last: it reads several
    /// course pages and what it finds lands in ``UpdateFeed`` rather than on an open
    /// screen.
    ///
    /// - Parameters:
    ///   - courses: Loaded as `courses`, titled Corsi.
    ///   - agenda: Loaded as `agenda` around the current date, titled Orario.
    ///   - career: Loaded as `career`, titled Carriera.
    ///   - notices: Loaded as `notices`, titled Avvisi.
    ///   - news: Loaded as `news`, titled Notizie.
    ///   - weBeep: Swept for updates as `webeep-updates`, unnamed on screen.
    ///   - status: Receives the begin and end of every pass.
    /// - Returns: A coordinator with all six registrations in place.
    static func standard(
        courses: CourseModel,
        agenda: AgendaModel,
        career: CareerModel,
        notices: NoticeModel,
        news: NewsModel,
        weBeep: WeBeepModel,
        status: DataStatus? = nil
    ) -> FreshnessCoordinator {
        let coordinator = FreshnessCoordinator()
        coordinator.status = status
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
    /// The closure captures its service strongly. Every service is held by
    /// ``PoliVerseApp`` for the life of the process and no service holds the
    /// coordinator, so there is neither anything to release nor a cycle to break.
    ///
    /// - Parameters:
    ///   - name: Identifies the registration in the log and in ``services``.
    ///   - title: The service's name on screen, used when a failed load has to be
    ///     reported. Omit for work with nothing to show for itself.
    ///   - failure: Read after each load; a non-empty message means that load did not
    ///     get what it went for.
    ///   - age: Read on demand for ``services``.
    ///   - run: The load itself.
    func register(_ name: String, title: LocalizedStringResource? = nil,
                  failure: Failure? = nil, age: Age? = nil, _ run: @escaping Load) {
        loads.append(Registration(name: name, title: title, failure: failure, age: age, run: run))
    }

    /// Every named service, read as it stands now rather than as it stood at the end
    /// of the last pass.
    ///
    /// Registrations without a title are omitted. Reading this inside a view's `body`
    /// is what keeps Impostazioni updating as loads land.
    var services: [ServiceStatus] {
        loads.compactMap { load in
            guard let title = load.title else { return nil }
            return ServiceStatus(id: load.name, title: String(localized: title),
                                 age: load.age?(), failure: load.failure?())
        }
    }

    /// Runs every registered load in order and returns when the last one is done.
    ///
    /// Callers may overlap freely. A gentle pass arriving while another is in flight
    /// waits for it instead of putting a second copy of every request on the wire. A
    /// forced pass always gets a pass of its own, chained behind whatever is running,
    /// because it promises data fetched after the moment it was asked for.
    ///
    /// The work runs in an unstructured `Task`, so a pass triggered by foregrounding
    /// or by reconnection finishes writing what it fetched even though the view whose
    /// `.task` started it has gone away. Individual requests still surface
    /// cancellation normally if the session tears down beneath them.
    ///
    /// A service's failure is read after its load rather than during it, since a
    /// service clears its own error when a load begins.
    ///
    /// - Parameter force: Passed to every registered load, bypassing their load
    ///   windows, and gives this pass a run of its own.
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
