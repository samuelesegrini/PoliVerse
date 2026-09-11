# PoliMi private API — research notes

Researched 2026-09-11. Builds on [endpoint-status.md](endpoint-status.md),
[polimi-auth.md](polimi-auth.md), [webeep.md](webeep.md) — it does not repeat them.

Primary sources only:

- **`BUNDLE`** — the official Servizi Online SPA bundle, public, no auth:
  `https://polimiapp.polimi.it/polimi_app/app/assets/index-iZo7M--C.js`
  (8.3 MB, minified, `viewVersion` 7.4.0). Cited by minified identifier.
- **`PROBE`** — unauthenticated `curl` against polimi.it, 2026-09-11. No
  credentials were used anywhere; every probe is a public GET or a
  non-authenticating redirect check.
- Moodle upstream source for the WeBeep section.

---

## 1. The scope-401 (`Code: 33`) — lead finding

### What the error actually means

The JAF gateway in front of `api.polimi.it` distinguishes several failure
modes, and the codes are stable. VERIFIED by PROBE against
`https://api.polimi.it/agenda/v1/matricola/000000/events?start_date=2026-09-11&n_events=5`:

| Request | HTTP | body |
| --- | --- | --- |
| no `Authorization` header | 401 | `{"statusCode":401,"message":"(POLIJ_033001) Il servizio richiede autenticazione"}` |
| `Authorization: Bearer FAKE` | 401 | `…JafUnauthorizedException: (POLIJ_004000) Ticket non valido (codice 15` |
| `Bearer FAKE` + `poliAuthProfile: 0` + `poliAuthD_profile: JAF_D_PROFILE_VUOTO` | 401 | identical — *codice 15* |

So the three states are distinct:

- **no token** → `POLIJ_033001`
- **unparseable / unknown token** → *codice 15*
- **our case, *codice 33*** → the token parsed fine, the user resolved fine,
  and the gateway then rejected the token's **granted scope set**.

Two consequences that narrow the search a lot:

1. It is **not** a missing/incorrect header. The profile headers change nothing
   in the error path (probe row 3), so `poliAuthProfile` is not what is failing.
2. It is **not** the request we send to `api.polimi.it` at all. It is the token
   we are holding. The token is genuinely missing `agenda` / `react_iae` in its
   grant.

### What is *not* the cause — ruled out by probe

**`al_id_srv` is irrelevant to the grant.** VERIFIED by PROBE: the same
authorize URL with `al_id_srv=` (empty) and with `al_id_srv=2428` produces a
byte-identical 303 `Location`, down to the `__pj1` signature:

```
GET https://oauthidp.polimi.it/oauthidp/oauth2/auth?client_id=1057407812
   &redirect_uri=https%3A%2F%2Fpolimiapp.polimi.it%2Fpolimi_app%2Fapp
   &access_type=offline&response_type=code&state=test
   &matricola=&al_pj_matricola=&access_token=
   &scope=openid+polimi_app+agenda&al_id_srv=<either>&al_id_srv_chiamante=
→ 303 https://aunicalogin.polimi.it/aunicalogin/aunicalogin.jsp
        ?lang=IT&id_servizio=2429&id_servizio_idp=828
        &scope=openid+polimi_app+agenda&redirect_uri=…&state=test
        &client_id=1057407812&__pj0=0&__pj1=8f5f7649d49de83faa4357704ef7566b
```

`al_id_srv` is dropped by the IdP. `id_servizio=2429` is the IdP's own service
id for the OAuth endpoint and is constant. **Sending `al_id_srv=2428` is
neither the fix nor the bug** — remove it or keep it, it makes no difference.
(2428 *is* a real service id: `/jaf/public/app?al_id_srv=2428` returns
`descSrvCorrente: {"it":"PoliMI APP"}`, and it is the value the SPA passes as
`logout_service_id`. It is simply not consulted by `/oauth2/auth`.)

**Scope encoding is not the cause.** VERIFIED by PROBE: `%20`-separated and
`+`-separated scope strings both normalise to `+` in the IdP's redirect, and
both are accepted.

**The full scope string is accepted verbatim.** VERIFIED by PROBE: the entire
32-item string from `/jaf/oauth/params` returns 303 to aunicalogin with the
scope echoed unchanged. The IdP *does* validate scope names — `scope=openid
polimi_app bogus_xyz` and a missing `scope` both return
`303 → …/oauth2/?error=invalid_request&error_description=SCOPE_NOT_VALID` —
so a 303 to aunicalogin is positive proof every requested scope name is valid
for client `1057407812`.

