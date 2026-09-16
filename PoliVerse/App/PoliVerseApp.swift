import SwiftUI
import UserNotifications

@main
struct PoliVerseApp: App {
    @State private var session: Session
    @State private var courses: CourseService
    @State private var agenda: AgendaService
    @State private var career: CareerService
    @State private var updates: UpdateFeed
    @State private var weBeep: WeBeepService
    @State private var cieID = CieIDRouter()
    @State private var downloads = FileDownloadService()
    @State private var rooms: RoomsService
    @State private var notices: NoticeService
    @State private var news: NewsService
    @State private var freeRooms: FreeRoomsService
    @State private var facilities = RoomFacilitiesService()
    @State private var campusMap: CampusMapService
    @State private var careers: CareersService
    @State private var notifications: NotificationService
    @State private var manifesti: ManifestiService
    @State private var personalTimetable: PersonalTimetableService
    @State private var programmes: StudyProgrammeService
    @State private var network: NetworkMonitor
    @State private var pending: PendingChanges
    @State private var liveActivity = LiveActivityController()
    @State private var onboarding = OnboardingState()
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

        // Through locals, like the rest: the `@State` wrappers are not
        // readable until the struct is fully initialised, and the freshness
        // registrations below need the instances themselves.
        let notices = NoticeService(session: session)
        _notices = State(initialValue: notices)
        let careers = CareersService(session: session)
        _careers = State(initialValue: careers)
        let news = NewsService(session: session)
        _news = State(initialValue: news)
        // Reads the public catalogue rather than the API client: occupancy
        // comes from maps_rest, which needs no token.
        let rooms = RoomsService()
        _rooms = State(initialValue: rooms)
        let manifesti = ManifestiService()
        _manifesti = State(initialValue: manifesti)
        let freeRooms = FreeRoomsService(catalogue: rooms)
        _freeRooms = State(initialValue: freeRooms)
        _campusMap = State(initialValue: CampusMapService(catalogue: rooms, freeRooms: freeRooms))
        // Before the two services that write to it.
        let updates = UpdateFeed()
        _updates = State(initialValue: updates)
        let weBeep = WeBeepService(session: session, feed: updates)
        _weBeep = State(initialValue: weBeep)
        let courses = CourseService(session: session, weBeep: weBeep)
        _courses = State(initialValue: courses)

        // Registered here, at the end of init: it has to happen before the
        // app finishes launching — registering later throws — and it captures
        // the services directly rather than through the State wrappers, which
        // are not readable until the struct is fully initialised.
        let agenda = AgendaService(session: session)
        _agenda = State(initialValue: agenda)
        _personalTimetable = State(initialValue: PersonalTimetableService(manifesti: manifesti, agenda: agenda))
        let career = CareerService(session: session, feed: updates)
        _career = State(initialValue: career)
        let programmes = StudyProgrammeService(manifesti: manifesti, session: session, career: career,
                                               careers: careers)
        _programmes = State(initialValue: programmes)
        courses.programme = programmes
        let notifications = NotificationService()
        _notifications = State(initialValue: notifications)
        // A change a load notices is news: delivered as it is found, from the
        // foreground or from a background refresh alike.
        updates.onNewUpdates = { await notifications.deliver($0) }
        // A WeBeep file is weighed against the student's own sittings.
        updates.sittings = { career.sessions }

        // Built last: it needs the session, and the services it sends
        // through are wired to it afterwards.
        let network = NetworkMonitor()
        _network = State(initialValue: network)
        let pending = PendingChanges(session: session, network: network)
        pending.weBeep = weBeep
        pending.career = career
        pending.courses = courses
        _pending = State(initialValue: pending)
        // Through the locals, not the `@State` wrappers: those are only
        // readable once the struct is fully initialised, and reading one too
        // early is a compile error that moves as the file is edited.
        courses.pending = pending
        career.pending = pending

        // Built here because this is the only place that holds every
        // service; the order lives in the factory, next to the class.
        let freshness = FreshnessCoordinator.standard(
            courses: courses, agenda: agenda, career: career,
            notices: notices, news: news, weBeep: weBeep)
        // One sentence about the data, told by the passes the coordinator
        // runs and read by the status line and Impostazioni.
        let status = DataStatus(session: session, network: network)
        freshness.status = status
        _status = State(initialValue: status)
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
            Group {
                #if DEBUG
                // `-NewUI` launches the restructured shell being tried out.
                if CommandLine.arguments.contains("-NewUI") { NewRootView() } else { RootView() }
                #else
                RootView()
                #endif
            }
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
                .environment(spid)
                .environment(loginMemory)
                .tint(Theme.brand)
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
                            await freshness.revalidate()
                            await personalTimetable.refreshIfStale()
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
        }
    }
}
