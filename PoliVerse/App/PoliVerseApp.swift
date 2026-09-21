import SwiftUI
import UserNotifications

@main
struct PoliVerseApp: App {
    @State private var session: Session
    @State private var courses: CourseModel
    @State private var agenda: AgendaModel
    @State private var career: CareerModel
    @State private var updates: UpdateFeed
    @State private var weBeep: WeBeepModel
    @State private var cieID = CieIDRouter()
    @State private var downloads = FileDownloadModel()
    @State private var rooms: RoomsModel
    @State private var notices: NoticeModel
    @State private var news: NewsModel
    @State private var freeRooms: FreeRoomsModel
    @State private var facilities = RoomFacilitiesModel()
    @State private var campusMap: CampusMapModel
    @State private var careers: CareersModel
    @State private var notifications: NotificationModel
    @State private var manifesti: ManifestiModel
    @State private var personalTimetable: PersonalTimetableModel
    @State private var programmes: StudyProgrammeModel
    @State private var network: NetworkMonitor
    @State private var pending: PendingChanges
    @State private var liveActivity = LiveActivityController()
    @State private var onboarding = OnboardingState()
    @State private var whatsNew = WhatsNewState()
    @State private var spid = SPIDCatalogue()
    @State private var loginMemory = LoginMethodMemory()
    @State private var freshness: FreshnessCoordinator
    @State private var status: DataStatus
    private let notificationRouter = NotificationRouter()
    private let background = BackgroundRefresh()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Before anything else: a report MetricKit has waiting is delivered to
        // whoever is subscribed, and a late subscription is how one gets lost.
        PerformanceMonitor.start()

