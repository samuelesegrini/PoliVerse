import Foundation
import Testing
@testable import PoliVerse

/// The report is the one piece of the diagnostics page that leaves the phone —
/// pasted into an email or an issue. What it must never carry is decided here:
/// no credential, even one hiding inside an error message, and no matricola
/// unless the student chose to include it.
@Suite("Rapporto di diagnostica")
struct DiagnosticsReportTests {
    private func snapshot() -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_790_000_000),
            device: .init(appVersion: "2.4 (318)", system: "iOS 27.0", model: "iPhone17,1",
                          language: "it", lowPowerMode: false, sharedContainer: true,
                          online: true, expensive: false),
            account: .init(state: "Collegato", loginMethod: "SPID", matricola: "10712345",
                           tokenExpiresAt: nil, scopes: ScopeAudit(current: "agenda carriera", recorded: "agenda carriera"),
                           profile: 1, authorised: true, cieError: nil),
            weBeep: .init(connected: true, courses: 6, failure: nil),
            services: [.init(name: "Orario", host: "api.polimi.it")],
            addressesFromPolitecnico: true,
            probes: [],
            pending: .init(queued: 0, abandoned: []),
            background: .init(refreshPermission: "Consentito", lastRun: nil, notifications: "Consentite",
                              scheduledReminders: 3, nextReminder: nil, liveActivities: true,
                              widgetsKnowAccount: true, lastWidgetReload: nil,
                              spotlightItems: nil, spotlightIndexedAt: nil),
            performance: .init(metricReports: 2, diagnosticReports: 0, latest: nil))
    }

    @Test("La matricola resta fuori finché non la si aggiunge")
    func matricolaIsOptIn() {
        let snapshot = snapshot()
        #expect(!DiagnosticsReport(snapshot, includesMatricola: false).text.contains("10712345"))
        #expect(DiagnosticsReport(snapshot, includesMatricola: true).text.contains("Matricola: 10712345"))
    }

    /// WeBeep authenticates file downloads with its token on the query string,
    /// so a failed download's message can carry a live credential.
    @Test("Un token dentro un messaggio d’errore viene tolto")
    func tokenInQueryIsRedacted() {
        var snapshot = snapshot()
        snapshot.weBeep.failure = "Download fallito: https://webeep.polimi.it/webservice/pluginfile.php/1/a.pdf?token=abc123def456&forcedownload=1"
        let text = DiagnosticsReport(snapshot, includesMatricola: false).text
        #expect(!text.contains("abc123def456"))
        #expect(text.contains("token=[rimosso]&forcedownload=1"))
    }

    @Test("Anche un Bearer e un access_token vengono tolti")
    func bearerAndAccessTokenAreRedacted() {
        var snapshot = snapshot()
        snapshot.account.cieError = "401 con Authorization: Bearer eyJhbGciOiJSUzI1NiJ9.payload.sig"
        snapshot.pending.abandoned = ["Preferito su WeBeep (access_token=zzz999)"]
        let text = DiagnosticsReport(snapshot, includesMatricola: false).text
        #expect(!text.contains("eyJhbGciOiJSUzI1NiJ9"))
        #expect(!text.contains("zzz999"))
        #expect(text.contains("Bearer [rimosso]"))
        #expect(text.contains("access_token=[rimosso]"))
    }

    @Test("Le sezioni ci sono tutte, sempre nello stesso ordine")
    func sectionsInOrder() {
        let text = DiagnosticsReport(snapshot(), includesMatricola: false).text
        let headings = ["PoliVerse — diagnostica", "## Dispositivo", "## Accesso", "## WeBeep",
                        "## Servizi del Politecnico", "## Collegamenti", "## Modifiche in coda",
                        "## In background", "## Prestazioni"]
        let positions = headings.map { text.range(of: $0)?.lowerBound }
        #expect(!positions.contains(nil))
        #expect(positions.compactMap(\.self) == positions.compactMap(\.self).sorted())
    }

    @Test("Gli ambiti mancanti sono nominati")
    func namesMissingScopes() {
        var snapshot = snapshot()
        snapshot.account.scopes = ScopeAudit(current: "agenda so2 presence_hub", recorded: "agenda")
        let text = DiagnosticsReport(snapshot, includesMatricola: false).text
        #expect(text.contains("Ambiti mancanti: so2, presence_hub"))
    }

    @Test("I collegamenti verificati dicono esito e tempo; se non verificati lo dicono")
    func probes() {
        var snapshot = snapshot()
        #expect(DiagnosticsReport(snapshot, includesMatricola: false).text.contains("Non verificati"))

        snapshot.probes = [
            .init(name: "Orario", result: .init(verdict: .reachable(status: 200), latency: .milliseconds(180))),
            .init(name: "Aule", result: .init(verdict: .timedOut, latency: nil)),
            .init(name: "WeBeep", result: .init(verdict: .serverFault(status: 503), latency: .milliseconds(90))),
        ]
        let text = DiagnosticsReport(snapshot, includesMatricola: false).text
        #expect(text.contains("Orario: risponde (200) in 180 ms"))
        #expect(text.contains("Aule: nessuna risposta in tempo"))
        #expect(text.contains("WeBeep: errore del server (503) in 90 ms"))
    }

    @Test("Un aggiornamento in background mai concluso non è detto concluso")
    func unfinishedBackgroundRun() {
        var snapshot = snapshot()
        snapshot.background.lastRun = .init(started: Date(timeIntervalSince1970: 1_790_000_000),
                                            finished: nil, outcome: .unfinished)
        let text = DiagnosticsReport(snapshot, includesMatricola: false).text
        #expect(text.contains("Ultimo aggiornamento in background: 2026-09-21T14:13:20Z, interrotto o in corso"))
    }
}
