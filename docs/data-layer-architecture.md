# Model layer: naming and structure

A plan for reorganising the 110 files that are not views: 49 in
`PoliVerse/Models`, 61 in `PoliVerse/Services`.

Nothing here has been done. Numbers were measured on the branch this was
written from; proposals say so.

---

## 1. What is there today

| Folder | Files | Lines | What lives there |
| --- | ---: | ---: | --- |
| `PoliVerse/Models` | 49 | 7 100 | Domain types, wire types and pure algorithms, one flat list |
| `PoliVerse/Services` | 61 | 11 532 | 27 `@Observable` models, 20 pure `enum`s, 4 actors, 20 that do networking, one flat list |
| `PoliVerse/Features` + `NewUI` | 93 | 19 851 | The two interfaces |
| `Shared` | 8 | 1 021 | What the widget extension needs too |

One app target. Xcode file-system-synchronized groups, so **moving a file on
disk does not touch `project.pbxproj`** — which is what makes this cheap to do
and cheap to undo.

Three facts worth having before deciding anything:

- **The model layer does not import SwiftUI.** One file does —
  `Services/AuthWebView.swift` — and it is a view in the wrong folder. There is
  no dependency direction to straighten out here, only filing.
- **`Session` is named by 49 files**, a quarter of the app, and holds four
  unrelated things: who the student is, the OAuth session, the sample-data
  switch, and login orchestration.
- **Six files hold both the shape the Politecnico sends and the shape the app
  reasons about** (`Career`, `Classroom`, `Course`, `Libretto`,
  `PoliMiProfile`, `User`). The endpoints move without notice
  (`docs/endpoint-status.md`), so this is the one boundary that has a real
  failure mode rather than a legibility complaint.

Only the third is a defect. The first two are the app being harder to read
than it needs to be — which is worth fixing, but not worth pretending is
urgent.

---

## 2. The architecture the app already has: MV

`PoliVerseApp` injects **27 `@Observable` objects** into the environment, and
views read them directly. There is not one `ViewModel` in the repository.

That is Model–View. Apple does not name a pattern, but its data-flow guidance
and sample code do exactly this: model types in the environment, SwiftUI
observing the properties a view actually reads, no object in between. The
community calls it MV.

So the question is not which architecture to adopt. It is whether the folders
say what the code already does. They do not.

**Why not MVC.** MVC's controller mediates between a view and a model because
UIKit's view cannot describe itself. A SwiftUI `View` is a description that
re-runs when the state it read changes — it is already the controller's job,
done by the framework. Adding controllers means writing by hand what
`@Observable` does, and introducing a layer with no state of its own.

**Why not MVVM.** A ViewModel per view duplicates the `View` struct: both
would hold per-screen state, and `@State` already does that without a second
type. MVVM earns its keep where a view framework cannot observe a model
directly. SwiftUI can.

**Why not the Clean/hexagonal shape** (an earlier draft of this document
proposed it): ports, gateways and adapters add three vocabulary items and a
wiring step at launch, to make testable something the test suite already tests
with `URLProtocol` stubs (`ConnectionProbeTests`, `RoomOccupancyTests`). That
is a layer bought at full price to replace a stub that works.

**What MV gets wrong, and the rule that fixes it.** MV's failure mode is one
enormous model object that the whole app depends on. This app already has it:
`Session`, fan-in 49. So the rule that matters is not a layering rule, it is
this one:

> **One model per area, never one model for the app.** A model owns one
> subject — the career, the courses, the materials — and knows nothing about
> the others.

```mermaid
flowchart LR
    V["Views<br/>read what they need"] -->|"@Environment"| M
    subgraph M["Model layer — one per area"]
      direction TB
      C["CareerModel"]
      K["CoursesModel"]
      W["MaterialsModel"]
      A["AgendaModel"]
    end
    M --> P["Pure types and algorithms<br/>no I/O, no clock"]
    M --> N["Endpoints<br/>+ their wire types"]
    style P fill:#27ae6022,stroke:#27ae60
```

---

## 3. The structure: one folder per area

The previous draft grouped by layer — `Domain/`, `Stores/`, `Gateways/`. That
was a mistake, and a measurable one: it spread Carriera across **four**
folders, where today it sits in two. The question asked every day is "where is
everything about the career?", and a layout should answer it in one place.

The layer belongs in the **file name**, where a reader sees it and the compiler
never needs it.

