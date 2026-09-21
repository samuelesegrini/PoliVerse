import SwiftUI

/// What PoliVerse is, before it asks for anything.
///
/// A deck of the app's own screens rather than a list of features: this used
/// to be five symbols over five paragraphs, which said what the app does
/// without ever showing it. ``FeatureTour`` draws the screens themselves, in
/// the look in use, and this step is the frame around it — the choice between
/// a real account and the sample data, stated here rather than left as a
/// switch in Settings, which is where it used to live while being on by
/// default.
struct WelcomeStepView: View {
    @Environment(Session.self) private var session
    private var tint = OnboardingTint()
    let advance: () -> Void

    var body: some View {
        FeatureTour {
            actions
        }
    }

    /// The choice the first screen exists to offer. Handed to the tour rather
    /// than stacked under it, so it comes out of the blur with the words.
    private var actions: some View {
        VStack(spacing: 14) {
                OnboardingPrimaryButton(title: "Accedi con account Polimi") {
                    // Explicit: the account route turns the sample data off,
                    // so nobody signs in and still reads invented lectures.
                    session.useMockData = false
                    advance()
                }

                Button {
                    session.useMockData = true
                    advance()
                } label: {
                    Text("Esplora con dati di esempio")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint.color)
                .accessibilityIdentifier("onboarding-demo")

                Text("PoliVerse non è un'app ufficiale del Politecnico di Milano. Le credenziali si inseriscono solo nella pagina di ateneo.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
    }
}

// MARK: - Previews

#Preview("Benvenuto") {
    WelcomeStepView(advance: {}).previewEnvironment()
}
