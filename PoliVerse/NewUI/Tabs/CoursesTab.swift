import SwiftUI

/// Placeholder for the Corsi tab of the new structure.
struct CoursesTab: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Corsi", systemImage: "books.vertical",
                                   description: Text("I tuoi corsi con materiali, avvisi e appelli."))
                .navigationTitle("Corsi")
        }
    }
}

#Preview("Corsi") {
    CoursesTab()
}
