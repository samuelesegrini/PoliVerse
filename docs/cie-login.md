# "Entra con CIE" inside PoliVerse

## The problem

The ateneo login offers CIE (Carta d'Identità Elettronica). Inside a plain
`WKWebView` the sequence goes:

1. The login page navigates to the CIE identity provider.
2. iOS hands that URL to the **CieID app**.
3. The user taps their card and enters the PIN.
4. CieID has no idea who called it, so it returns the authenticated URL to the
   **default browser**.

The session cookie lands in Safari. Our web view never sees it. The login is
gone — which is exactly the symptom: CieID opens, authentication succeeds,
Safari appears, and the app is still logged out.

## The fix

The CieID app accepts a **`sourceApp`** query parameter naming the URL scheme
to return to. From `italia/cieid-ios-sdk`,
`CieIDWKWebViewController.redirectFlow`:

```swift
let string = urlCaught.absoluteString + "&sourceApp=\(urlSchemeString)"
let finalURL = URL(string: "CIEID://" + string)
UIApplication.shared.open(finalURL)
```

So the navigation must be **intercepted before the web view follows it**,
cancelled, and re-opened by us with `sourceApp` attached. Allow it to proceed
even once and the hand-off happens without `sourceApp`, and the return goes to
Safari.

```
web view sees  https://ios.idserver.servizicie.interno.gov.it/...&nextUrl=...
     ↓ cancel
we open        CIEID://https://ios.idserver.servizicie.interno.gov.it/...&sourceApp=one.wape.PoliVerse
     ↓ user authenticates with card + PIN
CieID opens    one.wape.PoliVerse://https://idserver.servizicie.interno.gov.it/...
     ↓ onOpenURL → CieIDRouter
we strip to    https://idserver.servizicie.interno.gov.it/...
     ↓ load into the SAME web view (it holds the session)
login continues
```

## Pieces

| File | Role |
| --- | --- |
| `Services/CieIDBridge.swift` | detection, URL rewriting, return parsing |
| `Services/CieIDRouter.swift` | carries the return from `onOpenURL` to the live web view |
| `Services/AuthWebView.swift` | shared login web view; intercepts the hand-off |
| `Config/Info.plist` | registers the URL schemes |

Both logins (PoliMi OAuth and WeBeep Moodle) run on `AuthWebView`, so CIE works
identically in both and the handling exists once.

## Details that matter

**Interception condition.** Mirrors the SDK: an IdP URL containing
`ios.idserver.servizicie.interno.go` *and* `nextUrl`, or a path containing
`livello1` / `livello2` (the CIE assurance levels, which carry no `nextUrl`).

**The hand-off URL is built by string concatenation, not `URLComponents`.**
`CIEID://https://host/...` is not a legal URL — the whole https URL sits where
the host belongs — so composing it "properly" percent-escapes the payload and
CieID rejects it. The SDK concatenates for the same reason.

**CieID sometimes returns `https//` with one slash.** The official SDK patches
exactly that string before parsing. Not handling it breaks real logins while
every well-formed test still passes, so there is a test for it specifically.

**Two schemes, deliberately.** `one.wape.PoliVerse` for the CIE return (the SDK
asks integrators to use the bundle identifier) and `poliverse` for the Moodle
token. The payloads are unrelated and keeping them apart means neither handler
can mis-parse the other.

**`LSApplicationQueriesSchemes` is required.** Without `CIEID` listed,
`canOpenURL` returns false and we would wrongly report the app as missing.

**The web view uses a non-persistent data store.** The CieID detour backgrounds
PoliVerse for as long as the user takes with the card and PIN. If iOS reclaims
the app in that window, the in-memory cookies go with it and the login must be
restarted. Persisting them would survive that but would leave an ateneo session
on disk indefinitely. If restarts turn out to be common in practice, this is the
knob to turn.

## Verified

- Both schemes are registered and iOS delivers them to PoliVerse; an
  unregistered scheme is rejected (`simctl openurl`, contrasted).
- Return parsing, including the mangled `https//` form, the error parameter,
  and the router's consume-once behaviour — 14 tests.

## Not verified

The full round trip has **not** been run against the real CieID app, which
needs a physical CIE and NFC. What to watch on the first real attempt:

1. Whether CieID honours `sourceApp` here — the ateneo IdP is the Service
   Provider, not us, and the SDK is written for SPs integrating their own
   login page.
2. Whether the interception condition fires. If CieID never opens, log the
   URLs reaching `AuthWebView.decidePolicyFor` and compare against
   `isHandoffToCieID`.
3. Whether the returned URL actually resumes the session, or whether the IdP
   expects the browser to hold something extra.

If `sourceApp` turns out to be ignored because we are not a federated Service
Provider, the fallback is `ASWebAuthenticationSession`, which shares its cookie
jar with Safari — so a CieID return that lands in Safari would still be inside
the session the auth session can see. That is a larger change and worth trying
only if the approach above fails.
