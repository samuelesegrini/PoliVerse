import Foundation

/// Decides, for one page of the sign-in, whether the student sees the web view or
/// the app's own waiting screen.
///
/// A sign-in passes through four things: the Servizi Online bootstrap, the
/// Politecnico's chooser page, the chosen identity provider's own page, and the
/// return trip where the authorisation code is exchanged. Only the third must be
/// the university's, because it is where the credential is typed. The other three
/// are plumbing, and ``showsWebView`` hides them behind the app's own screen.
///
/// ``trimsPage`` additionally hides the parts of the chooser the student has
/// already chosen past.
nonisolated struct LoginStage: Equatable, Sendable {
    /// The page the web view is on, or `nil` before the first navigation.
    let url: URL?
    /// The sign-in method the student chose on the app's own screen.
    let method: PoliMiLoginMethod
    /// Whether the chosen method's button has already been pressed on the chooser.
    ///
    /// A federated sign-in that does not take — a wrong provider, a cancellation, an
    /// expired provider session — returns to the chooser, which is the page the app
    /// hides. Once the button has been pressed, the chooser is shown as the Politecnico
    /// wrote it, so that the student can choose again rather than watch a spinner over
    /// a page waiting for input.
    let hasPressed: Bool

    /// Creates a stage.
    ///
    /// - Parameters:
    ///   - url: The page the web view is on.
    ///   - method: The method the student chose.
    ///   - hasPressed: Whether that method's button has already been pressed.
    init(url: URL?, method: PoliMiLoginMethod, hasPressed: Bool = false) {
        self.url = url
        self.method = method
        self.hasPressed = hasPressed
    }

    /// Whether the page is Servizi Online — the bootstrap at the start and the code
    /// exchange at the end, neither of which the student needs to see.
    private var isServiziOnline: Bool {
        url?.host?.hasSuffix("polimiapp.polimi.it") == true
    }

    /// Whether the page is the Politecnico's own login page, carrying the password
    /// form, the SPID grid and the federated buttons.
    ///
    /// Recognised by its path rather than its host, because the federated entry points
    /// live on the same host and are a later stage.
    var isChooser: Bool {
        guard url?.host?.hasSuffix("aunicalogin.polimi.it") == true else { return false }
        return url?.path.hasSuffix("aunicalogin.jsp") == true
    }

    /// Whether the web view is on screen rather than the app's waiting screen.
    ///
    /// `false` before the first navigation and on Servizi Online. On the chooser it is
    /// `true` only for a method that stays there — the password, whose form is part of
    /// the page — or once ``hasPressed`` is set. Every other page is shown.
    var showsWebView: Bool {
        guard url != nil else { return false }
        if isServiziOnline { return false }
        // The chooser is what our native buttons replaced — except for the
        // password, whose form is part of it and has nowhere else to be, and
        // except on the way back from a method that did not take.
        if isChooser { return method.staysOnChooser || hasPressed }
        return true
    }

    /// Whether to apply ``PoliMiLoginMethod/pageTrimmingCSS``, which only the chooser
    /// has anything to trim and only the password stays on.
    var trimsPage: Bool {
        isChooser && method.pageTrimmingCSS != nil
    }
}
