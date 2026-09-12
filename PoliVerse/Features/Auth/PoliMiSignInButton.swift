import SwiftUI

/// The "Accedi con account Polimi" button, and everything behind it.
///
/// Extracted from ``LoginView`` when onboarding gained a sign-in step of its
/// own: the button is three lines, but what hangs off it is not — clearing the
/// old grant before starting, the IdP in a sheet, the CieID hand-off and the
/// "app not installed" alert, the matricola hint carried over from the career
/// switcher. Two copies of that would drift, and the half that drifts is the
/// half nobody tests by hand.
struct PoliMiSignInButton: View {
    @Environment(Session.self) private var session
    @Environment(CieIDRouter.self) private var cieID

    @State private var showingWeb = false
    @State private var showingCieIDMissing = false
    @State private var isPreparing = false
    @State private var webError: String?

    var body: some View {
        VStack(spacing: 12) {
            if case .exchangingCode = session.state {
                ProgressView("Accesso in corso…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                Button {
                    webError = nil
                    isPreparing = true
                    Task {
                        // Clears any stored token and ends the SSO session, so
                        // the IdP has to mint a new grant rather than replay
                        // the old one.
                        // The returned logout URL is not needed here: the
                        // call has already ended the SSO session, and the web
                        // view starts from the authorize endpoint.
                        _ = await session.prepareForLogin()
                        isPreparing = false
                        showingWeb = true
                    }
                } label: {
                    Group {
                        if isPreparing {
                            ProgressView().tint(Theme.onAccent)
                        } else {
                            Text("Accedi con account Polimi").font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .disabled(isPreparing)
                .background(Theme.brand, in: .capsule)
                .foregroundStyle(Theme.onAccent)
                .buttonStyle(.plain)
            }

            if let message = webError ?? failureMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        // The expensive part of this login is parsing 8 MB of JavaScript, and
        // it can happen while the user is still reading the screen rather than
        // after they have tapped and started waiting.
        .task {
            LoginWebKit.prewarm(
                URL(string: "https://polimiapp.polimi.it/polimi_app/app/")!)
        }
        .sheet(isPresented: $showingWeb) {
            NavigationStack {
                PoliMiAppLoginWebView(
                    oauthParams: session.directory.oauth,
                    router: cieID,
                    onCredentials: { token in
                        showingWeb = false
                        Task {
                            await session.completeLogin(token: token)
                            // Consumed either way: a hint that did not take is
                            // not worth re-applying to every future login.
                            session.pendingMatricola = nil
                        }
                    },
                    onError: { error in
                        showingWeb = false
                        webError = error.localizedDescription
                    },
                    onCieIDMissing: { showingCieIDMissing = true },
                    // Carries the enrolment the user asked to switch to, if
                    // they got here from the career switcher.
                    flow: .login(hintMatricola: session.pendingMatricola)
                )
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Servizi Online")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { showingWeb = false }
                    }
                }
                .overlay(alignment: .bottom) {
                    if cieID.isAwaitingCieID {
                        CieIDWaitingBanner()
                    }
                }
                .alert("App CieID non installata", isPresented: $showingCieIDMissing) {
                    Button("Apri App Store") { cieID.openAppStore() }
                    Button("Annulla", role: .cancel) {}
                } message: {
                    Text("Per accedere con la Carta d'Identità Elettronica serve l'app CieID.")
                }
            }
        }
    }

    private var failureMessage: String? {
        if case .failed(let message) = session.state { return message }
        return nil
    }
}
