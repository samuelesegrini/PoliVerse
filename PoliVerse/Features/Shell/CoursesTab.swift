import SwiftUI

/// Corsi: the courses with their materials, notices and sittings.
struct CoursesTab: View {
    /// The view's content.
    var body: some View {
        NavigationStack {
            NewDestination.courses.screen
                .flavorPaper()
                .profileButton()
                .dataStatusLine()
        }
    }
}

#Preview("Corsi") {
    CoursesTab().previewEnvironment()
}
