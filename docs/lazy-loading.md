# Lazy loading, and the APIs behind it

Toolchain as measured, not assumed: **Swift 6.4** (swiftlang-6.4.0.33.1),
**Xcode 27**, **iOS SDK 27**, deployment target **iOS 26** at the time of
measuring (now iOS 27), language mode 6,
`SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`,
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

## What is available

Every item below was type-checked against this SDK before being relied on,
rather than taken from release notes.

| API | Since | Used here |
| --- | --- | --- |
| `actor`, unstructured `Task` | 5.5 | the loader's core |
| `Synchronization.Mutex`, `Atomic` | 6.0 | not needed — the actor covers it |
| `@concurrent` | 6.2 | not needed — the actor's work already leaves the main actor |
| `nonisolated(nonsending)` | 6.2 | available; the project's default isolation makes it moot here |
| `Task.immediate` | 6.2 | no: every path here is genuinely async |
| `withDiscardingTaskGroup` | iOS 17 | considered; results are needed, so a plain group is right |
| `ContinuousClock` | iOS 16 | cache lifetimes — monotonic, so a clock change cannot expire the cache |
| `onScrollTargetVisibilityChange` | iOS 18 | the prefetch trigger |
| `onScrollPhaseChange`, `ScrollPosition` | iOS 18 | available, not needed yet |
| `BGAppRefreshTask` | iOS 13 | warming while closed |
| `BGContinuedProcessingTask` | iOS 26 | **no** — see below |
| `URLSessionConfiguration.background` | iOS 7 | no: these are small JSON reads, not downloads |

### Deliberately not used

**`BGContinuedProcessingTask`** (iOS 26) is the obvious match for the 150-request
campus occupancy pass, and it is wrong here: it is for work the *user started
and can see*, with a progress UI, not for speculative warming. Using it to
prefetch would put a system progress bar on screen for something nobody asked
for.

**`@concurrent`** would matter if the fetch closures were main-actor isolated
and needed pushing off. They are not — `ResourceLoader` is an actor and its
`fetch` is `@Sendable`, so the work already runs off the main actor. Adding the
attribute would be noise.

**A background `URLSession`** buys out-of-process downloads that survive
termination. Right for WeBeep files; wrong for a 2 KB JSON reply, where the
setup costs more than the request.

## The design

`ResourceLoader<Key, Value>` is an actor doing four things the app previously
could not:

1. **Coalesce.** Eight callers for one key cost one request. The old
   `isLoading` flag made the second caller give up and render nothing — which
   is why opening a room from search during the rooms-list load showed an empty
   screen.
2. **Cache**, with a lifetime on `ContinuousClock` and LRU eviction at a
   capacity, so a long session cannot grow without bound.
3. **Prefetch** at `.background` priority, returning as soon as the work is
   queued.
4. **Survive its callers.** The work runs in an unstructured `Task` held by the
   actor; callers await its value. With structured concurrency a caller that
   goes away cancels the work and takes it from every other screen waiting on
   it.

### Two things that were harder than they look

**`settle()` must wait for the write, not the fetch.** The result is filed by a
second task, so awaiting the fetch proves nothing about the cache. The first
version looped on `inFlight` and spun forever. `filing` is tracked separately
for exactly this.

**Failures are not cached.** Caching a nil would let one flaky moment poison a
resource for the life of the app.

### Where it is wired

| Consumer | Effect |
| --- | --- |
| `RoomFacilitiesService` | equipment + software per room, one hour, prefetched around the visible rows |
| `FreeRoomsService` | occupancy per room and day; the campus pass and a single detail now share one request |
| `RoomsView` | `.prefetching(...)` warms six rows either side of the visible window |
| `BackgroundRefresh` | agenda + career while the app is closed, then reminders are rescheduled |

The background refresh deliberately does **not** run the campus room pass: iOS
grants roughly thirty seconds and 150 requests would be killed half-done.

---

# The login, and why it was slow

## Measured

`GET https://polimiapp.polimi.it/polimi_app/app/` pulls:

| File | Size | Caching |
| --- | --- | --- |
| `index.html` | 3.4 KB | `private`, ETag, Last-Modified |
| `index-*.js` | **8,269,045 B** | `private`, ETag, Last-Modified |
| `index-*.css` | **5,425,236 B** | `private`, ETag, Last-Modified |

**13.7 MB**, and the app has to run it: a token this app mints directly is
rejected by the data services, while the one the SPA mints is accepted.

Everything above is cacheable — `private` means "not in shared caches", not
"do not store", and both files carry validators, so a second load should be
two 304s. The web view used `WKWebsiteDataStore.nonPersistent()`, which
discards the cache with the view, so **every login downloaded all 13.7 MB
again**.

## What changed

| | Before | After |
| --- | --- | --- |
| Data store | non-persistent | persistent, app-scoped identifier |
| Repeat login | 13.7 MB | revalidation only |
| Credential detection | poll every 400 ms, up to 25 times | pushed from `setItem` |
| Worst-case wait after success | ~10 s | none |
| Images/media/fonts on the SPA host | downloaded | blocked |
| Page load | starts when the user taps | starts when the login screen appears |

## The trade that had to be preserved

