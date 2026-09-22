import Foundation

/// Everything the diagnostics page knows, as plain values.
///
/// Gathered once by ``DiagnosticsCollector`` and then only read: the page draws it and
/// ``DiagnosticsReport`` writes it out, so what a student sees and what they send cannot
/// disagree.
///
/// No token or secret is a field here. The token's side is described by when it expires
/// and which scopes it carries.
nonisolated struct DiagnosticsSnapshot: Equatable, Sendable {
    /// The device and its network.
    struct Device: Equatable, Sendable {
        /// The app's version and build.
        var appVersion: String
        /// The operating system's name and version.
        var system: String
        /// The hardware identifier, for example `iPhone17,1`.
        var model: String
        /// The device's preferred language.
        var language: String
        /// Whether Low Power Mode is on, which suppresses background work.
        var lowPowerMode: Bool
        /// Whether the app group container exists. Without it the offline store falls back to
        /// the app's own folder and the widgets read nothing.
        var sharedContainer: Bool
        /// Whether a network path is available.
        var online: Bool
        /// Whether that path is metered.
        var expensive: Bool
    }

    /// The session and the token, without the token.
    struct Account: Equatable, Sendable {
        /// Where the session stands, in words.
        var state: String
        /// How the student signed in last, or `nil` when nothing was recorded.
        var loginMethod: String?
        /// The signed-in matricola. Written into a report only when the student opts in.
        var matricola: String?
        /// When the access token stops working, or `nil` when none is stored.
        var tokenExpiresAt: Date?
        /// Today's scopes against the token's, or `nil` when no token is stored.
        var scopes: ScopeAudit?
        /// The `poliAuthProfile` being sent.
        var profile: Int
        /// Whether the data services accept the token — `false` when a scope refusal has been
        /// seen.
        var authorised: Bool
        /// What the CieID app last reported, if anything.
        var cieError: String?
        /// Whether a CIE sign-in is over in the CieID app and has not returned.
        var cieAwaiting = false
    }

    /// The WeBeep connection.
    struct WeBeep: Equatable, Sendable {
        /// Whether a WeBeep token is held.
        var connected: Bool
        /// How many enrolled courses WeBeep reported.
        var courses: Int
        /// What the last WeBeep call failed with, if anything.
        var failure: String?
    }

    /// One backend and the host it currently resolves to.
    struct Service: Equatable, Sendable {
        /// The service's name on screen.
        var name: String
        /// The host its base URL points at.
        var host: String
    }

    /// One service's reachability check.
    struct Probe: Equatable, Sendable {
        /// The service's name on screen.
        var name: String
        /// How it answered.
        var result: ConnectionProbe.Result
    }

    /// The changes waiting to reach the Politecnico.
    struct Pending: Equatable, Sendable {
        /// How many are waiting.
        var queued: Int
        /// Labels of the changes given up on.
        var abandoned: [String]
    }

    /// What the app is allowed to do, and last did, while nobody is looking.
    struct Background: Equatable, Sendable {
        /// Whether iOS permits background refresh, in words.
        var refreshPermission: String
        /// The most recent background refresh, or `nil` when none has run.
        var lastRun: DiagnosticsLog.BackgroundRun?
        /// The notification permission, in words.
        var notifications: String
        /// How many reminders are pending.
        var scheduledReminders: Int
        /// When the soonest pending reminder fires, or `nil` when there is none.
        var nextReminder: Date?
        /// Whether Live Activities are permitted for this app.
        var liveActivities: Bool
        /// Whether a lecture's Live Activity is on the Lock Screen now.
        var liveActivityShowing = false
        /// Whether the app group's defaults name a student for the widgets to read.
        var widgetsKnowAccount: Bool
        /// When the widgets were last asked to reload.
        var lastWidgetReload: Date?
        /// How many items the last Spotlight pass indexed.
        var spotlightItems: Int?
        /// When that pass ran.
        var spotlightIndexedAt: Date?
    }

    /// What ``ReportArchive`` holds.
    struct Performance: Equatable, Sendable {
        /// How many metrics reports are stored.
        var metricReports: Int
        /// How many diagnostic reports are stored.
        var diagnosticReports: Int
        /// When the most recent arrived.
        var latest: Date?
    }

    /// When the snapshot was taken.
    var generatedAt: Date
    /// The device and its network.
    var device: Device
    /// The session and the token.
    var account: Account
    /// The WeBeep connection.
    var weBeep: WeBeep
    /// Each backend and the host it resolves to.
    var services: [Service]
    /// Whether those hosts came from `props` or are the baked-in fallbacks.
    var addressesFromPolitecnico: Bool
    /// The reachability checks. Empty until the student asks for them.
    var probes: [Probe]
    /// The changes waiting to reach the Politecnico.
    var pending: Pending
    /// What the app may do, and last did, in the background.
    var background: Background
    /// What the report archive holds.
    var performance: Performance
}

