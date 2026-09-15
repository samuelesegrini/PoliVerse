import SwiftUI

/// Placeholder for the Oggi tab of the new structure.
struct TodayTab: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Oggi", systemImage: "calendar.day.timeline.left",
                                   description: Text("Lezioni, esami e scadenze del giorno."))
                .navigationTitle("Oggi")
        }
    }
}

#Preview("Oggi") {
    TodayTab()
}