        #if DEBUG
        // `-ResetTodayStyle` forgets the saved looks, so a UI test starts on
        // the presets. Passing the keys as arguments instead would pin them:
        // the argument domain wins over every later save.
        if CommandLine.arguments.contains("-ResetTodayStyle") {
            for key in [TodayStyle.storageKey, TodayStyle.libraryKey, TodayStyle.selectionKey] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        #endif

        // One Session, shared: every service reads its auth state and mock
        // flag, so they must all observe the same instance.
        let session = Session()
        _session = State(initialValue: session)

        // Early, and before every service that records into it: a change the
        // student makes offline has to have somewhere to go from the first
        // frame, and taking the queue from an initialiser is what stops a
        // service being built without one by accident.
        let network = NetworkMonitor()
        _network = State(initialValue: network)
        let pending = PendingChanges(account: session, network: network)
        _pending = State(initialValue: pending)

        // Through locals, like the rest: the `@State` wrappers are not
        // readable until the struct is fully initialised, and the freshness
        // registrations below need the instances themselves.
        let notices = NoticeModel(account: session)
        _notices = State(initialValue: notices)
        let careers = CareersModel(session: session)
        _careers = State(initialValue: careers)
        let news = NewsModel(account: session)
        _news = State(initialValue: news)
        // Reads the public catalogue rather than the API client: occupancy
        // comes from maps_rest, which needs no token.
        let rooms = RoomsModel()
        _rooms = State(initialValue: rooms)
        let manifesti = ManifestiModel()
        _manifesti = State(initialValue: manifesti)
        let freeRooms = FreeRoomsModel(catalogue: rooms)
        _freeRooms = State(initialValue: freeRooms)
        _campusMap = State(initialValue: CampusMapModel(catalogue: rooms, freeRooms: freeRooms))
        // Before the feed, which delivers through it: a change a load notices
        // is news, from the foreground or from a background refresh alike.
        let notifications = NotificationModel()
        _notifications = State(initialValue: notifications)
        // Before the two services that write to it.
        let updates = UpdateFeed(onNewUpdates: { await notifications.deliver($0) })
        _updates = State(initialValue: updates)
        let weBeep = WeBeepModel(session: session, feed: updates)
        _weBeep = State(initialValue: weBeep)

        let agenda = AgendaModel(session: session)
        _agenda = State(initialValue: agenda)
        _personalTimetable = State(initialValue: PersonalTimetableModel(manifesti: manifesti, agenda: agenda))
        let career = CareerModel(account: session, feed: updates, pending: pending)
        _career = State(initialValue: career)
        // Before the course list, which reads teaching codes out of it.
        let programmes = StudyProgrammeModel(manifesti: manifesti, session: session, career: career,
                                               careers: careers)
        _programmes = State(initialValue: programmes)
        let courses = CourseModel(account: session, enrolments: weBeep,
                                  pending: pending, programme: programmes)
        _courses = State(initialValue: courses)

        // The one dependency in this file that genuinely cannot be an
        // argument: the career is built *with* the feed, so the feed cannot be
        // built with the career. A WeBeep file is weighed against the
        // student's own sittings, and this is how the feed asks for them.
        updates.sittings = { career.sessions }

        // The one place the queue's cycle is broken. Everything it sends
        // through exists by now, and registering it here — rather than filling
        // four optional slots on the queue — means forgetting it is one
        // mistake rather than four silent ones. See ``PendingChanges/deliver``.
        pending.deliver { action in
            switch action {
            case .courseFavourite(let moodleID, let value):
                return await weBeep.setFavourite(value, moodleID: moodleID)
            case .courseHidden(let moodleID, let value):
                return await weBeep.setHidden(value, moodleID: moodleID)
            case .targetAverage(let media):
                return await career.saveTarget(media)
            case .favouriteCareer(let matricola):
                guard let match = careers.careers.first(where: { $0.matricola == matricola })
                else { return false }
                await careers.markFavourite(match)
                return true
            }
        } confirmedBy: { action in
            // The optimistic override exists only while the change is unsent.
            courses.confirmDelivered(action)
        }

        // One sentence about the data, told by the passes the coordinator runs
        // and read by the status line and Impostazioni.
        let status = DataStatus(session: session, network: network)
        _status = State(initialValue: status)
        // Built here because this is the only place that holds every
        // service; the order lives in the factory, next to the class.
        let freshness = FreshnessCoordinator.standard(
            courses: courses, agenda: agenda, career: career,
            notices: notices, news: news, weBeep: weBeep, status: status)
        _freshness = State(initialValue: freshness)

        // Deliberately narrower than the coordinator's list: a background
        // refresh gets about 30 seconds in total, so it warms the two screens
        // a student opens to and leaves the rest to the next foregrounding.
        background.register {
            let started = Date.now
            let interval = PerfSignpost.begin(.backgroundRefresh)
            defer { PerfSignpost.end(interval) }
            await agenda.load(force: true)
            await career.load(force: true)
            // Not forced: the hourly window keeps a burst of background runs
            // from reading every course page each time.
            // Measured from the start of the task: iOS gives about 30 s in
            // all, and the reschedule below needs a few of them.
            await weBeep.checkForUpdates(until: started.addingTimeInterval(22))
            // Reminders follow whatever the refresh found: a lecture moved
            // overnight must not announce itself at the old time.
            await notifications.reschedule(
                events: agenda.events, exams: career.sessions, assignments: updates.deadlines, updates: updates.updates)
            // Before iOS is told the task is done: it may suspend the app with
            // saves still queued and the widget reload still gathering.
            await WidgetReloader.flush()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(courses)
                .environment(agenda)
                .environment(career)
                .environment(updates)
                .environment(weBeep)
                .environment(cieID)
                .environment(downloads)
                .environment(rooms)
                .environment(notices)
                .environment(news)
                .environment(freeRooms)
                .environment(facilities)
                .environment(campusMap)
                .environment(careers)
                .environment(notifications)
                .environment(manifesti)
                .environment(personalTimetable)
                .environment(programmes)
                .environment(network)
                .environment(pending)
                .environment(liveActivity)
                .environment(freshness)
                .environment(status)
                .environment(onboarding)
                .environment(whatsNew)
                .environment(spid)
                .environment(loginMemory)
                // The locale used to be pinned to it_IT, because every string
                // was hardcoded Italian and `.formatted(.relative(…))` would
                // otherwise render "4 weeks ago" beside "Lezioni". The String
                // Catalog removes that reason: dates and text now follow the
                // same language, whichever the reader has chosen.
                // CieID hands control back through our URL scheme. Route it to
                // the router, which passes it to whichever login web view is
                // on screen so the session can continue where it left off.
                .onOpenURL { url in
                    if cieID.handle(url) { return }
                    AppDestination(url: url)?.send()
                }
                // Set once, here: a delegate assigned from a view would be
                // replaced every time that view was rebuilt.
                .task {
                    UNUserNotificationCenter.current().delegate = notificationRouter
                    await notifications.refreshAuthorization()
                }
                // Asked for when the app leaves the screen, which is the
                // moment iOS is deciding whether to grant one.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        background.schedule()
                        Task { await WidgetReloader.appDidEnterBackground() }
                    }
                    if phase == .active {
                        Task {
                            await pending.flush()
                            // Not forced: `LoadWindow` makes a return from the
                            // app switcher free and a return after lunch one
                            // round trip. Forcing here would turn every glance
                            // at the multitasking view into five requests.
                            //
                            // Skipped mid-login: CieID (and the SPID/eIDAS
                            // providers) hand control back by backgrounding
                            // this app and then foregrounding it, which lands
                            // right here *before* `completeLogin` has finished
                            // exchanging the code. Revalidating now would race
                            // it — every service needing the OAuth token fails
                            // with no account yet to blame it on, and the
                            // resulting "Aggiornamento non riuscito per 4
                            // servizi" stuck around until the next foreground
                            // even once sign-in actually succeeded. The
                            // `session.state` watcher below covers the real
                            // post-login revalidate instead.
                            if session.state != .exchangingCode {
                                await freshness.revalidate()
                            }
                            await personalTimetable.refreshIfStale()
                            await freeRooms.refreshForWidgetIfNeeded()
                        }
                    }
                }
                // The moment signal returns is the moment to send what was
                // queued — not the next time the user happens to open a tab.
                .onChange(of: network.isOnline) { _, online in
                    if online {
                        Task {
                            await pending.flush()
                            // Forced, unlike the foreground path: whatever is
                            // on screen was fetched before the outage, and the
                            // window has no way of knowing that.
                            await freshness.revalidate(force: true)
                        }
                    }
                }
                // The queue is per matricola, so switching career must show
                // that career's waiting changes rather than the last one's.
                .onChange(of: session.student?.matricola) { _, _ in
                    pending.refresh()
                }
                // The one guaranteed moment a login (or career switch) has
                // just finished: token in hand, the account confirmed by
                // `/jaf/internal/user`. Forced, because this is the pass that
                // is supposed to fill an empty screen with Orario, Carriera,
                // Avvisi and Notizie right after signing in — a gentle run
                // here could still be joined to whatever the scene-phase
                // handler skipped above, and end up doing nothing.
                .onChange(of: session.state) { _, newValue in
                    if case .signedIn = newValue {
                        Task { await freshness.revalidate(force: true) }
                    }
                }
        }
    }
}
