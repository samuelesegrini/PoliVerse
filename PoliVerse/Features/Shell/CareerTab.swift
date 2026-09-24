import SwiftUI

/// Carriera: the libretto, the sittings and the results.
struct CareerTab: View {
    /// The environment's `shell`.
    @Environment(\.shell) private var shell

    /// The view's content.
    var body: some View {
        NavigationStack(path: Binding(get: { shell.careerPath }, set: { shell.careerPath = $0 })) {
            NewDestination.career.screen
                // The study plan, when a way in from outside asks for it.
                .navigationDestination(for: NewDestination.self) { $0.screen }
                .flavorPaper()
                .profileButton()
                .dataStatusLine()
        }
    }
}

#Preview("Carriera") {
    CareerTab().previewEnvironment()
}
