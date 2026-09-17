import SwiftUI

/// WeBeep signs in separately, and this is where that stops being a surprise.
///
/// The materials live on a Moodle with its own session, so the Politecnico
/// login just done does not carry over. Without this step the WeBeep tab is
/// simply empty with a login button on it, which reads as a broken feature
/// rather than a second front door.
struct WeBeepStepView: View {
    @Environment(WeBeepModel.self) private var weBeep
    @Environment(CourseModel.self) private var courses
    let advance: () -> Void

    @State private var showingLogin = false

    var body: some View {
        OnboardingStepLayout(
            symbol: "books.vertical.fill",
            title: "Collega WeBeep",
            detail: "Dispense, registrazioni e avvisi dei tuoi corsi. WeBeep ha una sessione sua, separata da quella dei Servizi Online, quindi serve un secondo accesso — una volta sola."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingPoint(
                    symbol: "arrow.down.circle",
                    text: "I file si scaricano e restano leggibili offline.")
                OnboardingPoint(
                    symbol: "clock.arrow.circlepath",
                    text: "Si può fare più tardi: la trovi nella scheda WeBeep quando ti serve.")
            }
        } actions: {
            if weBeep.isAuthenticated {
                OnboardingPrimaryButton(title: "Continua", action: advance)
            } else {
                OnboardingPrimaryButton(title: "Collega WeBeep") { showingLogin = true }
                OnboardingSkipButton(action: advance)
            }
        }
        .sheet(isPresented: $showingLogin) {
            WeBeepLoginSheet {
                await courses.load(force: true)
                advance()
            }
        }
    }
}

// MARK: - Previews

#Preview("WeBeep") {
    WeBeepStepView(advance: {}).previewEnvironment()
}
