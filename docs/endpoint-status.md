# Politecnico endpoints — how the official app does it

Verified 2026-09-11. Signal: **401 = path exists, 404 = gone.**

## The finding

**The official app does not hardcode service hosts.** On boot it fetches an
unauthenticated config and reads every backend's base URL out of it:

```
GET https://polimiapp.polimi.it/polimi_app/rest/jaf/public/props   → 200, no auth

{
  "iae.base_url":             "https://api.polimi.it/iae",
  "libretto.base_url":        "https://api.polimi.it/piano_studente",
  "ws_aule.base_url":         "https://api.polimi.it/ws_aule",
  "incattdid.base_url":       "https://api.polimi.it/incattdid",
  "richiesta_ausili.base_url":"https://api.polimi.it/multichance_new",
  "maps.base_url":            "https://onlineservices.polimi.it/maps_rest/rest"
}
```

That indirection is the whole story. The exams backend moved from
`www22.dmz.polimi.it/iae` to `api.polimi.it/iae`; the official app followed
automatically, and PoliFemo — which baked the old host into a constant in 2023
and has not touched `src/api` since 2024-08-09 — simply broke.

PoliVerse now reads the same config (`Services/ServiceDirectory.swift`) with the
current hosts as compiled-in fallbacks.

## How this was found

The official web app is a public SPA. Its bundle
(`/polimi_app/app/assets/index-*.js`, ~8 MB) contains the route table, the env
block and every path literal:

```js
REACT_APP_REST_PATH:        "/polimi_app/rest"
REACT_APP_AGENDA_REST_PATH: "https://api.{env.}polimi.it/agenda"   // {env.} empty in prod
```

No proxy or TLS interception needed — it is served to anyone who asks.

## Current map

### App / JAF — `https://polimiapp.polimi.it/polimi_app/rest`

| Path | |
| --- | --- |
| `/jaf/public/props` | **200, public** — the service map above |
| `/jaf/public/app` | 200, public — version info |
| `/jaf/public/i18n` | public strings |
| `/jaf/public/linksalto` | POST — SSO jump into another service |
| `/jaf/public/linklogout` | logout URL |
| `/jaf/internal/user` | **401** — identity |
| `/jaf/oauth/token/get`, `/jaf/oauth/token/refresh` | **401** — tokens |
| `/jaf/internal/profiles`, `/jaf/internal/updateReturnUrl` | 401 |
| `/v1/notifications`, `/v1/notifications/{id_notice}` | **401** — the bell. Body shape unconfirmed; see below |
| `/v1/io-e-polimi/{matricola}` | **401** — media, CFU. In use |
| `/v1/settings`, `/v1/careers/list` | 401, not used |

### IAE — `https://api.polimi.it/iae`

| Path | |
| --- | --- |
| `/v1/insegn/` | **401** — teachings + `appelliEsame` |
| `/v1/base/infoStud` | **401** |
| `/v1/base/counters` | **401** — career totals |
| `/v1/base/datas` | **401** |
| `/v1/check/generiche` | **401** |
| `/v1/iscriz/`, `/v1/prove/…` | exam enrolment and marks (in the bundle) |

### Agenda — `https://api.polimi.it/agenda`

```
GET /v1/matricola/{matricola}/events?start_date=yyyy-MM-dd&n_events=N   → 401
GET /v1/matricola/{matricola}/events/deadlines
```

Without parameters it answers **400** and names them itself:

```json
{"violations":[{"field":"start_date","message":"la data di inizio non e' valida"},
               {"field":"n_events","message":"Il numero degli eventi non pue' essere nullo"}]}
```

Those are the same parameter names PoliFemo used, so the query contract — and
very likely the response shape — survived the move. Only the host and path
changed.

### Libretto — `https://api.polimi.it/piano_studente`

| Path | |
| --- | --- |
| `/singoloinsegnamento/{id}` | **401** |
| `/simulazionemedia/…`, `/mediaobiettivo/…`, `/sequenzamedia/…` | grade simulation (in the bundle) |

## News

`GET {agenda}/v1/persona/news?start_date=…&end_date=…` — path and query
parameters VERIFIED from the bundle, response body not. `persona`, not
`matricola/{m}`: the token alone identifies the reader, so no matricola is
sent.

It sits beside `/v1/matricola/{m}/events` on the same service, whose shape
*is* known, so the agenda's names (`title: {it,en}`, `date_start`, `date_end`,
`type.type_dn`, `tags[].denomination`) lead the candidate lists in `NewsItem`
— as the likeliest answer, not an assumed one. Shape is logged the same way:
`news payload shape: …`, keys and types only.

An item is retired only by an *explicit* `date_end` in the past. Treating a
missing one as expired would empty the screen the moment a field-name guess is
wrong, which is the failure this design exists to avoid.

## Notifications: live, but shape unknown

`/v1/notifications` is in the official bundle's own typed client and answers
401 unauthenticated, so it exists. Its **response body has never been
captured** — the only field name known for certain is `id_notice`, from the
detail path `/v1/notifications/{id_notice}`.

`Notice` therefore reads fields by trying a list of candidate names
(`id_notice`/`id`, `titolo`/`title`/`oggetto`, `testo`/`body`/`messaggio`, …)
matched ignoring case and underscores, and accepts either a bare array or an
array behind any wrapper key. A wrong guess costs one field, not the screen.

