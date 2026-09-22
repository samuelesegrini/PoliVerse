import SwiftUI

/// Which enrolment the app is looking at, when there is more than one.
///
/// Shown only when the account actually has a choice. It does not switch here:
/// the token is bound to the matricola that was signed in with, and moving it
/// means signing out and back in — see ``CareerSwitchView``, which says so.
/// What this step does is make sure nobody spends a week wondering why their
/// exams are missing because the app is pointed at the triennale they
/// finished.
struct CareerStepView: View {
    /// The shared ``CareersModel``, from the environment.
    @Environment(CareersModel.self) private var careers
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The onboarding flow's accent, taken from the look in use.
    private var tint = OnboardingTint()
    /// Moves the flow on to the next step.
    let advance: () -> Void

    /// The view's content.
    var body: some View {
        OnboardingStepLayout(
            symbol: "person.2.badge.gearshape.fill",
            title: "Hai più di una carriera",
            detail: "Il codice persona è uno solo, ma ogni immatricolazione ha la sua matricola — e i servizi del Politecnico rispondono solo per quella con cui hai fatto l'accesso."
        ) {
            VStack(spacing: 10) {
                // The step exists because the account has more than one
                // enrolment, but the list itself can still be in flight — and
                // an empty column under "Hai più di una carriera" reads as the
                // app having lost them.
                if careers.careers.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Carico le tue carriere…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                ForEach(careers.careers) { career in
                    let inUse = career.matricola == session.student?.matricola
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(career.matricola)
                                .font(.subheadline.weight(.semibold))
                                // Digit-for-digit alignment between the rows:
                                // two matricole differ in one place and that
                                // place has to land under itself.
                                .monospaced()
                            Text(career.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if inUse {
                            Text("In uso")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(tint.color.opacity(0.15), in: .capsule)
                                .foregroundStyle(tint.color)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .lookCard(cornerRadius: 12)
                    // Nothing here is a choice — the token decides — so the
                    // rows must not all look equally live. The one in use is
                    // ringed, the others recede: a card that looks pressable
                    // and does nothing is worse than a card that looks read-only.
                    .overlay {
                        if inUse {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(tint.color.opacity(0.55), lineWidth: 1.5)
                        }
                    }
                    .opacity(inUse ? 1 : 0.55)
                    .accessibilityElement(children: .combine)
                }

                Text("Per cambiare serve un nuovo accesso: lo trovi in Impostazioni · Matricola. Da lì l'app te lo spiega prima di farlo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        } actions: {
            OnboardingPrimaryButton(
                title: careers.careers.isEmpty ? "Continua" : "Continua con questa"
            ) {
                // Remembered so the mismatch banner knows this was a choice
                // rather than an accident.
                if let current = careers.current { careers.remember(current) }
                advance()
            }
        }
    }
}

// MARK: - Previews

#Preview("Carriera") {
    CareerStepView(advance: {}).previewEnvironment()
}
