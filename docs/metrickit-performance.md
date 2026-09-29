# MetricKit, and making the app fast

Researched 2026-09-14 against Apple's documentation, WWDC session transcripts,
Swift Evolution, and — where the docs and the SDK could disagree — the
**iOS 27.0 SDK shipped with Xcode 27.0 (27A5252f)** on this machine.

Toolchain, as measured: Swift 6.4 (swiftlang-6.4.0.33.1), deployment target
**iOS 26.0** for the app and the widget extension, language mode 6,
`SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`,
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

Conventions in this note:

- **[iOS 27]** / **[iOS 26]** marks anything new or changed in that SDK.
- **[unverified]** marks a claim no primary source confirmed. Treat it as a
  hypothesis to measure, not a fact.
- `file:line` references are to the tree at commit `d7728e3` plus the working
  changes on `feature/novita-esame`.

The short version:

1. **MetricKit was rebuilt in iOS 27.** `MetricManager` (async sequences,
   `Codable`/`Sendable` value types, extended launch, state-segmented metrics)
   replaces `MXMetricManager`, which is marked deprecated in the docs. With an
   iOS 26 deployment target the app needs **both**: the new API behind
   `if #available(iOS 27, *)`, the old one for iOS 26 devices.
2. **What the app has today is a launch-only logger.** `LaunchMetrics` ignores
   every diagnostic (crashes, hangs, disk-write and CPU exceptions), keeps
   nothing, subscribes after the first frame, and its `measure` helper has no
   call sites.
3. **The largest likely runtime cost is ours, not the system's:** with
   Approachable Concurrency on, `nonisolated async` functions run on the
   *caller's* actor, so JSON decoding in `PoliMiAPI.send` and the synchronous
   atomic writes in `OfflineStore.save` very probably run on the main thread
   when called from the `@MainActor` services. That needs one Instruments trace
   to confirm, and it is the first thing Phase 2 fixes.

---

## 1. MetricKit, end to end

### 1.1 Two APIs, one app

| | `MXMetricManager` (legacy) | `MetricManager` **[iOS 27]** |
| --- | --- | --- |
| Availability | iOS 13+, docs say deprecated 27.0 | iOS 27.0+ |
| Shape | shared singleton + `MXMetricManagerSubscriber` delegate | instantiable class, two `AsyncSequence`s |
| Payloads | `MXMetricPayload`, `MXDiagnosticPayload` (NSObject, `jsonRepresentation()`) | `MetricReport`, `DiagnosticReport` (`Sendable`, `Codable` structs) |
| Values | per-category classes (`MXCPUMetric`, …) | one `MetricResult` enum + `MetricGroup` |
| Extended launch | `extendLaunchMeasurement(forTaskID:)` / `finish…` (iOS 16) | `trackLaunchTask(id:_:)`, sync and async |
| Custom signposts | `makeLogHandle(category:)` + `mxSignpost` | `logHandle(category:)` + `mxSignpost` |
| State segmentation | — | `StateReporting` domains |
| Memory-limit diagnostic | — | `MemoryExceptionDiagnostic` (iOS only) |

