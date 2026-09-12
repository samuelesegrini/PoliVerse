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
        _courses = State(initialValue: CourseService(session: session, weBeep: weBeep))

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
                .tint(Theme.brand)
                // Every user-facing string in the app is Italian, so pin the
                // locale too — otherwise `.formatted(.relative(…))` renders
                // "4 weeks ago" next to "Lezioni". Revisit when a String
                // Catalog adds real localisation.
                .environment(\.locale, Locale(identifier: "it_IT"))
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
                }
        }
    }
}
