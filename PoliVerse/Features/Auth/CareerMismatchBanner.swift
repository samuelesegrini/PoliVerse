import SwiftUI

/// Offers a switch when the app is signed in on the wrong enrolment.
///
/// The symptom this exists for is not obviously an account problem: exams,
/// libretto and the timetable all fail or come back empty while WeBeep and
/// news work perfectly, because the token is bound to a closed career and the
/// exam services refuse it. Nothing on screen would say so without this.
///
/// Advisory, never automatic: switching re-runs authorisation through a web
/// view, which is not something to do to someone without asking.
struct CareerMismatchBanner: View {
    /// The shared ``CareersModel``, from the environment.
    @Environment(CareersModel.self) private var careers
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session

    /// The view's content.
    var body: some View {
        if let suggested = careers.suggestedSwitch() {
            NavigationLink {
                CareerSwitchView()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sei sulla matricola \(session.student?.matricola ?? "—")")
                            .font(.subheadline.weight(.semibold))
                        Text("La carriera \(suggested.label.lowercased()) (\(suggested.matricola)) è quella attiva. Esami e orario rispondono solo per quella.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.12), in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .task { await careers.load() }
        }
    }
}

// MARK: - Previews

#Preview("Carriera sbagliata") {
    CareerMismatchBanner()
        .padding()
        .previewInNavigation()
}