```
PoliVerse/
  App/                    entry point, routing, intents          (unchanged)
  DesignSystem/                                                  (unchanged)
  Views/                  Features/ + NewUI/ converge here, later
  Model/
    Career/               Career.swift · CareerModel.swift · CareerAPI.swift · Wire.swift
                          ExamTimeline.swift · ExamContext.swift · Libretto.swift
    Courses/              Course.swift · CoursesModel.swift · CoursesAPI.swift · Wire.swift
                          Teacher.swift · Enrolment.swift
    Materials/            WeBeepFile.swift · MaterialsModel.swift · WeBeepAPI.swift · Wire.swift
                          MaterialChange.swift · DocumentClassifier.swift
    Timetable/            PersonalTimetable.swift · AgendaModel.swift · AgendaAPI.swift
                          CalendarExport.swift
    Places/               Classroom.swift · RoomsModel.swift · RoomsAPI.swift · Wire.swift
                          RoomBooking.swift · RoomFacility.swift · MapPlacement.swift
    Study/                Manifesto.swift · ManifestiModel.swift · ManifestiAPI.swift
                          StudyPlan.swift · StudyProgramme.swift
    Updates/              ExamUpdate.swift · UpdatesModel.swift · FeedItem.swift
                          Notice.swift · NewsItem.swift · NotificationPlan.swift
    Identity/             User.swift · Session.swift · PoliMiOAuth.swift
                          LoginWebKit.swift · CieID · SPIDCatalogue · Onboarding
    Sync/                 what was changed offline, and when to refresh
                          PendingChanges · ActionQueue · OptimisticFlags
                          FreshnessCoordinator · LoadWindow · DataStatus
    Platform/             SpotlightIndex · LiveActivityController · WidgetReloader
                          NotificationService · CalendarExporter · BackgroundRefresh
    Diagnostics/          DiagnosticsLog · DiagnosticsReport · ConnectionProbe
                          StorageAudit · PerformanceMonitor · PerfSignpost
    <Area>/Samples.swift  the area's sample data, as extensions on its own
                          types — Course.samples, ExamSession.samples(now:)
    Support/              shared by every area, names none of them
                          PoliMiAPI · ServiceDirectory · PoliMiProfile
                          Tokens · TokenStore · KeychainStore · DiskCache
                          HTMLText · HTMLScraper · RegexCache · JSONValue
                          SearchMatch · ResourceLoader · BackgroundJSON · NetworkMonitor
  Shared/                 app + widget extension                 (unchanged)
```

Suffixes carry the role, and are the whole convention:

| Suffix | What it is | How it is tested |
| --- | --- | --- |
| *(none)* | Value types and pure algorithms. No I/O, no clock of its own. | In memory, in milliseconds |
| `…Model` | The `@Observable` a view reads. `@MainActor`. Holds no parsing and no `URLSession`. | Driven through its API with a `URLProtocol` stub |
| `…API` | One endpoint family. Returns the area's own types, never wire types. | `URLProtocol` stub |
| `Wire` | The `…DTO`s of that area, `internal` to it, never in a signature a view can see. | The decoding tests that exist |

`CareerService` becomes `CareerModel` because it is a model, not a service.
`WeBeepAPI` already says what it is. `ManifestoParser` keeps no suffix because
it is pure. A folder should not need a glossary to be read correctly.

---

## 4. Three rules, in place of a matrix

1. **`Support/` names no area.** If something in `Support/` needs to know about
   Carriera, it belongs in `Model/Career/`. **Enforced.**
2. **The areas do not get more tangled.** Not "an area names no other area":
   that was this document's first draft, and measuring it killed it — **every
   area names between two and seven others, 52 edges in all.** Reaching zero
   is a rewrite, not a move, and a rule nobody can satisfy is decoration. So
   the edge count is recorded and the check fails only if it **grows**. The
   direction of travel is enforced; today's state is not pretended away.
3. **Nothing under `Model/` imports SwiftUI.** **Enforced**, and true as of the
   move: the one file that broke it, `AuthWebView`, was a view and now lives
   with the views.

`scripts/check-model-layer.sh` is all three, in bash and grep. It needs no
Xcode and no Swift toolchain, which makes it the one check in this repository
that can run on any machine, and in whatever CI it eventually gets.

Two rules earned their keep the moment they were first run. Rule 1 caught
`PoliMiAPI` reaching for `TokenStore` and `DataStatus` reaching for `Session`.
So the credential store (`Tokens`, `TokenStore`, `KeychainStore`) and the
transport's header values (`PoliMiProfile`) went to `Support/`, where
infrastructure belongs, and `DataStatus` went to `Sync/`, whose subject is
freshness. None of that was visible from reading the folders.

---

## 5. The path

**Precondition, not a phase.** The unit suite and the UI suite have to run
green on a Mac, once, before any file moves. The repo has no CI — no
`.github` at all — and the UI suite has never been compiled, so the safety net
every step below leans on is, at the moment, unproven. Tensioning it is step
zero and it is not optional.

Then three steps, three pull requests:

| Step | What | Touches logic | Effort |
| --- | --- | :-: | --- |
| **1** | Split the six files that hold both a DTO and a domain type; the DTOs become `Wire.swift` in their area. **Done.** | no | done |
| **2** | `git mv` the 110 files into `Model/<Area>/`. `AuthWebView` goes to the views. **Done** — see below. | no | done |
| **2b** | Rename `…Service` to `…Model` where the name lies. **Done** — all sixteen were `@Observable`, so all sixteen are models; `…API` stayed for the two that already said so. | no | done |
| **3** | Split `Session` into two: **who the student is** and **how they got in**. **Done, partly** — see below. | **yes** | done, with a remainder |