The non-persistent store was not careless: it guaranteed a Shibboleth session
could never outlive the login. That property is kept by deleting **cookies,
session storage and local storage** when the flow ends and on sign-out —
`WKWebsiteDataTypeDiskCache` is deliberately not in that list, which is the
whole point.

It also fixes a real failure the old comment described but could not solve: the
CieID detour backgrounds the app for as long as a card and PIN take, and if iOS
reclaimed it in that window the in-memory cookies went with it and the login
restarted from the top.

## Blocking is scoped, deliberately

Images, media and fonts are blocked **only on `polimiapp.polimi.it`**. The
identity providers — CIE, SPID, aunicalogin — are pages the user actually reads
and taps, and their buttons are frequently images; blocking there would make
the login unusable rather than fast. The SPA behind them is a page nobody
reads: it exists to run its JavaScript and hand back a credential.

---

# Launch time, and what iOS 27 does not offer

## The question asked

"Can new iOS 27 APIs improve launch times?" The honest answer is **no**, and it
is worth recording why so nobody re-does the search.

The SwiftUI interface in SDK 27 carries 133 `iOS 27` availability markers. The
only scene- or launch-adjacent ones are underscored private API
(`_makeSceneAccessory`). There is no public launch, prewarm or scene-caching
API added in this release, and raising the deployment target from 26 to 27
would drop users for no launch benefit.

> Update 2026-09-17: the owner raised the deployment target to iOS 27 anyway,
> for the other iOS 27 APIs (MetricKit's `MetricManager`, StateReporting,
> system reordering, `systemPrefersReducedResourceUsage`,
> `asyncImageURLSession`). The launch finding above still holds.

## What was actually on the launch path

`PoliVerseApp.init()` runs on the main thread before the first frame. It builds
twelve services, and two of them read from disk.

| Work | Measured | Verdict |
| --- | --- | --- |
| `DiskCache` room catalogue (353 rooms, 99 KB) | **1.28 ms** to decode | not worth moving |
| `DiskCache` course list | smaller again | not worth moving |
| `TokenStore` Keychain read | IPC to `securityd` | **moved** |
| `BGTaskScheduler.register` | closure capture | negligible |
| `WKWebsiteDataStore(forIdentifier:)` | lazy `static let` | already off the path |

The JSON was the obvious suspect and the measurement cleared it. The Keychain
read was the real one: `TokenStore.init` called `storage.load()`, and every
accessor on that actor is already `async`, so the read now happens on first use
— `Session.restore()`, after the first frame.

"Not loaded yet" and "signed out" both look like a nil token, so writes mark
the store loaded; otherwise a later read would go back to the Keychain and
resurrect what was just cleared. That has a test.

## Measurement is now part of the app

Guessing produced one real finding and two false ones, so `LaunchMetrics` keeps
the instruments:

- **`OSSignposter`** intervals for named phases, for Instruments on a device.
- **MetricKit** `MXAppLaunchMetric` for real launches in the field, logged
  rather than uploaded — the app has no analytics backend and adding one to
  measure launch would be a poor trade for the student whose data it would be.
- **`ActivePrewarm`** is read and logged, because a prewarmed launch has
  already paid for dynamic linking and its numbers are not comparable with a
  cold one. Mistaking the two is how launch "improvements" get celebrated.

## Measured with Instruments, 2026-09-12

Release build, iPhone 17 Pro simulator, iOS 27.0, *App Launch* template via
`xctrace`, 3,485 samples.

Share of samples whose stack passes through each image, in 200 ms buckets:

| Window | Samples | dyld | SwiftUI + AttributeGraph | PoliVerse |
| --- | --- | --- | --- | --- |
| 0.0–2.0 s | ~590 | **100 %** | 0 % | **0 %** |
| 2.2–2.4 s | 69 | 100 % | 10 % | 9 % |
| 2.4–2.6 s | 113 | 100 % | 76 % | 50 % |
| 2.6–3.0 s | 360 | 61–73 % | 39–49 % | 28–36 % |

**The first two seconds are entirely the dynamic linker.** Not one sample in
that window touches app code, SwiftUI, or anything we wrote. Our own code first
appears at 2.2 s, by which point dyld has finished.

Over the whole trace, PoliVerse accounts for 1,153 frames of which 510 are
`main`/`$main` — the frame present on every stack. The rest:

```
15  PoliVerseApp.init()
 8  Session.restore()
 7  ServiceDirectory.load()
 5  Session.init()      5  RoomsService.init(session:)
 2  KeychainStore.load(account:)
```

`KeychainStore.load` now appears under `Session.restore()` — after launch,
which is what the lazy change was for — and at two samples it was never going
to be visible at this scale. The change was right; the expectation of a
measurable win was not.

### What this does and does not prove

`dyld_sim` is the **simulator's** linker, without the optimised shared cache a
real device has, so this over-states dyld badly. What it does establish is the
ordering: there is nothing of ours in the pre-UI phase to optimise, and the app
links no third-party frameworks to trim.

Two limitations found the hard way:

- The `life-cycle-period` table — the one holding the actual launch phases — is
  **empty on the simulator**. That is the "table without a known input source"
  warning `xctrace` prints. Time to first draw is not measurable here at all.
- Only a device gives a representative number, which is what the MetricKit
  subscription added alongside is for.

**Conclusion: no further launch work is justified by this data.** The next real
measurement has to come from a device.
