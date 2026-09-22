import SwiftUI

/// What the app is connected to, whether it is working, how its moving parts
/// are doing, and the detail to quote when something is not.
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
/// 3. **The rows**, each section with a footer that says in one sentence how
///    that part of the app works, so a row that looks wrong can be read
///    against what it should be doing.
///
/// The diagnostic sections are read from one ``DiagnosticsSnapshot``, the same
/// value "Condividi rapporto" writes out, so what the student reads there and
/// what they send cannot disagree. The WeBeep, services and pending sections
/// read the live services instead, because their buttons change them and the
/// row must follow at once.
struct ConnectionsView: View {
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``WeBeepModel``, from the environment.
    @Environment(WeBeepModel.self) private var weBeep
    /// The shared ``NetworkMonitor``, from the environment.
    @Environment(NetworkMonitor.self) private var network
    /// The shared ``PendingChanges``, from the environment.
    @Environment(PendingChanges.self) private var pending
    /// The shared ``NotificationModel``, from the environment.
    @Environment(NotificationModel.self) private var notifications
    /// The shared ``LiveActivityController``, from the environment.
    @Environment(LiveActivityController.self) private var liveActivity
    /// The shared ``CieIDRouter``, from the environment.
    @Environment(CieIDRouter.self) private var cieID
    /// The shared ``LoginMethodMemory``, from the environment.
    @Environment(LoginMethodMemory.self) private var loginMemory
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()

    /// Whether the WeBeep login sheet is presented.
    @State private var connectingWeBeep = false
    /// Whether disconnecting WeBeep is being confirmed.
    @State private var confirmingDisconnect = false
    /// Everything the page reports, gathered in one pass.
    @State private var snapshot: DiagnosticsSnapshot?
    /// What each service answered when last asked, in ``DiagnosticsCollector/services`` order.
    @State private var probes: [DiagnosticsSnapshot.Probe] = []
    /// True while the services are being asked.
    @State private var isProbing = false
    /// True while a failed request is being tried again.
    @State private var isRetrying = false
    /// Whether the shared report names the matricola.
    @State private var includesMatricola = false

    /// Drawn behind WeBeep, in this order. Three, because the badge takes the
    /// fourth corner. Accesso and Aule are left out of the picture: one is the
    /// door to the others rather than something a student recognises, the
    /// other the least used.
    private static let pictured: [ServiceDirectory.Service] = [.iae, .agenda, .libretto]
    /// Listed under Servizi del Politecnico. WeBeep has a section of its own.
    private static let listed: [ServiceDirectory.Service] = [.app, .iae, .agenda, .libretto, .wsAule]

    /// Reads the app's state into a snapshot, without touching the network.
    private var collector: DiagnosticsCollector {
        DiagnosticsCollector(session: session, weBeep: weBeep, network: network, pending: pending,
                             notifications: notifications, liveActivity: liveActivity,
                             cieID: cieID, loginMemory: loginMemory)
    }