Nothing else. `Session` is split into two rather than four because a type for
one boolean is not a type. The two interfaces converge when it is decided which
one ships — that is a product question, and filing does not answer it.

```mermaid
flowchart LR
    P["0 · Tests green<br/>on a Mac, once"] --> S1["1 · Wire out<br/>6 files"]
    S1 --> S2["2 · Areas<br/>110 files, one git mv"]
    S2 --> S3["3 · Session<br/>in two"]
    style P fill:#c0392b22,stroke:#c0392b
```

Every step is a `git mv` plus renames, so a step is abandoned with
`git revert` and nothing is left behind.

### What step 2 actually did

110 files, `git mv` only — git recorded all 110 as renames and nothing else
changed. `project.pbxproj` was not touched and did not need to be: the
synchronized root group picks the new tree up by path, exactly as predicted.
71 path references in `docs/` were updated to match.

Areas as they came out, largest first: Support 15, Identity 12, Materials 12,
Diagnostics 12, Updates 10, Places 9, Career 8, Study 8, Courses 6, Platform 6,
Sync 6, Timetable 4 — 109 files, plus `AuthWebView` to the views.

### The sample data

`MockData` was 392 lines and one `enum` naming every area, which is why it
needed a folder of its own: rule 1 would not have it in `Support/`. It is gone.
Each area now carries its own `Samples.swift` — `extension Course { static let
samples }`, `extension ExamSession { static func samples(now:) }` — so the
sample data sits beside the type it describes, and the folder that existed only
to hold the exception no longer exists.

The straight split would have made one thing worse. `"Basi di Dati"` and its
code `097785` were typed out **six times across five areas**; in one file you
could at least see the copies together, and in six folders you could not. So
the courses became the spine: `Course.samples`, with a name for each, and every
other area's samples take the name and the code from it. **No course code is
written out by hand twice anywhere in the app.**

That cost one edge — `Timetable -> Courses`, the ratchet caught it at 53 — and
it is written down in `scripts/model-layer-baseline.txt` with the reason. One
edge for one source of truth, on data a student actually sees: sample data
ships here, it is what "Esplora con dati di esempio" shows.

### What step 3 did, and did not do

`Session` was 387 lines. It is now 185, and `LoginFlow` is 241: the restore at
launch, the login, the logout and the career re-login moved out whole, bodies
unchanged.

The usage data decided the cut. Of roughly 150 uses of a `Session` across the
app, **140 are `student` and `useMockData`** — who the student is, and which
mode the app is in. The OAuth machinery is reached from thirteen places. So
the identity half kept the name and the call sites, and the login half became
its own type.

`LoginFlow` is reached as `session.login`, not injected on its own. That is
the part that is deliberately unfinished, and it matters: **`Session`'s fan-in
is still 49.** Separating the code is done; separating the dependencies means
injecting `LoginFlow` into the six views that drive a login, which is a
one-line change per view — and it is the one change that wants a compiler,
because the login path is the only path in this app that no test can
exercise. It needs a real Politecnico account.

`Sync/` was not in the plan. It exists because rule 1 found two files —
`PendingChanges` and `FreshnessCoordinator` — that name four to six area
models each and so could not be shared infrastructure. Their subject is
"what was changed offline, and when to refresh", which is an area like any
other. A rule that produces a folder nobody thought of is a rule doing its
job.

---

## 6. What this plan refuses

- **SPM modules, for now.** All 100 test files import
  `@testable import PoliVerse`. Splitting the target breaks every one of them,
  and `@testable` does not cross a module boundary the way a single target
  allows. The folder move changes **no import statement at all**, because one
  target needs none. Revisit only if build time is measured and found wanting.
- **A dependency-injection framework.** `@Environment` is the injection
  mechanism SwiftUI already provides, and 27 registrations at the root are a
  graph you can read. A container would hide it.
- **Ports and protocols between a model and its API.** The `URLProtocol` stubs
  already in the suite do that job with no extra type.
- **ADR files.** `docs/` is already a decision record, written better than any
  template.
- **Restructuring the views.** Later, and only after the interface question is
  settled.

---

## 7. Open questions

1. **`Features/` vs `NewUI/`.** Is the old interface going away? Step 2 does
   not depend on the answer; the view reorganisation does entirely.
2. **`Shared/` and the areas.** `AgendaEvent`, `PoliMiDate`,
   `FreeRoomsSnapshot`, `CareerSnapshot` and `RoomOccupancy` are needed by the
   widget and so live in `Shared/`, which means Timetable and Places will each
   sit in two places. Leaving them and saying so is defensible; the
   alternative needs the SPM question reopened.
3. **`ExamContext` and `ExamTimeline`** read sittings, the libretto and updates
   together. `Model/Career/` is proposed above; a case can be made for a small
   area of their own.
