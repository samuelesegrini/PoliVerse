import Foundation

/// What the student should be looking at, for a given page of the login.
///
/// The login is four things in a row: the Servizi Online app bootstrapping,
/// the Politecnico's chooser page, an identity provider's own page, and the
/// return trip where the code is exchanged. Only the third has to be the
/// university's — it is where the credential is typed, and putting our own
/// fields in front of it would be asking for a password the app has promised
/// never to see.
///
/// The other three are plumbing, and a student watching a redirect chain
/// cannot tell a working login from a broken one. So they are covered by our
/// own screen, and this decides which is which.
nonisolated struct LoginStage: Equatable, Sendable {
    let url: URL?
    let method: PoliMiLoginMethod
    /// Whether the chosen method's button has already been pressed.
    ///
    /// This is what stops the one stuck state the design can produce. A SPID
    /// login that fails — wrong provider, cancelled at the provider, an
    /// expired session — comes back to the chooser page, and the chooser is
    /// the page we hide. Without this the student would be left watching our
    /// spinner over a page that was waiting for them, and the button is not
    /// pressed a second time, so nothing would ever move again.
    ///
    /// Coming back to the chooser after pressing means the method did not take.
    /// The page is then shown as the Politecnico wrote it, chooser and all,
    /// because a login that looks less like ours beats one that cannot finish.
    let hasPressed: Bool

    init(url: URL?, method: PoliMiLoginMethod, hasPressed: Bool = false) {
        self.url = url
        self.method = method
        self.hasPressed = hasPressed
    }

    /// Servizi Online: the bootstrap at the start and the code exchange at the
    /// end. Never anything the student needs to see.
    private var isServiziOnline: Bool {
        url?.host?.hasSuffix("polimiapp.polimi.it") == true
    }

    /// The Politecnico's own login page — the one carrying the password form,
    /// the twelve SPID logos and the three federated buttons. Recognised by
    /// its page rather than its host, because the federated entry points live
    /// on the same host and are a later stage.
    var isChooser: Bool {
        guard url?.host?.hasSuffix("aunicalogin.polimi.it") == true else { return false }
        return url?.path.hasSuffix("aunicalogin.jsp") == true
    }

    /// Whether the web view is on screen, or our own waiting screen is.
    var showsWebView: Bool {
        guard url != nil else { return false }
        if isServiziOnline { return false }
        // The chooser is what our native buttons replaced — except for the
        // password, whose form is part of it and has nowhere else to be, and
        // except on the way back from a method that did not take.
        if isChooser { return method.staysOnChooser || hasPressed }
        return true
    }

    /// Whether to hide the parts of the page the student has already chosen
    /// past. Only the chooser has anything to trim, and only the password
    /// stays on it long enough to matter.
    var trimsPage: Bool {
        isChooser && method.pageTrimmingCSS != nil
    }
}
