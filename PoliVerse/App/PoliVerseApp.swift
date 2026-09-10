import SwiftUI

@main
struct PoliVerseApp: App {
    @State private var session: Session
    @State private var courses: CourseService

    init() {
        // One Session, shared: CourseService reads its auth state, so it must
        // be the same instance the views observe.
        let session = Session()
        _session = State(initialValue: session)
        _courses = State(initialValue: CourseService(session: session))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(courses)
                .tint(Theme.brand)
                // Every user-facing string in the app is Italian, so pin the
                // locale too — otherwise `.formatted(.relative(…))` renders
                // "4 weeks ago" next to "Lezioni". Revisit when a String
                // Catalog adds real localisation.
                .environment(\.locale, Locale(identifier: "it_IT"))
        }
    }
}
