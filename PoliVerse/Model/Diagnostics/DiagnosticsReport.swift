import Foundation

/// Everything the diagnostics page knows, as plain values.
///
/// Gathered once from the live services and then only read: the page draws
/// it and ``DiagnosticsReport`` writes it out, so what a student sees and what
/// they send can never disagree. No token or secret is a field here — the
/// token's side is described by when it expires and which scopes it has.
nonisolated struct DiagnosticsSnapshot: Equatable, Sendable {
    struct Device: Equatable, Sendable {
        var appVersion: String
        var system: String
        var model: String
        var language: String
        var lowPowerMode: Bool
        /// Whether the app group container exists. Without it the offline
        /// store falls back to the app's own folder and widgets read nothing.
        var sharedContainer: Bool
        var online: Bool
        var expensive: Bool
    }

    struct Account: Equatable, Sendable {
        var state: String
        var loginMethod: String?
        var matricola: String?
        var tokenExpiresAt: Date?
        var scopes: ScopeAudit?
        var profile: Int
        var authorised: Bool
        var cieError: String?
        /// A CIE login handed to the CieID app and not back yet.
        var cieAwaiting = false
    }

    struct WeBeep: Equatable, Sendable {
        var connected: Bool
        var courses: Int
        var failure: String?
    }

    struct Service: Equatable, Sendable {
        var name: String
        var host: String
    }

    struct Probe: Equatable, Sendable {
        var name: String
        var result: ConnectionProbe.Result
    }

    struct Pending: Equatable, Sendable {
        var queued: Int
        /// Labels of changes given up on after the last attempt.
        var abandoned: [String]
    }

    struct Background: Equatable, Sendable {
        var refreshPermission: String
        var lastRun: DiagnosticsLog.BackgroundRun?
        var notifications: String
        var scheduledReminders: Int
        var nextReminder: Date?
        var liveActivities: Bool
        /// Whether a lecture's Live Activity is on the Lock Screen now.
        var liveActivityShowing = false
        var widgetsKnowAccount: Bool
        var lastWidgetReload: Date?
        var spotlightItems: Int?
        var spotlightIndexedAt: Date?
    }

    struct Performance: Equatable, Sendable {
        var metricReports: Int
        var diagnosticReports: Int
        var latest: Date?
    }

    var generatedAt: Date
    var device: Device
    var account: Account
    var weBeep: WeBeep
    var services: [Service]
    var addressesFromPolitecnico: Bool
    /// Empty until "Verifica collegamenti" has run.
    var probes: [Probe]
    var pending: Pending
    var background: Background
    var performance: Performance
}

/// The snapshot as text, to paste into an email or an issue.
///
/// Labels are fixed Italian and dates ISO 8601 whatever the phone's region,
/// so two reports can be compared line by line; the values the page shows —
/// states, service names, change labels — arrive already in the phone's
/// language, as the student saw them. Two rules are the point of this type:
///
/// - **No credential leaves**, not even one hiding in free text. WeBeep puts
///   its token on download URLs, and an error message quoting that URL would
///   otherwise carry a live key into someone's inbox. Every free-text value
///   passes through ``redacted(_:)``.
/// - **The matricola is opt-in.** It identifies a student to anyone who reads
///   the report, and most problems are diagnosable without it.
nonisolated struct DiagnosticsReport: Sendable {
    let text: String

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

    private static func date(_ date: Date) -> String {
        date.formatted(.iso8601)
    }

    static func describe(_ result: ConnectionProbe.Result) -> String {
        let time = result.milliseconds.map { " in \($0) ms" } ?? ""
        return switch result.verdict {
        case .reachable(let status): "risponde (\(status))\(time)"
        case .serverFault(let status): "errore del server (\(status))\(time)"
        case .timedOut: "nessuna risposta in tempo"
        case .unreachable(let code): "irraggiungibile (errore \(code.rawValue))"
        }
    }

    /// Takes out anything that looks like a credential: token-bearing query
    /// parameters and `Bearer` values. Deliberately broad — a false positive
    /// costs a few characters of a bug report, a miss costs a live key.
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