**There is no second token, no token-for-service exchange, no audience or
resource parameter, and the `linksalto` jump is not involved in API calls.**
VERIFIED from BUNDLE: exactly one credential object (`oauthCredentials` in
`sessionStorage`, const `Kpe`) is minted, and one request interceptor
(`uxe`, and its openapi-fetch twin `Fhe`) attaches it to *every* client —
`/polimi_app/rest`, `api.polimi.it/agenda`, `iae.base_url`,
`libretto.base_url`, `maps.base_url`, `richiesta_ausili.base_url`.
`linksalto` (`POST /jaf/public/linksalto`) is only used by the `C7`/`Nde`
navigation hook to hand the browser a `jump_url` for a *different web app*; it
returns no token and is never called before an API request.

### Best-supported explanation

The token PoliVerse holds was minted against an **older grant that did not
include the service scopes**, and re-running authorize is silently replaying
that same grant instead of creating a new one.

This is exactly what the server's own message says to do — *"Effettuare
logout/login o disinstallare e reinstallare l'applicazione"* — and
[endpoint-status.md](endpoint-status.md) already established the invariant that
makes it possible: **a token's scopes are fixed at creation, and
`/jaf/oauth/token/refresh/{token}` never widens them.** Three ways that state
survives a "fresh login" in an iOS app:

1. **A stale refresh token in the Keychain.** `B9()` in BUNDLE returns the
   cached access token and only refreshes; it never re-authorizes. If PoliVerse
   mirrors that, a token minted before the scope list was corrected keeps being
   refreshed forever, and `/jaf/internal/user` keeps working (scope
   `polimi_app`) while `agenda` and `react_iae` keep 401-ing. INFERRED, but it
   fits the observed asymmetry exactly.
2. **A surviving aunicalogin SSO cookie.** `WKWebView` with the default
   (persistent) data store keeps the `aunicalogin.polimi.it` session across
   logins. With a live SSO session the IdP can skip the consent/authorisation
   step and re-issue a code against the *existing* grant, ignoring the widened
   `scope` in the new authorize request. This is the standard reason an OAuth
   server tells a user to log out rather than just retry.
3. A **hardcoded legacy scope string** still in the binary. The old list in
   [polimi-auth.md](polimi-auth.md) contains `esami`, which no longer exists in
   `/jaf/oauth/params`; note the IdP rejects unknown scope names outright with
   `SCOPE_NOT_VALID`, so if that string were being sent the login would fail
   visibly rather than produce a narrow token — check that the runtime request
   really carries the fetched string, not the constant.

### Recommended fix, in order

1. **Log the authorize URL that is actually opened** and confirm the `scope=`
   query item contains `agenda react_iae pianostudente webeep`. One line of
   evidence settles hypothesis 3 immediately.
2. **Hard-reset the credential**: delete both access and refresh token from the
   Keychain before authorizing. Never refresh across a scope-list change —
   the app already knows the granted scope list, so store it with the token and
   force a full re-authorize when it differs from `/jaf/oauth/params`.
3. **Kill the SSO session, not just the app session.** VERIFIED by PROBE, this
   is public and needs no auth:

   ```
   GET https://polimiapp.polimi.it/polimi_app/rest/jaf/public/linklogout?lang=it&logout_service_id=2428
   → {"targetURL":"https://aunicalogin.polimi.it/aunicalogin/aunicalogin.jsp?mode=logout&id_servizio=2428&lang=it&__pj0=0&__pj1=…"}
   ```

   Load `targetURL` in the login `WKWebView` before starting authorize.
4. **Use a non-persistent `WKWebsiteDataStore`** for the login web view (or
   clear cookies for `*.polimi.it` first), so hypothesis 2 cannot recur.
5. Call `POST /jaf/oauth/revoke` (authenticated, via the app host) on logout —
   that is what the official app does (`bde` in BUNDLE) and it is the only
   server-side invalidation available.

If after 1–4 a demonstrably fresh token still returns *codice 33*, the
remaining possibility is that the grant is bound to `client_id` +
`redirect_uri` and PoliVerse's `redirect_uri` differs from the official one by
so much as a trailing slash. The official value is computed at runtime
(`vde`/`Oxe` in BUNDLE, regex `/^(\/\w+\/app)(\/?.*)$/` applied to
`location.pathname + search`) and in production evaluates to exactly
`https://polimiapp.polimi.it/polimi_app/app` — no trailing slash, no path, no
query.

