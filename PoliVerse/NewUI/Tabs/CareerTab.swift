import SwiftUI

/// Placeholder for the Carriera tab of the new structure.
struct CareerTab: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Carriera", systemImage: "graduationcap",
                                   description: Text("Libretto, piano di studi e media."))
                .navigationTitle("Carriera")
        }
    }
}

#Preview("Carriera") {
    CareerTab()
}
