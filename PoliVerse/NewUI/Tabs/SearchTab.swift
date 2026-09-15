import SwiftUI

/// The Cerca tab of the new structure. With the search role, the tab bar
/// shows it as its own button apart from the other tabs, and selecting it
/// turns that button into the search field.
struct SearchTab: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Cerca", systemImage: "magnifyingglass",
                                   description: Text("Corsi, aule, docenti ed esami."))
                .navigationTitle("Cerca")
        }
        .searchable(text: $query, prompt: "Corsi, aule, docenti")
    }
}

#Preview("Cerca") {
    SearchTab()
}