---

## 2. The authorize → code → token sequence, exactly

VERIFIED from BUNDLE, function `Sde` (the one containing `oauthServer` and
`al_pj_matricola`). Params are built with `URLSearchParams`, so **every key is
present even when empty**, and in this order:

```
GET {oauthServer}/auth            # {oauthServer} = https://oauthidp.polimi.it/oauthidp/oauth2
  ?client_id=1057407812           # from /jaf/oauth/params .clientId
  &redirect_uri=https%3A%2F%2Fpolimiapp.polimi.it%2Fpolimi_app%2Fapp
  &access_type=offline            # .accessType
  &response_type=code             # .responseType
  &state=<uuid v4>                # crypto.randomUUID, saved to storage key "oauthCheck"
  &matricola=                     # empty on login
  &al_pj_matricola=               # empty on login
  &access_token=                  # empty on login; current token when switching career
  &scope=<the full string from /jaf/oauth/params, space-separated>
  &al_id_srv=                     # from the SPA's own URL params; empty when opened directly
  &al_id_srv_chiamante=           # ditto
```

Career switch (`Lxe` → `Sde(matricola)`) uses the path
`{oauthServer}/careerChange` instead of `/auth`, fills `matricola` /
`al_pj_matricola` / `access_token`, and sends **`scope=` empty**; it then
revokes the old token.

Return leg, VERIFIED from BUNDLE (`$de`, `Cxe`):

```
→ https://polimiapp.polimi.it/polimi_app/app?code=<code>&state=<uuid>
  # state MUST equal the stored one; the app throws otherwise
GET https://polimiapp.polimi.it/polimi_app/rest/jaf/oauth/token/get/<code>     # plain axios, NO auth header
→ { accessToken, refreshToken, expiresIn }        # expiresIn in seconds
GET …/rest/jaf/oauth/token/refresh/<refreshToken>  # same shape
POST …/rest/jaf/oauth/token? — no. Logout is: POST /jaf/oauth/revoke (authenticated)
```

Storage: one JSON object under `sessionStorage["oauthCredentials"]` =
`{accessToken, refreshToken, accessTokenExpiration}` where
`accessTokenExpiration = expiresIn*1000 + Date.now()`. `B9()` returns the
access token, refreshing first if `accessTokenExpiration < Date.now()`, with a
module-level in-flight promise (`UE`) collapsing concurrent refreshes — the
same single-flight design as PoliVerse's `actor TokenStore`.

Live public config, VERIFIED by PROBE `GET /polimi_app/rest/jaf/oauth/params`:

```json
{"oauthServer":"https://oauthidp.polimi.it/oauthidp/oauth2","responseType":"code",
 "clientId":"1057407812","accessType":"offline",
 "aunicaLoginGetServizio":"https://aunicalogin.polimi.it/aunicalogin/getservizioOAuth.xml",
 "scope":"aule policard portale_so incarichi orario account webmail compila_quest openid rubrica richass guasti prenotazione code carriera alumni webeep richieste_occupazione maps polimi_app teamwork faqappmobile rich_sing_occup react_iae multichance_richieste_ausili pianostudente incattdid presentazionepianireact cataloghi_aule agenda so2 prenotazioni presence_hub"}
```

Unchanged from the list in endpoint-status.md. The new field vs. that note is
`aunicaLoginGetServizio`, used only by the anonymous SSO probe and the
`__legacyUnsafeJump` path.

---

## 3. The two HTTP clients

VERIFIED from BUNDLE.

**`li` is plain axios**, `li = Wce(M9)` — the default instance. Its only
configuration is `li.defaults.baseURL = "/polimi_app/rest"`. It carries **no
auth header**. It is used for exactly the public/unauthenticated calls:
`/jaf/public/app`, `/jaf/public/i18n`, `/jaf/public/props`,
`/jaf/oauth/params`, `/jaf/oauth/token/get/{code}`,
`/jaf/oauth/token/refresh/{t}`, `/jaf/public/linklogout`,
`POST /jaf/public/linksalto`.

**`Qr` is the authenticated client factory:**

