import SwiftUI

/// Not yet implemented.
///
/// `GET /rest/me/polimi/{matricola}` returns mean, earned CFU and planned CFU;
/// exam records come from `/rest/v1/insegn` on the exams host.
struct CareerView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Carriera", systemImage: "chart.bar")
            } description: {
                Text("Media, CFU ed esiti non sono ancora collegati.")
            }
            .navigationTitle("Carriera")
        }
    }
}
