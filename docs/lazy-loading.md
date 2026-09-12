# Lazy loading, and the APIs behind it

Toolchain as measured, not assumed: **Swift 6.4** (swiftlang-6.4.0.33.1),
**Xcode 27**, **iOS SDK 27**, deployment target **iOS 26**, language mode 6,
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
