import SwiftUI

@main
struct PoliVerseApp: App {
    @State private var session: Session
    @State private var courses: CourseService
    @State private var agenda: AgendaService
    @State private var career: CareerService
    @State private var weBeep: WeBeepService
    @State private var cieID = CieIDRouter()
    @State private var downloads = FileDownloadService()
    @State private var rooms = RoomsService()
    @State private var notices: NoticeService

    init() {
        // One Session, shared: every service reads its auth state and mock
        // flag, so they must all observe the same instance.
        let session = Session()
        _session = State(initialValue: session)

        _agenda = State(initialValue: AgendaService(session: session))
        _career = State(initialValue: CareerService(session: session))
        _notices = State(initialValue: NoticeService(session: session))
        let weBeep = WeBeepService(session: session)
        _weBeep = State(initialValue: weBeep)
        _courses = State(initialValue: CourseService(session: session, weBeep: weBeep))
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
        }
    }
}