```js
Qr = ({baseURL = "/polimi_app/rest", profile, dprofile, config,
       disableOAuthTokenRefresh = false} = {}) => {
  const d = li.create({baseURL, ...config});
  if (profile  !== undefined) d.defaults.headers["poliAuthProfile"]   = profile;
  if (dprofile !== undefined) d.defaults.headers["poliAuthD_profile"] = dprofile;
  d.interceptors.request.use(uxe);          // auth
  if (!disableOAuthTokenRefresh) d.interceptors.response.use(id, cxe(d));
  return d;
}
```

Request interceptor `uxe` — this is the complete set of things attached to
every authenticated call, to any host:

```js
headers.Authorization = `Bearer ${await B9()}`
headers["poliAuthProfile"]   ??= ctx.profile?.profile  ?? 0
headers["poliAuthD_profile"] ??= ctx.profile?.dprofile ?? "JAF_D_PROFILE_VUOTO"
```

No `al_id_srv`, no default query params, no `X-`-anything. The openapi-fetch
middleware `Fhe` (used for the agenda and the `/polimi_app/rest` v1 surface)
does the same three headers, except it omits `poliAuthD_profile` when
`dprofile` is falsy.

Response interceptor `cxe`: on 401 and only once per request (`config._retry`),
re-fetch the token, replace the header, replay. A second 401 signs the user
out. **Note this retries a scope-401 too, which is why a wrong-scope token
produces two identical 401s per call.**

Per-service `profile` values come from `/jaf/public/props`, VERIFIED by PROBE:

```json
{"iae.base_url":"https://api.polimi.it/iae",                     "iae.profile":"0",
 "libretto.base_url":"https://api.polimi.it/piano_studente",     "libretto.profile":"0",
 "ws_aule.base_url":"https://api.polimi.it/ws_aule",             "ws_aule.profile":"3",
 "incattdid.base_url":"https://api.polimi.it/incattdid",         "incattdid.profile":"0",
 "richiesta_ausili.base_url":"https://api.polimi.it/multichance_new","richiesta_ausili.profile":"3",
 "maps.base_url":"https://onlineservices.polimi.it/maps_rest/rest","maps.profile":"0",
 "piani.base_url":"", "piani.profile":""}
```

**The profile drives an extra query param.** VERIFIED from BUNDLE (`M_`,
`Dze`, `V7`, `j_e`):

```js
profile === 0 ? client.get(path)
              : client.get(path, {params: {matricola}})
```

i.e. a student (`profile 0`) sends no `matricola`; a staff/service profile
(`profile 3`, e.g. `ws_aule`) must send `?matricola=<m>`. Implement this or
the `ws_aule` and `multichance` calls will fail even with a good token.

---

## 4. Endpoint surface

### 4a. App host — `https://polimiapp.polimi.it/polimi_app/rest`

`/jaf/*` as documented in endpoint-status.md. Additionally the bundle has a
typed openapi client (`k1`/`bh`) on this same base, VERIFIED from BUNDLE and
confirmed live (all **401**, i.e. they exist — PROBE):

| Method | Path | Notes |
| --- | --- | --- |
| GET | `/v1/settings` | 401 |
| GET | `/v1/careers/list` | 401 — career list for the matricola switcher |
| GET | `/v1/careers/favorite/{matricola}` | INFERRED path only |
| GET | `/v1/notifications`, `/v1/notifications/{id_notice}` | 401 |
| GET | `/v1/io-e-polimi/esc`, `/v1/io-e-polimi/{registration_number}` | "Io e PoliMi" summary card |
| POST | `/v1/io-e-polimi/qr-access` | campus QR access |
| GET | `/v1/fallback/app/{version}`, `/v1/fallback/lib/{lib_name}/{version}` | |
| — | `/v1/devices/register`, `/v1/devices/unregister`, `/v1/sync/{registration_number}`, `/v1/persona/tags`, `/v1/persona/tags/preferences` | present as literals in BUNDLE; host attribution INFERRED |

`POST /jaf/public/linksalto` body shape, VERIFIED from BUNDLE (`C7`) and by a
PROBE that reached validation:

```json
{"target_service_id": <int>, "return_url": "<absolute url>",
 "params": {"lang":"it","polij_device_category":"DESKTOP|TABLET",
            "polij_into_webview":false,"polij_style":"…",
            "al_pj_matricola":"…","al_id_srv_chiamante":"…"}}
→ {"jump_url": "…"}
```

PROBE with `target_service_id: 2428` →
`400 {"violations":[{"field":"id_servizio","message":"Unauthorized"}]}` —
the endpoint validates that the caller may jump to that service.

### 4b. Agenda — `https://api.polimi.it/agenda`

