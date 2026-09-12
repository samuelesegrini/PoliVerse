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

Shape **VERIFIED** 2026-09-11, 40 items on a real account:

```json
{"news_id": 4412, "news_source_id": 3,
 "title": {"it","en"}, "text": {"it","en"},
 "publication_start": "…", "publication_end": "…",
 "event_start": "…", "event_end": "…",
 "show_agenda": true, "tags": [{…}]}
```

The body is `text`, not `description`. **There are two date pairs**, and the
first cut of this app read neither: it guessed `date_start` from the agenda's
events, so all forty items came back undated and unsorted. `publication_*` is
when the item is on the board; `event_*` is when the announced thing happens.
Expiry uses `publication_end`; the date shown is `event_start` where there is
one, because "when is the seminar" is the question a reader has.

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
as `notifications payload shape: …`.

A real account returned `array[0]` on 2026-09-11: the endpoint works and the
inbox was simply empty, so the field names above remain unconfirmed. The empty
case is at least verified to render as an empty inbox rather than as an
error. Values are deliberately excluded: a notification is the
student's own mail, and the log gets pasted into bug reports.

Once a real shape is known, narrow the candidate lists to the true names and
delete the rest.

## One person, several matricole — and the token binds to one

A `codicePersona` is stable; a **matricola is per enrolment**. Finishing a
triennale and starting a magistrale gives one person two matricole, and nearly
every endpoint here is parameterised by matricola.

The OAuth token is bound to one of them. Point the app at the closed career
and its services refuse the token outright — which is the real explanation for
the Code 6 section below, and for an agenda that returns `0 events` while
WeBeep and news work perfectly.

```
GET  /v1/careers/list            → [{matricola, desc_tipo_carriera:{it,en},
                                      desc_stato_carriera:{it,en}}]
PUT  /v1/careers/favorite/{matricola}   (405 on GET — it is a write)
```

Field names VERIFIED from the bundle, which renders each row as
`L.matricola`, `L.desc_tipo_carriera?.[lang]`, `L.desc_stato_carriera?.[lang]`.

**Switching is an OAuth flow, not a parameter.** From the bundle's
`[Cambio Matricola]` path:

```js
const m = `${t.oauthServer}/${n ? "careerChange" : "auth"}`
new URLSearchParams({client_id, redirect_uri, access_type, response_type,
                     state, matricola: n, al_pj_matricola: n,
                     access_token: a, scope: n ? "" : t.scope, ...})
```

So: same authorize machinery, different endpoint, the chosen matricola under
**both** names, the current token as proof of identity, and an **empty scope**
— it moves an existing grant rather than requesting a new one.

**`/careerChange` errors.** Reproduced 2026-09-12 in PoliVerse *and in the
official app* for this account, so it is the Politecnico's own path that is
broken, not our reproduction of it. The code is kept — the flow is right and
the endpoint may recover — but it is not what the app offers.

**What works instead:** set the favourite while the current token still
functions, then sign out and back in.

```
PUT /v1/careers/favorite/{matricola}     ← with the working token
   → sign out (ending the SSO session)
   → log in again; the new token binds to the favourite
```

The authorize request additionally carries `matricola` / `al_pj_matricola` as
a hint, with the **full scope** and no access token — a hinted login is still
a login, and asking for an empty scope there would mint a token with no
authority. The favourite is the lever; the hint is a courtesy.

## "Utente non abilitato Code: 6" is not only ws_aule

Observed 2026-09-12 on `iae`, after a fresh login:

```
401 host=iae path=/v1/base/counters authHeader=true
{"statusCode":401,"message":"...JafUnauthorizedException: Utente non abilitato Code: 6"}
```

`/v1/insegn` answers the same. The day before, both worked and `insegn`
returned 0 sittings. Nothing in the app's request construction changed in
between, and **re-authenticating does not clear it** — the run above had just
re-minted the token.

So Code 6 is the backend saying *this account is not enabled for this service
right now*, not *this request is malformed* and not *this token is stale*. For
`iae` (iscrizione appelli esami) the likeliest cause is the calendar: between
sessions, or before enrolment is renewed for the new academic year, the
service is closed to the student.

Consequences encoded in the app:

- never re-authenticate on Code 6 — it is a loop;
- never retry it — the answer will not change within a session;
- say what the server said, rather than "Il server ha risposto 401".

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

## Rooms — catalogue and occupancy

The maps service is **public and needs no token**:

```
GET https://onlineservices.polimi.it/maps_rest/rest/spazi/aula       → 200, 353 rooms
GET .../spazi/edificio                                               → 200, 152 buildings
GET .../spazi/campus, /spazi/sede, /spazi/piano                      → 200
```

Rooms carry `sigla`, `capienza`, `posti_disabili` and the `csi*` codes that
join them to a building, floor and campus. Every number is a string.

### Occupancy — `maps_rest`, public, VERIFIED working

**`GET /ricerca/aula/occupazione/{idaula}/{yyyy-MM-dd}`** → `200`, no token:

```json
[{"inizio":"08:15","fine":"10:15"},{"inizio":"10:15","fine":"12:15"}]
```

