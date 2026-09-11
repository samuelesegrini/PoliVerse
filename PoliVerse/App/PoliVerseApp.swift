import SwiftUI

@main
struct PoliVerseApp: App {
    @State private var session: Session
    @State private var courses: CourseService
    @State private var agenda: AgendaService
    @State private var career: CareerService
    @State private var weBeep: WeBeepService

    init() {
        // One Session, shared: every service reads its auth state and mock
        // flag, so they must all observe the same instance.
        let session = Session()
        _session = State(initialValue: session)
        _courses = State(initialValue: CourseService(session: session))
        _agenda = State(initialValue: AgendaService(session: session))
        _career = State(initialValue: CareerService(session: session))
        _weBeep = State(initialValue: WeBeepService(session: session))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(courses)
                .environment(agenda)
                .environment(career)
                .environment(weBeep)
                .tint(Theme.brand)
                // Every user-facing string in the app is Italian, so pin the
                // locale too — otherwise `.formatted(.relative(…))` renders
                // "4 weeks ago" next to "Lezioni". Revisit when a String
                // Catalog adds real localisation.
                .environment(\.locale, Locale(identifier: "it_IT"))
        }
    }
}
