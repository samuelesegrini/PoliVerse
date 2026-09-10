# Authenticating against Politecnico services

Reverse-engineered from [PoliNetworkOrg/PoliFemo](https://github.com/PoliNetworkOrg/PoliFemo)
(`src/pages/Login.tsx`, `src/api/HttpClient.ts`), then simplified.

There is no public, documented PoliMi API. Everything below is the private
backend the official app talks to, and it can change without notice.

## The flow PoliFemo uses (two legs)

1. **Microsoft SSO → PoliNetwork token.** Loads
   `login.microsoftonline.com/common/oauth2/v2.0/authorize` with client_id
   `a06b160b-8d5d-4be2-b452-ea3b768998ed` and `redirect_uri=https://api.polinetwork.org/staging/v1/auth/code`.
   The redirect target renders the token **as a JSON response body**, which
   PoliFemo scrapes with injected JS:
   `window.ReactNativeWebView.postMessage(document.body.innerText)`.
2. **PoliMi IdP → PoliMi token.** Reusing the session cookie leg 1 left behind,
   navigates to `oauthidp.polimi.it/oauthidp/oauth2/auth`, which cascade-redirects
   to `polimiapp.polimi.it/polimi_app/app?code=<authcode>`.

## The flow PoliVerse uses (one leg)

The PoliNetwork token only unlocks PoliNetwork's own features — news, room
search, groups, account settings. PoliVerse needs none of them, so leg 1 is
dropped. With no session cookie present the PoliMi IdP prompts for credentials
itself, then redirects with the authcode exactly as before.

```
GET https://oauthidp.polimi.it/oauthidp/oauth2/auth
      ?client_id=1057407812
      &redirect_uri=https://polimiapp.polimi.it/polimi_app/app
      &scope=openid polimi_app aule … carriera orario esami webeep pianostudente
      &access_type=offline
      &response_type=code
  ↓ (user authenticates on the ateneo page)
→ https://polimiapp.polimi.it/polimi_app/app?code=<authcode>
  ↓
GET /rest/jaf/oauth/token/get/<authcode>
→ { accessToken, refreshToken, expiresIn }
```

Refresh: `GET /rest/jaf/oauth/token/refresh/<refreshToken>`.
Note the refresh token travels in the **URL path**, so it will appear in any
server-side access log. Not our choice, but worth knowing.

Implemented in `Services/PoliMiOAuth.swift` and `Services/LoginWebView.swift`.

`ASWebAuthenticationSession` cannot be used: it needs either a custom URL scheme
or an https callback on a domain we own via Associated Domains, and the redirect
lands on `polimiapp.polimi.it`. Intercepting `WKWebView` navigation is the only
option short of PoliMi registering a scheme for us.

## Hosts

| Host | Purpose |
| --- | --- |
| `polimiapp.polimi.it/polimi_app` | user info `/rest/jaf/internal/user`, gradebook `/rest/me/polimi/{matricola}`, timetable `/agenda/api/me/{matricola}/events` |
| `www22.dmz.polimi.it/iae` | teachings `/rest/v1/insegn`, exam booking `/rest/v1/iscriz/...` |
| `webeep.polimi.it` | Moodle — see below |

All three take the same `Authorization: Bearer <accessToken>`.

## What we changed, and why

| PoliFemo | PoliVerse |
| --- | --- |
| Tokens in `AsyncStorage` — plaintext in the app container | Keychain, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` |
| Concurrent 401s each trigger their own refresh (their `// TODO: await for token to refresh`) | `actor TokenStore` collapses them into one in-flight `Task` |
| `RETRY_INDEFINETELY` on HTTP 500, every 3 s, forever | 3 attempts, exponential backoff |
| `staging` PoliNetwork URL hardcoded in shipping builds | PoliNetwork not used |
| Authcode extracted with `url.replace(prefix, "")` | Query parsed properly, survives `&state=` |
| Token scraped from `document.body.innerText` | Not needed — leg 1 is gone |

The refresh race is the one worth dwelling on. PoliMi rotates the refresh token,
so when five parallel requests all 401 and all refresh, the first response
invalidates the token the other four are mid-flight with, and the user is
silently logged out. Making the store an `actor` makes that unrepresentable.

## WeBeep — unresolved

**PoliFemo has no WeBeep integration.** `grep -ri webeep` across that repository
returns exactly one hit: the scope string in the login URL. There was no logic
to port.

WeBeep is a stock Moodle. Moodle's REST API needs its own `wstoken`, which the
PoliMi OAuth token is not. The intended path is the handshake the official
Moodle app performs on SSO-only sites:

1. `GET /admin/tool/mobile/launch.php?service=moodle_mobile_app&passport=<n>&urlscheme=poliverse`
2. Moodle bounces through the institutional IdP (likely silent, since the user
   just authenticated)
3. Redirect to `poliverse://token=<base64>` decoding to `siteid:::wstoken:::privatetoken`
4. Then `/webservice/rest/server.php?wstoken=…&wsfunction=core_course_get_contents`

**Not yet implemented.** Two things must happen first: verify the passport
signature (step 3's payload is signed against the value sent in step 1 — skipping
that check would let another app replay the redirect), and confirm WeBeep has
`tool_mobile` enabled at all. Until then `WeBeepService.isLive` is `false` and
the UI says so on screen rather than pretending.