/// A ``DiagnosticsSnapshot`` as text, to paste into an email or an issue.
///
/// Labels are fixed Italian and dates are ISO 8601 whatever the device's region, so two
/// reports can be compared line by line. The values the page shows — states, service
/// names, change labels — arrive already in the device's language, as the student saw
/// them.
///
/// Two rules are the point of this type:
///
/// - No credential leaves, not even one hiding in free text. WeBeep puts its token on
///   download addresses, and an error quoting one would otherwise carry a live key into
///   somebody's inbox, so every free-text value passes through ``redacted(_:)``.
/// - The matricola is opt-in: it identifies a student to anyone who reads the report, and
///   most problems are diagnosable without it.
nonisolated struct DiagnosticsReport: Sendable {
    /// The report, ready to copy.
    let text: String

    /// Writes a snapshot out as text.
    ///
    /// - Parameters:
    ///   - snapshot: What the diagnostics page gathered.
    ///   - includesMatricola: Whether to include the matricola.
    init(_ snapshot: DiagnosticsSnapshot, includesMatricola: Bool) {
        var lines: [String] = []
        func section(_ title: String) { lines.append(""); lines.append("## \(title)") }
        func line(_ label: String, _ value: String) { lines.append("\(label): \(Self.redacted(value))") }
        func yesNo(_ flag: Bool) -> String { flag ? "sì" : "no" }
        let date = Self.date

        lines.append("PoliVerse — diagnostica")
        lines.append("Generato: \(date(snapshot.generatedAt))")

        section("Dispositivo")
        line("App", snapshot.device.appVersion)
        line("Sistema", snapshot.device.system)
        line("Modello", snapshot.device.model)
        line("Lingua", snapshot.device.language)
        line("Risparmio energetico", yesNo(snapshot.device.lowPowerMode))
        line("Contenitore condiviso", yesNo(snapshot.device.sharedContainer))
        line("Rete", snapshot.device.online ? (snapshot.device.expensive ? "connessa, a consumo" : "connessa") : "assente")

        section("Accesso")
        line("Sessione", snapshot.account.state)
        if let method = snapshot.account.loginMethod { line("Metodo", method) }
        if includesMatricola, let matricola = snapshot.account.matricola { line("Matricola", matricola) }
        line("Token", snapshot.account.tokenExpiresAt.map { "scade \(date($0))" } ?? "nessuna scadenza nota")
        if let scopes = snapshot.account.scopes {
            if scopes.isUnknown {
                line("Ambiti", "\(scopes.requestedCount) richiesti, non registrati sul token")
            } else {
                line("Ambiti", "\(scopes.grantedCount) su \(scopes.requestedCount) sul token")
                if !scopes.missing.isEmpty { line("Ambiti mancanti", scopes.missing.joined(separator: ", ")) }
                if !scopes.retired.isEmpty { line("Ambiti non più richiesti", scopes.retired.joined(separator: ", ")) }
            }
        }
        line("Profilo", String(snapshot.account.profile))
        line("Autorizzazione", snapshot.account.authorised ? "concessa" : "non concessa")
        if snapshot.account.cieAwaiting { line("CIE", "in attesa dell’app CieID") }
        if let error = snapshot.account.cieError { line("Errore CIE", error) }

        section("WeBeep")
        line("Stato", snapshot.weBeep.connected ? "collegato, \(snapshot.weBeep.courses) corsi" : "non collegato")
        if let failure = snapshot.weBeep.failure { line("Errore", failure) }

        section("Servizi del Politecnico")
        line("Indirizzi", snapshot.addressesFromPolitecnico ? "aggiornati dal Politecnico" : "predefiniti")
        for service in snapshot.services { line(service.name, service.host) }

        section("Collegamenti")
        if snapshot.probes.isEmpty {
            lines.append("Non verificati")
        }
        for probe in snapshot.probes {
            line(probe.name, Self.describe(probe.result))
        }

        section("Modifiche in coda")
        line("In attesa", String(snapshot.pending.queued))
        for label in snapshot.pending.abandoned { line("Abbandonata", label) }

        section("In background")
        let background = snapshot.background
        line("Aggiornamento in background", background.refreshPermission)
        if let run = background.lastRun {
            let outcome = switch run.outcome {
            case .completed: "concluso"
            case .expired: "interrotto da iOS"
            case .unfinished: "interrotto o in corso"
            }
            line("Ultimo aggiornamento in background", "\(date(run.started)), \(outcome)")
        } else {
            line("Ultimo aggiornamento in background", "mai registrato")
        }
        line("Notifiche", background.notifications)
        line("Promemoria programmati", String(background.scheduledReminders))
        if let next = background.nextReminder { line("Prossimo promemoria", date(next)) }
        line("Live Activity", (background.liveActivities ? "consentite" : "non consentite")
             + (background.liveActivityShowing ? ", una in corso" : ""))
        line("Widget", background.widgetsKnowAccount ? "sanno di chi sono i dati" : "senza account")
        if let reload = background.lastWidgetReload { line("Ultima ricarica dei widget", date(reload)) }
        if let items = background.spotlightItems, let at = background.spotlightIndexedAt {
            line("Spotlight", "\(items) elementi, \(date(at))")
        }

        section("Prestazioni")
        line("Rapporti MetricKit", "\(snapshot.performance.metricReports) metriche, \(snapshot.performance.diagnosticReports) diagnostiche")
        if let latest = snapshot.performance.latest { line("Ultimo rapporto", date(latest)) }

        text = lines.joined(separator: "\n")
    }

    /// A date as ISO 8601, so two reports compare line by line whatever the device's region.
    ///
    /// - Parameter date: The date to write.
    /// - Returns: The formatted date.
    private static func date(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    /// A probe's verdict in words, with its latency where there is one.
    ///
    /// - Parameter result: What the probe found.
    /// - Returns: The phrase, shared by the page and the report.
    static func describe(_ result: ConnectionProbe.Result) -> String {
        let time = result.milliseconds.map { " in \($0) ms" } ?? ""
        return switch result.verdict {
        case .reachable(let status): "risponde (\(status))\(time)"
        case .serverFault(let status): "errore del server (\(status))\(time)"
        case .timedOut: "nessuna risposta in tempo"
        case .unreachable(let code): "irraggiungibile (errore \(code.rawValue))"
        }
    }

    /// Removes anything that looks like a credential: token-bearing query parameters and
    /// `Bearer` values.
    ///
    /// Deliberately broad — a false positive costs a few characters of a bug report, a miss
    /// costs a live key.
    ///
    /// - Parameter text: The value to write.
    /// - Returns: The value with credentials replaced.
    static func redacted(_ text: String) -> String {
        var result = text
        let patterns: [(String, String)] = [
            (#"(?i)\b((?:access_|refresh_|ws)?token|code)=[^&\s)]+"#, "$1=[rimosso]"),
            (#"(?i)\bBearer\s+[A-Za-z0-9\-._~+/]+=*"#, "Bearer [rimosso]"),
        ]
        for (pattern, template) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result = regex.stringByReplacingMatches(
                in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        return result
    }
}
