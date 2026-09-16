import SwiftUI

extension NewDestination {
    /// The screen a place opens, inside a navigation stack that is not its
    /// own: a tab's, Cerca's, or the panel's.
    @MainActor @ViewBuilder
    var screen: some View {
        switch self {
        case .courses: WeBeepView(embedded: true)
        case .career: CareerView(embedded: true)
        case .calendar: CalendarView(embedded: true)
        case .freeRooms: FreeRoomsView()
        case .map: CampusMapView()
        case .studyPlan: StudyPlanView()
        case .news: NewsView()
        case .notices: NoticesView(embedded: true)
        }
    }
}

/// The student's photo in a bar, opening Impostazioni on the profile.
struct ProfileBarButton: View {
    @Environment(Session.self) private var session
    @Environment(\.shell) private var shell

    var body: some View {
        Button { shell.openProfile() } label: {
            // Laid out at a symbol's width so the bar sizes its glass as the
            // same circle as the other buttons; the photo draws a little
            // larger inside it.
            ProfileAvatar(student: session.student, size: 34)
                .frame(width: 12, height: 12)
        }
        .accessibilityLabel("Profilo")
        .accessibilityIdentifier("bar-profile")
    }
}

extension View {
    /// The profile at the leading edge of a root screen's bar: the same way
    /// in from every root.
    func profileButton() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarLeading) { ProfileBarButton() }
        }
    }
}