`NoticeService` logs the payload's **shape** — keys and types, never values —
as `notifications payload shape: …`. One run on a real account replaces every
guess above with fact. Values are deliberately excluded: a notification is the
student's own mail, and the log gets pasted into bug reports.

Once a real shape is known, narrow the candidate lists to the true names and
delete the rest.

## What moved

| Was (PoliFemo, still shipping) | Now |
| --- | --- |
| `www22.dmz.polimi.it/iae/rest/v1/insegn` | `api.polimi.it/iae/v1/insegn/` |
| `polimiapp…/polimi_app/agenda/api/me/{m}/events` | `api.polimi.it/agenda/v1/matricola/{m}/events` |
| `polimiapp…/polimi_app/rest/me/polimi/{m}` | gone — `iae/v1/base/counters` is the likely successor |

`www22.dmz.polimi.it` still resolves but refuses public connections; off-campus
it fails as DNS `-1003`. `dmz` in the hostname was the clue.

## OAuth scopes are served too, and they drift

```
GET https://polimiapp.polimi.it/polimi_app/rest/jaf/oauth/params   → 200, no auth

{"oauthServer":"https://oauthidp.polimi.it/oauthidp/oauth2",
 "responseType":"code","clientId":"1057407812","accessType":"offline",
 "scope":"aule policard portale_so incarichi orario account webmail compila_quest
  openid rubrica richass guasti prenotazione code carriera alumni webeep
  richieste_occupazione maps polimi_app teamwork faqappmobile rich_sing_occup
  react_iae multichance_richieste_ausili pianostudente incattdid
  presentazionepianireact cataloghi_aule agenda so2 prenotazioni presence_hub"}
```

Compared with the list PoliFemo hardcoded in 2023:

- **added**: `agenda`, `so2`, `prenotazioni`, `presence_hub`, `cataloghi_aule`,
  `portale_so`, `richieste_occupazione`, `incattdid`, `presentazionepianireact`
- **removed**: `esami`, `incarichidocente`

This is a nastier failure than a moved host. A token minted without `agenda`
logs in fine, works for everything it does cover, and returns **401** from the
agenda service — which looks exactly like a broken endpoint. It was the cause of
`Agenda load failed: Il server ha risposto 401` after the paths were corrected.

Two consequences:

- The app fetches `/jaf/oauth/params` and builds the authorization URL from it,
  so a scope added upstream costs a fetch rather than a broken feature.
- **A token's scopes are fixed at creation and refreshing never widens them.**
  The granted scope is stored with the token; when it no longer matches, the
  app signs out so the next login mints a token that covers the new service.

## Required headers

Every authenticated call needs all three, not just the first:

```
Authorization:     Bearer <token>
poliAuthProfile:   <service profile from props, else the user's profile>
poliAuthD_profile: <account's dprofile, else JAF_D_PROFILE_VUOTO>
```

Omitting `poliAuthD_profile`, or sending the user's profile where the service
declares its own, yields 401 "Scope OAuth non valido … Code: 33" — an error
that blames the token and is nothing to do with it. See
[polimi-auth.md](polimi-auth.md#the-code-33-scope-error--resolved).

## Rooms — catalogue yes, occupancy no

The maps service is **public and needs no token**:

```
GET https://onlineservices.polimi.it/maps_rest/rest/spazi/aula       → 200, 353 rooms
GET .../spazi/edificio                                               → 200, 152 buildings
GET .../spazi/campus, /spazi/sede, /spazi/piano                      → 200
```

Rooms carry `sigla`, `capienza`, `posti_disabili` and the `csi*` codes that
join them to a building, floor and campus. Every number is a string.

**Live occupancy is not reachable.** Checked 2026-09-11:

| Source | Result |
| --- | --- |
| `www7.ceda.polimi.it`, `www11.ceda.polimi.it`, `aule.polimi.it` | resolve, refuse connections — campus-internal, like `www22.dmz` |
| PoliNetwork `/v1/rooms/search` (what PoliFemo uses) | 302 to Cloudflare Access sign-in |
| `maps_rest` `/spazi/impegni`, `/spazi/prenotazioni`, `/spazi/occupazione` | 500 |
| the agenda | only *this* student's lectures, not what rooms are doing |

So the app ships the catalogue and says plainly that it cannot tell which rooms
are free. The internal hosts may well answer on campus Wi-Fi — that is the
thread to pull if this is wanted.

## Unverified

`/v1/base/counters` is live and sits with the other career calls in the bundle,
but its **response shape has not been seen**. If it does not match
`GradeBookDTO`, `PoliMiAPI` logs the first 400 bytes of the body on a decode
failure — read that and the real shape is obvious.

Everything else is verified only as far as "the path exists and demands a
token". The response shapes for `/v1/insegn/` and the agenda are assumed
unchanged from PoliFemo's, which is plausible given the agenda kept its
parameter names, but the first authenticated run is what will confirm it.

## How the other apps handle this

| App | Approach |
| --- | --- |
| Official web app | fetches `props`; survives migrations |
| `PoliNetworkOrg/PoliFemo` | hardcoded 2023 hosts; `src/api` untouched since 2024-08-09; these features are presumably broken |
| `matteovisotto/myPoliFile` | WeBeep only — avoids the problem entirely by talking to Moodle |
| `toto04/webeep-sync` | WeBeep only, same |

Only the official app solves it, and it solves it by not hardcoding. That is
the pattern worth copying, and the reason `ServiceDirectory` exists.
