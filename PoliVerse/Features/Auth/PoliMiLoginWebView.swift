import SwiftUI

/// The PoliMi OAuth login, wrapped around ``AuthWebView`` so the CIE detour is
/// handled the same way it is for WeBeep.
struct PoliMiLoginWebView: View {
    let router: CieIDRouter
    let onCode: (String) -> Void
    let onError: (any Error) -> Void
    var onCieIDMissing: () -> Void = {}

    var body: some View {
        AuthWebView(
            startURL: PoliMiOAuth.authorizationURL,
            router: router,
            decide: { url in
                if let code = PoliMiOAuth.authCode(from: url) {
                    onCode(code)
                    return .finish
                }
                return .allow
            },
            onError: onError,
            onCieIDMissing: onCieIDMissing
        )
    }
}
