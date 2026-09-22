import OSLog
import SwiftUI

/// Choose which enrolment the app is looking at.
///
/// Switching is not cosmetic. The token is bound to one matricola, so the
/// other career's services refuse it outright — a student who finished the
/// triennale and started the magistrale sees "Utente non abilitato" across
/// exams and an empty timetable until this is pointed at the right one.
///
/// ## Why this signs out
///
/// The Politecnico has an endpoint for exactly this — `/careerChange`, which
/// moves an existing grant without a new login — and it **errors**, in the
/// official app as well as here. So the honest route is the one that works:
/// tell the Politecnico which enrolment to prefer while the current token
/// still functions, then sign out and back in. The new token binds to the
/// favourite.
///
/// Said plainly on screen rather than hidden behind a spinner, because being
/// signed out is not what anyone expects from a picker.
struct CareerSwitchView: View {
    /// The shared ``CareersModel``, from the environment.
    @Environment(CareersModel.self) private var careers
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// Closes this screen or sheet.
    @Environment(\.dismiss) private var dismiss

    /// The enrolment the student has asked to switch to, whose confirmation is up.
    /// `true` while the switch is being set up.
    @State private var pending: Career?
    @State private var working = false
    /// Diagnostic log for this type, under the `careers` category.
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "careers")

    /// The view's content.
    var body: some View {
        List {
            Section {
                ForEach(careers.careers) { career in
                    Button {
                        pending = career
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(career.matricola)
                                    .font(.subheadline.weight(.semibold))
                                    .monospaced()
                                Text(career.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if career.matricola == session.student?.matricola {
                                Image(systemName: "checkmark").foregroundStyle(Theme.brand)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(working || career.matricola == session.student?.matricola)
                }
            } header: {
                Text("Le tue carriere")
            } footer: {
                Text("Il codice persona è uno solo; ogni immatricolazione ha la sua matricola. I servizi del Politecnico rispondono solo per quella su cui è stato fatto l'accesso.")
            }
            .lookRow()

            if careers.careers.isEmpty && !careers.isLoading {
                Section {
                    Text(careers.errorMessage ?? "Nessuna carriera restituita dal Politecnico.")
                        .foregroundStyle(.secondary)
                }
                .lookRow()
            }
        }
        .lookList()
        .navigationTitle("Matricola")
        .navigationBarTitleDisplayMode(.inline)
        .task { await careers.load() }
        .confirmationDialog(
            "Passare a \(pending?.matricola ?? "")?",
            isPresented: .init(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            Button("Esci e riaccedi") {
                if let pending { switchCareer(to: pending) }
            }
            Button("Annulla", role: .cancel) { pending = nil }
        } message: {
            Text("Il Politecnico non permette di cambiare matricola senza un nuovo accesso: l'app uscirà e ti chiederà di rientrare con CIE o SPID.")
        }
        .overlay {
            if working { ProgressView().controlSize(.large) }
        }
    }

    /// Remembers the choice, tells the Politecnico which enrolment to favour, and signs out so
    /// the student can sign back in on it.
    ///
    /// - Parameter career: The enrolment to move to.
    private func switchCareer(to career: Career) {
        working = true
        Task {
            // Order matters: the favourite must be set while the *current*
            // token still works. After signing out there is nothing to
            // authenticate the request with.
            careers.remember(career)
            await careers.markFavourite(career)
            await session.login.beginCareerRelogin(matricola: career.matricola)
            working = false
            dismiss()
        }
    }
}

// MARK: - Previews

#Preview("Scelta matricola") {
    CareerSwitchView().previewInNavigation()
}
