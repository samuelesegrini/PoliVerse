import Foundation

/// One SPID identity provider, as the Politecnico's login page lists it.
///
/// The page renders each as `<li class="spid-idp-button-link" data-idp="…">`
/// wrapping a submit button whose `formaction` carries a numeric `id_idp`. Both are
/// recorded, and ``slug`` is what the selection script matches on: the number is an
/// internal identifier the Politecnico can renumber, while the slug names the
/// provider.
nonisolated struct SPIDProvider: Identifiable, Hashable, Sendable {
    /// The `data-idp` value on the list item.
    let slug: String
    /// The `id_idp` value in the button's `formaction`, used as a fallback selector and
    /// for diagnostics.
    let identifier: String
    /// The provider's name on the app's own button.
    let name: String

    /// ``slug``.
    var id: String { slug }

    /// The twelve providers, in the order the login page lists them. Measured from the
    /// live page on 2026-09-12.
    static let all: [SPIDProvider] = [
        SPIDProvider(slug: "arubaID", identifier: "1298", name: "Aruba"),
        SPIDProvider(slug: "etnaID", identifier: "2606", name: "Etna"),
        SPIDProvider(slug: "infocamereID", identifier: "2651", name: "InfoCamere"),
        SPIDProvider(slug: "infocertID", identifier: "1202", name: "InfoCert"),
        SPIDProvider(slug: "intesiID", identifier: "2976", name: "Intesi Group"),
        SPIDProvider(slug: "lepidaID", identifier: "1604", name: "Lepida"),
        SPIDProvider(slug: "namirialID", identifier: "1433", name: "Namirial"),
        SPIDProvider(slug: "posteID", identifier: "1201", name: "Poste Italiane"),
        SPIDProvider(slug: "registerID", identifier: "1434", name: "Register"),
        SPIDProvider(slug: "sielteID", identifier: "1234", name: "Sielte"),
        SPIDProvider(slug: "teamSystemID", identifier: "2547", name: "TeamSystem"),
        SPIDProvider(slug: "timID", identifier: "1200", name: "TIM"),
    ]
}

/// How the student identifies themselves, chosen on the app's own screen rather
/// than on the Politecnico's.
///
/// The identity provider presents every option at once — a password form, a grid of
/// twelve SPID logos and three further federated buttons — on a page whose layout
/// is the university's. Each option is a submit button on a page the app already
/// loads in a web view it owns, so the choice is made natively and
/// ``selectionScript`` presses the matching button. What the student then sees is
/// their provider's own page.
///
/// - Important: ``password`` presses nothing. PoliVerse never collects the person
///   code or the password; the form on the Politecnico's page is the only place
///   they are entered.
nonisolated enum PoliMiLoginMethod: Identifiable, Hashable, Sendable, CaseIterable {
    /// The Politecnico's own credential form, which lives on the chooser page itself.
    case password
    /// SPID, through one of the twelve providers in ``SPIDProvider/all``.
    case spid(SPIDProvider)
    /// The Carta d'Identità Elettronica, by way of the CieID app.
    case cie
    /// eIDAS, for a European electronic identity.
    case eidas
    /// eduGAIN, for an account at another academic institution.
    case eduGAIN

    /// The methods as the chooser screen offers them, with one SPID entry standing for
    /// the whole provider list, which is presented on a screen of its own.
    static var allCases: [PoliMiLoginMethod] {
        [.password, .spid(SPIDProvider.all[0]), .cie, .eidas, .eduGAIN]
    }

    /// A stable identifier; the SPID case includes its provider's slug.
    var id: String {
        switch self {
        case .password: "password"
        case .spid(let provider): "spid-\(provider.slug)"
        case .cie: "cie"
        case .eidas: "eidas"
        case .eduGAIN: "edugain"
        }
    }

    /// Whether choosing this leaves the student on the Politecnico's login page.
    ///
    /// Only ``password`` does, because its form is part of that page. Every other
    /// method navigates to a provider the app does not control, and that navigation is
    /// when the web view becomes visible.
    var staysOnChooser: Bool {
        if case .password = self { return true }
        return false
    }

    /// JavaScript that presses this method's button on the loaded chooser page.
    ///
    /// Empty for ``password``, whose form is already on screen. SPID is matched on the
    /// provider slug with the numeric identifier as a fallback; the three federated
    /// methods are matched on the endpoint their form posts to.
    ///
    /// The script evaluates to `true` when a button was found and pressed.
    var selectionScript: String {
        switch self {
        case .password:
            return ""
        case .spid(let provider):
            // The slug first; the numeric id as the fallback, so a markup
            // change that drops `data-idp` does not take SPID down with it.
            return """
            (function () {
              var button =
                document.querySelector('[data-idp="\(provider.slug)"] button') ||
                document.querySelector('button[formaction*="id_idp=\(provider.identifier)"]');
              if (button) { button.click(); return true; }
              return false;
            })()
            """
        case .cie:
            return Self.press(endpoint: "IngressoCIE.do")
        case .eidas:
            return Self.press(endpoint: "IngressoEIDAS.do")
        case .eduGAIN:
            return Self.press(endpoint: "IngressoEduGAIN.do")
        }
    }

    /// A script that presses the button whose `formaction` names an endpoint.
    ///
    /// - Parameter endpoint: The endpoint to match, for example `IngressoCIE.do`.
    /// - Returns: The script, evaluating to `true` when the button was found.
    private static func press(endpoint: String) -> String {
        """
        (function () {
          var button = document.querySelector('button[formaction*="\(endpoint)"]');
          if (button) { button.click(); return true; }
          return false;
        })()
        """
    }

    /// CSS that hides the parts of the chooser page this method does not need, or `nil`
    /// when nothing needs hiding.
    ///
    /// Supplied for ``password`` alone, whose form shares the page with the federated
    /// options. The federated section is one wrapper, `.ingressoFederato`, and the
    /// credential form is its sibling `.ingressoPolimi`, so hiding the first leaves the
    /// second untouched — along with the section's own headings and dividers, which a
    /// list of individual buttons would leave behind.
    var pageTrimmingCSS: String? {
        guard case .password = self else { return nil }
        return ".ingressoFederato { display: none !important; }"
    }
}
