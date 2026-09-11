# Politecnico endpoint status

Probed 2026-09-11 from the public internet. The signal is **401 vs 404**: an
unauthenticated request to a path that exists returns 401, a path that is gone
returns 404.

## polimiapp.polimi.it/polimi_app

| Path | Status | |
| --- | --- | --- |
| `/rest/jaf/internal/user` | **401** | works — this is why login succeeds |
| `/rest/jaf/oauth/token/get/{code}` | **401** (JSON) | works — token exchange |
| `/rest/jaf/oauth/token/refresh/{token}` | assumed live | same family |
| `/rest/jaf/public/linksalto` | **405** on GET | exists, wants POST |
| `/agenda/api/me/{matricola}/events` | **404** | **gone** |
| `/agenda/api/me/{matricola}/lectures/{id}` | **404** | **gone** |
| `/rest/me/polimi/{matricola}` | **404** | **gone** |

The host is alive (18.102.217.97) and the `jaf` API family survives. The agenda
and gradebook APIs do not.

A scan of plausible replacements under the surviving namespace —
`/rest/jaf/internal/{agenda,orario,carriera,esami,libretto,pianostudente}`,
`/rest/jaf/{agenda,orario,carriera}/me`, `/rest/v1/*`, `/rest/me*` — returned
404 for every one.

## www22.dmz.polimi.it/iae

Resolves (131.175.187.18) but **refuses connections from the public internet**
(`curl` reports HTTP 000). On a real device off-campus it fails earlier still,
as a DNS error:

```
NSURLErrorDomain -1003 "A server with the specified hostname could not be found"
NSErrorFailingURLStringKey=https://www22.dmz.polimi.it/iae/rest/v1/insegn?lang=IT
```

`dmz` in the hostname is the clue: an internal host. It may be reachable on
campus Wi-Fi or through the ateneo VPN — worth testing, but it cannot be relied
on for an app used off-campus.

This is the course list (`/rest/v1/insegn`) and exam booking, so **courses,
exam sittings and everything derived from them are unavailable** off-campus.

## Where that leaves the app

| Feature | Source | State |
| --- | --- | --- |
| Login, user identity | `polimiapp` `jaf` | works |
| WeBeep materials | `webeep.polimi.it` Moodle | works |
| Courses | `www22` `/rest/v1/insegn` | unreachable off-campus |
| Timetable | `polimiapp` `/agenda/...` | endpoint withdrawn |
| Career, grades | `polimiapp` `/rest/me/polimi/...` | endpoint withdrawn |
| Exam sittings | `www22` `/rest/v1/insegn` | unreachable off-campus |

## PoliFemo is in the same position

`PoliNetworkOrg/PoliFemo` still ships these exact paths — `git log` shows
`src/api` untouched since 2024-08-09. It is not a newer source to copy from;
it has the same dead endpoints and presumably the same broken features.

## Finding the current endpoints

They cannot be discovered from outside: there is no published API, and probing
only distinguishes "exists" from "gone". The realistic route is to watch what
the official Polimi app actually calls:

1. A proxy with TLS interception (mitmproxy, Charles, Proxyman) with its CA
   trusted on the device.
2. Open the official app, use the timetable and libretto.
3. Read the hosts and paths off the flow list.

Certificate pinning may prevent this. If it does, the alternative is the
`linksalto` endpoint — POST `target_service_id` and it returns a `jump_url`
into the relevant service as an authenticated web page. That gives a web view,
not JSON, so it would mean embedding those pages rather than building native
screens for them.

## What the app does about it now

- **No mock fallback on a failed real request.** Previously a failure quietly
  substituted sample data, so a user who had turned sample data off saw
  invented courses and an invented weighted average presented as their own.
  Now a failure shows an error and an empty state.
- **Permanent failures are not retried.** DNS `-1003` was being retried with
  backoff, three to six times per request, across two services calling the same
  endpoint — burning battery and delaying the error. Only genuinely transient
  codes retry now.
- **404 reads as "service withdrawn"**, not "server error".
