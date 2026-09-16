import SwiftUI

/// What the app is connected to, whether it is working, and the detail to
/// quote when it is not.
///
/// Built on the same principles as ``DataStorageView``, so the two read as
/// one kind of page:
///
/// 1. **A picture first.** WeBeep in front in clear glass, the Politecnico's
///    services behind it in tinted glass, and one badge on the corner that
///    carries the only news that matters — the way an "add" icon carries its
///    plus. A student who opened this page because something is wrong sees
///    *whether* it is wrong before reading anything.
/// 2. **One sentence** under it that says what the badge means and what to do.
/// 3. **The rows**, each with the action that belongs to it.
///
/// The screen it replaces mixed account details, interface toggles, cache
/// sizes, sign-out and a disclosure group of URLs in one form. Everything else
/// already has its own page in Impostazioni; this keeps the connections and
/// the diagnostics, and the sample-data switch, which is the other thing a
/// student reaches for when the real data will not come.
struct ConnectionsView: View {
    @Environment(Session.self) private var session
    @Environment(WeBeepService.self) private var weBeep
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.colorScheme) private var scheme
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    @State private var connectingWeBeep = false
    @State private var confirmingDisconnect = false

    /// Drawn behind WeBeep, in this order. Three, because the badge takes the
    /// fourth corner. Accesso and Aule are left out of the picture: one is the
    /// door to the others rather than something a student recognises, the
    /// other the least used.
    private static let pictured: [ServiceDirectory.Service] = [.iae, .agenda, .libretto]
    /// Listed under Servizi del Politecnico. WeBeep has a section of its own.
    private static let listed: [ServiceDirectory.Service] = [.app, .iae, .agenda, .libretto, .wsAule]

    var body: some View {
        @Bindable var session = session
        let ramp = FlavorRamp(style: style, scheme: scheme)
        let colours = colours(from: ramp)
        let health = health

        List {
            Section {
                VStack(spacing: 18) {
                    HeroTileStack(
                        tiles: ([.weBeep] + Self.pictured).map { service in
                            HeroTile(id: service.rawValue, symbol: service.symbol,
                                     colour: colours[service] ?? ramp.neutral)
                        },
                        placeholder: HeroTile(id: "empty", symbol: "network", colour: ramp.neutral),
                        badge: health.badge(accent: style.accent(scheme)),
                        mode: ramp.mode)
                        .frame(maxWidth: .infinity)

                    VStack(spacing: 6) {
                        Text(health.title)
                            .font(.title2.weight(.bold))
                        Text(health.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .contentTransition(.opacity)
                    .animation(.snappy, value: health)
                }
                .listRowInsets(EdgeInsets(top: 20, leading: 24, bottom: 16, trailing: 24))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                ServiceRow(title: "WeBeep", detail: weBeepDetail, symbol: ServiceDirectory.Service.weBeep.symbol,
                           colour: colours[.weBeep] ?? ramp.neutral) {
                    StatusLabel(ok: weBeep.isAuthenticated,
                                text: weBeep.isAuthenticated ? "Collegato" : "Non collegato")
                }
                if weBeep.isAuthenticated {
                    Button("Scollega WeBeep", role: .destructive) { confirmingDisconnect = true }
                } else {
                    Button("Collega WeBeep") { connectingWeBeep = true }
                }
            } header: {
                Text("WeBeep")
            } footer: {
                Text("Un accesso separato da quello del Politecnico, che può scadere per conto suo. Serve per i materiali dei corsi e per gli avvisi dei docenti.")
            }

            Section {
                ForEach(Self.listed, id: \.rawValue) { service in
                    ServiceRow(title: service.title, detail: host(of: service), symbol: service.symbol,
                               colour: colours[service] ?? ramp.neutral) { EmptyView() }
                }
                LabeledContent("Indirizzi") {
                    Text(session.directory.didLoad ? "Aggiornati dal Politecnico" : "Predefiniti")
                }
                LabeledContent("Autorizzazione") {
                    StatusLabel(ok: !session.serviceAuthorizationFailed,
                                text: session.serviceAuthorizationFailed ? "Non concessa" : "Concessa")
                }
                LabeledContent("Ambiti OAuth") {
                    Text(session.directory.oauth.scope.split(separator: " ").count, format: .number)
                }
                LabeledContent("Profilo") {
                    Text(verbatim: String(session.profileID))
                }
            } header: {
                Text("Servizi del Politecnico")
            } footer: {
                Text("Utile per segnalare un problema: dove l’app cerca i servizi del Politecnico e con quale accesso.")
            }

            Section {
                Toggle("Usa dati di esempio", isOn: $session.useMockData)
            } footer: {
                Text("Con i dati di esempio l’app funziona senza collegarsi ai server del Politecnico. Disattivalo per usare il tuo account.")
            }

            #if DEBUG
            Section {
                NavigationLink {
                    MetricReportsView()
                } label: {
                    Text(verbatim: "MetricKit")
                }
                NavigationLink {
                    CareerDiagnosticsView()
                } label: {
                    Text(verbatim: "Diagnostica carriera")
                }
            } header: {
                Text(verbatim: "Sviluppo")
            }
            #endif
        }
        .navigationTitle("WeBeep e diagnostica")
        .navigationBarTitleDisplayMode(.inline)
        // The course count is the proof the connection works, not just that a
        // token is stored; ask once if nothing has asked yet.
        .task {
            if weBeep.isAuthenticated, weBeep.courses.isEmpty, weBeep.state != .loading {
                await weBeep.loadCourses()
            }
        }
        .sheet(isPresented: $connectingWeBeep) {
            WeBeepLoginSheet { await weBeep.loadCourses() }
        }
        .confirmationDialog("Scollegare WeBeep?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Scollega", role: .destructive) { weBeep.signOut() }
        } message: {
            Text("I materiali già scaricati restano sul dispositivo. Per vederne di nuovi dovrai ricollegarti.")
        }
    }

    /// One ramp step per service, in the order the picture draws them, so the
    /// front tile is the deepest and a row's icon matches its tile.
    private func colours(from ramp: FlavorRamp) -> [ServiceDirectory.Service: Flavor.RGB] {
        let order: [ServiceDirectory.Service] = [.weBeep] + Self.pictured + [.wsAule, .app]
        return Dictionary(uniqueKeysWithValues: zip(order, ramp.colours(order.count)))
    }

    private func host(of service: ServiceDirectory.Service) -> String {
        let url = session.directory.baseURL(for: service)
        return url.host() ?? url.absoluteString
    }

    private var weBeepDetail: String {
        guard weBeep.isAuthenticated else { return String(localized: "Materiali dei corsi") }
        switch weBeep.state {
        case .failed(let message): return message
        case .loading: return String(localized: "Controllo in corso…")
        case .ready where !weBeep.courses.isEmpty:
            return String(localized: "\(weBeep.courses.count) corsi")
        case .ready, .needsLogin: return String(localized: "Accesso salvato")
        }
    }

    // MARK: - The one piece of news

    /// What the badge and the sentence say, by a fixed precedence — the same
    /// order ``DataStatus`` uses, for the same reasons: sample data first,
    /// because then nothing else on the page is true; no connection before any
    /// failure, because it explains the failures.
    private enum Health: Equatable {
        case sample, offline, unauthorised, weBeepFailing(String), weBeepMissing, fine

        /// - Parameter accent: the look's accent, for the one badge that is
        ///   an invitation rather than a warning.
        func badge(accent: Color) -> HeroBadge {
            switch self {
            case .sample: HeroBadge(symbol: "theatermasks.fill", tint: .orange)
            case .offline: HeroBadge(symbol: "wifi.slash", tint: .gray)
            case .unauthorised, .weBeepFailing: HeroBadge(symbol: "exclamationmark", tint: .orange)
            // A plus, like the badge on an "add" icon: the fix is to add
            // something, not that something broke.
            case .weBeepMissing: HeroBadge(symbol: "plus", tint: accent)
            case .fine: HeroBadge(symbol: "checkmark", tint: .green)
            }
        }

        var title: LocalizedStringResource {
            switch self {
            case .sample: "Dati di esempio"
            case .offline: "Senza connessione"
            case .unauthorised: "Servizi non autorizzati"
            case .weBeepFailing: "WeBeep non risponde"
            case .weBeepMissing: "WeBeep non collegato"
            case .fine: "Tutto collegato"
            }
        }

        var detail: LocalizedStringResource {
            switch self {
            case .sample: "Finché li usi l’app non si collega né al Politecnico né a WeBeep."
            case .offline: "Quando torna la rete l’app si ricollega da sola."
            case .unauthorised: "Il Politecnico non ha concesso l’accesso ai tuoi dati. Esci e rientra per rinnovarlo."
            case .weBeepFailing(let message): "\(message)"
            case .weBeepMissing: "Collegalo per vedere i materiali dei corsi e gli avvisi dei docenti."
            case .fine: "WeBeep e i servizi del Politecnico rispondono."
            }
        }
    }

    private var health: Health {
        if session.useMockData { return .sample }
        if !network.isOnline { return .offline }
        if session.serviceAuthorizationFailed { return .unauthorised }
        if case .failed(let message) = weBeep.state, weBeep.isAuthenticated { return .weBeepFailing(message) }
        if !weBeep.isAuthenticated { return .weBeepMissing }
        return .fine
    }
}

