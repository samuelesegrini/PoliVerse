# Data freshness — how the screen stops being stale

The question: **how does server data get fresher without the student pulling
to refresh?** Answered against Apple's own documentation and against what the
Politecnico's servers actually send, measured rather than assumed.

The short version: the backend gives us **nothing** to build on — no ETag, no
`Last-Modified`, no `Cache-Control`, no push. So every option below is
client-side, and the win is not "fetch more often" but **revalidate on the
moments the user is already there** — on foregrounding and on reconnection,
which the app now does through `FreshnessCoordinator`.

---

## Current state

### How a fetch happens

Every service follows one shape. `AgendaService` is the reference:

| Step | Where |
| --- | --- |
| View appears → `.task { await agenda.load(around: .now) }` | `Features/Home/HomeView.swift:123-132` |
| `load` asks `LoadWindow` whether to go to the network at all | `Services/AgendaService.swift:66-69` |
| Disk copy is restored first, so something is on screen | `Services/AgendaService.swift:58-62`, `78` |
| Request goes out through `PoliMiAPI.send` | `Services/PoliMiAPI.swift:202` |
| Result is written back to the shared container | `Services/AgendaService.swift:118` |
| Widgets are told | `Services/AgendaService.swift:122` |
| `age` is published for the freshness bar | `Services/AgendaService.swift:123` |

The same `load(force:)` signature exists on `FreeRoomsService.swift:144`,
`NewsService.swift:46`, `NoticeService.swift:62`, `CareerService.swift:136`.

### There is a cache, and it is ours, not URLSession's

`OfflineStore` (`Shared/OfflineStore.swift:18`) writes JSON per account into
the app group container (`Shared/OfflineStore.swift:34`), and `CachedSlot`
(`Shared/OfflineStore.swift:212`) restores it lazily, keyed by matricola
(`Shared/OfflineStore.swift:231-239`). Age comes back with the value
(`Shared/OfflineStore.swift:218-219`) and drives `FreshnessBar`
(`DesignSystem/FreshnessBar.swift:11-34`), which stays silent under 15 minutes
and speaks up past that (`Shared/OfflineStore.swift:180-188`).

This is already **stale-while-revalidate at the model layer**: cached value
first, network after, `age` says which you are looking at. What is missing is
the *revalidate* trigger — see below.

`DiskCache` (`Services/DiskCache.swift:10`) is the older, global-keyed
predecessor; `OfflineStore`'s doc comment says why it was replaced
(`Shared/OfflineStore.swift:6-17`).

### What suppresses fetches

`LoadWindow` (`Services/LoadWindow.swift:14`): 300 seconds
(`Services/LoadWindow.swift:17`), keyed on the data's source so a career
switch always reloads (`Services/LoadWindow.swift:34-41`). `force: true` from
pull-to-refresh bypasses it. A failed load deliberately does not mark
(`Services/LoadWindow.swift:46-49`).

`ResourceLoader` (`Services/ResourceLoader.swift`) coalesces, caches on
`ContinuousClock` and prefetches for the per-room calls — documented in
[lazy-loading.md](lazy-loading.md).

### What the user has to do today

Pull to refresh, on seven screens: `HomeView.swift:111`,
`CalendarView.swift:68`, `CareerView.swift:23`, `StudyPlanView.swift:72`,
`NewsView.swift:39`, `NoticesView.swift:43`, `RoomsView.swift:111`,
`FreeRoomsView.swift:43`, `CourseMaterialsView.swift:118`.

Everything else is appearance-driven `.task`, gated by the 5-minute window.

### What did not happen before the coordinator

