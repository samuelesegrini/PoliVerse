import SwiftUI

/// Corsi: the courses with their materials, notices and sittings.
struct CoursesTab: View {
    var body: some View {
        NavigationStack {
            NewDestination.courses.screen
                .profileButton()
                .demoModeBanner()
        }
    }
}

#Preview("Corsi") {
    CoursesTab().previewEnvironment()
}
