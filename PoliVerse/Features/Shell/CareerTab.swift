import SwiftUI

/// Carriera: the libretto, the sittings and the results.
struct CareerTab: View {
    var body: some View {
        NavigationStack {
            NewDestination.career.screen
                .profileButton()
                .dataStatusLine()
        }
    }
}

#Preview("Carriera") {
    CareerTab().previewEnvironment()
}
