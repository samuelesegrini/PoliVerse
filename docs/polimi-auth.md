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

## Agenda (calendar)

```
GET /agenda/api/me/{matricola}/events?start_date=yyyy-MM-dd&n_events=200
GET /agenda/api/me/{matricola}/lectures/{event_id}     # detail, not used yet
```

Count-based, not range-based: it returns the next `n_events` items from
`start_date` with no end bound, so "this week" means over-fetching and
filtering client-side. PoliFemo asks for 200 and does the same.

`event_type.typeId` classifies the entry and must not be renumbered:

| id | meaning |
| --- | --- |
| 1 | lecture |
| 2 | exam |
| 3 | news |
| 4 | deadline |
| 5 | custom |

Most strings arrive as an `{ it, en }` pair; the app prefers `it`.

### The timestamp trap

`date_start` and `date_end` look like `2026-03-14T09:15:00` — **no timezone
designator**. They are Politecnico wall-clock time, i.e. Europe/Rome.

Two ways to get this wrong, both easy to ship:

- `JSONDecoder.dateDecodingStrategy = .iso8601` **throws** on these strings, so
  the whole response fails to decode.
- Parsing them as UTC "works" and is silently wrong: a 09:15 lecture in July
  displays at 11:15, and in January at 10:15. The offset changes with daylight
  saving, so it does not even look like a constant bug.

`PoliMiDate` in `Models/AgendaEvent.swift` pins the zone explicitly and is
verified against both CET and CEST dates. Day grouping uses a Rome calendar
too, with `firstWeekday = 2` — building a `Calendar` by identifier rather than
from a locale defaults to Sunday, which is wrong for an Italian week.

## Career

```
GET /rest/me/polimi/{matricola}          # app host: mean, given_cfu, planned_cfu, exam_stats
GET /rest/v1/insegn?lang=IT              # exams host: teachings, each with appelliEsame[]
```

One `/rest/v1/insegn` response carries both the course list and every exam
sitting, so `CourseService` and `CareerService` share one fetch rather than
calling it twice.

A sitting splits its timestamp across two fields — `d_app` (day) and `ora_ok`
(time) — recombined by `PoliMiDate.applying(time:to:)`.

Result state lives in `iscrizioneAttiva`. Pass/fail comes from `verb_positivo`
rather than parsing the mark text, which can be `28`, `30 e lode`, `SUPERATO`
or `IDONEO`. `rifiutabile` says whether the mark can still be refused.

## Rooms — not available

PoliFemo's free-room search (`/v1/rooms/search`, occupancy data) is served by
**PoliNetwork**, not PoliMi, and needs the PoliNetwork token from the Microsoft
SSO leg this app deliberately skips. Adding room search means reinstating that
leg, which is a real cost: a second token to store, refresh and revoke.

## WeBeep

Resolved — see [webeep.md](webeep.md). WeBeep is a stock Moodle and exposes a
supported token handshake at `admin/tool/mobile/launch.php`; no scraping is
needed. PoliFemo has no WeBeep code to borrow, but `toto04/webeep-sync` and
`matteovisotto/myPoliFile` both do.