The first two of these are now fixed — see [What is implemented](#what-is-implemented);
they are kept here because they are the reason it exists.

- **No refresh on foreground.** `scenePhase` is observed twice and neither
  reloads data: `PoliVerseApp.swift:132-136` schedules a background task and
  flushes the pending-writes queue; `RootView.swift:68-72` only routes a
  pending Control Center destination. A phone unlocked after four hours shows
  four-hour-old lectures until the user pulls.
- **No refresh when the network returns.** `PoliVerseApp.swift:138-141` flushes
  `PendingChanges` on `network.isOnline` going true, but no service reloads.
  Walk out of a basement and the screen stays as stale as it was underground.
- **No conditional requests.** `PoliMiAPI` builds a plain `URLRequest`
  (`Services/PoliMiAPI.swift:376`) on `URLSession.shared`
  (`Services/PoliMiAPI.swift:139`), sets no `cachePolicy`, sends no
  `If-None-Match`, and handles no 304 — the `switch` treats every 2xx as fresh
  data (`Services/PoliMiAPI.swift:205-206`) and has no 304 arm at all. Same for
  `RoomsService.swift:129` and `FreeRoomsService.swift:300`.
- **No push of any kind.** No `registerForRemoteNotifications` anywhere in the
  tree; `Config/PoliVerse.entitlements` declares only the app group;
  `Config/Info.plist:13-16` declares `UIBackgroundModes = [fetch]` and nothing
  else. `LiveActivityController` starts activities with `pushType: nil`
  (`Services/LiveActivityController.swift:73`) and says why
  (`Services/LiveActivityController.swift:8-11`).

### Background and widget refresh, as it stands

`BackgroundRefresh` (`Services/BackgroundRefresh.swift:20`) registers one
`BGAppRefreshTask` id (`Config/Info.plist:9-12`), reschedules an hour out
(`Services/BackgroundRefresh.swift:41-43`), and its work is agenda + career +
reminder rescheduling (`App/PoliVerseApp.swift:76-83`). It is scheduled on
entering background (`App/PoliVerseApp.swift:134`) and re-armed before each run
(`Services/BackgroundRefresh.swift:56`).

Widgets read the shared container and are reloaded by the app after a
successful fetch — `AgendaService.swift:122`, `CareerService.swift:240`,
`FreeRoomsService.swift:248`. Their own timelines carry `.after` policies:
6 hours (`PoliVerseWidgets/CareerWidget.swift:28`), next lecture boundary
(`NextLectureWidget.swift:54`), next occupancy step
(`FreeRoomsWidget.swift:61`), midnight (`TodayWidget.swift:51`).

---

## What the Politecnico's servers actually give us

**Measured 2026-09-12** with `curl -D -`, no auth, three public endpoints:

```
GET https://polimiapp.polimi.it/polimi_app/rest/jaf/public/props
GET https://onlineservices.polimi.it/maps_rest/rest/spazi/aula
GET https://onlineservices.polimi.it/maps_rest/rest/ricerca/aula/occupazione/67/2026-09-14
```

All three answered `200` with exactly these headers: `date`, `content-type`,
`content-length`, `set-cookie: INGRESSCOOKIE`, `content-security-policy`,
`strict-transport-security`, `x-content-type-options`, `x-frame-options`.

**No `ETag`. No `Last-Modified`. No `Cache-Control`. No `Expires`. No `Vary`.**

An `If-Modified-Since` sent to `/spazi/aula` returned `200` with the full body,
not `304`.

Three consequences, and they close off most of the textbook answers:

1. **Conditional requests are impossible.** There is no validator to echo back.
   `reloadRevalidatingCacheData` has nothing to revalidate against
   ([cachePolicy](https://developer.apple.com/documentation/foundation/nsurlrequest/cachepolicy-swift.enum/reloadrevalidatingcachedata)).
2. **`URLCache` buys nothing reliable.** The default
   `useProtocolCachePolicy` returns a cached response only when it "is not
   stale (past its expiration date)", and otherwise revalidates
   ([Apple](https://developer.apple.com/documentation/foundation/nsurlrequest/cachepolicy-swift.enum/useprotocolcachepolicy)).
   With no freshness headers at all, there is no expiration date to reason
   about, and any hit would rest on heuristic freshness rather than on
   anything the server promised. `OfflineStore`'s explicit `age` is a better
   answer than an opaque HTTP cache for exactly this reason.
3. **There is no push.** There is no Politecnico-operated APNs channel, and
   nothing in [endpoint-status.md](endpoint-status.md) — including
   `/v1/notifications`, whose body has still never been captured — offers a
   subscription, a webhook, a long-poll, or a change feed. Every "push"
   option below therefore requires **a server this project does not have**.

### The authenticated hosts, measured

**Measured 2026-09-12**, `curl -D -`, no token — the paths from
[endpoint-status.md](endpoint-status.md):

```
GET https://api.polimi.it/agenda/v1/matricola/{matricola}/events?…  → 401
GET https://api.polimi.it/piano_studente/elencoinsegnamenti/{matricola} → 401
GET https://api.polimi.it/iae/v1/base/counters                      → 401
GET https://webeep.polimi.it/login/index.php                        → 200
```

The three `api.polimi.it` services answer with **no `ETag`, no
`Last-Modified`, no `Cache-Control`, no `Expires`, no `Vary`** — the gateway
is a bare `Server: Apache` with no caching middleware in the response path at
all. WeBeep, being a Moodle, is the opposite and worse: it answers `200` with

```
Cache-Control: no-store, no-cache, must-revalidate, no-transform
Expires: Mon, 20 Aug 1969 09:23:00 GMT
Last-Modified: <the moment of the request>
```

`no-store` forbids keeping the response at all, and a `Last-Modified` equal to
now can never produce a `304`. So WeBeep actively rules out HTTP caching
rather than merely omitting it.

**How far this goes.** The `api.polimi.it` measurements are of `401`
responses, because a signed-in call needs a token this repo cannot mint
outside the app. A `401` from the gateway is strong evidence about the
response pipeline — no layer in it adds validators — but it is not the same
body as a `200`, so it is not proof that the authenticated `200` carries no
`ETag`. It is, however, as far as a measurement can go without a live
session, and combined with WeBeep's explicit `no-store` and the public
endpoints' silence, nothing in this API surface supports conditional
requests. **The remaining check**, for whoever next has a live token in a
proxy: one authenticated `200` on `/agenda/v1/matricola/…/events`, looking
for `ETag`.

---

## Options

| Option | What it buys | Cost / limit | Primary source |
| --- | --- | --- | --- |
| Refresh on `scenePhase == .active` | The single biggest win: data is re-fetched at the exact moment the user looks. Costs one request per foregrounding, gated by `LoadWindow`. | Fires on every return from the app switcher; must stay window-gated or it is a request per tab glance. | [ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase) |
| Refresh on `NetworkMonitor.isOnline` → true | Turns "offline, showing 3 h old" into fresh within a second of signal returning. The hook already exists for `PendingChanges` (`PoliVerseApp.swift:138-141`). | None material. | repo: `App/PoliVerseApp.swift:138-141` |
| `.task(id:)` keyed on a freshness token | Re-runs the load when the key changes — account, selected date, or a bumped "refresh generation". "If the `id` value changes, SwiftUI cancels and restarts the task." | Equatable key must genuinely change; already used at `RootView.swift:80,91` and `CalendarView.swift:71`. | [task(id:…)](https://developer.apple.com/documentation/swiftui/view/task(id:name:priority:file:line:_:)) |
| Keep `.refreshable` | The explicit escape hatch. "the list enables a standard pull-to-refresh gesture"; the indicator stays up for the duration of the async handler. | Nothing — it is already right. Keep it as the user's override, not as the only path. | [refreshable](https://developer.apple.com/documentation/swiftui/view/refreshable(action:)) |
| Stale-while-revalidate in the model | Already built: cached value on screen instantly, network after, `age` published. Extend it so *every* trigger follows the same path. | Requires `age` on every service (missing on `FreeRoomsService`). | repo: `Shared/OfflineStore.swift:212-246`, `DesignSystem/FreshnessBar.swift:11` |
| `URLCache` + `If-None-Match` / 304 | Would be the professional answer on a normal backend: bytes saved, one round trip, server-authoritative. | **Not available.** No validators and no `Cache-Control` on any measured endpoint (see above). | [URLCache](https://developer.apple.com/documentation/foundation/urlcache) |
| `BGAppRefreshTask` (in place) | Warms agenda + career while closed. "the system decides the best time to launch your background task, and provides your app up to 30 seconds of background runtime." | 30 s; the system decides *if* it runs at all, from usage patterns. Requires the `fetch` background mode — already declared. | [Choosing background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app), [BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask) |
| Silent / background push | The only true "server told us" mechanism. Wakes the app with `content-available: 1`, `apns-push-type: background`, `apns-priority: 5`, then 30 s to work. | **Needs a server we do not have and the Politecnico does not offer.** Also: "the system doesn't guarantee their delivery… don't try to send more than two or three per hour", and held notifications are coalesced to the newest. | [Pushing background updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) |
| WidgetKit push notifications | Server-driven timeline reloads. "When WidgetKit receives a push notification, it reloads your timelines, similar to when you call `reloadTimelines`." | Same server problem. Also budgeted: "the system budgets WidgetKit push notifications and delivers them opportunistically". | [WidgetKit push](https://developer.apple.com/documentation/widgetkit/updating-widgets-with-widgetkit-push-notifications) |
| ActivityKit push / push-to-start | Would let a lecture Live Activity start and update itself. | Same server problem; `pushType: .token`, tokens arrive asynchronously via `pushTokenUpdates`, and frequent updates need `NSSupportsLiveActivitiesFrequentUpdates`. Not startable by push at all below iOS 17.1. | [ActivityKit push](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications), [NSSupportsLiveActivitiesFrequentUpdates](https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivitiesfrequentupdates) |
| More `WidgetCenter.reloadAllTimelines()` | Nothing. Already called after every successful fetch. | Reloads are budgeted: "a daily budget typically includes from 40 to 70 refreshes… roughly every 15 to 60 minutes". Calling more does not raise the ceiling. | [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date) |
| Client-side polling / long-poll | Would close the gap for a live free-rooms view. | The endpoints are plain request/response — no long-poll, no streaming, nothing in the WADL ([endpoint-status.md](endpoint-status.md)). A timer polling `maps_rest` is battery spend for data that changes on a lecture-hour boundary. | repo: [endpoint-status.md](endpoint-status.md) |
| SwiftData as the UI's source of truth | `@Query` re-renders views automatically on any write, from any process. Would remove the "who calls reload" question entirely. | A migration of nine services off `OfflineStore`, for a store whose extension-shared write story is the part that matters here and is the part not yet proven for this app. | [SwiftData](https://developer.apple.com/documentation/swiftdata) |
| `@Observable` (in place) | Already the mechanism: every service is `@Observable`, so a write to `events` re-renders whatever read it. | None. | [Observation](https://developer.apple.com/documentation/observation), repo: `Services/AgendaService.swift:20` |

---

## What is implemented

Stages one and two of the plan below are in the tree; stage three remains
blocked on infrastructure.

| Change | Where |
| --- | --- |
| `FreshnessCoordinator` — the single list of "everything the app shows", coalescing concurrent runs | `Services/FreshnessCoordinator.swift` |
| The list itself, written once, in `FreshnessCoordinator.standard` — the app and the preview environment both build from it | `Services/FreshnessCoordinator.swift` |
| Revalidate on `scenePhase == .active`, unforced so `LoadWindow` gates it | `App/PoliVerseApp.swift` (`onChange(of: scenePhase)`) |
| Revalidate forced when `NetworkMonitor.isOnline` goes true | `App/PoliVerseApp.swift` (`onChange(of: network.isOnline)`) |
| `HomeView`'s `.task` and `.refreshable` route through the coordinator, so the list exists once | `Features/Home/HomeView.swift` |
| `FreeRoomsService.age`, derived from the fetch time, and a `FreshnessBar` on the screen. It is not a ticking clock — it re-reads on redraw, which is enough for a bar that stays silent under fifteen minutes | `Services/FreeRoomsService.swift`, `Features/Search/FreeRoomsView.swift` |
| Per-service windows: 15 min for libretto, courses and news; 60 s for free rooms, replacing its key-only guard so a day already seen can still be refetched; 5 min kept for agenda and notices | `Services/CareerService.swift`, `CourseService.swift`, `NewsService.swift`, `FreeRoomsService.swift` |
| A free-rooms pass that produced nothing does not stamp the fetch, following `LoadWindow`'s rule that a failed load must not suppress the retry | `Services/FreeRoomsService.swift` |
| Free rooms revalidates on foreground from its own screen rather than app-wide, because a campus pass is up to 158 requests | `Features/Search/FreeRoomsView.swift` |

Covered by `PoliVerseTests/FreshnessCoordinatorTests.swift` (ordering, force
propagation, gentle runs joining the one in flight, and the rule that every
forced run gets a pass of its own — a second pull to refresh must fetch) and the freshness suite
in `PoliVerseTests/FreeRoomsTests.swift`.

The background task's list is deliberately *not* the coordinator's: it keeps
agenda and career only, because 30 seconds is the whole budget.

---

## Recommended architecture

The backend offers no freshness signal, so the strategy is: **make the app
revalidate at every moment the user's attention arrives, and never make the
user ask.** Three stages, cheapest first.

### First — the two missing triggers, and one place to put them

Both are one-line hooks next to code that already exists.

1. **Foreground.** Extend `PoliVerseApp.swift:132-136`: on
   `scenePhase == .active`, call the same non-forced `load()` the `.task`
   modifiers call. `LoadWindow` already suppresses anything fetched in the
   last 300 s (`Services/LoadWindow.swift:37-41`), so returning from the app
   switcher costs nothing and returning after lunch costs one request.
   Reading the aggregate phase from the `App` is correct here: "The app
   reports a value of `active` if any scene is active"
   ([ScenePhase](https://developer.apple.com/documentation/swiftui/scenephase)).

2. **Reconnection.** Extend `PoliVerseApp.swift:138-141`: alongside
   `pending.flush()`, force a reload. Here `force: true` is right — the data
   on screen was fetched before the outage, and `LoadWindow` cannot know that.

Both should route through **one coordinator**, not nine call sites. Something
like a `FreshnessCoordinator` holding the services that have a
`load(force:)`, with a single `revalidate(force:)`. (As built, the references
are strong: the app owns every service for the life of the process, so weak
ones would buy nothing but a silent failure mode.) The shape of the
problem — "the same five loads, triggered from four places" — is already
visible in `HomeView.swift:111-121`, `HomeView.swift:123-132` and
`App/PoliVerseApp.swift:76-83` repeating the same list three times.

Keep `.refreshable` everywhere it is. It is the user's override and the
documented gesture, and staged revalidation does not replace it.

### Next — make the staleness legible everywhere, and tighten the window

- Give `FreeRoomsService` an `age` and a `FreshnessBar`; it is the one
  user-facing service without them, and it is the one where acting on stale
  data means walking to an occupied room.
- Consider a **per-service** `LoadWindow` interval instead of one global 300 s
  (`Services/LoadWindow.swift:17`). A libretto does not change hourly; room
  occupancy changes on the lecture boundary. A window of 15 minutes for career
  and 60 seconds for free rooms is more honest than one number for both.
- The foreground reload should cover the same five services Home already
  loads (`HomeView.swift:123-132`) rather than only the two the background
  task covers (`App/PoliVerseApp.swift:76-83`) — otherwise a student who
  foregrounds onto the Notices screen gets a stale bell.

### Later — and only if a server appears

**There is no server, and none is planned.** Everything in this stage is
recorded for whoever picks it up, not queued.

Everything push-shaped is blocked on infrastructure, not on iOS. If this
project ever runs a small server that polls the Politecnico on the student's
behalf, the order to adopt is:

1. **Background push** (`apns-push-type: background`, `apns-priority: 5`,
   `content-available: 1`, plus the Remote notification background mode) to
   wake the app when the agenda actually changes. Budget for "two or three per
   hour" as the documented ceiling, which suits a timetable perfectly.
2. **WidgetKit push** so the Lock Screen follows without the app running.
3. **ActivityKit push-to-start**, which would remove the manual "sto andando"
   tap that `LiveActivityController.swift:8-11` currently calls the only
   honest option.

Until then, **do not** add a polling timer and do not lengthen the background
task's reach. `BGAppRefreshTask` already covers "warm while closed" at the
only budget iOS grants, and its 30-second ceiling is why the campus room pass
is deliberately excluded (`Services/BackgroundRefresh.swift:11-14`).

**SwiftData** is not recommended now. It would be the right answer if the
widget extension needed to *write*, or if several processes contended over the
same records. Neither is true: the app writes, the extensions read, and
`OfflineStore` already does that across the app group. Adopting it to solve a
trigger problem would be a migration paying for a feature we do not need.

---

## Constraints and gotchas

- **30 seconds, both ways.** `BGAppRefreshTask` and a background push each get
  "up to 30 seconds"; exceed it and the system terminates the app
  ([choosing background strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app),
  [pushing background updates](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app)).
  The current refresh closure (`App/PoliVerseApp.swift:76-83`) does three
  things; adding a fourth needs measuring, not assuming.
- **The system decides whether background refresh runs at all**, from how the
  person uses the app. A refresh that never fires must degrade to "loads on
  open", which is what `BackgroundRefresh.swift:16-18` already documents.
- **Background push is best-effort and coalescing.** "the system doesn't
  guarantee their delivery"; a newer background notification "discards the
  older notification and only holds the newest one". Never treat one as a
  delivery receipt for a specific change.
- **Widget reloads are budgeted**, 40–70 a day for a frequently-viewed widget,
  with a minimum of about 5 minutes between timeline entries
  ([keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)).
  Reloads while the containing app is in the foreground do **not** count — so
  the existing `reloadAllTimelines()` calls after a foreground fetch are free.
- **`scenePhase == .active` fires often.** Without the `LoadWindow` gate, a
  foreground-refresh hook turns every glance at the app switcher into five
  round trips. The gate is the whole safety mechanism; do not pass `force` on
  the foreground path.
- **A 401 is not always a stale token.** `PoliMiAPI` distinguishes "not
  entitled" (`Code: 6`) and "wrong scope" (`Code: 33`) from an expired session
  (`Services/PoliMiAPI.swift:208-243`). More automatic refreshes mean more
  chances to hit those, and neither must trigger a login loop — the existing
  handling covers it, and any new trigger must go through `send`, not around
  it.
- **Cancellation is not failure.** More triggers mean more requests abandoned
  when a view goes away; `APIError.cancelled` exists precisely so those do not
  surface as "Impossibile raggiungere i server del Politecnico"
  (`Services/PoliMiAPI.swift:46-49`).
- **The Politecnico API supports none of the conditional-request machinery.**
  Verified by measurement, above. Any design that assumes a 304 will not work.
- **Unverified and worth checking**: whether the authenticated hosts emit
  validators for a signed-in caller; and whether `/v1/notifications` could act
  as a cheap change signal — its response body has still never been captured
  ([endpoint-status.md](endpoint-status.md)).

---

## Sources

Apple developer documentation:

- ScenePhase — https://developer.apple.com/documentation/swiftui/scenephase
- `refreshable(action:)` — https://developer.apple.com/documentation/swiftui/view/refreshable(action:)
- `RefreshAction` — https://developer.apple.com/documentation/swiftui/refreshaction
- `task(id:name:priority:file:line:_:)` — https://developer.apple.com/documentation/swiftui/view/task(id:name:priority:file:line:_:)
- Observation — https://developer.apple.com/documentation/observation
- SwiftData — https://developer.apple.com/documentation/swiftdata
- URLCache — https://developer.apple.com/documentation/foundation/urlcache
- `URLSessionConfiguration.urlCache` — https://developer.apple.com/documentation/foundation/urlsessionconfiguration/urlcache
- `useProtocolCachePolicy` — https://developer.apple.com/documentation/foundation/nsurlrequest/cachepolicy-swift.enum/useprotocolcachepolicy
- `reloadRevalidatingCacheData` — https://developer.apple.com/documentation/foundation/nsurlrequest/cachepolicy-swift.enum/reloadrevalidatingcachedata
- `returnCacheDataElseLoad` — https://developer.apple.com/documentation/foundation/nsurlrequest/cachepolicy-swift.enum/returncachedataelseload
- Choosing background strategies for your app — https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app
- BGTaskScheduler — https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler
- BGAppRefreshTask — https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask
- BGAppRefreshTaskRequest — https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtaskrequest
- Pushing background updates to your app — https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app
- Sending notification requests to APNs — https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns
- Keeping a widget up to date — https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
- Updating widgets with WidgetKit push notifications — https://developer.apple.com/documentation/widgetkit/updating-widgets-with-widgetkit-push-notifications
- Developing a WidgetKit strategy — https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy
- Starting and updating Live Activities with ActivityKit push notifications — https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications
- NSSupportsLiveActivitiesFrequentUpdates — https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivitiesfrequentupdates

Measured against the Politecnico's servers, 2026-09-12, `curl -D -`:

- `https://polimiapp.polimi.it/polimi_app/rest/jaf/public/props`
- `https://onlineservices.polimi.it/maps_rest/rest/spazi/aula`
- `https://onlineservices.polimi.it/maps_rest/rest/ricerca/aula/occupazione/67/2026-09-14`

In this repo: [endpoint-status.md](endpoint-status.md),
[lazy-loading.md](lazy-loading.md), [polimi-api-research.md](polimi-api-research.md).