VERIFIED from BUNDLE (`DB`/`Vb` openapi client, base
`REACT_APP_AGENDA_REST_PATH = "https://api.{env.}polimi.it/agenda"`, where
`{env.}` → `""` in prod, `"test."`/`"dev."` on those hostnames):

```
GET /v1/matricola/{matricola}/events
      ?n_events=<int>&start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
      &in_evidenza=<bool>&only_show_agenda=<bool>
GET /v1/matricola/{matricola}/events/deadlines
      ?start_date=…&end_date=…&in_evidenza=…&only_show_agenda=…
GET /v1/persona/news?start_date=…&end_date=…&show_in_agenda=…&filter_by_interests=…
```

**New vs. endpoint-status.md:** `end_date` exists (the official app asks
`start_date = today`, `end_date = today + 1 month` for events, `+ 1 year` for
deadlines and news), and `in_evidenza` / `only_show_agenda` are real boolean
filters — `in_evidenza=true, only_show_agenda=false` drives the home carousel,
`in_evidenza=true, only_show_agenda=true` the "next activity" card. That means
server-side range filtering is available and the over-fetch-and-filter approach
in `polimi-auth.md` is no longer necessary.

Response shape, VERIFIED (field access in BUNDLE, not a schema): an array of

```
event_id, title:{it,en}, description?:{it,en}, date_start, date_end,
event_type:{typeId, type_dn:{it,en}}, event_subtype (string, keys
LBL_FORMA_DIDATTICA_*), tags:[{event_tag_id, denomination:{it,en}}]
```

Known `event_tag_id` values branch the card artwork: 6, 8, 81, else default.
The `typeId` table in polimi-auth.md is still used. Timestamps are still
timezone-less wall-clock — the bundle parses them with dayjs local time,
confirming the Europe/Rome reading.

`/v1/settings` and `/v1/careers/list` are **404 on this host** (PROBE) — they
live on the app host. Do not mix the two `v1` namespaces.

### 4c. IAE (exams) — `https://api.polimi.it/iae`

VERIFIED from BUNDLE. Every call goes through `M_`/`V7`/`j_e`/`Dze`, so
`poliAuthProfile: 0` (from `iae.profile`) and no `matricola` param.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/v1/base/infoStud` | student info; the app reads `.matricola` from it |
| GET | `/v1/base/counters` | career counters (feeds the "Esami" summary card) |
| GET | `/v1/base/datas` | base reference data |
| GET | `/v1/check/generiche` | generic pre-checks / blocking messages |
| GET | `/v1/check/iscriz/{a}/{b}/{c}` | enrolment eligibility check |
| GET | `/v1/insegn?lang=IT` | all teachings, each with `appelliEsame[]` |
| GET | `/v1/insegn/{a}/{b}[/{c}]?lang=IT` | one teaching |
| POST | `/v1/iscriz/{a}/{b}/{c}?lang=IT` body `{cRisposta, cRispostaAteneo}` | enrol in a sitting |
| POST | `/v1/iscriz/straord/{a}/{b}?lang=IT` body `{cRisposta:null, cRispostaAteneo}` | extraordinary sitting |
| PATCH | `/v1/iscriz/{id}` body `{cRisposta}` or `{cRispostaAteneo}` | amend answers |
| DELETE | `/v1/iscriz/{id}` | withdraw |
| GET | `/v1/prove/{c_appello}` | sitting detail |
| GET | `/v1/prove/correzioni/{c_appello}` | list of correction documents |
| GET | `/v1/prove/correzione/{id}` | **`responseType: blob`** — a file, not JSON |
| PATCH | `/v1/esito/rifiuta/{id}` body `{}` | refuse the mark |
| PATCH | `/v1/esito/richcoll/{id}` body `{}` | request a meeting about the mark |

Field names confirmed in use: `appello.c_appello`,
`appello.iscrizioneAttiva.{xverbEsito, hasCorrezioni}`, plus the
`iscrizioneAttiva` / `verb_positivo` / `rifiutabile` fields polimi-auth.md
already lists. Message objects are `{messaggio, tipo:"W", tipo_messaggio:"B",
esito:"N"}`. `PROBE: /v1/insegn/ → 401`, `/v1/base/counters → 401`.
**Response shapes beyond these field names are INFERRED.**

### 4d. Libretto / piano studente — `https://api.polimi.it/piano_studente`