Busy bands, times only — the date is the one requested — as wall clock in
Rome. Date-sensitive and real: 2026-12-25 and 2027-08-15 return `[]`, a
teaching day returns the grid above.

`{idaula}` is the catalogue's **`idaula`**, not `sigla` and not `csiv`: the
code answers 500, the `csiv` 404. All 353 rooms carry one.

Some rooms answer `MSG_OCCUPAZIONI_NASCOSTE` — the university hides those
deliberately. They are reported as unknown, never as free.

Two more, also public, also keyed on `idaula`, sharing one shape:

```
GET /ricerca/aula/dotazioni/{idaula} → [{"id":4,"it":"Video proiettore","en":"Video projector"}]
GET /ricerca/aula/software/{idaula}  → [{"id":348,"it":"Overleaf","en":"Overleaf"}]
```

`[]` for most rooms; software only for the computer labs (rooms 67 and 1541
among them). The `id` is an internal catalogue with no published key, so the
UI matches icons on the wording instead.

### Coordinates — real, unlike the outlines

`GET /spazi/edificio/geojson?filter=` carries a bbox per building in
`properties` (`SWLAT`/`SWLNG`/`NELAT`/`NELNG`) keyed by `POLIMI_ID_SPAZIO`,
which is the catalogue's `csie`.

**The polygons are not footprints.** Of 465 building features, 142 "detailed"
rings are generated ellipses (checked: min/max radius from the centroid > 0.45
for all 142) and the other 155 are axis-aligned boxes. Only the bbox centres
are true, so the app pins those onto MapKit and draws no geometry of its own.

`/spazi/campus/geojson`, `/spazi/sede/geojson` and `/spazi/edificio/geojson`
all need `filter` present and **empty**; any value, or omitting it, returns
500. `/spazi/geojson` works without it.

**How it was found, after two dead ends:** `maps_rest` publishes a WADL at
`/rest/application.wadl` — 151 endpoints, machine-readable, unauthenticated.
The 500s recorded earlier against `/spazi/impegni` and friends were just
"unknown path" in disguise. Ask a service to describe itself before guessing
at it; `POST /ricerca` and `/ricerca/v2` remain undocumented and were not
needed.

### Occupancy — `ws_aule`, staff only

An earlier revision of this file concluded occupancy was unreachable. **That
was wrong.** The findings behind it still hold — the CEDA hosts refuse
connections off campus, PoliNetwork sits behind Cloudflare Access, and
`maps_rest` 500s on `/spazi/impegni` — but they did not support the
conclusion, because `props` has always listed a service that was never probed:

```
ws_aule.base_url = https://api.polimi.it/ws_aule
ws_aule.profile  = 3
```

The official bundle's `registroLezioni` chunk calls exactly two paths on it:

```js
getSedi: url: "/cata/sedi"
getAule: url: `/cata/aule?inizio=${fmt(a)}&fine=${fmt(b)}&sede=${sede}`
```

Both answer **401** unauthenticated — byte-identical to `/iae/v1/insegn`,
which this app already calls successfully — so they exist and take our token.
Checked 2026-09-11.

`inizio` / `fine` are `yyyy-MM-dd`: the bundle's formatter (`cAt`) emits no
time component. The scope list already grants `aule` and `cataloghi_aule`.

**`ws_aule.profile` is 3, not 0** — the first service where that matters. The
official client appends `matricola` as a query parameter whenever a service's
profile is non-zero, a rule `APIRequest.sendsMatricola` had encoded but never
applied, because `iae` and `libretto` both report 0.

**A student account is refused.** `/cata/sedi` with the service profile
answers 401:

```json
{"statusCode":401,
 "message":"jaf.model2.exceptions.JafUnauthorizedException: Utente non abilitato Code: 6"}
```

The token is fine — every other service accepts it in the same session.

Retrying with the account's own profile (1) was tried and is also refused,
with a *different* error:

```
Code 33 — "Scope OAuth non valido. Effettuare logout/login…"
```

So: **profile 3 → "you do not hold this profile" (Code 6); profile 1 → "this
profile may not use this service" (Code 33).** Both closed, by two different
mechanisms. The OAuth scope is not the problem — `/jaf/oauth/params` grants
`aule`, `cataloghi_aule`, `prenotazione`, `prenotazioni`, `richieste_occupazione`
and `rich_sing_occup` to this client, so the grant exists and the *account* is
what the service is checking.

Conclusion: `/cata/*` is staff-only. It backs `registroLezioni`, a lecture
register, and `/cata/aule` is how a teacher finds a room to book. There is no
student-facing equivalent in `props`. The code is correct and would work for
an account that holds profile 3; it is kept, and the screen says plainly that
the profile lacks access.

Note the classification trap: this arrives as `JafUnauthorizedException`, the
same exception as a genuinely bad token, so the scope check claimed the
session had expired and offered a login that would change nothing. "Utente non
abilitato" / "Code: 6" is now matched first.

Response shape is still **not** verified — no account here can reach it. It is
read leniently and logged as `aule payload shape:` / `sedi payload shape:`.

Free time is **derived**, not requested: the service says what is booked, and
the gaps between bookings are the answer.

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