    /// The view's content.
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
                        // Not a reason for the badge — it stays the one piece
                        // of news — but lost changes are the student's own
                        // work, and they should not have to scroll to learn it.
                        if !pending.failed.isEmpty {
                            // Worded around the number, so one lost change
                            // does not read "1 modifiche".
                            Text("Modifiche non inviate: \(pending.failed.count). Le trovi più in basso.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
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
            .lookRow()

            weBeepSection(colour: colours[.weBeep] ?? ramp.neutral)
            accountSection
            servicesSection(colours: colours, neutral: ramp.neutral)
            pendingSection
            backgroundSection
            deviceSection
            performanceSection
            reportSection

            Section {
                Toggle("Usa dati di esempio", isOn: $session.useMockData)
            } footer: {
                Text("Con i dati di esempio l’app funziona senza collegarsi ai server del Politecnico. Disattivalo per usare il tuo account.")
            }
            .lookRow()
        }
        .lookList()
        .navigationTitle("WeBeep e diagnostica")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // The course count is the proof the connection works, not just
            // that a token is stored; ask once if nothing has asked yet.
            if weBeep.isAuthenticated, weBeep.courses.isEmpty, weBeep.state != .loading {
                await weBeep.loadCourses()
            }
        }
        // Re-read whenever something the snapshot depends on moves, so a row
        // never shows the state from before the button the student just
        // pressed.
        .task(id: RefreshKey(session: session.state, authorised: !session.serviceAuthorizationFailed,
                             weBeep: weBeep.isAuthenticated, courses: weBeep.courses.count,
                             online: network.isOnline, pending: pending.count,
                             failed: pending.failed.count, mock: session.useMockData)) {
            await reload()
        }
        .refreshable { await reload() }
        .sheet(isPresented: $connectingWeBeep) {
            WeBeepLoginSheet { await weBeep.loadCourses() }
        }
        .confirmationDialog("Scollegare WeBeep?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Scollega", role: .destructive) { weBeep.signOut() }
        } message: {
            Text("I materiali già scaricati restano sul dispositivo. Per vederne di nuovi dovrai ricollegarti.")
        }
    }

    /// What the page watches to know the snapshot is stale.
    private struct RefreshKey: Equatable {
        /// The session's state, and whether the services accepted its token.
        let session: Session.State, authorised: Bool
        /// Whether WeBeep is connected, how many courses it lists, whether the network is up, how many queued changes wait and have failed, and whether the sample data is on.
        let weBeep: Bool, courses: Int, online: Bool, pending: Int, failed: Int, mock: Bool
    }

    /// Gathers a fresh snapshot, keeping the probe results already in hand.
    private func reload() async {
        snapshot = await collector.snapshot(probes: probes)
    }

    // MARK: - Sections

    /// WeBeep: whether it is connected, what it answered, and the way to connect or disconnect it.
    ///
    /// - Parameter colour: The tile's colour, from the look's ramp.
    /// - Returns: The section.
    private func weBeepSection(colour: Flavor.RGB) -> some View {
        Section {
            ServiceRow(title: "WeBeep", detail: weBeepDetail, symbol: ServiceDirectory.Service.weBeep.symbol,
                       colour: colour) {
                VStack(alignment: .trailing, spacing: 2) {
                    StatusLabel(ok: weBeep.isAuthenticated,
                                text: weBeep.isAuthenticated ? "Collegato" : "Non collegato")
                    if let probe = probe(for: .weBeep) {
                        ProbeLabel(result: probe.result)
                    }
                }
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
        .lookRow()
    }

    /// The session: its state, the way the student last signed in, and the scopes the token carries.
    @ViewBuilder
    private var accountSection: some View {
        if let account = snapshot?.account {
            Section {
                LabeledContent("Sessione", value: account.state)
                if let method = account.loginMethod {
                    LabeledContent("Ultimo metodo di accesso", value: method)
                }
                LabeledContent("Token") {
                    if let expiry = account.tokenExpiresAt {
                        if expiry > .now {
                            Text("Valido fino alle \(expiry.formatted(date: .omitted, time: .shortened))")
                        } else {
                            Text("Si rinnova alla prossima richiesta")
                        }
                    } else {
                        Text("Nessuno")
                    }
                }
                if let scopes = account.scopes {
                    LabeledContent("Ambiti") {
                        StatusLabel(ok: scopes.isCurrent, text: scopeSummary(scopes))
                    }
                    if !scopes.missing.isEmpty {
                        LabeledContent("Mancano", value: scopes.missing.joined(separator: ", "))
                    }
                }
                LabeledContent("Autorizzazione") {
                    StatusLabel(ok: account.authorised, text: account.authorised ? "Concessa" : "Non concessa")
                }
                LabeledContent("Profilo") { Text(verbatim: String(account.profile)) }
                if account.cieAwaiting {
                    LabeledContent("CIE") { Text("In attesa dell’app CieID") }
                }
                if let error = account.cieError {
                    LabeledContent("Errore CIE") {
                        Text(error).foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Accesso al Politecnico")
            } footer: {
                Text("Il token dura poco e si rinnova da solo, ma porta con sé solo gli ambiti chiesti quando è nato: se il Politecnico ne aggiunge uno, serve uscire e rientrare.")
            }
            .lookRow()
        }
    }

    /// The Politecnico's own services, each with its host and what it last answered.
    ///
    /// - Parameters:
    ///   - colours: One colour per service, from the look's ramp.
    ///   - neutral: The colour for a service the ramp has none for.
    /// - Returns: The section.
    private func servicesSection(colours: [ServiceDirectory.Service: Flavor.RGB], neutral: Flavor.RGB) -> some View {
        Section {
            ForEach(Self.listed, id: \.rawValue) { service in
                ServiceRow(title: service.title, detail: host(of: service), symbol: service.symbol,
                           colour: colours[service] ?? neutral) {
                    if let probe = probe(for: service) {
                        ProbeLabel(result: probe.result)
                    }
                }
            }
            Button {
                isProbing = true
                Task {
                    probes = await collector.probe()
                    await reload()
                    isProbing = false
                }
            } label: {
                LabeledContent {
                    if isProbing { ProgressView() }
                } label: {
                    Text(probes.isEmpty ? "Verifica collegamenti" : "Verifica di nuovo")
                }
            }
            .disabled(isProbing || !network.isOnline)
            .accessibilityIdentifier("diagnostics-probe")
            LabeledContent("Indirizzi") {
                Text(session.directory.didLoad ? "Aggiornati dal Politecnico" : "Predefiniti")
            }
            NavigationLink {
                DataStorageView()
            } label: {
                Text("Ultimi aggiornamenti dei dati")
            }
        } header: {
            Text("Servizi del Politecnico")
        } footer: {
            Text("La verifica chiede a ogni servizio, WeBeep compreso, se c’è, senza credenziali. Conta che risponda, anche con un errore come 404: dice se la rete arriva al Politecnico e quanto in fretta, non se i tuoi dati sono corretti.")
        }
        .lookRow()
    }

    /// Changes made without a network: how many wait, and which have been refused.
    @ViewBuilder
    private var pendingSection: some View {
        Section {
            LabeledContent("In attesa di invio") {
                if pending.isFlushing {
                    ProgressView()
                } else {
                    Text(pending.count, format: .number)
                }
            }
            ForEach(Array(pending.failed.enumerated()), id: \.offset) { _, action in
                Label(action.label, systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    .foregroundStyle(.orange)
            }
            if !pending.failed.isEmpty {
                Button {
                    isRetrying = true
                    Task {
                        await pending.retryFailures()
                        isRetrying = false
                    }
                } label: {
                    LabeledContent {
                        if isRetrying { ProgressView() }
                    } label: {
                        Text("Riprova a inviarle")
                    }
                }
                .disabled(isRetrying || !network.isOnline)
                Button("Lasciale perdere", role: .destructive) { pending.acknowledgeFailures() }
            }
        } header: {
            Text("Modifiche in coda")
        } footer: {
            Text("Le modifiche fatte senza rete, come un corso tra i preferiti, restano in coda e partono appena torna la connessione. Dopo \(ActionQueue.maxAttempts) tentativi rifiutati si fermano qui.")
        }
        .lookRow()
    }

    /// Background refresh: whether iOS allows it, and how the last run went.
    @ViewBuilder
    private var backgroundSection: some View {
        if let background = snapshot?.background {
            Section {
                LabeledContent("Aggiornamento in background", value: background.refreshPermission)
                LabeledContent("Ultimo giro") {
                    if let run = background.lastRun {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(run.started, format: .relative(presentation: .named))
                            Text(outcome(of: run))
                                .font(.caption)
                                .foregroundStyle(run.outcome == .completed ? Color.secondary : .orange)
                        }
                    } else {
                        Text("Mai registrato")
                    }
                }
                LabeledContent("Notifiche", value: background.notifications)
                LabeledContent("Promemoria programmati") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(background.scheduledReminders, format: .number)
                        if let next = background.nextReminder {
                            Text("Il prossimo \(next.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Live Activity") {
                    VStack(alignment: .trailing, spacing: 1) {
                        StatusLabel(ok: background.liveActivities,
                                    text: background.liveActivities ? "Consentite" : "Disattivate")
                        if background.liveActivityShowing {
                            Text("Una in corso")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Widget") {
                    VStack(alignment: .trailing, spacing: 1) {
                        StatusLabel(ok: background.widgetsKnowAccount,
                                    text: background.widgetsKnowAccount ? "Collegati al tuo account" : "Senza account")
                        if let reload = background.lastWidgetReload {
                            Text("Aggiornati \(reload.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent("Spotlight") {
                    if let items = background.spotlightItems, let at = background.spotlightIndexedAt {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(items) elementi")
                            Text(at, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Mai indicizzato")
                    }
                }
            } header: {
                Text("In background")
            } footer: {
                Text("Circa una volta all’ora, quando iOS lo concede, l’app aggiorna orario, carriera e novità di WeBeep in circa trenta secondi, poi riprogramma i promemoria e aggiorna i widget. iOS decide quando: con Risparmio energetico o l’aggiornamento disattivato, non succede.")
            }
            .lookRow()
        }
    }

    /// The device's own side of things: notifications, Live Activities, and low-power mode.
    @ViewBuilder
    private var deviceSection: some View {
        if let device = snapshot?.device {
            Section {
                LabeledContent("App", value: device.appVersion)
                LabeledContent("Sistema", value: device.system)
                LabeledContent("Modello", value: device.model)
                LabeledContent("Lingua", value: device.language)
                LabeledContent("Rete") {
                    StatusLabel(ok: device.online,
                                text: device.online ? (device.expensive ? "Connessa, a consumo" : "Connessa") : "Assente")
                }
                LabeledContent("Risparmio energetico") {
                    Text(device.lowPowerMode ? "Attivo" : "Spento")
                }
                LabeledContent("Spazio condiviso con i widget") {
                    StatusLabel(ok: device.sharedContainer, text: device.sharedContainer ? "Presente" : "Assente")
                }
            } header: {
                Text("Dispositivo")
            } footer: {
                Text("Lo spazio condiviso è dove l’app lascia orario e carriera per i widget: senza, l’app funziona ma i widget restano vuoti.")
            }
            .lookRow()
        }
    }

    /// What MetricKit has delivered: the reports on performance and on crashes, which stay on the device.
    @ViewBuilder
    private var performanceSection: some View {
        if let performance = snapshot?.performance {
            Section {
                LabeledContent("Rapporti di iOS") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(performance.metricReports) sulle prestazioni, \(performance.diagnosticReports) su blocchi e chiusure")
                        if let latest = performance.latest {
                            Text(latest, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.trailing)
                }
                #if DEBUG
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
                #endif
            } header: {
                Text("Prestazioni")
            } footer: {
                Text("Una volta al giorno iOS consegna all’app un riassunto di avvio, memoria e batteria, e un rapporto per ogni blocco o chiusura. Restano sul dispositivo.")
            }
            .lookRow()
        }
    }

    /// The whole page as text, to attach to a bug report, with or without the matricola.
    @ViewBuilder
    private var reportSection: some View {
        if let snapshot {
            let report = DiagnosticsReport(snapshot, includesMatricola: includesMatricola).text
            Section {
                Toggle("Includi la matricola", isOn: $includesMatricola)
                ShareLink(item: report, subject: Text("PoliVerse — diagnostica")) {
                    Label("Condividi rapporto", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = report
                } label: {
                    Label("Copia rapporto", systemImage: "doc.on.doc")
                }
            } header: {
                Text("Rapporto")
            } footer: {
                Text("Tutto quello che c’è in questa pagina, in testo, da allegare a una segnalazione. Non contiene password né token: se un messaggio d’errore ne cita uno, viene tolto.")
            }
            .lookRow()
        }
    }

    // MARK: - Helpers

    /// What one service answered when last asked.
    ///
    /// - Parameter service: The service.
    /// - Returns: Its answer, or `nil` before it has been asked.
    private func probe(for service: ServiceDirectory.Service) -> DiagnosticsSnapshot.Probe? {
        guard let index = DiagnosticsCollector.services.firstIndex(of: service), index < probes.count else { return nil }
        return probes[index]
    }

    /// How many of the scopes asked for were granted.
    ///
    /// - Parameter scopes: What the token carries.
    /// - Returns: The count, or a note that nothing was recorded.
    private func scopeSummary(_ scopes: ScopeAudit) -> LocalizedStringResource {
        if scopes.isUnknown { return "Non registrati" }
        return "\(scopes.grantedCount) su \(scopes.requestedCount)"
    }

    /// How a background run ended, in words.
    ///
    /// - Parameter run: The run.
    /// - Returns: The wording.
    private func outcome(of run: DiagnosticsLog.BackgroundRun) -> LocalizedStringResource {
        switch run.outcome {
        case .completed: "Concluso"
        case .expired: "Interrotto da iOS"
        case .unfinished: "Interrotto o in corso"
        }
    }

    /// One ramp step per service, in the order the picture draws them, so the
    /// front tile is the deepest and a row's icon matches its tile.
    private func colours(from ramp: FlavorRamp) -> [ServiceDirectory.Service: Flavor.RGB] {
        let order: [ServiceDirectory.Service] = [.weBeep] + Self.pictured + [.wsAule, .app]
        return Dictionary(uniqueKeysWithValues: zip(order, ramp.colours(order.count)))
    }

    /// The host a service is reached at, as the directory currently resolves it.
    ///
    /// - Parameter service: The service.
    /// - Returns: Its host.
    private func host(of service: ServiceDirectory.Service) -> String {
        let url = session.directory.baseURL(for: service)
        return url.host() ?? url.absoluteString
    }

    /// WeBeep's second line: what it last said, or what it is for when it is not connected.
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
        /// The states, in the precedence the page reads them: sample data, then no connection, then an unauthorised token, then WeBeep failing, then WeBeep not connected, then everything working.
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

        /// What the state is called at the top of the page.
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

        /// One line saying what it means, or what to do about it.
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

    /// Where the app stands, by the precedence above.
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
    /// The service's name.
    let title: LocalizedStringResource
    /// One line under it, such as its host or what it last said.
    let detail: String
    /// The tile's SF Symbol.
    let symbol: String
    /// The tile's colour.
    let colour: Flavor.RGB
    /// The `trailing` this view draws.
    @ViewBuilder let trailing: Trailing

    /// The view's content.
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

/// A probe's answer, short enough for a row's trailing edge.
private struct ProbeLabel: View {
    /// What the service answered.
    let result: ConnectionProbe.Result

    /// The view's content.
    var body: some View {
        switch result.verdict {
        case .reachable:
            StatusLabel(ok: true, text: "Risponde · \(result.milliseconds ?? 0) ms")
        case .serverFault(let status):
            StatusLabel(ok: false, text: "Errore \(status)")
        case .timedOut:
            StatusLabel(ok: false, text: "Nessuna risposta")
        case .unreachable:
            StatusLabel(ok: false, text: "Irraggiungibile")
        }
    }
}

/// Fine or not, said in words with a symbol beside them rather than by colour
/// alone.
private struct StatusLabel: View {
    /// True when nothing is wrong.
    let ok: Bool
    /// What to say.
    let text: LocalizedStringResource

    /// The view's content.
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

/// How the page names and pictures each service.
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
        case .maps: "Mappa del campus"
        }
    }

    /// The service's SF Symbol.
    var symbol: String {
        switch self {
        case .app: "person.badge.key"
        case .iae: "graduationcap"
        case .agenda: "calendar"
        case .libretto: "list.bullet.clipboard"
        case .weBeep: "books.vertical"
        case .wsAule: "building.2"
        case .maps: "map"
        }
    }
}

// MARK: - Previews

#Preview("WeBeep e diagnostica") {
    NavigationStack { ConnectionsView() }.previewEnvironment()
}
