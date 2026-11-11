import SwiftUI

/// A skippable account check: three live results, with no queue of login sheets.
struct JourneyConnections: View {
    @Environment(Session.self) private var session
    @Environment(CareersModel.self) private var careers
    @Environment(OnboardingState.self) private var onboarding
    let advance: () -> Void
    @State private var choosingCareer = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    JourneyTitle(resource: "I tuoi servizi,\n_collegati._")
                    JourneyNote(text: "Un accesso, tre collegamenti. Se serve un altro passaggio, puoi completarlo qui.")
                    ConnectionRows(appearance: .onboarding)
                    JourneyNote(text: "Puoi continuare: i collegamenti proseguono in background. Li ritrovi in Impostazioni.")
                    if careers.hasChoice {
                        JourneyLink(title: "Scegli la matricola") { choosingCareer = true }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            // Extend the viewport into the page insets so shadows have room;
            // keep vertical clipping above the fixed Continue button.
            .padding(.horizontal, -24)
            .scrollBounceBehavior(.basedOnSize)
            Spacer(minLength: 12)
            JourneyAction(title: "Continua", action: advance)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding-connections")
        .task { await careers.load() }
        .sheet(isPresented: $choosingCareer) {
            JourneyCareerSheet { choosingCareer = false }
        }
        .task(id: session.student == nil) {
            if session.student == nil, onboarding.reopensSignIn {
                choosingCareer = false
                onboarding.jumpJourney(to: .signIn)
            }
        }
    }
}
