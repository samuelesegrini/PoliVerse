import Foundation

/// One SPID identity provider, as the Politecnico's login page lists it.
///
/// The page renders each as `<li class="spid-idp-button-link" data-idp="…">`
/// wrapping a submit button whose `formaction` carries a numeric `id_idp`.
/// Both are recorded, and the **slug** is what the script matches on: the
/// number is an internal identifier the Politecnico can renumber without
/// anyone noticing, while `posteID` names the provider and cannot quietly
/// become a different company.
nonisolated struct SPIDProvider: Identifiable, Hashable, Sendable {
    /// `data-idp` on the list item.
    let slug: String
    /// `id_idp` in the button's `formaction`, kept for diagnostics and as a
    /// second way to find the button if the slug ever disappears.
    let identifier: String
    /// What to call it on our own button.
    let name: String

    var id: String { slug }

    /// Measured from the live login page on 2026-09-12. Twelve providers, in
    /// the order the page lists them.
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

/// How the student wants to identify themselves, chosen on our own screen
/// rather than on the Politecnico's.
///
/// ## Why this exists
///
/// The IdP presents all of these at once: a password form, a grid of twelve
/// SPID logos, and three more federated buttons — on a page whose layout is
/// the university's and whose CSS is loaded from four stylesheets. Nothing
/// about it can be made to look like the rest of the app.
///
/// It can, however, be **driven**. Every one of those is a submit button on a
/// page we already load in a web view we already own, so the choice can be
/// made on a native screen and the matching button pressed from underneath.
/// What the student then sees is their identity provider's own page — which
/// is the one screen that must never be ours, because it is where the
/// credential is typed.
///
/// - Important: the password case deliberately presses nothing. PoliVerse
///   does not collect the codice persona or the password; the form on the
///   Politecnico's page is the only place they are ever entered.
nonisolated enum PoliMiLoginMethod: Identifiable, Hashable, Sendable, CaseIterable {
    case password
    case spid(SPIDProvider)
    case cie
    case eidas
    case eduGAIN

    /// `CaseIterable` with one SPID entry standing for the provider list,
    /// which is presented on a screen of its own.
    static var allCases: [PoliMiLoginMethod] {
        [.password, .spid(SPIDProvider.all[0]), .cie, .eidas, .eduGAIN]
    }

    var id: String {
        switch self {
        case .password: "password"
        case .spid(let provider): "spid-\(provider.slug)"
        case .cie: "cie"
        case .eidas: "eidas"
        case .eduGAIN: "edugain"
        }
    }

    /// True when choosing this leaves the student on the Politecnico's own
    /// login page — which only the password does, because its form is part of
    /// that page. Everything else navigates to a provider we do not control,
    /// and that navigation is the moment the web view has to become visible.
    var staysOnChooser: Bool {
        if case .password = self { return true }
        return false
    }

    /// JavaScript that presses this method's button on the loaded page.
    ///
    /// Empty for the password, which is already on screen. The others are
    /// matched on what identifies them rather than on position: SPID by its
    /// provider slug, the federated three by the endpoint their form posts to.
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

    private static func press(endpoint: String) -> String {
        """
        (function () {
          var button = document.querySelector('button[formaction*="\(endpoint)"]');
          if (button) { button.click(); return true; }
          return false;
        })()
        """
    }

    /// CSS that leaves only the part of the page this method needs.
    ///
    /// Used for the password alone: its form lives on the same page as the
    /// SPID grid, so revealing the form means revealing the chooser we just
    /// replaced. Hiding the federated blocks leaves the two fields and nothing
    /// else — the student sees the Politecnico's own form, on the Politecnico's
    /// own domain, without being asked to choose twice.
    /// Measured on the live page: the federated section is one wrapper,
    /// `.ingressoFederato`, holding the SPID link, CIE, eIDAS and eduGAIN; the
    /// credential form is its sibling `.ingressoPolimi`. Hiding the first
    /// leaves the second untouched, which is why this is one selector rather
    /// than a list of the buttons — a list leaves the section's own headings
    /// and dividers behind, and risks matching something inside the form.
    var pageTrimmingCSS: String? {
        guard case .password = self else { return nil }
        return ".ingressoFederato { display: none !important; }"
    }
}