Sources: [MetricKit](https://developer.apple.com/documentation/metrickit),
[MetricKit updates, June 2026](https://developer.apple.com/documentation/updates/metrickit),
[MXMetricManager API](https://developer.apple.com/documentation/metrickit/mxmetricmanager-api),
[MetricManager](https://developer.apple.com/documentation/metrickit/metricmanager).

Apple's position, from [Meet the new MetricKit (WWDC26)](https://developer.apple.com/videos/play/wwdc2026/222/):
the new APIs "are the future of the framework", every advance shown that year
is exclusive to them, and `MXMetricManager` users should migrate.

**A discrepancy worth knowing.** The documentation pages mark every `MX*` symbol
"deprecated 27.0", but the SDK header marks them
`API_DEPRECATED("Use MetricManager instead.", ios(13.0, API_TO_BE_DEPRECATED))`
(`MetricKit.framework/Headers/MXMetricManager.h:51,68,76`). `API_TO_BE_DEPRECATED`
is a soft deprecation, so with an iOS 26 target the legacy calls are expected to
compile without warnings. **[unverified: not compiled]**

**What this means for PoliVerse.** The deployment target is 26.0
(`PoliVerse.xcodeproj/project.pbxproj:323,360,484,516`). Raising it to 27 to
drop the legacy path would drop iOS 26 users, which `lazy-loading.md` already
rejected for launch; the same reasoning holds. Ship both, pick one at runtime.

Whether registering **both** managers in one process delivers each report twice
is not documented. **[unverified]** Register exactly one per OS version.

### 1.2 Setup, lifecycle, delivery

**Where to register.** As early as possible, and keep the object alive.

- New API: "This setup should be done at app start up to avoid any data loss
  from delayed subscription. MetricManager should be kept alive so that the
  streams can continue to deliver reports"
  ([WWDC26 222](https://developer.apple.com/videos/play/wwdc2026/222/)).
  Create **one** instance: two tasks iterating the same sequence of two
  managers "both receive a non-deterministic subset of reports rather than a
  full copy" ([MetricManager](https://developer.apple.com/documentation/metrickit/metricmanager)).
- Legacy API: "MetricKit starts accumulating reports for your app after calling
  `shared` for the first time", and "calls to add a subscriber and to receive
  reports are safe to use in performance-sensitive code, such as during app
  launch" ([MXMetricManager](https://developer.apple.com/documentation/metrickit/mxmetricmanager)).

That contradicts the comment at `PoliVerse/App/PoliVerseApp.swift:163-166`, which
defers `LaunchMetrics.start()` to a `.task` because "subscribing is not free".
Apple says it is safe at launch; move it into `init()` and measure with a
signpost if in doubt.

**Delivery cadence.**

| Kind | When | Source |
| --- | --- | --- |
| Metric reports | covering the previous 24 h, at most once per day; can be more than one payload a day when metrics come from different system sources; include undelivered earlier days | [MetricKit](https://developer.apple.com/documentation/metrickit), [MXMetricManager](https://developer.apple.com/documentation/metrickit/mxmetricmanager) |
| Diagnostic reports | immediately, iOS 15+ (before that, bundled daily) | same |
| New API entries | one full-day entry plus smaller breakdowns "typically a few hours each", present only when they have data | [WWDC26 222](https://developer.apple.com/videos/play/wwdc2026/222/) |
| Hang diagnostics | not for every hang: only when the device has hang detection enabled or is in a sampling group | [DiagnosticReport](https://developer.apple.com/documentation/metrickit/diagnosticreport) |

**Past payloads (legacy only).** `pastPayloads` returns daily reports "generated
since the last allocation of the shared manager instance";
`pastDiagnosticPayloads` only covers the current process lifetime, is readable
after the first subscriber callback, and "doesn't include diagnostics from
previous app instances"
([pastPayloads](https://developer.apple.com/documentation/metrickit/mxmetricmanager/pastpayloads),
[pastDiagnosticPayloads](https://developer.apple.com/documentation/metrickit/mxmetricmanager/pastdiagnosticpayloads)).
Neither replaces persisting what arrives. The new API has no equivalent in the
SDK interface. **[iOS 27]**

**The concurrency trap PoliVerse already hit.** The legacy subscriber is called
on a MetricKit queue. Under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` the
class must be `nonisolated`, or the runtime isolation check aborts — which
`LaunchMetrics.swift:58-61` records happening. With the new API the question
disappears: the reports are `Sendable` values consumed with `for await`.

### 1.3 Every metric

New-API names, grouped as Apple groups them
([MetricKit](https://developer.apple.com/documentation/metrickit),
[MetricResult](https://developer.apple.com/documentation/metrickit/metricresult)).
"State" means the metric also appears in `stateEntries`
([MetricReport](https://developer.apple.com/documentation/metrickit/metricreport)).

| Group | `MetricResult` cases | Shape | State | Legacy home |
| --- | --- | --- | --- | --- |
| Launch | `timeToFirstDraw`, `optimizedTimeToFirstDraw`, `applicationResumeTime`, `extendedLaunch` **[iOS 27]** | histograms | no | `MXAppLaunchMetric` |
| Responsiveness | `hangTime` (hangs over 9 s land in the last bucket), `hitchTime` | histogram / ratio | yes | `MXAppResponsivenessMetric`, `MXAnimationMetric` |
| Runtime | `totalForegroundTime`, `totalBackgroundTime`, `totalBackgroundAudioTime`, `totalBackgroundLocationTime`, `locationActivityTime`, `foregroundTermination`, `backgroundTermination` | scalars / counts | yes | `MXAppRunTimeMetric`, `MXAppExitMetric` |
| CPU / memory | `cpuTime`, `cpuInstructionsCount`, `peakMemory`, `suspendedMemory` (`AverageStatistics`) | scalars | no | `MXCPUMetric`, `MXMemoryMetric` |
| Network | `totalWiFiUpload/Download`, `totalCellularUpload/Download`, `cellularConditionTime` | scalars / histogram | no | `MXNetworkTransferMetric`, `MXCellularConditionMetric` |
| Storage | `logicalDiskWrites`, `totalFileCount` **[iOS 27]**, `totalFileSize` (binary vs data), `totalDiskSpaceCapacity` | scalars | no | `MXDiskIOMetric`, `MXDiskSpaceUsageMetric` |
| Display / GPU | `pixelLuminance`, `gpuTime`, `metalFrameRate` **[iOS 27]** | scalars | no | `MXDisplayMetric`, `MXGPUMetric` |
| Custom | `signpostInterval` | histogram + optional CPU, memory, writes, hitches | yes | `MXSignpostMetric` |

Sources for the details: [HangTimeMetric](https://developer.apple.com/documentation/metrickit/hangtimemetric),
[ExtendedLaunchMetric](https://developer.apple.com/documentation/metrickit/extendedlaunchmetric),
[Analyzing app performance with MetricKit](https://developer.apple.com/documentation/metrickit/analyzing-app-performance-with-metrickit).

Two things to keep straight when reading launch numbers:

- `optimizedTimeToFirstDraw` is the prewarmed launch; `LaunchMetrics.swift:67-69`
  already logs it apart from the cold one, which is right.
- Launch metrics measure to the first frame; work after it "doesn't contribute
  to the launch-time metric" but users still perceive it
  ([Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time)).
  That is what extended launch is for — see 1.7.

Hang rate as Organizer reports it: seconds of unresponsiveness per hour,
counting only periods over 250 ms; MetricKit "provides the same hang rate metric
as a histogram"
([Analyzing responsiveness issues in your shipping app](https://developer.apple.com/documentation/xcode/analyzing-responsiveness-issues-in-your-shipping-app)).
Hitch-ratio targets from Apple's tooling: under 5 ms/s good, 5–10 ms/s
investigate, 10 ms/s or more act now
([Eliminate animation hitches with XCTest, WWDC20](https://developer.apple.com/videos/play/wwdc2020/10077/)).

### 1.4 Every diagnostic

| `DiagnosticResult` case | Carries | Since | Notes |
| --- | --- | --- | --- |
| `.crash(CrashDiagnostic)` | call stack, `exceptionType`, `exceptionCode`, `signal`, ObjC `exceptionReason`, `virtualMemoryRegionInfo`, `terminationReason`, `terminationCategory` **[iOS 27]** | iOS 14 (`MXCrashDiagnostic`) | category (`watchdog`, `taskTimeout`, `fileLock`, `badAccess`, …) lines up with the termination metrics |
| `.hang(HangDiagnostic)` | call stack, `hangDuration` | iOS 14 | sampled population only |
| `.cpuException(CPUExceptionDiagnostic)` | call stack, `totalCPUTime`, `totalSampledTime` | iOS 14 | fatal or non-fatal |
| `.diskWriteException(DiskWriteExceptionDiagnostic)` | call stack, `totalBytesWritten` | iOS 14 | threshold described as 1 GB/day in [WWDC20](https://developer.apple.com/videos/play/wwdc2020/10081/); current docs only say "a certain threshold in a 24-hour period" |
| `.appLaunch(AppLaunchDiagnostic)` | call stack, `launchDuration` | iOS 16 (`MXAppLaunchDiagnostic`) | only launches over "the diagnostic threshold" (value not documented) |
| `.memoryException(MemoryExceptionDiagnostic)` | call stack | **[iOS 27]**, iOS/iPadOS only | app **or extension** killed for exceeding its memory limit |

Sources: [DiagnosticResult](https://developer.apple.com/documentation/metrickit/diagnosticresult),
[CrashDiagnostic](https://developer.apple.com/documentation/metrickit/crashdiagnostic),
[CrashDiagnostic.TerminationCategory](https://developer.apple.com/documentation/metrickit/crashdiagnostic/terminationcategory-swift.struct),
[MemoryExceptionDiagnostic](https://developer.apple.com/documentation/metrickit/memoryexceptiondiagnostic),
[Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes).

`DiagnosticReport.environment` carries app version and build, OS, device type,
`isTestFlightApp`, `pid`, `bundleIdentifier`, the StateReporting `states` active
just before the event, and `signpostData` — the `OSSignposter` intervals that
were open when it happened
([Analyzing app performance with MetricKit](https://developer.apple.com/documentation/metrickit/analyzing-app-performance-with-metrickit),
[SignpostRecord](https://developer.apple.com/documentation/metrickit/signpostrecord)).
That last field is the cheapest context the app can buy: name the intervals
well and every hang report says what the app was doing.

### 1.5 JSON, and symbolication

**Legacy JSON.** `MXCallStackTree.jsonRepresentation()` produces
`{"callStackTree": {"callStackPerThread": Bool, "callStacks": [{"threadAttributed": Bool, "callStackRootFrames": [frame]}]}}`
where a frame has `binaryName`, `binaryUUID`, `address`,
`offsetIntoBinaryTextSegment`, `sampleCount` and nested `subFrames`
([jsonRepresentation()](https://developer.apple.com/documentation/metrickit/mxcallstacktree/jsonrepresentation())).
Payloads have their own `jsonRepresentation()`.

**New API.** Both report types are `Codable`; encode with `JSONEncoder`. Setting
`encoder.userInfo[MetricReport.encodingFormatKey] = MetricReport.EncodingFormat.byStateReportingDomain`
groups the output by domain. The JSON schema of the new encoding is not
documented, so persist it but don't hand-parse it on a server yet. **[iOS 27]**
([Analyzing app performance with MetricKit](https://developer.apple.com/documentation/metrickit/analyzing-app-performance-with-metrickit)).
`CallStackTree` deduplicates binaries in `binaryInfo` keyed by UUID and offers
`forEachFrame(_:)` for an iterative walk
([CallStackTree](https://developer.apple.com/documentation/metrickit/callstacktree)).

**Symbolication.** Stacks are "unsymbolicated and designed for off-device
processing", with everything `atos` needs
([What's new in MetricKit, WWDC20](https://developer.apple.com/videos/play/wwdc2020/10081/)).
For each frame in our binary:

```
atos -arch arm64 -o PoliVerse.app.dSYM/Contents/Resources/DWARF/PoliVerse \
     -l <load address> -i <address>
```

The load address is `address − offsetIntoBinaryTextSegment`. `-i` expands
inlined frames, `-dedup` reveals functions the linker merged
([Adding identifiable symbol names to a crash report](https://developer.apple.com/documentation/xcode/adding-identifiable-symbol-names-to-a-crash-report)).
Requirement: keep the dSYM for every build that ships. Release already builds
`dwarf-with-dsym` (`project.pbxproj`, Release config); archives keep them. Match
by `binaryUUID` (`dwarfdump --uuid`).

### 1.6 Custom metrics with signposts

```swift
let log = MetricManager.logHandle(category: "Network")        // iOS 27
// let log = MXMetricManager.makeLogHandle(category: "Network") // iOS 26
mxSignpost(.begin, log: log, name: "agenda.load")
// …
mxSignpost(.end, log: log, name: "agenda.load")
```

- Only `mxSignpost` populates CPU time, memory, logical writes;
  `mxSignpostAnimationIntervalBegin` (iOS 15) adds hitch data. `OSSignposter` on
  the same handle gives counts and durations only
  ([Monitoring app performance with MetricKit](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit)).
- Don't alter `dso`, `signpostID` or `format`
  ([mxSignpost](https://developer.apple.com/documentation/metrickit/mxsignpost(_:dso:log:name:signpostid:_:_:))).
  The default `signpostID` is `.exclusive`, so overlapping intervals of the same
  name on one handle will not pair correctly — use distinct names for work
  that can overlap. **[unverified: inferred from the signature]**
- "The system limits the number of custom signpost metrics saved to the log …
  Limit use of custom metrics to critical sections of code"
  ([MXSignpostMetric](https://developer.apple.com/documentation/metrickit/mxsignpostmetric)).
  The limit is not published. **[unverified]**
- `mxSignpost` itself is **not** deprecated and exists unchanged in the iOS 27
  interface (`MetricKit.swiftinterface:277,281`), so signpost call sites work on
  both paths; only the log-handle factory differs.

### 1.7 Extended launch

| | iOS 16–26 | iOS 27 |
| --- | --- | --- |
| API | `MXMetricManager.extendLaunchMeasurement(forTaskID:)` then `finishExtendedLaunchMeasurement(forTaskID:)`, both `throws` | `@MainActor trackLaunchTask(id:onTrackingError:_:)`, sync and `async` overloads |
| Rules | main thread; first task must start before the first scene becomes active; tasks must overlap; max 16 | end point is the later of first frame and completion of all tracked tasks |
| Errors | thrown | `LaunchTaskError.Reason`: `invalidID`, `maxCountExceeded`, `pastDeadline`, `duplicateTask`, `taskUnknown`, `internalFailure` (SDK interface) |
| Result | reported in launch metrics | `MetricResult.extendedLaunch`, interval entries only |

Sources: [extendLaunchMeasurement(forTaskID:)](https://developer.apple.com/documentation/metrickit/mxmetricmanager/extendlaunchmeasurement(fortaskid:)),
[trackLaunchTask](https://developer.apple.com/documentation/metrickit/metricmanager/tracklaunchtask(id:ontrackingerror:_:)-48k2s),
[ExtendedLaunchMetric](https://developer.apple.com/documentation/metrickit/extendedlaunchmetric),
SDK `MetricKit.swiftinterface` (the `Reason` cases are not on the doc page).

`pastDeadline` exists, so late starts fail; the deadline itself is not
documented beyond the scene rule above. **[unverified]**
`XCTApplicationLaunchMetric()` measures "first frame … and complete all extended
launch tasks", so the same instrumentation drives local tests
([XCTApplicationLaunchMetric](https://developer.apple.com/documentation/xctest/xctapplicationlaunchmetric)).

For PoliVerse, the perceived launch is `RootView`'s `await session.restore()`
(`PoliVerse/App/RootView.swift:25`) plus the Home screen showing cached agenda
data. That is the one task worth tracking.

### 1.8 State segmentation **[iOS 27]**

`StateReporting` lets the app declare domains (one active state each) and report
transitions; MetricKit then returns hang time, hitch time, terminations,
signpost intervals and runtime metrics per state. CPU, memory, network, disk,
GPU and launch are interval-only
([MetricReport](https://developer.apple.com/documentation/metrickit/metricreport),
[Getting started with StateReporting](https://developer.apple.com/documentation/statereporting/getting-started-with-statereporting)).

Rules that bite:

- Register domains in `MetricManager(enabledStateReportingDomains:)`.
- `StateReporter.reporter(for:stableMetadata:volatileMetadata:)` with different
  metadata types for the same domain **crashes**; an empty label is a fatal
  error; use `nil` to clear.
- Rate-limited: call at "human-interaction timescales" only.
- Only stable metadata reaches MetricKit; unique-state limits exist and
  `environment.hasExceededStateLimit` flags overflow.
- Instruments shows transitions in Points of Interest — validate there first
  ([WWDC26 222](https://developer.apple.com/videos/play/wwdc2026/222/)).

Doc bug: the sample
[Track performance by app state](https://developer.apple.com/documentation/metrickit/track-performance-by-app-state-using-metrickit)
calls `MetricManager.stateReporter(for:stableMetadata:)`. **That symbol is not in
the iOS 27.0 SDK** (`grep` of every framework `.swiftinterface`); the real entry
point is `StateReporter.reporter(for:…)` in `StateReporting.swiftinterface:66`.

Natural domain for PoliVerse: the selected tab in `NewRootView`
(`PoliVerse/NewUI/NewRootView.swift`), labels `today`, `courses`, `career`,
`search` — a small fixed set, exactly what Apple recommends. Taken from
`NewDestination.Tab.allCases` rather than written out, so the labels cannot
drift from the tabs on screen. They did once: the set was the five tabs of the
previous interface, kept after that interface stopped being the one students
see, and every report was filtered out in silence.

### 1.9 Extensions and widgets

- Metric reports: "metric data isn't available for app extensions"; states
  emitted in an extension don't appear in a `MetricReport`
  ([Getting started with StateReporting](https://developer.apple.com/documentation/statereporting/getting-started-with-statereporting)).
- Diagnostic reports: extension state can appear in them, and "the system
  delivers diagnostic reports to the main app, not the extension itself". The
  extension must create its own `MetricManager` with its domains
  (same source). **[iOS 27]**
- `MemoryExceptionDiagnostic` explicitly covers extensions
  ([MemoryExceptionDiagnostic](https://developer.apple.com/documentation/metrickit/memoryexceptiondiagnostic)),
  relevant because extensions have "a much lower per-process memory limit"
  ([jetsam event reports](https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports)).
- Whether the legacy `MXMetricManager` delivers anything about widget
  extensions to the host app on iOS 26: not documented. **[unverified]**

So: the widget extension should not subscribe on iOS 26; on iOS 27 it only needs
a `MetricManager` if it reports states. The app's collector will receive
diagnostics that mention it.

### 1.10 Privacy and upload

- MetricKit data is aggregated on device and has no user identifier in the
  documented fields; diagnostic environments do include `pid`, device type,
  region format and app build
  ([DiagnosticReport.Environment](https://developer.apple.com/documentation/metrickit/diagnosticreport/environment-swift.struct)).
  Call stacks are addresses, not data.
- Organizer's hang reports come only from "users who consent to share data with
  app developers"
  ([Analyzing responsiveness issues](https://developer.apple.com/documentation/xcode/analyzing-responsiveness-issues-in-your-shipping-app)).
  Whether MetricKit **delivery to the app** is gated by the same setting is not
  stated in any Apple document found. Secondary sources claim it is not.
  **[unverified]**
- Uploading is the app's decision and the app's disclosure. `data-freshness.md`
  and `LaunchMetrics.swift:52-56` record the current position: no analytics
  backend. Nothing below changes that without a decision.

Options, cheapest first:

| Option | Backend | Cost to the student | Notes |
| --- | --- | --- | --- |
| Keep on device, view in a DEBUG screen, pull via Xcode (Devices → Download Container) | none | none | right default for this app |
| Opt-in "Send diagnostics" share sheet (`ShareLink` of the JSON files) | none (mail/Files) | explicit action | keeps a human in the loop |
| App Store Connect API `perfPowerMetrics` + `diagnosticSignatures` | Apple | none | aggregated, consenting users only; scriptable from a Mac ([docs](https://developer.apple.com/documentation/appstoreconnectapi/power-and-performance-metrics-and-logs)) |
| CloudKit private database | Apple | user's iCloud quota | data stays in the student's account; developer can't see it — useful only for sync, not analysis **[judgement]** |
| Self-hosted endpoint | ours | privacy label + consent | only if the other options prove insufficient |

### 1.11 Testing

- Xcode: **Debug → Simulate MetricKit Payloads**. Simulated reports "contain
  sample data, not actual data from your app, for all domains registered"
  ([Monitoring app performance](https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit)).
- Real reports need a device; "MetricKit doesn't deliver reports on simulated
  devices"
  ([sample](https://developer.apple.com/documentation/metrickit/track-performance-by-app-state-using-metrickit)).
- Unit-test the handling, not MetricKit: legacy payload classes can't be
  constructed with data **[unverified]**, but new-API reports are `Codable`, so
  a saved simulated JSON can be decoded as a fixture. Persist one simulated
  report per type and keep it under `PoliVerseTests/Fixtures/`.

### 1.12 Recommended architecture (Swift 6, strict concurrency)

```
PoliVerseApp.init()
  └─ PerformanceMonitor.start()                     @MainActor, cheap, once
       ├─ iOS 27: MetricsStream (final class, holds MetricManager)
       │     Task.detached(priority: .utility) { for await r in manager.metricReports { await archive.store(r) } }
       │     Task.detached(priority: .utility) { for await r in manager.diagnosticReports { await archive.store(r) } }
       └─ iOS 26: LegacySubscriber (nonisolated final class: NSObject, MXMetricManagerSubscriber)
             didReceive → Task { await archive.store(json:kind:) }
ReportArchive (actor)
  ├─ encodes (JSONEncoder, off main), writes one file per report
  ├─ Application Support/MetricKit/, excluded from backup, not the app group
  ├─ caps: N files / M bytes, oldest deleted first
  └─ summary() → small Sendable struct for a DEBUG screen and os_log
PerfSignpost (nonisolated enum)
  ├─ OSSignposter(subsystem:…, category: .pointsOfInterest) — Instruments
  └─ mxSignpost on the MetricKit handle — field metrics, a short fixed list
```

Why each choice:

- **Detached, low priority consumers.** Reports are `Sendable`, and encoding a
  day's report is work the UI does not need. WWDC26 222 suggests "a detached
  task or a dedicated service class".
- **An actor for the archive** serialises writes without a lock, the same
  pattern as `ResourceLoader`.
- **Legacy subscriber stays `nonisolated`** and does nothing but hand the JSON
  `Data` (a `Sendable` value) to the actor — the crash recorded in
  `LaunchMetrics.swift:58-61` cannot recur.
- **Application Support, not the app group.** The widget has no use for the
  reports, and `OfflineStore` is the student's data; mixing the two would make
  `Session`'s sign-out wipe (`Session.swift:312`) delete diagnostics or, worse,
  make diagnostics look like account data.
- **Write once per report, not atomically on every change.** Atomic writes cost
  extra writes ([Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes));
  a report file is written once and never updated, so `.atomic` is fine *here*.

---

## 2. The rest of Apple's tooling

| Tool | Answers | Notes for this project | Source |
| --- | --- | --- | --- |
| Xcode Organizer | field trends: launch, hangs, hitches, memory, disk writes, battery, storage | Xcode 27 adds an **Insights** overview, **Metric Goals** (similar apps + own history), a **Storage** pane (Documents & Data vs App Size), a **Hitches** metric beyond scrolling, and "Generate Recommendations" from reports **[Xcode 27]** | [Xcode updates](https://developer.apple.com/documentation/updates/xcode), [WWDC26 258](https://developer.apple.com/videos/play/wwdc2026/258/), [storage metrics](https://developer.apple.com/documentation/xcode/monitoring-your-app-s-storage-metrics) |
| App Store Connect API | same data, scriptable; diagnostic signatures and logs; AI `DiagnosticInsight` | no app changes needed | [Power and performance metrics](https://developer.apple.com/documentation/appstoreconnectapi/power-and-performance-metrics-and-logs) |
| Instruments: Time Profiler / CPU Profiler | busy main thread | Instruments 27: Flame Graph, **Top Functions**, **Run Comparison** between traces **[Xcode 27]** | [WWDC26 268](https://developer.apple.com/videos/play/wwdc2026/268/), [call tree views](https://developer.apple.com/documentation/xcode/analyzing-cpu-profiles-with-call-tree-views) |
| Instruments: Hangs | hangs over a configurable threshold, synchronous and async | included in Time Profiler, CPU Profiler, Hitches templates | [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness) |
| Instruments: **Swift Executors** / Swift Concurrency | which tasks sit on the main actor | new executor tracks in Instruments 27 **[Xcode 27]** — the tool to confirm the hotspots in 3.3 | [WWDC26 268](https://developer.apple.com/videos/play/wwdc2026/268/) |
| Instruments: System Trace | blocked main thread (I/O, locks, IPC) | Inspector shows syscall arguments and on/off-core time | same |
| Instruments: SwiftUI | long view bodies (orange > 500 µs, red > 1 ms), unnecessary updates, Cause & Effect graph | Instruments 26+ | [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance), [WWDC25 306](https://developer.apple.com/videos/play/wwdc2025/306/) |
| Instruments: App Launch | time profile + thread states over launch | life-cycle table is empty on the simulator, as `lazy-loading.md` found; use a device | [Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time) |
| Instruments: Allocations / Leaks / VM Tracker | heap growth, transient allocations | — | [Analyze heap memory, WWDC24](https://developer.apple.com/videos/play/wwdc2024/10173/) |
| Instruments: Network | request timing, connection reuse | — | — |
| Instruments: Power Profiler, CPU Counters | energy, micro-architecture | Xcode 26 | [Xcode updates](https://developer.apple.com/documentation/updates/xcode) |
| Processor Trace | every instruction, no sampling bias | needs A18 iPhone / M4; keep traces to seconds | [WWDC25 308](https://developer.apple.com/videos/play/wwdc2025/308/) |
| `OSSignposter` + `.pointsOfInterest` | named intervals on every trace | also becomes `signpostData` in diagnostics | [OSSignposter](https://developer.apple.com/documentation/os/ossignposter), [WWDC26 268](https://developer.apple.com/videos/play/wwdc2026/268/) |
| Thread Performance Checker | priority inversions, non-UI work on main | on by default for Run; disable when profiling; `PERFC_SUPPRESSION_FILE` | [Diagnosing performance issues early](https://developer.apple.com/documentation/xcode/diagnosing-performance-issues-early) |
| On-device Hang Detection | hangs in dev and TestFlight builds, no Xcode | Settings → Developer → Hang Detection; threshold ≥ 250 ms | [WWDC22 10082](https://developer.apple.com/videos/play/wwdc2022/10082/) |
| XCTest `XCTApplicationLaunchMetric` | launch incl. extended launch tasks | needs a UI test target — the project has none | [docs](https://developer.apple.com/documentation/xctest/xctapplicationlaunchmetric) |
| XCTest `XCTOSSignpostMetric(subsystem:category:name:)` | duration of a named signpost; also `scrollingAndDecelerationMetric`, `navigationTransitionMetric` | pairs with the signposts in 1.12 | [docs](https://developer.apple.com/documentation/xctest/xctossignpostmetric) |
| XCTest `XCTHitchMetric(application:)` | hitches in a UI test | **[iOS 26]** — usable with this deployment target | [docs](https://developer.apple.com/documentation/xctest/xcthitchmetric) |
| `measure(_:)` baselines | main-thread code budget | 100 ms for discrete interactions, ~5 ms for per-row code | [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness) |

Thresholds to design against, all from Apple:

| Interaction | Budget | Source |
| --- | --- | --- |
| Discrete (tap → update) | < 100 ms total, assume under half for our main-thread work | [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness) |
| Continuous (scroll, animation) | < 1 refresh interval (8.3 / 16.7 ms); aim < 5 ms of main-thread work | same |
| Tool reporting | 250 ms "micro hang", 500 ms+ "proper hang" | [Analyze hangs with Instruments, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10248/) |
| Hang backtrace capture in the field | main thread unresponsive ≥ 1 s | [Analyzing responsiveness issues](https://developer.apple.com/documentation/xcode/analyzing-responsiveness-issues-in-your-shipping-app) |
| Launch | first frame within 400 ms, ~300 ms of it ours | [Optimizing App Launch, WWDC19](https://developer.apple.com/videos/play/wwdc2019/423/) |

Always profile a Release build on a device
([WWDC26 268](https://developer.apple.com/videos/play/wwdc2026/268/),
[WWDC19 423](https://developer.apple.com/videos/play/wwdc2019/423/)).

---

## 3. Playbook, grounded in this code

### 3.1 Launch

What Apple says, compressed from
[Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time),
[WWDC19 423](https://developer.apple.com/videos/play/wwdc2019/423/),
[WWDC22 110362](https://developer.apple.com/videos/play/wwdc2022/110362/),
[WWDC23 10268](https://developer.apple.com/videos/play/wwdc2023/10268/):

- Fewer dynamic frameworks; built-in frameworks cost much less (shared cache).
  Mergeable libraries give static-link launch cost in Release while keeping
  dynamic linking in Debug (Xcode 15+).
- No static initializers (`+load`, C++ constructors,
  `__attribute__((constructor))`).
- Do only what the first frame needs; show stale data while refreshing;
  initialise non-view functionality on first use.
- Keep the first view hierarchy simple.
- Track post-first-frame work with signposts (and now extended launch).
- iOS 16+ precomputes Swift protocol conformance checks in the dyld closure
  ([WWDC22 110363](https://developer.apple.com/videos/play/wwdc2022/110363/)) —
  free with our target.

Where PoliVerse stands (from `lazy-loading.md`, measured 2026-09-12): no
third-party frameworks, `MERGED_BINARY_TYPE = none` is correct because there is
nothing to merge, Keychain read already deferred, JSON caches cleared by
measurement. Remaining launch items:

| Item | Where | Action |
| --- | --- | --- |
| `PoliVerseApp.init()` builds ~20 services eagerly | `PoliVerse/App/PoliVerseApp.swift:33-117` | measure first; only services with I/O in `init` matter. The State-macro change below may already help |
| `@State` holding `@Observable` classes | same file | **[iOS 27 SDK]** "classes initialized and stored using State properties are now lazy … only initialized once", back-deployed to iOS 17 ([What's new in SwiftUI, WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/)). Here the values are assigned in `App.init`, which runs once anyway, so expect no launch change; building with Xcode 27 may surface the new "use before initialization" error if a default is also given |
| Metric subscription deferred to `.task` | `PoliVerseApp.swift:166` | move into `init` (1.2) |
| `LaunchMetrics.measure` never called | `PoliVerse/Model/Diagnostics/LaunchMetrics.swift:36` | wrap `session.restore()` and first cached render, or delete |
| No field number for the real "ready" moment | `RootView.swift:25` | extended launch around `session.restore()` (1.7) |

No new public launch API exists in iOS 27 beyond MetricKit's measurement, which
agrees with the SwiftUI interface search in `lazy-loading.md`.

### 3.2 SwiftUI rendering

Apple guidance:

- Keep `body` cheap: no formatter creation, filtering, sorting or string work;
  precompute in the model
  ([WWDC25 306](https://developer.apple.com/videos/play/wwdc2025/306/),
  [Demystify SwiftUI performance, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10160/)).
- Scope dependencies: `@Observable` tracks what `body` reads, including
  indirectly — reading a whole array in each row makes every row update when
  one element changes; give rows granular models (WWDC25 306).
- In `List`/lazy stacks, each `ForEach` element should resolve to a **constant
  number of views**; conditional content or `AnyView` forces building all rows
  to learn identities. Filter at the data level (WWDC23 10160;
  [Dive into lazy stacks and scrolling, WWDC26](https://developer.apple.com/videos/play/wwdc2026/321/)).
- Lazy stacks prefetch: set a row up in `init` rather than in `onAppear`, don't
  change row layout after appearing, don't rely on absolute content offset,
  keep durable state out of row `@State` (WWDC26 321).
- Existential-heavy hot paths (`any P`) showed up as
  `swift_project_boxed_opaque_existential` in Top Functions; generics or
  concrete types fixed it ([WWDC26 268](https://developer.apple.com/videos/play/wwdc2026/268/),
  [Explore Swift performance, WWDC24](https://developer.apple.com/videos/play/wwdc2024/10217/)).
- **[iOS 27]** `AsyncImage` honours HTTP caching by default and accepts a custom
  session via `asyncImageURLSession` (WWDC26 269). `ContentBuilder` unifies
  builders and speeds type checking for any deployment target when building
  with Xcode 27 (same session) — a build-time, not runtime, win.

PoliVerse findings (static reading; confirm with the SwiftUI instrument):

| Finding | Where | Why it matters | Fix |
| --- | --- | --- | --- |
| Week strip filters and sorts the day's events **per day, per body evaluation** | `PoliVerse/Features/Calendar/CalendarView.swift:119` calls `agenda.events(on:)` which filters + sorts all events (`PoliVerse/Model/Timetable/AgendaService.swift:199-204`) | 7 × O(n log n) on the main thread each time the view updates | use `daysWithEvents()` (`AgendaService.swift:208`) once, or cache a `[Date: [AgendaEvent]]` in `AgendaService` when `events` changes |
| `dayEvents` recomputed in body the same way | `CalendarView.swift:36`, `HomeView.swift:33` | same | same cache |
| `AnyView` | none found | — | keep it that way |
| Lazy containers | `HomeView.swift:39`, `CalendarView.swift:168` use `LazyVStack`; 52 `ScrollView`/`List` sites vs 4 lazy stacks | eager `VStack` inside long `ScrollView`s builds every row | audit the long lists (`NewsView`, `NoticesView`, `ExamUpdatesView`, `CourseDetailView`) with the SwiftUI instrument before changing |

### 3.3 Main thread and Swift concurrency

The rule has changed under this project's settings, and Apple's older article
predates it.

- [Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
  says nonisolated async functions run on the thread pool "beginning with
  Swift 5.7".
- [SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md)
  (implemented Swift 6.2, flag `NonisolatedNonsendingByDefault`) makes them
  **run on the caller's actor**; `@concurrent` is the explicit way off.
- `SWIFT_APPROACHABLE_CONCURRENCY` enables `NonisolatedNonsendingByDefault`
  ([Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference)),
  and this project sets it (`project.pbxproj`, both configs).
- WWDC25: with main-actor-by-default, move decoding off with `@concurrent`;
  plain `nonisolated` "will stay on the main actor" when called from it
  ([Embracing Swift concurrency](https://developer.apple.com/videos/play/wwdc2025/268/)).
- WWDC26 shows the fix for a main-actor thumbnail hang as `@concurrent`, and a
  synchronous `data.write` on the main thread as the blocked-thread example
  ([WWDC26 268](https://developer.apple.com/videos/play/wwdc2026/268/)).

Hotspots that follow from that. Each is **[unverified until traced]** with the
Swift Executors and System Trace instruments; the reasoning is solid, the cost
is unmeasured.

| # | Finding | Where | Fix |
| --- | --- | --- | --- |
| H1 | `PoliMiAPI` is a `nonisolated final class`; `send(_:as:)` decodes JSON after `await session.data(for:)`. Called from `@MainActor` services, the decode runs on the main actor | `PoliVerse/Model/Support/PoliMiAPI.swift:176-190` | mark the decoding helper `@concurrent`, or make `send` `@concurrent` (its arguments and result are `Sendable`) |
| H2 | Services decode again themselves on the main actor | `NewsService.swift:84`, `NoticeService.swift:84,115`, `CareerService.swift:269,287`, `CareersService.swift:56`, `RoomsService.swift:137`, `RoomFacilitiesService.swift:106`, `FreeRoomsService.swift:350`, `CampusMapService.swift:136`, `WeBeepAPI.swift:72,79`, `ServiceDirectory.swift:220,268` | a `@concurrent static func decode<T: Decodable & Sendable>` helper next to `PoliMiAPI` |
| H3 | Every payload is parsed **a second time** just to log its shape, at `.notice` | `JSONShape.describe(data)` at 6 sites, e.g. `NewsService.swift:82`, `CareerService.swift:268,286` | wrap in `#if DEBUG`, or log at `.debug`. Whether OSLog skips evaluating a `.notice` argument is not documented; notice is persisted, so assume it runs **[unverified]** |
| H4 | `OfflineStore.save` encodes and writes `.atomic` synchronously; its callers are main-actor services | `Shared/OfflineStore.swift:110-118`; callers `AgendaService.swift:118`, `CareerService.swift:228,257`, `CourseService.swift:109,129`, `NewsService.swift:93`, `NoticeService.swift:92`, `WeBeepService.swift:367`, `FreeRoomsService.swift:281`, `UpdateFeed.swift:60,186`, `ActionQueue.swift:158` | give `OfflineStore` an async `@concurrent` save (the type is already `Sendable`), or route writes through an actor that coalesces repeated saves of the same slot |
| H5 | `ISO8601DateFormatter()` allocated twice **per parsed value** | `PoliVerse/Model/Updates/Notice.swift:137-138` | `static let` formatters, as `PoliMiDate` already does (`Shared/AgendaEvent.swift:201-216`); or `Date.ISO8601FormatStyle` |
| H6 | `NSRegularExpression` compiled on every call | `PoliVerse/Model/Support/HTMLScraper.swift:103,112`, `HTMLText.swift:276`, `ResultsFileReader.swift:121` | cache compiled patterns per pattern string (the type is `nonisolated`, so a `Mutex`-guarded dictionary or static lets) |
| H7 | `OfflineStore.url(…)` runs a regex replacement on the account for every read and write | `Shared/OfflineStore.swift:101-104` | compute the sanitised account once per store/slot |
| H8 | Widget reload after every service save, all kinds | `AgendaService.swift:122`, `CareerService.swift:258`, `FreeRoomsService.swift:284` — `reloadAllTimelines()` | see 3.7 |

H1–H4 sit on every screen's load path, which is why they come first.

### 3.4 Networking

- Modern protocols cut round trips: IPv6, TLS 1.3, HTTP/3 are used
  automatically by `URLSession` once the server supports them; HTTP/3 has been
  on by default since iOS 15 and is used only after the server advertises it
  (`Alt-Svc`)
  ([Reduce networking delays, WWDC22](https://developer.apple.com/videos/play/wwdc2022/10078/),
  [Accelerate networking with HTTP/3 and QUIC, WWDC21](https://developer.apple.com/videos/play/wwdc2021/10094/)).
  Whether Politecnico hosts advertise HTTP/3 is a server fact — check the
  headers the way `data-freshness.md` did. Nothing to change client-side.
- Wi-Fi ↔ cellular stalls: `multipathServiceType = .handover` on the session
  configuration (WWDC22 10078). Requires the Multipath entitlement
  **[unverified for this app]**; worth it only if the students' walk between
  buildings shows up as timeouts.
- `URLSessionConfiguration.urlCache` defaults to the shared cache for default
  sessions ([urlCache](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/urlcache)).
  `data-freshness.md` measured that the JSON APIs send no validators, so HTTP
  caching buys nothing there; the app's own `OfflineStore` is the cache.
- PoliVerse today: `PoliMiAPI` uses `URLSession.shared` (`PoliMiAPI.swift:139`),
  `ManifestiService` builds its own session with `returnCacheDataElseLoad`
  (`ManifestiService.swift:49-54`, deliberately separate cookie jar). Coalescing
  and prefetch already exist (`ResourceLoader`, `lazy-loading.md`). No change
  recommended until the Network instrument shows connection setup dominating.
- Widgets: network requests are possible but the extension "may not have
  enough time"; use background sessions if ever needed
  ([Making network requests in a widget extension](https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension)).
  PoliVerse's widgets read the shared container only (`WidgetAgenda.swift:5-8`),
  which is the cheaper design — keep it.

### 3.5 Disk I/O and write exceptions

From [Reducing disk writes](https://developer.apple.com/documentation/xcode/reducing-disk-writes):
batch writes; separate frequently changing from static data; "use atomic writes
only when needed" because they add a temp file, unlink and rename; prefer
SwiftData/Core Data/SQLite (WAL) for frequently edited data.

For PoliVerse: every `OfflineStore.save` rewrites a whole JSON file atomically
(`OfflineStore.swift:114`), and `FreshnessCoordinator` now revalidates on every
foregrounding. Unchanged data is rewritten anyway. Cheap wins, in order:

1. Skip the write when the encoded bytes equal what was last written for that
   slot (hash in memory).
2. Move the write off the main actor (H4).
3. Only then consider whether `.atomic` is needed per slot — for the widget's
   files it is (a torn read would show garbage), for logs like `UpdateFeed`
   maybe not.

`logicalDiskWrites` and `diskWriteException` from 1.3/1.4 are the before/after
numbers.

### 3.6 Memory and jetsam

- Peak memory and memory at suspension are the two field metrics; a larger
  suspended footprint makes the app a likelier jetsam victim
  ([Reducing your app's memory use](https://developer.apple.com/documentation/xcode/reducing-your-app-s-memory-use)).
- Extensions have a much lower limit
  ([jetsam event reports](https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports));
  **[iOS 27]** `MemoryExceptionDiagnostic` now reports it.
- PoliVerse: `ResourceLoader` caches are LRU-bounded (`capacity: 64/128`,
  `ManifestiService.swift:58,67`) — good. `WKWebsiteDataStore` is persistent by
  design (`lazy-loading.md`). Watch `FreeRoomsWidget` and `TodayWidget`, which
  decode whole cached files on each timeline (`WidgetAgenda.swift:20-25`); fine
  at today's sizes.

### 3.7 Energy, widgets and background work

- WidgetKit budget: typically 40–70 reloads a day for a frequently viewed
  widget; entries at least ~5 minutes apart; reloads while the app is in the
  foreground don't count
  ([Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)).
  **[iOS 27 guidance]** "frequent reloads while your app is in the foreground
  might be throttled", and "a final call to reload when your app enters the
  background is usually a good idea"
  ([WidgetKit foundations, WWDC26](https://developer.apple.com/videos/play/wwdc2026/277/)).
- PoliVerse calls `reloadAllTimelines()` from three services
  (`AgendaService.swift:122`, `CareerService.swift:258`,
  `FreeRoomsService.swift:284`); a foreground revalidation can fire all three
  within seconds, each reloading every widget kind. Replace with
  `reloadTimelines(ofKind:)` for the affected kinds, coalesced, plus one reload
  when `scenePhase` becomes `.background` (`PoliVerseApp.swift:171`). Background
  refresh runs (`PoliVerseApp.swift:103-116`) still need their reload, since the
  app is not foreground then.
- Existing timelines already follow the guidance: `.after` at real boundaries
  (`data-freshness.md`).
- Background: one `BGAppRefreshTask` with a ~30 s budget, deliberately narrow
  (`BackgroundRefresh.swift`). `BGContinuedProcessingTask` **[iOS 26]** shows a
  Live Activity with progress and is for user-initiated work
  ([BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)) —
  already rejected for prefetching in `lazy-loading.md`. `MetricKit`'s
  `backgroundTermination` with `CrashDiagnostic.TerminationCategory.taskTimeout`
  will say if the refresh overruns.
- Energy: audit frame rates, limit background time, defer discretionary work;
  dark content saves power on OLED
  ([Power down, WWDC22](https://developer.apple.com/videos/play/wwdc2022/10083/)).
  No custom `CADisplayLink` or location use found in the app.

### 3.8 Binary size and build settings

Measured with `xcodebuild -showBuildSettings -configuration Release`:

| Setting | App | Widgets | Verdict |
| --- | --- | --- | --- |
| `SWIFT_OPTIMIZATION_LEVEL` | unset → Xcode default **`-O`** (`Swift.xcspec`, `DefaultValue = "-O"`) | same | right for an app; `-Osize` trades speed for size and this binary has no size problem on record |
| `SWIFT_COMPILATION_MODE` | `wholemodule` | `wholemodule` | right |
| `DEAD_CODE_STRIPPING` | `YES` | — | right |
| `STRIP_INSTALLED_PRODUCT` / `STRIP_SWIFT_SYMBOLS` | `YES` / `YES` | — | right; keep dSYMs for symbolication (1.5) |
| `LLVM_LTO` | unset (no LTO) | — | affects C/ObjC only; there is none in this target — leave off **[judgement]** |
| `MERGED_BINARY_TYPE` | `none` | — | nothing to merge |
| `ENABLE_TESTABILITY` | `NO` in Release | — | right |

Sources: [Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference),
[Configuring mergeable libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries).
New optimiser controls for hot code, only after a profile points at them:
`@inline(always)` ([SE-0496](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0496-inline-always.md),
Swift 6.3) and `@specialized` ([SE-0460](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0460-specialized.md),
Swift 6.3); `Span`/borrowing accessors for copy-heavy code
([What's new in Swift, WWDC26](https://developer.apple.com/videos/play/wwdc2026/262/)).
None is warranted by anything measured so far.

Organizer's new Storage pane splits App Size from Documents & Data and flags
cache-folder growth **[Xcode 27]**
([Monitoring your app's storage metrics](https://developer.apple.com/documentation/xcode/monitoring-your-app-s-storage-metrics)).
The `WKWebsiteDataStore` disk cache (13.7 MB of SPA, `lazy-loading.md`) will
show up there; that is expected, not a regression.

---

## 4. Implementation plan

Order: **measure → collect → fix the main thread → guard against regressions**.
Each phase lists what to measure before and after so a change is never
celebrated on a guess (the rule `lazy-loading.md` was written around).

### Phase 0 — baseline (half a day, no code)

1. Release build on a physical iPhone (oldest supported device available).
   Instruments **App Launch** × 5 cold launches (force-quit between); record
   median time to first frame and time until Home shows cached lectures.
2. Instruments **Time Profiler + Swift Executors + Hangs** while: cold launch →
   Home → Calendar week swipe → News → Notices → background → foreground (the
   `FreshnessCoordinator` path). Save the `.trace`; it is the Run Comparison
   baseline for Phase 2.
3. **System Trace** over one foreground revalidation, to confirm or clear H4.
4. **SwiftUI** template while swiping the Calendar week strip.
5. Organizer: note current hang rate, launch, disk writes, Storage for 2.0.
6. Enable Settings → Developer → Hang Detection on the test phone.

### Phase 1 — full MetricKit collection (ship first)

Goal: every metric and diagnostic MetricKit offers is received on both iOS 26
and iOS 27, persisted on device, visible in the log and in a DEBUG screen, and
nothing leaves the device.

**Constraints**

- Deployment target stays **iOS 26.0**. Every `MetricManager`, `MetricReport`,
  `DiagnosticReport`, `LaunchTaskID`, `StateReporting` symbol goes behind
  `@available(iOS 27, *)` / `if #available(iOS 27, *)`.
- Exactly one manager per process: legacy on iOS 26, new on iOS 27.
- No subscription in the widget extension in this phase.
- No `Info.plist` or entitlement changes; no upload.

**Step 1.1 — `PoliVerse/Model/Diagnostics/ReportArchive.swift` (new)**

```swift
import Foundation
import OSLog

/// On-device store for MetricKit reports. One file per report, never updated.
actor ReportArchive {
    enum Kind: String, Sendable { case metric, diagnostic }

    struct Summary: Sendable {
        let metricCount: Int
        let diagnosticCount: Int
        let latest: Date?
    }

    static let shared = ReportArchive()

    private let directory: URL
    private let maxFiles: Int
    private let maxBytes: Int
    private let log = Logger(subsystem: "segrini.samuele.PoliVerse", category: "metrics")

    init(directory: URL? = nil, maxFiles: Int = 60, maxBytes: Int = 5_000_000) { … }

    /// iOS 26 path: `payload.jsonRepresentation()`.
    func store(json: Data, kind: Kind, receivedAt: Date = .now) { … }

    /// iOS 27 path. Encoding happens here, off the main actor.
    @available(iOS 27, *)
    func store(_ report: MetricReport) { … }      // JSONEncoder, .byStateReportingDomain
    @available(iOS 27, *)
    func store(_ report: DiagnosticReport) { … }

    func summary() -> Summary { … }
    func files() -> [URL] { … }                    // for the DEBUG screen / ShareLink
    func prune() { … }                             // oldest first until under both caps
}
```

Details that matter:

- Directory: `applicationSupportDirectory/MetricKit/`, created on first write,
  `URLResourceValues.isExcludedFromBackup = true`.
- File name: `<ISO8601 received>-<kind>-<short UUID>.json`, so sorting by name
  sorts by time and `prune()` needs no metadata reads.
- One `.notice` log line per report with kind, byte size and, for diagnostics,
  the case name (`crash`/`hang`/…) — never the payload.
- `DiagnosticReport` case name on iOS 27: switch over `report.result` with
  `@unknown default` (Apple's docs require it for forward compatibility).
- Import `MetricKit` in this file only for the `@available(iOS 27, *)` overloads.

Test: `PoliVerseTests/ReportArchiveTests.swift` — temp directory, store 70
small JSON blobs, assert 60 remain and the oldest were removed; assert the byte
cap; assert `summary()` counts. Same style as `CachedSlotTests.swift`.

**Step 1.2 — `PoliVerse/Model/Diagnostics/PerformanceMonitor.swift` (new; replaces `LaunchMetrics.swift`)**

```swift
import MetricKit
import OSLog

@MainActor
enum PerformanceMonitor {
    static var isPrewarmed: Bool { ProcessInfo.processInfo.environment["ActivePrewarm"] == "1" }

    /// Call from `PoliVerseApp.init()`. Idempotent.
    static func start() {
        guard !started else { return }; started = true
        if #available(iOS 27, *) { ModernStream.shared.start() }
        else { MXMetricManager.shared.add(LegacySubscriber.shared) }
    }
    private static var started = false
}

@available(iOS 27, *)
final class ModernStream: Sendable {
    static let shared = ModernStream()
    let manager = MetricManager()            // held for the process lifetime

    func start() {
        let manager = manager
        Task.detached(priority: .utility) {
            for await report in manager.metricReports { await ReportArchive.shared.store(report) }
        }
        Task.detached(priority: .utility) {
            for await report in manager.diagnosticReports { await ReportArchive.shared.store(report) }
        }
    }
}

nonisolated final class LegacySubscriber: NSObject, MXMetricManagerSubscriber, Sendable {
    static let shared = LegacySubscriber()
    func didReceive(_ payloads: [MXMetricPayload]) {
        for p in payloads { let json = p.jsonRepresentation(); Task { await ReportArchive.shared.store(json: json, kind: .metric) } }
    }
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for p in payloads { let json = p.jsonRepresentation(); Task { await ReportArchive.shared.store(json: json, kind: .diagnostic) } }
    }
}
```

- `MetricManager` is declared `@unchecked Sendable` in the SDK
  (`MetricKit.swiftinterface:1184`), so capturing it in detached tasks is legal.
- `jsonRepresentation()` is called inside the callback, on MetricKit's queue;
  only `Data` crosses into the actor. Whether `MXMetricPayload` is `Sendable`
  under Swift 6 is not something to rely on. **[unverified]**
- Keep the existing launch-histogram log lines (they are useful in Console) by
  moving the body of `LaunchMetricCollector.didReceive` into `LegacySubscriber`
  after the archive call; on iOS 27 log `timeToFirstDraw` /
  `optimizedTimeToFirstDraw` / `extendedLaunch` bucket counts from
  `report.intervalEntries.fullDayEntry`.
- Delete `PoliVerse/Model/Diagnostics/LaunchMetrics.swift` once its content has moved;
  its doc comment's history belongs at the top of the new file.

**Step 1.3 — wire it in `PoliVerse/App/PoliVerseApp.swift`**

- Call `PerformanceMonitor.start()` at the top of `init()` (line 33), before
  services are built.
- Remove `LaunchMetrics.start()` from the `.task` at line 166 and the comment
  above it.

**Step 1.4 — extended launch around session restore**

In `PoliVerse/App/RootView.swift:25`, wrap `await session.restore()`:

```swift
if #available(iOS 27, *) {
    await ModernStream.shared.manager.trackLaunchTask(
        id: "session-restore",
        onTrackingError: { error in Logger(…).notice("launch task: \(String(describing: error.reason), privacy: .public)") }
    ) { await session.restore() }
} else {
    let id = MXLaunchTaskID("session-restore")   // verify spelling against the header before use
    try? MXMetricManager.extendLaunchMeasurement(forTaskID: id)
    await session.restore()
    try? MXMetricManager.finishExtendedLaunchMeasurement(forTaskID: id)
}
```

- `trackLaunchTask` is `@MainActor`; `RootView`'s `.task` already is.
- Legacy rule: must start before the first scene becomes active — a `.task` on
  the root view may already be too late. If the legacy call throws, log it and
  leave it; don't move work earlier to satisfy a metric. The exact Swift
  spelling of `MXLaunchTaskID` construction is **[unverified]**: check
  `MXMetricManager.h` before writing it.

**Step 1.5 — signposts: `PoliVerse/Model/Diagnostics/PerfSignpost.swift` (new)**

```swift
nonisolated enum PerfSignpost {
    static let poi = OSSignposter(subsystem: "segrini.samuele.PoliVerse", category: .pointsOfInterest)
    static let metricLog: OSLog = {
        if #available(iOS 27, *) { MetricManager.logHandle(category: "PoliVerse") }
        else { MXMetricManager.makeLogHandle(category: "PoliVerse") }
    }()

    static func interval<T>(_ name: StaticString, _ work: () async throws -> T) async rethrows -> T {
        let state = poi.beginInterval(name, id: poi.makeSignpostID())
        mxSignpost(.begin, log: metricLog, name: name)
        defer { mxSignpost(.end, log: metricLog, name: name); poi.endInterval(name, state) }
        return try await work()
    }
}
```

Fixed list of names, no more in this phase (Apple limits custom metrics):

| Name | Around | File |
| --- | --- | --- |
| `session.restore` | `session.restore()` | `RootView.swift:25` |
| `agenda.load` | body of `load(around:force:)` | `AgendaService.swift:66` |
| `career.load` | `load(force:)` | `CareerService.swift:148` |
| `freshness.revalidate` | `revalidate(force:)` | `FreshnessCoordinator.swift:94` |
| `background.refresh` | closure body | `PoliVerseApp.swift:103` |

Overlap check: `agenda.load` has an `isLoading` guard (`AgendaService.swift:67`),
so it cannot overlap itself; `freshness.revalidate` can be triggered by both
foregrounding and network return — verify it cannot run twice at once before
using an exclusive signpost there, or give the two triggers distinct names.

**Step 1.6 — DEBUG viewer**

`PoliVerse/Features/Auth/DiagnosticsView.swift` (new, `#if DEBUG`): list
`ReportArchive.files()` newest first with kind and size, a `ShareLink` per file,
and a "Delete all" button. Link it from wherever the notification settings
screen is reached (`NotificationSettingsView.swift`) under `#if DEBUG`. Release
builds get nothing.

**Step 1.7 — verify Phase 1**

| Check | How | Pass |
| --- | --- | --- |
| iOS 27 device, simulated payloads | Debug → Simulate MetricKit Payloads | one metric and one diagnostic file per simulation; log lines appear; no main-thread work in Time Profiler during encode |
| iOS 26 device (or iOS 26 runtime on device) | same menu | JSON files from `jsonRepresentation()` |
| No double delivery | count files per simulation on each OS | exactly one per report |
| Launch unaffected | App Launch template, 5 runs vs Phase 0 | median within noise |
| Signposts | Points of Interest lane | five named intervals, balanced |
| Fixtures | copy one simulated iOS 27 metric + diagnostic JSON into `PoliVerseTests/Fixtures/` | decode with `JSONDecoder` into `MetricReport` / `DiagnosticReport` in a test |
| Unit tests | `ReportArchiveTests` | green |

### Phase 2 — take work off the main thread (the speed phase)

Each item: Run Comparison against the Phase 0 trace, filtered to the matching
signpost.

1. **H1/H2** — `@concurrent` JSON decode helper in `PoliMiAPI.swift`; switch the
   listed services to it. Measure: Swift Executors main-actor track during
   `agenda.load`, `career.load`.
2. **H3** — `JSONShape.describe` behind `#if DEBUG`. Measure: CPU in those
   intervals.
3. **H4 + 3.5** — async `OfflineStore.save` off the main actor, skip identical
   writes. Measure: System Trace shows no `write`/`rename` on the main thread
   during `freshness.revalidate`; `logicalDiskWrites` per day in the next
   MetricKit reports.
4. **H5–H7** — cached formatters and regexes, sanitised account computed once.
   Measure: Top Functions over a News/Notices load and a Manifesti page.
5. **3.2** — per-day event cache in `AgendaService`; `CalendarView` reads it.
   Measure: SwiftUI instrument, Long View Body Updates for `CalendarView` while
   swiping weeks.
6. **H8 / 3.7** — `reloadTimelines(ofKind:)` for affected kinds, coalesced,
   plus a reload on entering background. Measure: count reloads with a
   signpost per call; widget freshness unchanged on the Lock Screen.

### Phase 3 — context and regression guards

1. **[iOS 27]** `StateReporting`: domain `segrini.samuele.PoliVerse.tab`, labels = tab
   values from `NewDestination.Tab`, reported by `NewRootView` from
   `.onChange(of: shell.selection, initial: true)`. Register the domain in
   `MetricManager(enabledStateReportingDomains:)` (Step 1.2 changes from
   `MetricManager()`). Validate in Points of Interest before shipping.
   Optional second domain: data source (`live` / `offline` / `mock`) — three
   labels, useful to separate demo-mode sessions.
2. **Performance tests.** New UI test target `PoliVerseUITests` (a project
   change — decide deliberately):
   `measure(metrics: [XCTApplicationLaunchMetric()])` for cold launch;
   `XCTHitchMetric(application:)` **[iOS 26]** over a Calendar week swipe and a
   News scroll; `XCTOSSignpostMetric(subsystem: "segrini.samuele.PoliVerse",
   category: "PointsOfInterest", name: "agenda.load")` in mock-data mode for
   deterministic timing. Baselines: 100 ms for discrete actions, hitch ratio
   < 5 ms/s.
3. Unit-level `measure` on the pure hot functions: `ManifestoParser.detail`,
   `HTMLText` parsing, `PoliMiDate.parse` over a real payload fixture.
4. Thread Performance Checker stays on for Run (default); make any new warning
   a bug.

### Phase 4 — using field data

1. Weekly: Organizer Insights + Metric Goals **[Xcode 27]**; after each release,
   Regressions.
2. Optional script against the App Store Connect API (`perfPowerMetrics`,
   `diagnosticSignatures`) — aggregated, consenting users, no app change.
3. Symbolication helper script (outside the app): read a diagnostic JSON,
   compute `address − offsetIntoBinaryTextSegment` per `PoliVerse` frame, run
   `atos -i` against the archived dSYM matched by `binaryUUID`.
4. Only if on-device reports prove insufficient: decide on an opt-in upload
   (1.10). That is a privacy decision first and an engineering task second.

### What to watch, before and after

| Metric | Field source | Local source | Target |
| --- | --- | --- | --- |
| Time to first draw (cold, prewarmed apart) | `timeToFirstDraw`, `optimizedTimeToFirstDraw` | App Launch template | no regression; < 400 ms on recent devices |
| Time to usable Home | `extendedLaunch` **[iOS 27]** | `session.restore` signpost, `XCTApplicationLaunchMetric` | down after Phase 2 |
| Hang rate | `hangTime`, `.hang` diagnostics | Hangs instrument, on-device detection | no hangs ≥ 250 ms on the load paths |
| Hitch ratio | `hitchTime` (per tab in Phase 3) | `XCTHitchMetric`, SwiftUI instrument | < 5 ms/s |
| Disk writes | `logicalDiskWrites`, `.diskWriteException` | System Trace | down after 3.5 |
| Memory | `peakMemory`, `suspendedMemory`, `.memoryException` **[iOS 27]** | Allocations | no growth release to release |
| Terminations | `foregroundTermination`, `backgroundTermination`, `terminationCategory` | — | no `watchdog` / `taskTimeout` |
| Widget reloads | — | signpost per reload call | fewer per foreground session |

---

## 5. Second pass, after WWDC26 (2026-09-28)

Phases 1 and 2 above had landed: `PerformanceMonitor` on the new
`MetricManager`, `StateReporting` by tab, `trackLaunchTask` around session
restore, `PerfSignpost`, `@concurrent` decoding, `OfflineStore` writes on a
queue, `WidgetReloader`, the per-day agenda index. The deployment target is now
iOS 27 / macOS 27 (watchOS 26), so the legacy `MXMetricManager` path described
in §1.1 was never needed and is not in the code.

This pass followed four WWDC26 sessions:
[Profile, fix, and verify (268)](https://developer.apple.com/videos/play/wwdc2026/268/),
the [SwiftUI Group Lab (8120)](https://developer.apple.com/videos/play/wwdc2026/8120/),
[Dive into lazy stacks and scrolling (321)](https://developer.apple.com/videos/play/wwdc2026/321/) and
[Meet the new MetricKit (222)](https://developer.apple.com/videos/play/wwdc2026/222/).

### 5.1 Blocked on the system: offline reads (268)

Writes had moved to a queue, but every **read** still called `flush()` — a
`DispatchQueue.sync` behind whatever encode was pending — then read and decoded
the file on the caller, which was almost always the main actor. That is the
session's third hang class: a thread waiting, not computing.

| Change | Where |
| --- | --- |
| `OfflineStore.loaded(_:as:account:)`: `@concurrent`, waits with `flushed()`, reads off the caller | `Shared/OfflineStore.swift` |
| `CachedSlot.claimRestore` / `Claim.read()` / `finish(_:with:)`: a restore split around the suspension, which drops a read overtaken by a save | same |
| Legacy-folder migration moved onto the write queue instead of running when `OfflineStore.shared` is first touched in `App.init` | same |
| Agenda, WeBeep materials, recordings (three files read together), free-rooms widget check, other careers' libretti, the Watch snapshot, App Intents and entity queries read with `loaded` | the models, `WatchSync`, `AppEntities`, `*Intent*.swift` |
| `Store` uses `loaded` instead of its own `@concurrent` wrapper | `Model/Store/Store.swift` |
| `UpdateFeed` keeps the shown account's log in memory; opening the feed and recording a pass no longer read it back | `Model/Updates/UpdateFeed.swift` |
| `PendingChanges` reads the queue asynchronously at init, on account change and on flush (every foregrounding) | `Model/Sync/PendingChanges.swift`, `ActionQueue.read` |
| Widgets use `OfflineStore.shared` instead of building a store per read | `PoliVerseWidgets/` |

Still synchronous, deliberately: sign-out's `clear(account:)`, Impostazioni's
"clear all", `PendingChanges.record` / `acknowledgeFailures` (one small file on
a tap), and the widget timeline providers (no UI thread to protect).

### 5.2 Views that recomputed on every pass (8120, 321)

The group lab's rule — `body` does no filtering, sorting or string work;
dependencies are scoped — against what the static survey found:

| Finding | Fix |
| --- | --- |
| `CurrentClass` and `TodayDigest.timetable` filtered and sorted **every** event, from `RootView` (every pass), Oggi's sections, the flavors, the Mac views | they are handed `agenda.events(on:)`, the day index |
| Course cards, Corsi rows and the course page lowercased every event's title per course to find its lessons | `AgendaModel.events(matchingCourse:)` over a title index built when `events` changes |
| `FeedItem.items` (quadratic: each sighting against every other) rebuilt for the tab badge, every course card and the updates screen, twice | `UpdateFeed.items`, `recentItems`, `recentItems(for:)`, cached until `updates` changes or the hour turns |
| A regular expression compiled per call in `Course.teachingCode`, `FeedItem.items(from:for:)`, `PartialExams` | a byte check; `RegexCache` |
| `FileDownloadModel.status(for:)` did `createDirectory` + `fileExists` for every file of the materials screen, every pass | each course folder listed once off the main actor; kept in step by download, delete and "remove all" |
| `@AppStorage` look decoded (two `JSONDecoder`s) three times per `RootView` pass | `TodayStyle(rawValue:)` remembers the last string it decoded |
| `EnrolmentOverrides.all()` decoded on every `CoursesPage` init | remembers the last bytes it decoded |
| `RichText` parsed its HTML on every pass | `HTMLText.attributed` caches by fragment |
| `ByteCountFormatter` built per call, `SubjectSymbol` folded per row | built once; chosen symbols cached by name |
| `DayStrip` rebuilt 121 dates on every scrolled day, inside a `GeometryReader` wrapping the scroll view | dates built once in `@State`; the width from `onGeometryChange` |
| Calendar week strip filtered a day into an array to test `isEmpty`; `weekDays` built twice | `contains(where:)`; the last day computed directly |

Looked at and left alone:

- **Lazy containers.** The long lists are already `List` or `LazyVStack`
  (News, Notices, the updates feed, materials, the calendar day). Corsi and the
  course page are `VStack`s of a bounded number of cards; their rows were
  expensive because of the scans above, not because they were eager.
- **Rows with a variable view count** (`if … { Divider() }`) sit inside a
  plain `VStack` card, not directly in a lazy container, so identity is not
  resolved per row.
- **`GeometryReader`** elsewhere sits in backgrounds for bars and scales, or
  lays out a whole screen from its size (`LookEditor`): the pattern the lab
  calls fine.
- **`AnyView`**: only in the DEBUG Mac snapshot hook.
- **Existentials (268).** `any Account`, `any HTTP` and the other protocol
  properties are held by models and read once per load; no view body or row
  touches one. Nothing for Top Functions to find, so nothing converted.

### 5.3 Measured

`PoliVersePerformance` on the iPhone 17 Pro simulator, Release, sample data,
`main` (e8c6453) against this pass. Launch was run as three interleaved rounds
of five, so both builds saw the same machine load.

| Test | `main` | This pass |
| --- | --- | --- |
| `testAgendaLoad`, `agenda.load` signpost | 3.3 ms mean (2.8–3.9) | **0.4 ms** mean (0.40–0.45) |
| `testLaunch`, first frame responsive, median of 15 | 3.824 s | 3.768 s — no change beyond noise |
| `testTabSwitchingCost`, CPU time per round of the four tabs | 2.460 s | 2.440 s — flat |
| `testTabSwitchingCost`, instructions retired | 12.17 G | 12.22 G — flat |

What the numbers say, and do not:

- **The first attempt regressed `agenda.load` to 894 ms.** `loaded` waited for
  the write queue with a plain `async` at the queue's utility QoS; at launch the
  wait sat behind other work for most of a second. The blocking `flush()` never
  showed this because a synchronous wait donates the caller's priority. The
  wait is now enqueued at `.userInitiated` with `.enforceQoS`. Part of the
  remaining gain is that sample data no longer reads the student's agenda copy
  at all.
- **Sample data hides most of 5.2.** It has a handful of courses and updates,
  so the per-card scans cost little either way; the tab-switch numbers are
  flat because the work removed was small *in this data set*. A real account
  with a full timetable and a term's worth of updates is where they show.
- **The hitch tests measure nothing on the simulator.** `XCTHitchMetric`
  records no samples there; the three hitch tests pass without a number. They
  need a device.
- `testCoursesScrollHitches` failed on `main` before measuring: it looked for a
  collection view, and Corsi is a scroll view of cards. It now finds the scroll
  view. `CustomizeAnimationTests` did not compile (`press(forDuration:thenDragTo:)`
  was given a coordinate), which stopped the whole UI test target building; the
  drag now starts from the sticker's coordinate.
- `ContentScreensUITests.testCareerSectionsEachShowSomething` looked for
  `segmentedControls["Sezione"]`, which iOS 27 does not expose, and never
  scrolled to the picker, which now sits below the fold. It looks for the
  Libretto and Appelli segments and scrolls to them.

### 5.4 Measured on a device

iPhone 12 Pro, iOS 27.2, Release, sample data, `main` against this pass.

| Test | `main` | This pass |
| --- | --- | --- |
| `agenda.load` signpost | 0.7 ms | 0.5 ms |
| Launch, first frame responsive (interleaved rounds) | 0.972 s | 0.955 s |
| Corsi scroll, hitch ratio | 9.6 ms/s | 8.2 ms/s |
| Oggi scroll, hitch ratio | 16.3 ms/s | 15.6 ms/s |
| Calendar week paging, hitch ratio (three runs each) | 12.5 / 16.3 / 17.0 ms/s | 13.3 / 15.1 / 19.6 ms/s |
| Tab switching, CPU time | 1.91 s | 1.94 s |

- **Launch regressed by 13 ms before it improved.** `PendingChanges` now reads
  its queue just after launch and assigned `count` and `failed` whether or not
  they changed; an `@Observable` property notifies on every assignment, so an
  empty queue that stayed empty redrew everything showing the count, inside the
  launch window. It assigns on a change only.
- **Observation was too coarse for the agenda.** Paging the calendar past the
  fetched month replaces `events`, and every view that read any day or any
  course depended on the whole index: Oggi under the calendar, the Corsi cards
  in their tab, the shell's class-now accessory. `AgendaModel` now hands out one
  small `@Observable` `Slice` per day and per course, reassigned only when its
  entries change, and the indexes themselves are not observed. A Time Profiler
  pass of the calendar paging on the simulator (Instruments attaches there,
  with `--device <simulator>`) showed Oggi's page re-evaluating on every flip
  before, and not after.
- **`TodayStyle` compared by encoding itself to JSON.** It declared `Equatable`
  without `==`, so the standard library's `RawRepresentable` `==` won over the
  synthesised one and every comparison encoded both looks. SwiftUI compares the
  look, an environment value, on every update. It now has a memberwise `==`.
- **Calendar paging was the animation.** After both fixes above the app's
  code was under 1% of the main thread while paging, and the device numbers did
  not move (`main` 10.6–12.1 ms/s, this branch 11.8–13.4). Taking the animation
  away halved them: **5.7 and 5.9 ms/s** over two runs, steady from one
  iteration to the next. Animating only the week strip was no better than
  animating the page (12.4, 13.8): the cost is the look's material under the
  strip being redrawn on every animated frame, not the size of what animates.
  A turned week now changes without animation; tapping a day and "Oggi" still
  animate. One short hitch per turned week remains, at Apple's 5 ms/s line.
- The Swift Concurrency and System Trace passes need the same Xcode-launched
  profile, and a signed-in account to exercise the offline cache and the
  network; sample data skips both.

### 5.5 On a real account

`RealDataPerformanceTests` on the iPhone 12 Pro, iOS 27.2, Release, signed in.
The first run, in the afternoon on 8e7f299:

| Measurement | Result |
| --- | --- |
| Launch, first frame responsive | 0.60 s |
| `session.restore` | **2.0 s**, behind `LaunchGate` |
| `offline.read`, every record at launch | under 1 ms |
| `freshness.revalidate` | **11.4 s** (`agenda.load` 2.0 s, `career.load` 2.7 s) |
| Calendar paging, hitch ratio | 11.2 ms/s, 0.42 s `agenda.load` per page |
| Corsi / Oggi / Carriera / Novità scroll | 7.1 / 9.0 / 3.1 / 4.5 ms/s |
| Memory after a walk | 78 MB, peak 125 MB, flat across iterations |

The offline reads that §5.1 moved were already cheap on real data. The time was
on the network, in series:

| Finding | Fix |
| --- | --- |
| Restoring waited on four round trips — OAuth params, props, `/jaf/internal/user`, profiles — one after another, behind a spinner; and any failure of `/user`, including no connection, showed the sign-in screen with the token and every offline copy on the device | The student and profile id confirmed last are kept in the token's Keychain record, so they go wherever it goes. A launch signs in as them at once and confirms in the background (`LoginFlow.confirm`); only a refused token signs out (`LoginFlow.refusesToken`). The directory's two requests, and `/user` with the profiles, now go out together |
| The refresh after launch ran its six loads in series | They start in registration order and run together; `TokenStore` still refreshes once for all |
| Paging the calendar past the held month replaced the agenda window. Today left `events`, and the widgets' file, the reminders and the Watch followed — and every page rescheduled every reminder | Paged weeks are added to the spans held (`loadedSpans`); `NotificationModel.reschedule` leaves an unchanged plan alone |
| A week asked for while another load was in flight — the calendar opened during the launch refresh — returned at `guard !isLoading` and was never fetched | A call arriving mid-load waits for it, then decides |
| Oggi's "In arrivo" read the whole agenda, so every paged week redrew it | `AgendaModel.milestones()`, a slice of the exams and deadlines |

Measured by alternating the builds in one sitting, late evening, three
iterations each:

| Test | Before (two rounds) | After (two rounds) |
| --- | --- | --- |
| `session.restore` | 0.90 s, 0.87 s | **0.11 s, 0.018 s** |
| `freshness.revalidate` | 5.5 s, 4.8 s | 2.6 s, 3.4 / 3.0 / 15.8 s |
| Launch, first frame responsive | 0.48 s, 0.45 s | 0.73 s, 0.72 s |
| Calendar paging, hitch ratio | 11.5, 10.0 ms/s | 9.8, 11.1 ms/s |

- **Launch "regressed" by 0.25 s because it now measures a different frame.**
  Before, the first frame was `LaunchGate` and the main thread then sat idle for
  the restore; the student's timetable arrived at about 0.45 + 0.9 s plus
  building the shell. Now the shell with the student's data is the launch. An
  App Launch trace of the new build shows that quarter-second as SwiftUI
  building the shell — navigation stacks, layout — with no app code of note.
- **One refresh took 15.8 s**, `agenda.load` and `career.load` each ~15.6 s: the
  shape of a 15-second request timeout. Not seen again; worth watching.
- The calendar's hitches did not move: they are the page change, as §5.4 found.
- `testCalendarPaging` paged four weeks per iteration. Once fetched weeks were
  kept, later iterations loaded nothing, and XCTest drops a metric missing from
  any iteration; it pages six. `testBiggestCourseMaterialsScrolling` never ran:
  the course cards are not buttons to XCUITest, since the row merges its
  children; it now looks for any element with the identifier.
- A test runner newly installed on the phone asks for the passcode before
  UI automation can start; until then the run fails with "Timed out while
  enabling automation mode".

## Not verified, in one place

- Whether registering both `MXMetricManager` and `MetricManager` duplicates
  reports.
- Whether MetricKit delivery to the app depends on the "Share with App
  Developers" setting.
- The custom-signpost limit, the app-launch diagnostic threshold, the extended
  launch deadline.
- Whether legacy MetricKit reports anything about widget extensions on iOS 26.
- Whether `.notice` OSLog interpolations are evaluated when not streamed.
- The actual cost of H1–H8: all are inferred from code and SE-0461, none traced.
- `API_TO_BE_DEPRECATED` compiling warning-free with an iOS 26 target, and the
  Swift spelling of `MXLaunchTaskID` construction.
- The `MetricManager.stateReporter(for:)` call in Apple's sample: absent from
  the SDK, so treated as a documentation error.
