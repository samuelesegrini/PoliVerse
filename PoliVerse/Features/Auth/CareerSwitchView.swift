import OSLog
import SwiftUI

/// Choose which enrolment the app is looking at.
///
/// Switching is not cosmetic. The token is bound to one matricola, so the
/// other career's services refuse it outright — a student who finished the
/// triennale and started the magistrale sees "Utente non abilitato" across
/// exams and an empty timetable until this is pointed at the right one.
struct CareerSwitchView: View {
    @Environment(CareersService.self) private var careers
    @Environment(Session.self) private var session
    @Environment(CieIDRouter.self) private var cieID
    @Environment(\.dismiss) private var dismiss

    @State private var switching: Career?
    @State private var token: String?
    @State private var failure: String?
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "careers")

    var body: some View {
        Group {
            if let switching {
                // The same web view as login, pointed at /careerChange. The
                // session is never dropped: if this fails the old career is
                // still signed in and working.
                PoliMiAppLoginWebView(
                    oauthParams: session.oauthParams,
                    router: cieID,
                    onCredentials: { token in
                        Task { await complete(with: token, career: switching) }
                    },
                    onError: { error in
                        failure = userFacingMessage(error)
                        self.switching = nil
                    },
                    switchingTo: switching,
                    currentToken: token
                )
                .overlay(alignment: .top) {
                    Text("Passaggio a \(switching.matricola)…")
                        .font(.caption)
                        .padding(8)
                        .background(.bar, in: .capsule)
                        .padding(.top, 8)
                }
            } else {
                list
            }
        }
        .navigationTitle("Matricola")
        .navigationBarTitleDisplayMode(.inline)
        .task { await careers.load() }
    }

    private var list: some View {
        List {
            if let failure {
                Section {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                ForEach(careers.careers) { career in
                    Button {
                        start(career)
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
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.brand)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(career.matricola == session.student?.matricola)
                }
            } header: {
                Text("Le tue carriere")
            } footer: {
                Text("Il codice persona è uno solo; ogni immatricolazione ha la sua matricola. I servizi del Politecnico rispondono solo per quella su cui è stato fatto l'accesso, quindi cambiarla rifà l'autorizzazione — senza uscire dall'account.")
            }

            if careers.careers.isEmpty && !careers.isLoading {
                Section {
                    Text("Nessuna carriera restituita dal Politecnico.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func start(_ career: Career) {
        failure = nil
        // Fetched before the web view appears: the IdP needs it in the
        // authorize URL, and reading it is async.
        Task {
            token = await session.currentAccessToken
            switching = career
        }
    }

    private func complete(with token: PoliMiToken, career: Career) async {
        careers.remember(career)
        await session.adopt(token)
        await careers.markFavourite(career)
        log.notice("Career switched to \(career.matricola, privacy: .public)")
        switching = nil
        dismiss()
    }
}
