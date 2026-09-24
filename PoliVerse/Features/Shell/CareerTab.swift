import SwiftUI

/// Carriera: the libretto, the sittings and the results.
struct CareerTab: View {
    /// The view's content.
    var body: some View {
        NavigationStack {
            NewDestination.career.screen
                .flavorPaper()
                .profileButton()
                .dataStatusLine()
        }
    }
}

#Preview("Carriera") {
    CareerTab().previewEnvironment()
}
