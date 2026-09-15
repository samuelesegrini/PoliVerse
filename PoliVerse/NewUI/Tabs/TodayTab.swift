import SwiftUI

/// The Oggi tab of the tab layout: the day's lessons, exams and deadlines,
/// under the shared ``TodayBar``.
struct TodayTab: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                ContentUnavailableView("Oggi", systemImage: "calendar.day.timeline.left",
                                       description: Text("Lezioni, esami e scadenze del giorno."))
                    .padding(.top, 120)
            }
            .todayBar()
        }
    }
}

#Preview("Oggi") {
    TodayTab().previewEnvironment()
}
