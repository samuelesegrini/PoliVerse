import Testing
@testable import PoliVerse

/// A token only carries the scopes that were asked for when it was minted, and
/// the Politecnico changes that list. Comparing the two is how the diagnostics
/// page explains "servizi non autorizzati" by name instead of by symptom.
@Suite("Ambiti OAuth")
struct ScopeAuditTests {
    @Test("Con gli stessi ambiti non manca niente")
    func matchingScopes() {
        let audit = ScopeAudit(current: "agenda carriera webeep", recorded: "agenda carriera webeep")
        #expect(audit.isCurrent)
        #expect(audit.missing.isEmpty)
        #expect(audit.retired.isEmpty)
    }

    @Test("Nomina gli ambiti aggiunti dopo il token, nell’ordine della richiesta")
    func namesMissingScopes() {
        let audit = ScopeAudit(current: "aule agenda carriera so2", recorded: "aule carriera")
        #expect(!audit.isCurrent)
        #expect(audit.missing == ["agenda", "so2"])
    }

    /// "3 su 4" is what the page says; the count must be of today's list,
    /// not of whatever the old token happened to carry.
    @Test("Conta quanti degli ambiti richiesti ha il token")
    func countsGrantedOfRequested() {
        #expect(ScopeAudit(current: "aule agenda carriera so2", recorded: "aule carriera esami").grantedCount == 2)
        #expect(ScopeAudit(current: "agenda carriera", recorded: nil).grantedCount == 0)
    }

    @Test("Nomina gli ambiti che il Politecnico non chiede più")
    func namesRetiredScopes() {
        let audit = ScopeAudit(current: "agenda", recorded: "agenda esami incarichidocente")
        #expect(audit.retired == ["esami", "incarichidocente"])
        #expect(audit.missing.isEmpty)
        // Asking for less than the token has does not break anything the app
        // calls, but the session code re-authenticates on any difference, so
        // the page must not call it current either.
        #expect(!audit.isCurrent)
    }

    /// Scopes are compared as a set: the same list in another order, or with
    /// the doubled spaces the fallback string is built from, is the same grant.
    @Test("Ordine, spazi doppi e ripetizioni non contano")
    func ignoresFormatting() {
        let audit = ScopeAudit(current: "carriera  agenda\nagenda", recorded: " agenda carriera ")
        #expect(audit.isCurrent)
        #expect(audit.requestedCount == 2)
    }

    /// Tokens minted before the app recorded their scope are exactly the ones
    /// that predate a scope change, so "unknown" must never read as "fine".
    @Test("Senza ambito registrato il token non è considerato aggiornato")
    func unknownRecordedScope() {
        let audit = ScopeAudit(current: "agenda carriera", recorded: nil)
        #expect(!audit.isCurrent)
        #expect(audit.isUnknown)
        #expect(audit.missing.isEmpty)
        #expect(audit.requestedCount == 2)
    }
}
