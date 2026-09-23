# Lecture recordings (recman + Webex)

**Feasible, with a native player and optional download.** The Politecnico's
recording archive (recman) lists every recorded lecture with its teaching code,
and each row leads to a Webex recording that serves plain HLS. `AVPlayer` plays
it as is: Picture in Picture, playback speed, lock-screen controls and a resume
position come for free, and watch progress becomes real data instead of a
checkbox.

The cost is a second kind of session. The app deliberately ends the Shibboleth web
session after sign-in (`LoginWebKit.endSession()`), and this feature needs one
that lives on. See [The session decision](#the-session-decision).

Probed on 2026-09-23 from two browser captures of one student account (CIE
sign-in), two recordings of the same course. Tags follow
[next-features-research.md](next-features-research.md): **[V]** seen in the
captures, **[?]** not verified, **[J]** judgement.

## The chain

```
1. servizionline.polimi.it portal → Servizi.do?evn_srv&idServizio
       ↓ aunicalogin.polimi.it (reuses the SSO cookie, evn_checkCookieSSO)
2. onlineservices.polimi.it/recman_frontend/?ticket=…
       ↓ 302
3. …/recman_frontend/controller/ArchivioListActivity.do?jaf_currentWFID=…&__pj0&__pj1
       ← HTML table, one row per recording, each with a transfer_id
4. GET ArchivioListActivity.do?evn_preview_link=evento&transfer_id=<n>&jaf_currentWFID=…
       → 302 politecnicomilano.webex.com/politecnicomilano/ldr.php?RCID=…
       → 302 …/recordingservice/sites/politecnicomilano/recording/playback/<recordingId>
5. Playback page HTML  ← carries "ticket" (ticketTTL 5400 s) and "userId"
       (first visit without a Webex session: /stream answers 403, the page goes
        through idbroker-eu.webex.com → SAML → shibidp.polimi.it → aunicalogin,
        which reuses the SSO cookie, and comes back)
6. GET politecnicomilano.webex.com/webappng/api/v1/recordings/<recordingId>/stream?siteurl=politecnicomilano
       headers: ticket, wbxUserId, siteId, siteFullUrl, clientType
       ← JSON with hlsURL, mp4URL, audioURL, duration, fileSize and the download flags
7. hlsURL → nfg1wss.webex.com/nbr/MultiThreadDownloadServlet/<base64 params>/hls.m3u8
       → AVPlayer
```

- **[V]** Recman's `evn_preview_link` answers with a redirect straight to Webex; there
  is no intermediate page.
- **[V]** The HLS playlist is `application/vnd.apple.mpegurl`, `#EXT-X-VERSION:6`,
  fragmented MP4 with `#EXT-X-MAP` and `#EXT-X-BYTERANGE` into one
  `merge_0_<ms>.mp4`. Segments answer 206 with `Accept-Ranges: bytes` and
  `Access-Control-Allow-Origin: *`. `AVPlayer` supports this format.
- **[V]** The playlist's path segment is base64 of `siteid, recordid, confid, from,
  trackingID, language, userid, serviceRecordID, ticket, timestamp, islogin,
  isprevent, ispwd, play, siteurl, recordingViewerInfoToken`. The ticket travels in
  the URL, so the media requests carry no auth header.
- **[?]** Whether the media host also needs cookies. The captures were exported
  "sanitized" by Chrome, which strips `Cookie` and `Set-Cookie`, so their absence
  proves nothing. The same applies to the `/stream` call. Test from `URLSession`
  with an empty cookie store before relying on it.
- **[?]** Whether the transfer_id → recordingId pair is stable. It should be, since
  both are archive ids, but only one resolution per recording was seen.

### Recman

A Struts/JAF application like [manifesti.md](manifesti.md), but authenticated and
session-stateful: every URL carries `jaf_currentWFID`, `__pj0` and `__pj1`, minted
per session. None of them can be built offline, so recman has to be *walked* from
the portal each session, never deep-linked.

**[V]** Table columns: Riproduci, Anno Accademico, Data Registrazione, Corso,
Forma didattica, Argomento, Ospiti, Durata, Dimensione. A row reads:

| Field | Example | Notes |
| --- | --- | --- |
| Anno Accademico | `2026 / 27` | |
| Data Registrazione | `21/09/2026 13:34` | when the recording started, not the timetable slot |
| Corso | `090950 - DISTRIBUTED SYSTEMS (<docente>)` | **teaching code first**, then title and lecturer |
| Forma didattica | `Lezione` | also `Laboratorio`, `Esercitazione`, `Altro` |
| Argomento | free text from the lecturer | |
| Durata / Dimensione | `135 min` / `198 MB` | Webex reports 8 122 s / 207 944 795 bytes for the same lecture (MiB vs MB) |
| `transfer_id` | in the Riproduci link | the stable key |

**[V]** Filters in the form: `aa`, `fromDateReg`/`toDateReg`, `tipologia`,
`argomento`, `contesto`. **[?]** Pagination: the captured account had only a
handful of rows; no paging control was visible.

### Webex `/stream`

**[V]** Fields that matter (others omitted):

| Field | Seen | Use |
| --- | --- | --- |
| `downloadRecordingInfo.downloadInfo.hlsURL` | present | playback |
| `downloadRecordingInfo.downloadInfo.mp4URL` | present | download |
| `downloadRecordingInfo.downloadInfo.audioURL` | present | audio-only, not planned |
| `duration` (ms), `fileSize` (bytes) | 5 690 000 / 147 MB; 8 122 000 / 208 MB | ≈ 90 MB per hour |
| `preventDownload`, `enforcePreventDownload` | `false`, `false` | **gate for download** |
| `passwordProtected`, `enforcePasswordProtected` | `false` | |
| `needShowDisclaimer` | `true` | the app must show it too |
| `canPlayback`, `requireLogin` | `true`, `true` | |

`orgRecordingSettings` answered `allowDownload: true, allowPlayback: true` for the
site.

The page also fetches `chat.json` and the meeting's participant list. **[J]** The
app must not: both are other people's personal data
([academic-intelligence-layer.md](academic-intelligence-layer.md) §18), and
neither is needed to watch a lecture.

## Linking to the rest of the app

**[V]** The teaching code is in the Corso column, so a recording joins a course
exactly on `teachingCode` (`Course.swift:207`) plus the academic year. There is no
third naming variant to reconcile.

**[J]** Joining a recording to a *timetable slot* is by date and time, with
tolerance: the Data Registrazione column is when recording started (`13:34`,
`08:27`, `16:28`), which need not equal the slot's start. Match on the same day and course, nearest slot start within the
recording's span; anything ambiguous stays unlinked to a slot but still linked
to the course.

## Data model

```swift
/// One row of the recman archive.
struct Recording: Codable, Identifiable {
    let transferID: Int            // recman, stable
    let academicYear: String       // "2026 / 27"
    let recordedAt: Date
    let teachingCode: String       // "090950"
    let courseTitle: String
    let form: Form                 // lezione, laboratorio, esercitazione, altro
    let topic: String?
    let duration: Duration
    let size: Measurement<UnitInformationStorage>
    var webexRecordingID: String?  // learnt on first play, cached
}

/// What the student has done with it — user-owned, not a cache.
struct RecordingProgress: Codable {
    let transferID: Int
    var position: Duration
    var completed: Bool            // e.g. position ≥ 90 % of duration
    var lastWatched: Date
}
```

- The list is a cache and belongs in `OfflineStore`, per account, wiped on sign-out
  like every other record.
- **[J]** Progress is not a cache: it cannot be refetched. It belongs in the
  user-data store the notes/study-session work needs anyway, keyed per person
  rather than per matricola. Until that store exists, `OfflineStore` is acceptable
  for an MVP, knowing sign-out loses it.
- Stream info (`hlsURL`, `mp4URL`, ticket) is never persisted: it expires in 90
  minutes and contains a credential.

## The session decision

Today `LoginWebKit.endSession()` removes cookies and web storage when sign-in
finishes, "so a Shibboleth session still cannot outlive the flow"
(`LoginWebKit.swift:14-16`). Recman and Webex both need that SSO session.

Options:

0. **Jump from the app's token.** The official app opens its web services with
   `POST /jaf/public/linksalto` (`docs/polimi-api-research.md` §4a), which answers
   with a signed-in `jump_url`. No second sign-in and no SSO cookie kept from the
   app's login. **[?]** The endpoint checks which services the caller may reach
   (2428 was refused), so it may refuse recman too.
1. **Re-run the web sign-in on each visit to recordings.** No lasting session, but
   the student may face the Politecnico's login page (and CIE/OTP) each time. Poor
   for a feature used several times a week.
2. **A dedicated, persistent `WKWebsiteDataStore` for recordings.** It holds the
   aunicalogin SSO cookie and the Webex session, is used only by the recordings
   flow, and is removed on sign-out alongside `OfflineStore.clear(account:)`. The
   main sign-in store stays as it is.

**[J]** Option 0 first, option 2 as the fallback when the jump is refused. Option 2 keeps the existing guarantee for the main flow, and the
recordings store holds only what a browser tab would. The decision must be written
down (here, and in the `LoginWebKit` doc comment) so the next reader doesn't take
the persistent store for a leak.

**[?]** How long the SSO cookie lives. If it lasts only hours, option 2 degrades
towards option 1 and the feature needs a smooth "sign in again" sheet.

## Download

**[J]** Allowed only when `preventDownload == false && enforcePreventDownload ==
false`, started by the student, one lecture at a time. This matches the Download
button the lecturer enabled on Webex; it is not a bulk mirror.

- Background `URLSession` download of `mp4URL`, stored like WeBeep files
  (`FileDownloadModel`): Application Support, `isExcludedFromBackup`.
- The ticket in the URL expires after 90 minutes. A download that fails after that
  needs a fresh `/stream` call and a new URL; resume data may not survive the change
  **[?]**.
- No share sheet, no export to Files: the recording contains other students'
  voices.
- Show size before downloading (≈ 90 MB/h) and the total in the storage screen,
  with delete.

`FileDownloadModel.download(_:)` today uses a foreground `session.download(from:)`
with no progress delegate. That is fine for PDFs and not for a 200 MB file; the
same fix helps WeBeep videos.

## Risks

- **[J]** Both sources are undocumented. `webappng/api/v1` is the Webex web app's
  own API, not the public Webex REST API; recman is JAF pages. Either can change
  without notice. From day one the feature needs a "recordings unavailable" state
  that still offers *Apri nel browser*.
- **[?]** The public Webex REST API (`webexapis.com/v1/recordings`) would be more
  stable, but it needs a registered integration and returns download links to
  hosts; whether a student can list recordings shared with them was not checked.
- **[?]** Only recordings with download allowed and no password were seen, both
  from one lecturer. The behaviour with `preventDownload: true` or a password is
  unknown.
- **[J]** Streaming with the student's own session is the same act as watching in
  the browser, and fits the perimeter in
  [academic-intelligence-layer.md](academic-intelligence-layer.md) §0. It writes
  nothing to university systems
  ([writes-to-university-systems.md](writes-to-university-systems.md)).

## MVP

| Step | What | Size |
| --- | --- | --- |
| 1 | Recman list in the course hub: walk the portal in a hidden `WKWebView` on the recordings store, parse the table, join on `teachingCode` + year. Tap opens Webex in the browser. | M |
| 2 | Native player: follow the redirect, read ticket and userId from the playback page, call `/stream`, play `hlsURL` in `AVPlayerViewController`. Disclaimer first. PiP needs the audio background mode and a `.playback` audio session. | M |
| 3 | Progress: save position on pause and every few seconds; "da recuperare" count per course; resume where the student stopped. | S |
| 4 | Download, gated on the flags above, with background session and ticket refresh. | S–M |

Step 1 is worth shipping alone. Steps 2–3 are the reason to build it.

## Implementation status

Step 1 is in the code (2026-09-23):

- `Model/Recordings/RecmanParser.swift` reads the list. The live page differs from
  the first capture: every cell writes its column's name above its value
  ("Data", then "21/09/2026 13:34"), the headers are Anno Accademico, Data, Corso,
  Forma didattica, Argomento, Ospiti, Durata, the Durata cell reads
  "135 min / 198 MB", and the play link sits in the last cell. Cells are read by
  their label, by position as a fallback. `RecmanParserTests` covers both shapes.
- `Model/Recordings/RecmanBrowser.swift` walks recman in a hidden `WKWebView` on
  `RecordingsWebKit.dataStore`. The archive opens empty; the browser fills in the
  course, picks the latest academic year and presses search. A search over every
  year returns the oldest first, a hundred at a time.
- `Model/Recordings/RecordingsModel.swift` reads **one course at a time** and keeps
  what it reads as an offline copy per account, with each recording's Webex
  address. **[V]** The archive (2314) is not the student's list: searched for the
  latest year it returned a hundred recordings of the whole Politecnico
  (2026-09-12 … 2026-09-22) and none of the student's course, while that course's
  WeBeep link returned exactly its five. Ways in, in order:
  1. The course's WeBeep "Registrazioni" link (`id_servizio=2294&c_classe_webeep=…`,
     read from `core_course_get_contents`); the list comes back filled.
  2. The archive, with the search narrowed to the course's teaching code in the
     Corso field (`contesto`), for a course without that link — first through
     `RecmanJump` (**[V]** `linksalto` refuses 2294 and 2314 with
     `id_servizio: Unauthorized`; asked once per launch), then through the kept
     session. **[V]** `contesto` matches on the teaching code: searched for
     `089182`, the archive returned that course's five recordings and no other.
  Either needs the recordings' own session; `RecordingsSignInSheet` signs in when
  it is missing. Rows of another course are never filed under this one.
- **[V]** Every cookie the session holds is session-only — `SSO_LOGIN` and
  `S2314_` on aunicalogin included — so WebKit drops them when the app quits.
  `RecordingsWebKit.saveSession()` keeps them in the Keychain (this device only)
  after each read that got through, and `restoreSession()` puts them back once per
  launch; a kept session older than a day is dropped. **[V]** After a relaunch the
  restored cookies reached the archive without a sign-in. **[?]** How long the
  Politecnico honours them.
- `LoginFlow.signOut()` empties the recordings' web store and the kept session.

Step 2 (2026-09-23, not yet tried on a device):

- `Model/Recordings/WebexPlayback.swift` opens the recording's Webex page in a
  hidden `WKWebView` on the same session and captures the page's own `/stream`
  answer with a script watching `fetch` and `XMLHttpRequest`, so the app never
  rebuilds that request or its headers. Content rules keep the page from loading
  the video, images, fonts, the chat and the participant list.
- `Features/Recordings/RecordingPlayer.swift` plays `hlsURL` in
  `AVPlayerViewController`, presented by UIKit so Picture in Picture can take it
  over and hand it back; the `audio` background mode keeps it playing with the
  screen off. Webex's cookies go along with the media requests
  (`AVURLAssetHTTPCookiesKey`) in case the media host wants them.
- **[V]** Webex keeps its sign-in per page, so each look-up passes through its
  identity broker: `sites/politecnicomilano/login` → `idbroker…/IdBMeetingsLogin`
  → `doSSO.jsp`, which asks for the account's email (the broker remembers it only
  in a cookie it did not set here) → `POST /idb/globalLogin` (`email`,
  `emailHash`, `domainHash`, …) → SAML to `shibidp.polimi.it`, which passes on the
  kept session → `loginSuccessPage` → playback page → `/stream`. The Sign In button
  stays disabled until the page's own validation runs, so `WebexPlayback` fills
  `IDToken1`, sets `nameValidated` and calls the page's `processForm()`. The
  email is the institutional one from the profile, or the one the student gives
  once when that is refused.
- When `needShowDisclaimer` is set, a notice about other participants' voices is
  shown before the first recording. When Webex will not say where it streams,
  the recording opens on Webex in the browser, as in step 1.

Step 3 (2026-09-23):

- `RecordingProgress` (in `Recording.swift`) keeps, per recording, where the
  student stopped and the length the player measured. Nine tenths played count
  as watched; a recording can also be marked watched, or unwatched, by hand from
  its row's menu.
- `RecordingPlayer` reports the position every five seconds and once more on
  closing; `RecordingsModel.played(to:of:in:final:)` writes it every fifteen
  seconds, and at once on closing or on becoming watched. The next play starts
  five seconds before the stopping point, unless the recording was barely begun
  or played to the end.
- The course page's "Registrazioni" row shows how many recordings are left to
  watch; the list shows a bar and the minutes left for a recording under way, and
  a check for one watched.
- **[J]** Kept in `OfflineStore` per account, so signing out loses it, as the data
  model section accepts for now.

Step 4 (2026-09-23, not yet tried on a device):

- `RecordingDownloads` downloads a recording's `mp4URL` on a background
  `URLSession` (`segrini.samuele.PoliVerse.recordings`) that carries on off
  screen; `PoliVerseApp` hands iOS's relaunch for finished downloads to it with
  `.backgroundTask(.urlSession(…))`. Webex's cookies go on the request.
- Offered from a row's menu only while Webex has not said no: the look-up that
  starts it reads `preventDownload`/`enforcePreventDownload`, and a refusal hides
  the option for that recording. A page instead of a video (an expired ticket)
  or a file under a megabyte counts as a failure.
- Files go to `Application Support/Recordings/<transfer_id>.mp4`, excluded from
  backup, and are deleted at sign-out. No share sheet, no export.
- A saved recording plays from the file, without Webex, and keeps its resume
  point. The list says "offline" and the header counts them.
- **[J]** Force-quitting the app cancels its background downloads; iOS does that
  on purpose. The cancellation arrives on the next launch, often with resume data,
  which is kept as `<transfer_id>.resume` and resumed at once while the download
  is under 80 minutes old (Webex's ticket lasts 90); after that the row offers
  "Riprendi il download", which starts again from a fresh address.

## Still to verify

1. The SSO cookie's lifetime: open recman a day later without signing in.
2. A recording with `preventDownload: true`, and one with a password.
3. Cookies on `/stream` and on `nfg1wss.webex.com`: repeat with an unsanitized
   capture, or test from `URLSession`.
4. Recman pagination on an account with many recordings, and the `contesto`
   filter's values.
5. Whether a recording deleted by the lecturer disappears from recman or leaves a
   dead row.
