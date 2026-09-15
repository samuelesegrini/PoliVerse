import SwiftUI

/// The Cerca tab of the new structure. Its search role lets the tab bar float
/// it apart from the other tabs.
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
