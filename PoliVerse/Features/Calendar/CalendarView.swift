import SwiftUI

/// Not yet implemented.
///
/// The endpoint is known — `GET /agenda/api/me/{matricola}/events` on the app
/// host, with lecture detail at `/agenda/api/me/{matricola}/lectures/{id}` —
/// so this is wiring, not research.
struct CalendarView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Calendario", systemImage: "calendar")
            } description: {
                Text("L'orario delle lezioni non è ancora collegato.")
            }
            .navigationTitle("Calendario")
        }
    }
}