VERIFIED from BUNDLE, all with `poliAuthProfile: 0` (`libretto.profile`).
`PROBE: /singoloinsegnamento/1 → 401`.

| Method | Path |
| --- | --- |
| GET | `/singoloinsegnamento/{id}` |
| GET | `/testatapiano/{matricola}` |
| GET | `/elencoinsegnamenti/{matricola}` |
| GET | `/sequenzamedia/{matricola}`, `/sequenzamedia2/{matricola}` |
| GET | `/mediaobiettivo/{matricola}` |
| PUT | `/mediaobiettivo/insertmediaobiettivo` body `{matricola, media}` |
| GET | `/simulazionemedia/mediasimulata/{matricola}` |
| GET | `/simulazionemedia/insegnsenzavoto/{matricola}` |
| GET | `/simulazionemedia/votoobiettivo/{matricola}` |
| PUT | `/simulazionemedia/checkvotoobiettivo/` body `{matricola}` |
| PUT | `/simulazionemedia/insertvotoobiettivo` body `{matricola, c_insegn, voto}` |
| DELETE | `/simulazionemedia/deletevotoobiettivo` body `{matricola, c_insegn}` |

`/sequenzamedia` + `/elencoinsegnamenti` + `/testatapiano` together are the
real gradebook — a better successor to the dead `/rest/me/polimi/{m}` than
`iae/v1/base/counters`.

### 4e. Rooms — `https://api.polimi.it/ws_aule`

**Not resolvable from this bundle.** The base URL and `ws_aule.profile: "3"`
are in `props`, but no `ws_aule` path literal appears in `app.js` — the room
catalogue is behind the `cataloghi_aule` scope and lives in a separate web app
reached by `linksalto`. PROBE: `https://api.polimi.it/ws_aule/` and
`/ws_aule/v1/aule` both **404** — so the paths are not under a `v1` prefix, or
not at the root. Unresolved; the maps surface below is the usable substitute.

### 4f. Maps — `https://onlineservices.polimi.it/maps_rest/rest`

VERIFIED from BUNDLE, `profile 0`:

```
GET  poi/taglist/all
POST poi/tags/struttura        body {csi, box:{sw:{lat,lng}, ne:{lat,lng}}, profile}
POST poi/list                  body <filter>
GET  poi/{id}
GET  poi/geo/{id}
GET  poi/defs/{id}
GET  poi/{a}/{b}
POST poi/instance[?param=…]    body <poi>
PUT  poi/instance/{id}
DELETE poi/instance/{id}
GET  /ricerca/suggerimenti
GET  ricerca/preferito/{id}
POST ricerca/preferito/        body {...poi, id:"0"}
```

Default bounding box in the bundle is all of northern Italy
(`sw 42.8169,6.4838 — ne 47.0680,13.5803`).

---

## 5. WeBeep

[webeep.md](webeep.md) is accurate and complete for the handshake; nothing in
this research contradicts it. Two additions:

- `webeep` is a first-class OAuth scope in `/jaf/oauth/params`, and the
  official app reaches WeBeep only via `linksalto` (a browser jump), never with
  the JAF bearer token. So there is no PoliMi-token route into Moodle — the
  Moodle `wstoken` really is the only option, as webeep.md concludes.
- `app.js` contains no WeBeep/Moodle code at all (no `webservice/rest`,
  no `wsfunction`), so the bundle adds nothing to the function list already
  taken from myPoliFile.

`itssosh/webeep-cli` and `jonardan/webeep-downloader` were not inspected in
this pass; the existing list from `toto04/webeep-sync` and
`matteovisotto/myPoliFile` already covers the functions PoliVerse uses.

---

## 6. Verified / inferred summary

**VERIFIED (probe or bundle source):** the codice 15 vs codice 33 distinction;
`al_id_srv` being ignored by the IdP; scope-name validation at the IdP; the
full authorize parameter list and order; the single-token model with no
exchange or audience; the `li`/`Qr` client configuration and the exact three
headers; the `profile === 0 ? … : matricola` rule; every path listed in §4a–4f
that is marked 401 by probe or appears as a literal in the bundle; the props
and oauth/params bodies.

**INFERRED:** which of the three staleness mechanisms is producing the codice
33 in PoliVerse specifically (needs the actual authorize URL logged); all
response body shapes except where field names are quoted from bundle usage; the
host attribution of `/v1/devices/*`, `/v1/sync/*`, `/v1/persona/tags*`; the
entire `ws_aule` path surface.
