import Foundation
import Testing
@testable import PoliVerse

/// Decides what is on screen at each moment of the login. Getting it wrong in
/// one direction shows the student the Politecnico's plumbing — the Servizi
/// Online bootstrap, the chooser we just replaced with our own buttons. In the
/// other direction it hides the page where they are meant to type their
/// password, which would look like the app had frozen.
@Suite("Login stage")
struct LoginStageTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    @Test("The Servizi Online bootstrap is ours to hide")
    func bootstrapIsHidden() {
        let stage = LoginStage(
            url: url("https://polimiapp.polimi.it/polimi_app/app/"), method: .password)
        #expect(!stage.showsWebView)
    }

    @Test("The chooser page is hidden: our buttons replaced it")
    func chooserIsHidden() {
        let stage = LoginStage(
            url: url("https://aunicalogin.polimi.it/aunicalogin/aunicalogin.jsp?lang=IT&id_servizio=2429"),
            method: .cie)
        #expect(!stage.showsWebView)
    }

    /// The password form is part of the chooser page, so the page has to be
    /// shown — trimmed to the form — rather than waited out.
    @Test("The chooser is shown for the password, which has its form on it")
    func chooserShownForPassword() {
        let stage = LoginStage(
            url: url("https://aunicalogin.polimi.it/aunicalogin/aunicalogin.jsp?lang=IT"),
            method: .password)
        #expect(stage.showsWebView)
        #expect(stage.trimsPage)
    }

    @Test("The password form's own POST target stays visible")
    func credentialPostIsVisible() {
        let stage = LoginStage(
            url: url("https://aunicalogin.polimi.it/aunicalogin/aunicalogin/controller/IdentificazioneUnica.do"),
            method: .password)
        #expect(stage.showsWebView)
    }

    /// A provider's own page is the one screen that must never be ours.
    @Test("An identity provider's page is always visible")
    func providerIsVisible() {
        for host in ["posteid.poste.it", "id.lepida.it", "login.aruba.it", "idp.namirial.com"] {
            let stage = LoginStage(url: url("https://\(host)/login"), method: .spid(SPIDProvider.all[0]))
            #expect(stage.showsWebView, "\(host) must be shown")
        }
    }

    /// Coming back to Servizi Online means the identity provider is done and
    /// the code is being exchanged — ours again, and the last thing the
    /// student should watch is a redirect chain.
    @Test("The return to Servizi Online is hidden again")
    func returnIsHidden() {
        let stage = LoginStage(
            url: url("https://polimiapp.polimi.it/polimi_app/app?code=abc&state=xyz"),
            method: .spid(SPIDProvider.all[0]))
        #expect(!stage.showsWebView)
    }

    /// Before anything has loaded there is no URL, and showing an empty web
    /// view is worse than showing our own screen.
    @Test("Nothing loaded yet is ours")
    func noURLIsHidden() {
        #expect(!LoginStage(url: nil, method: .password).showsWebView)
    }

    @Test("Only the chooser page is trimmed, and only for the password")
    func trimmingIsNarrow() {
        #expect(!LoginStage(url: url("https://posteid.poste.it/"), method: .password).trimsPage)
        #expect(!LoginStage(
            url: url("https://aunicalogin.polimi.it/aunicalogin/aunicalogin.jsp"),
            method: .cie).trimsPage)
    }

    /// The stuck state this design can produce, and the one that matters: a
    /// SPID login that fails comes back to the page we hide, and the button is
    /// never pressed twice, so a hidden chooser is a login that can never
    /// finish.
    @Test("Coming back to the chooser after pressing shows it")
    func chooserShownAfterFailedSelection() {
        let stage = LoginStage(
            url: url("https://aunicalogin.polimi.it/aunicalogin/aunicalogin.jsp?lang=IT"),
            method: .spid(SPIDProvider.all[0]),
            hasPressed: true)
        #expect(stage.showsWebView)
    }

    @Test("Before pressing, the chooser is still ours to hide")
    func chooserHiddenBeforePressing() {
        let stage = LoginStage(
            url: url("https://aunicalogin.polimi.it/aunicalogin/aunicalogin.jsp"),
            method: .cie,
            hasPressed: false)
        #expect(!stage.showsWebView)
    }

    /// Revealing the chooser must not also strip it: the trimming exists to
    /// leave the password form alone on the page, and a student who has landed
    /// back here needs the other ways in.
    @Test("A revealed chooser is not trimmed for a federated method")
    func revealedChooserKeepsItsOptions() {
        let stage = LoginStage(
            url: url("https://aunicalogin.polimi.it/aunicalogin/aunicalogin.jsp"),
            method: .eidas,
            hasPressed: true)
        #expect(!stage.trimsPage)
    }

    /// The CIE flow leaves for another app entirely and comes back to a page
    /// on the same host; it must not be mistaken for the chooser.
    @Test("The CIE return page is visible")
    func cieReturnVisible() {
        let stage = LoginStage(
            url: url("https://aunicalogin.polimi.it/aunicalogin/aunicalogin/federato/cie/IngressoCIE.do"),
            method: .cie)
        #expect(stage.showsWebView)
    }
}
