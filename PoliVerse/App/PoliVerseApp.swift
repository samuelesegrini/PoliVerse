import SwiftUI
import UserNotifications

@main
struct PoliVerseApp: App {
    @State private var session: Session
    @State private var courses: CourseService
    @State private var agenda: AgendaService
    @State private var career: CareerService
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
    @State private var manifesti = ManifestiService()
    @State private var network: NetworkMonitor
    @State private var pending: PendingChanges
    private let notificationRouter = NotificationRouter()
    private let background = BackgroundRefresh()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // One Session, shared: every service reads its auth state and mock
        // flag, so they must all observe the same instance.
        let session = Session()
        _session = State(initialValue: session)

        _notices = State(initialValue: NoticeService(session: session))
        _careers = State(initialValue: CareersService(session: session))
        _news = State(initialValue: NewsService(session: session))
        // Reads the public catalogue rather than the API client: occupancy
        // comes from maps_rest, which needs no token.
        let rooms = RoomsService()
        _rooms = State(initialValue: rooms)
        let freeRooms = FreeRoomsService(catalogue: rooms)
        _freeRooms = State(initialValue: freeRooms)
        _campusMap = State(initialValue: CampusMapService(catalogue: rooms, freeRooms: freeRooms))
        let weBeep = WeBeepService(session: session)
        _weBeep = State(initialValue: weBeep)
        let courses = CourseService(session: session, weBeep: weBeep)
        _courses = State(initialValue: courses)

        // Registered here, at the end of init: it has to happen before the
        // app finishes launching — registering later throws — and it captures
        // the services directly rather than through the State wrappers, which
        // are not readable until the struct is fully initialised.
        let agenda = AgendaService(session: session)
        _agenda = State(initialValue: agenda)
        let career = CareerService(session: session)
        _career = State(initialValue: career)
        let notifications = NotificationService()
        _notifications = State(initialValue: notifications)

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

        background.register {
            await agenda.load(force: true)
            await career.load(force: true)
            // Reminders follow whatever the refresh found: a lecture moved
            // overnight must not announce itself at the old time.
            await notifications.reschedule(
                events: agenda.events, exams: career.sessions)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(courses)
                .environment(agenda)
                .environment(career)
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
                .environment(network)
                .environment(pending)
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
                    // After the first frame, deliberately: subscribing is not
                    // free and nothing about it needs to happen before the UI
                    // is on screen.
                    LaunchMetrics.start()
                }
                // Asked for when the app leaves the screen, which is the
                // moment iOS is deciding whether to grant one.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { background.schedule() }
                    if phase == .active { Task { await pending.flush() } }
                }
                // The moment signal returns is the moment to send what was
                // queued — not the next time the user happens to open a tab.
                .onChange(of: network.isOnline) { _, online in
                    if online { Task { await pending.flush() } }
                }
                // The queue is per matricola, so switching career must show
                // that career's waiting changes rather than the last one's.
                .onChange(of: session.student?.matricola) { _, _ in
                    pending.refresh()
                }
        }
    }
}
