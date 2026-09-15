import SwiftUI

/// Placeholder for the Cerca tab of the new structure.
struct SearchTab: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Cerca", systemImage: "magnifyingglass",
                                   description: Text("Corsi, aule, docenti ed esami."))
                .navigationTitle("Cerca")
        }
    }
}

#Preview("Cerca") {
    SearchTab()
}
