import SwiftUI

/// The ways into the Politecnico, as our own buttons.
///
/// ## What this replaces
///
/// The IdP's login page offers six things at once: a codice persona form, a
/// grid of twelve SPID logos, and CIE, eIDAS and EduGAIN. It is the
/// university's layout, loaded from four of its stylesheets, and nothing about
/// it can be made to look like the rest of the app.
///
/// It can be driven, though — every one of those is a submit button on a page
/// this web view already loads. So the *choice* happens here, natively, and
/// ``PoliMiAppLoginWebView`` presses the matching button from underneath. The
/// student then lands on their identity provider's own page, which is the one
/// screen that must stay the provider's: it is where the credential is typed.
///
/// PoliVerse never offers fields of its own for the codice persona or the
/// password. That promise is made on the sign-in step of the onboarding, and
/// this is the file that has to keep it.
///
/// Everything behind the buttons — clearing the old grant, the IdP sheet, the
/// CieID hand-off and its "app not installed" alert, the matricola hint from
/// the career switcher — was extracted out of ``LoginView`` when onboarding
/// gained a sign-in step, so the two cannot drift.
struct PoliMiSignInButton: View {
    @Environment(Session.self) private var session
    @Environment(CieIDRouter.self) private var cieID

    @State private var showingWeb = false
    @State private var showingCieIDMissing = false
    @State private var showingSPID = false
    @State private var showingMore = false
    @State private var isPreparing = false
    @State private var webError: String?
    @State private var method: PoliMiLoginMethod = .password

    var body: some View {
        VStack(spacing: 12) {
            if case .exchangingCode = session.state {
                ProgressView("Accesso in corso…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                Button { start(.password) } label: {
                    Group {
                        if isPreparing {
                            ProgressView().tint(Theme.onAccent)
                        } else {
                            Text("Codice persona e password").font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .disabled(isPreparing)
                .background(Theme.brand, in: .capsule)
                .foregroundStyle(Theme.onAccent)
                .buttonStyle(.plain)

                Button { showingSPID = true } label: {
                    Label("Entra con SPID", systemImage: "person.badge.shield.checkmark")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .disabled(isPreparing)
                .background(Color(.secondarySystemGroupedBackground), in: .capsule)
                .foregroundStyle(.primary)
                .buttonStyle(.plain)

                Button { start(.cie) } label: {
                    Label("Entra con CIE", systemImage: "creditcard")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .disabled(isPreparing)
                .background(Color(.secondarySystemGroupedBackground), in: .capsule)
                .foregroundStyle(.primary)
                .buttonStyle(.plain)

                // Behind a tap: the Politecnico offers both, and between them
                // they serve students with a non-Italian EU identity and staff
                // arriving from another university's federation. Neither is
                // the common path, and putting five buttons on the screen
                // makes the common one harder to find.
                Button { showingMore = true } label: {
                    Text("Altri modi per accedere").font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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
        .sheet(isPresented: $showingSPID) {
            SPIDProviderPicker { provider in
                showingSPID = false
                start(.spid(provider))
            }
        }
        .confirmationDialog("Altri modi per accedere", isPresented: $showingMore, titleVisibility: .visible) {
            Button("eIDAS · identità di un altro paese UE") { start(.eidas) }
            Button("EduGAIN · altro ateneo o ente di ricerca") { start(.eduGAIN) }
            Button("Annulla", role: .cancel) {}
        }
        .sheet(isPresented: $showingWeb) { webSheet }
    }

    private func start(_ chosen: PoliMiLoginMethod) {
        method = chosen
        webError = nil
        isPreparing = true
        Task {
            // Clears any stored token and ends the SSO session, so the IdP has
            // to mint a new grant rather than replay the old one. The returned
            // logout URL is not needed: the call has already ended the session,
            // and the web view starts from the authorize endpoint.
            _ = await session.prepareForLogin()
            isPreparing = false
            showingWeb = true
        }
    }

    private var webSheet: some View {
        NavigationStack {
            PoliMiAppLoginWebView(
                oauthParams: session.directory.oauth,
                router: cieID,
                onCredentials: { token in
                    showingWeb = false
                    Task {
                        await session.completeLogin(token: token)
                        // Consumed either way: a hint that did not take is not
                        // worth re-applying to every future login.
                        session.pendingMatricola = nil
                    }
                },
                onError: { error in
                    showingWeb = false
                    webError = error.localizedDescription
                },
                onCieIDMissing: { showingCieIDMissing = true },
                // Carries the enrolment the user asked to switch to, if they
                // got here from the career switcher.
                flow: .login(hintMatricola: session.pendingMatricola),
                method: method
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

    private var failureMessage: String? {
        if case .failed(let message) = session.state { return message }
        return nil
    }
}

/// The twelve SPID providers, as a list of our own.
///
/// A native list rather than the page's logo grid: the grid is an image sprite
/// with the providers' marks in it, and reproducing those would mean shipping
/// twelve trademarks we have no licence to. Their names are the honest way to
/// say the same thing.
struct SPIDProviderPicker: View {
    let choose: (SPIDProvider) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(SPIDProvider.all) { provider in
                Button { choose(provider) } label: {
                    HStack {
                        Text(provider.name)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Entra con SPID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Scegli il gestore con cui hai fatto SPID. Le credenziali si inseriscono sulla sua pagina.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Previews

#Preview("Modi di accesso") {
    PoliMiSignInButton().padding(28).previewEnvironment()
}

#Preview("SPID") {
    SPIDProviderPicker { _ in }
}
