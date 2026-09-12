import Foundation
import Testing
@testable import PoliVerse

/// The Politecnico's login page offers six ways in — a password form, twelve
/// SPID providers, CIE, eIDAS and EduGAIN — as submit buttons on one page.
/// These cover the part that decides which of them a native button actually
/// presses, because pressing the wrong one is a login that silently becomes
/// somebody else's identity provider.
@Suite("Login methods")
struct PoliMiLoginMethodTests {
    @Test("Every method the page offers has a case")
    func allMethodsPresent() {
        let methods = PoliMiLoginMethod.allCases
        #expect(methods.contains(.password))
        #expect(methods.contains(.cie))
        #expect(methods.contains(.eidas))
        #expect(methods.contains(.eduGAIN))
        #expect(methods.contains { if case .spid = $0 { return true } else { return false } })
    }

    /// Measured on the live page 2026-09-12: twelve providers, each an `li`
    /// carrying its own `data-idp` slug.
    @Test("All twelve SPID providers are listed")
    func spidProviders() {
        #expect(SPIDProvider.all.count == 12)
        let slugs = Set(SPIDProvider.all.map(\.slug))
        #expect(slugs.contains("posteID"))
        #expect(slugs.contains("arubaID"))
        #expect(slugs.contains("infocamereID"))
        #expect(slugs.count == 12, "a duplicated slug would press the wrong provider")
    }

    @Test("Each provider carries the id the page submits")
    func providerIdentifiers() {
        #expect(SPIDProvider.all.first { $0.slug == "posteID" }?.identifier == "1201")
        #expect(SPIDProvider.all.first { $0.slug == "timID" }?.identifier == "1200")
    }

    /// The slug is what the script matches on. The numeric id is the more
    /// obvious key and the more fragile one: it is an internal identifier the
    /// Politecnico can renumber, while `data-idp="posteID"` names the provider.
    @Test("A SPID method presses the matching provider's own button")
    func spidScriptTargetsProvider() {
        let poste = SPIDProvider.all.first { $0.slug == "posteID" }!
        let script = PoliMiLoginMethod.spid(poste).selectionScript
        #expect(script.contains("posteID"))
        #expect(!script.contains("arubaID"))
    }

    @Test("The federated methods press their own entry point")
    func federatedScripts() {
        #expect(PoliMiLoginMethod.cie.selectionScript.contains("IngressoCIE.do"))
        #expect(PoliMiLoginMethod.eidas.selectionScript.contains("IngressoEIDAS.do"))
        #expect(PoliMiLoginMethod.eduGAIN.selectionScript.contains("IngressoEduGAIN.do"))
    }

    /// The trimming leaves the student on the Politecnico's page with only
    /// the form they asked for. Hiding the form itself would be the worst
    /// possible outcome: a login page with nothing to fill in.
    @Test("Trimming hides the federated section and nothing else")
    func trimmingKeepsTheForm() {
        let css = PoliMiLoginMethod.password.pageTrimmingCSS
        #expect(css?.contains("ingressoFederato") == true)
        #expect(css?.contains("ingressoPolimi") == false)
        #expect(css?.contains("table-credenziali") == false)
    }

    @Test("Only the password trims the page")
    func onlyPasswordTrims() {
        #expect(PoliMiLoginMethod.cie.pageTrimmingCSS == nil)
        #expect(PoliMiLoginMethod.spid(SPIDProvider.all[0]).pageTrimmingCSS == nil)
        #expect(PoliMiLoginMethod.eidas.pageTrimmingCSS == nil)
    }

    /// The password form is already on the page the chooser lives on, so there
    /// is nothing to press — pressing anything would navigate away from it.
    @Test("The password method presses nothing")
    func passwordPressesNothing() {
        #expect(PoliMiLoginMethod.password.selectionScript.isEmpty)
    }

    /// Everything but the password leaves the page for somewhere we do not
    /// control, which is exactly when the web view has to become visible.
    @Test("Only the password method keeps the student on the Politecnico's page")
    func staysOnPage() {
        #expect(PoliMiLoginMethod.password.staysOnChooser)
        #expect(!PoliMiLoginMethod.cie.staysOnChooser)
        #expect(!PoliMiLoginMethod.spid(SPIDProvider.all[0]).staysOnChooser)
    }
}
