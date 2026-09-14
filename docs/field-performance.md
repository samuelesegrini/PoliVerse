# Field performance: the routine

How to read what real students' phones say about PoliVerse, and what to do
with it. The research, sources and reasoning behind every step are in
`metrickit-performance.md`; this is the part you run.

Three sources, from cheapest to most detailed:

| Source | What it has | Who it covers | Where |
| --- | --- | --- | --- |
| Xcode Organizer | per-version launch, hangs, memory, disk writes, battery, terminations, storage; regressions and insights | users sharing analytics with developers, aggregated | Xcode → Window → Organizer |
| App Store Connect API | the same data plus diagnostic signatures and their logs, as JSON | same | `scripts/asc-performance.py` |
| MetricKit on the device | every report the app received, split by tab and data source on iOS 27 | one phone | Settings → Diagnostica → MetricKit (Debug builds), or the app container |

No analytics backend: nothing leaves a student's phone unless they share it.
That stays true until someone decides otherwise — see "Upload" below.

---

## Every week

1. **Organizer → Insights**, for the latest version. Anything marked as a
   regression or trending up gets a line in the issue tracker with the metric,
   the version and the percentile.
2. **Organizer → Metric goals** **[Xcode 27]**: note which goals the latest
   version misses.
3. Or, in one command, the same numbers with the change from the previous
   version:

   ```bash
   scripts/asc-performance.py metrics
   ```

   The JSON is kept in `build/field-performance/metrics-<date>.json`
   (git-ignored), so weeks can be compared later.

## After each release

Wait until the version has a few days of use — Apple only publishes a
version's numbers once enough devices report.

1. **Organizer → Regressions** against the previous version.
2. Top diagnostic signatures of the release build, with call stacks:

   ```bash
   scripts/asc-performance.py signatures --build <CFBundleVersion> --top 5
   ```

   Hangs, disk writes and launches, ranked by share of reports. Logs land in
   `build/field-performance/build-<number>/`.
3. Symbolicate anything whose frames are still addresses:

   ```bash
   scripts/symbolicate-metrickit.py build/field-performance/build-<number>/01-hangs-logs.json --dsyms ~/Library/Developer/Xcode/Archives
   ```

   The script matches frames to dSYMs by UUID, so pointing it at the whole
   archives folder is fine. **Keep every shipped archive**: without the dSYM of
   the exact build, a stack stays a list of addresses.

## When a report comes from one phone

A crash or hang someone can reproduce, or a TestFlight tester's phone:

1. Debug build: Settings → Diagnostica → MetricKit, share the report's JSON.
   Release build: Xcode → Devices → the app → Download Container, then
   `AppData/Library/Application Support/MetricKit/`.
2. `scripts/symbolicate-metrickit.py <report>.json --dsyms <archive>`.
3. On iOS 27 the report's `environment.states` says which tab was open and
   whether the phone was on sample data, and `signpostData` names the interval
   in progress (`agenda.load`, `freshness.revalidate`, …). Start there.

## Setting up the API key (once)

App Store Connect → Users and Access → Integrations → App Store Connect API →
Team Keys → generate a key with the **Developer** role. Download the `.p8` (it
can be downloaded only once) and keep it outside the repository. Then, in the
shell that runs the script:

```bash
export ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/.appstoreconnect/AuthKey_….p8
```

The script signs a 20-minute token with `openssl`; the key never leaves the Mac.

## Reading the numbers

- Launch: cold and prewarmed are different populations — compare like with
  like. Extended launch (iOS 27) ends when the session is restored, which is
  the moment a student can use the app.
- Hangs: Organizer counts seconds of unresponsiveness per hour over 250 ms.
- Hitches: under 5 ms/s is good, 5–10 investigate, over 10 act.
- Sample-data sessions do no networking; on iOS 27 they are their own state
  and should not be averaged with live ones.

Before fixing anything, reproduce it locally with the `PoliVersePerformance`
scheme or Instruments, and compare before and after. A fix that was not
measured is a guess (`lazy-loading.md`).

## Upload: not decided

Phase 4 ends with a decision, not code. Uploading MetricKit reports from
students' phones would give per-tab data for every iOS 27 user instead of one
phone at a time, at the cost of a privacy disclosure, a consent step and a
server. It is worth reopening only if Organizer and the API together cannot
explain a problem. The options are compared in `metrickit-performance.md`
§1.10; the cheapest step up is an opt-in "send diagnostics" share sheet, which
needs no server.
