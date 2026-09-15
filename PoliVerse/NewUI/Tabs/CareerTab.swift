import SwiftUI

/// Carriera: the libretto, the sittings and the results.
struct CareerTab: View {
    var body: some View {
        NavigationStack {
            NewDestination.career.screen
                .profileButton()
                .demoModeBanner()
        }
    }
}

#Preview("Carriera") {
    CareerTab().previewEnvironment()
}
