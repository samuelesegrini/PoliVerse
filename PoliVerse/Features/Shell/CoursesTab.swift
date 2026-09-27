import SwiftUI

/// Corsi: the courses with their materials, notices and sittings.
struct CoursesTab: View {
    /// The view's content.
    var body: some View {
        NavigationStack {
            #if os(macOS)
            // The Mac keeps the list beside the course; see ``MacCoursesView``. Its
            // table's status bar says what the floating status line would.
            MacCoursesView()
            #else
            NewDestination.courses.screen
                .flavorPaper()
                .profileButton()
                .dataStatusLine()
            #endif
        }
    }
}

#Preview("Corsi") {
    CoursesTab().previewEnvironment()
}