// MARK: - Rows

/// A service as a row: its tile, its name, one line of detail, and whatever
/// the row needs on the trailing edge.
private struct ServiceRow<Trailing: View>: View {
    let title: LocalizedStringResource
    let detail: String
    let symbol: String
    let colour: Flavor.RGB
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            GlassTile(symbol: symbol, colour: colour, side: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            trailing
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fine or not, said in words with a symbol beside them rather than by colour
/// alone.
private struct StatusLabel: View {
    let ok: Bool
    let text: LocalizedStringResource

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
        }
        .labelStyle(.titleAndIcon)
        .font(.subheadline)
        .foregroundStyle(ok ? Color.secondary : .orange)
        .symbolRenderingMode(.hierarchical)
    }
}

extension ServiceDirectory.Service {
    /// The name a student would use, not the host's.
    var title: LocalizedStringResource {
        switch self {
        case .app: "Accesso"
        case .iae: "Corsi ed esami"
        case .agenda: "Orario"
        case .libretto: "Piano di studi"
        case .weBeep: "WeBeep"
        case .wsAule: "Aule"
        }
    }

    var symbol: String {
        switch self {
        case .app: "person.badge.key"
        case .iae: "graduationcap"
        case .agenda: "calendar"
        case .libretto: "list.bullet.clipboard"
        case .weBeep: "books.vertical"
        case .wsAule: "building.2"
        }
    }
}

// MARK: - Previews

#Preview("WeBeep e diagnostica") {
    NavigationStack { ConnectionsView() }.previewEnvironment()
}
