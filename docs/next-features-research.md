# Next features: what PoliVerse should build next

Researched 2026-09-17, on `feature/cerca` at `1d9d410`. Read-only: I read the code, docs and design boards but did not build or run the app. Apple pages were checked on the same date: each URL below returned HTTP 200 from its developer.apple.com JSON. Politecnico endpoints are cited from the repo's own probe notes (`docs/endpoint-status.md`, `docs/polimi-api-research.md`). I did not probe them again.

Labels: **[V]** verified in code, git history or a fetched page. **[J]** judgement call. **[?]** not verified.

Scope: the owner has said the app now targets **iOS 27**. Apple availability below comes from each page's `metadata.platforms`, read from its developer.apple.com JSON on 2026-09-17. "What's new" is from the June 2026 entries on the Updates pages:
- SwiftUI: https://developer.apple.com/documentation/updates/swiftui
- App Intents: https://developer.apple.com/documentation/updates/appintents
- Foundation Models: https://developer.apple.com/documentation/updates/foundationmodels
- MetricKit: https://developer.apple.com/documentation/updates/metrickit

The ActivityKit and WidgetKit Updates pages have no June 2026 entry.

## Deployment target: it does not match iOS 27

- **[V]** `IPHONEOS_DEPLOYMENT_TARGET = 26.0` (`PoliVerse.xcodeproj/project.pbxproj:394`; it is the only value in the project).
- **[V]** `docs/lazy-loading.md:147-152` argued against raising it to 27, because the release adds no launch API and the change would drop users. The owner's decision overrides that note. The note should be updated when the target changes.
- **[V]** Once the target is 27, these paths can go:

| Site | Now | With target 27 |
|------|-----|----------------|
| `PoliVerse/NewUI/Shared/CurrentClassAccessory.swift:88-100` | `#available(iOS 26.1)`; the 26.0 branch shows "a quiet placeholder" | Keep only `tabViewBottomAccessory(isEnabled:content:)` (iOS 26.1, https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:)) |
| `PoliVerse/NewUI/Shared/TodayLanding.swift:155-160,336-350` | The system reorder container on iOS 27; a hand-written `.draggable`/drop fallback otherwise | Delete `DragToReorder`'s fallback and the non-27 section path |
| `PoliVerse/Services/PerformanceMonitor.swift:18,46-49,60-…` | `MetricManager` on 27, `MXMetricManager` + `LegacyMetricSubscriber` otherwise | Delete the legacy subscriber; `MetricManager` is iOS 27.0 and "replaces `MXMetricManager` and its subscriber protocol" (Updates/MetricKit; https://developer.apple.com/documentation/metrickit/metricmanager) |
| `PoliVerse/Services/PerfSignpost.swift:46-49` | `MXMetricManager.makeLogHandle` fallback | Keep only the iOS 27 branch |
| `PoliVerse/Services/PerformanceStates.swift:41,48,52,59` | `guard #available(iOS 27)`; "On iOS 26 everything here is a no-op" (`:19`) | Drop the guards; StateReporting is iOS 27.0 (https://developer.apple.com/documentation/statereporting) |
| `PoliVerse/Services/ReportArchive.swift:71,83,94` | `@available(iOS 27, *)` | Drop the annotations and any legacy report path |

- **[V]** A grep for `#available` / `@available(iOS` finds no other sites in `PoliVerse`, `Shared` or `PoliVerseWidgets`.
- **[J]** `docs/metrickit-performance.md` §1.8 and "Not verified" (`:996-1010`) still discuss iOS 26 behaviour. They become history once the target moves.
- **[?]** The SwiftUI Updates page says that building with Xcode 27 makes `@State` use the `State()` macro, which "only initializes and stores your property once when it's a class" (https://developer.apple.com/documentation/swiftui/state()). `NewRootView` holds a class this way (`@State private var shell = ShellState()`, `NewRootView.swift:12`). This is a toolchain effect, not a target effect. I did not check which Xcode builds the release.

## What changed since the last review

**[V]** Most gaps listed in `docs/newui-information-architecture-review.md` (2026-09-15) have been closed:

- Both shells now share the app-level jobs through `.appShellDuties` (`PoliVerse/NewUI/NewRootView.swift:61`, `PoliVerse/App/RootView.swift:90`).
- The tabs host real screens (`PoliVerse/NewUI/Shared/NewDestinationScreen.swift:8-17`), and Cerca hosts the old `SearchView` (`PoliVerse/NewUI/Tabs/SearchTab.swift`). From there, Manifesti, the personal timetable, teachers and the grade simulator are reachable again.
- The Aggiungi menu and the search fields that did nothing are gone. Grepping `TodayBar.swift`, `SettingsSheet.swift` and `SinglePageHome.swift` for `query` and `Aggiungi` finds nothing.
- The priorities in `docs/doability-2026-09-14.md` (table at `:289-300`) have landed: a native timetable with sections (commits `3fc7acd`, `f6a7c5d`, `4dd3135`), a full-screen floor plan with zoom (`60cad5d`), a progressive map (`71a134d`, `77ed1b1`), a course hub with notices and forums (`86ec020`, `b284572`), partial exams (`9462bb1`) and WeBeep enrolment classification (`c7500b5`).
- The last ~25 commits are almost all visual passes: glass course pages, the exam page and Cerca.

So the next features are mostly **new capability**, not a return to parity.

## Summary

| # | Feature | Why now | Effort | Dependencies / blockers | Evidence |
|---|---------|---------|--------|-------------------------|----------|
| 1 | Deadline detail screen (WeBeep assignment) | The only Oggi row that opens nothing; the spec says it is missing | S | none; `mod_assign_get_assignments` is already called | `TodaySectionView.swift:193-198`, `information-architecture.md:38` |
| 2 | iPad / sidebar layout for NewUI | The app ships for iPad, NewUI is the default, and the spec asks for `.sidebarAdaptable` | M | design pass | `project.pbxproj:474`, `RootView.swift:9`, `information-architecture.md:124` |
| 3 | Decide the fate of the old UI (`MainTabView`) | Two shells double the cost of every feature; the flag comment still says "on this branch" | M | owner decision, merge of `feature/*` | `RootView.swift:7-9,26-30` |
| 4 | Exam-day Live Activity | Session planning; the lecture Live Activity path already exists | S–M | none (starts manually, no push) | `LiveActivityController.swift:6-11,62`, `academic-intelligence-layer.md` §22 |
| 5 | Siri/Spotlight entities for courses, exams and rooms (App Entities + `IndexedEntity`) | Intents are screen-level only; Spotlight already indexes courses and rooms by hand | M | none | `AppShortcuts.swift:9-39`, `SpotlightIndex.swift:57,129` |
| 6 | Official corrections viewer (`/v1/prove/correzioni`) | The app already knows when a correction exists but sends the student to the web | M | response shape unverified; the file is a blob | `ExamDetailView.swift:211-214`, `polimi-api-research.md:384-386` |
| 7 | Show enrolment eligibility before sending to Servizi Online (read-only `/v1/check/iscriz`) | Reduces the round trips out of the app without writing to the university system | M | shape unverified; Code 6 closes `iae` between sessions | `ExamDetailView.swift:216-220`, `polimi-api-research.md:377`, `endpoint-status.md:199-224` |
| 8 | On-device summary of course notices (Foundation Models) | Notices and forums now live in the course hub; the AIL doc lists it as a future feature | M | device eligibility; Italian support to check at runtime | `academic-intelligence-layer.md` §22 and open question 11 |
| 9 | Exam export to Calendar | EventKit export exists for the timetable; §22 lists it for exams | S | none | `Services/CalendarExporter.swift`, `Features/Career/AddToCalendarSheet.swift` |
| 10 | Narrow `/v1/notifications` to real field names | The inbox has worked on a guessed shape since 2026-09-11 | S | needs a non-empty real payload | `endpoint-status.md:122-145`, `NoticeService.swift:80` |
| 11 | In-app enrolment / withdrawal / refusing a mark | Highest student value, but it writes to the real system | L | owner/legal decision; request bodies partly unknown | `ExamDetailView.swift:216-217`, `polimi-api-research.md:378-387`, `academic-intelligence-layer.md:26` |

Ranks 1–3 finish what exists. Ranks 4–9 add capability on top of data the app already fetches. Ranks 10–11 depend on outside facts.

---

## 1. Deadline detail screen

- **[V]** The Scadenze section builds its rows with `opens: nil`, so tapping one does nothing (`PoliVerse/NewUI/Shared/TodaySectionView.swift:193-198`). The In arrivo section shares the same deadline data (`:178`).
- **[V]** The spec admits the gap: "le scadenze WeBeep non hanno ancora una schermata" (`docs/information-architecture.md:38`).
- **[V]** The data is already there. `AssignmentDeadline` (`PoliVerse/Models/Assignment.swift:4`) comes from `mod_assign_get_assignments` (`PoliVerse/Services/WeBeepAPI.swift:132`).
- **[J]** A sheet like `EventDetailView` would be enough: title, course, due date, the assignment's intro text, "Apri su WeBeep", and "Aggiungi al Calendario" through the existing `CalendarExporter`. Adding it to `shell.detail` (`NewRootView.swift:55-59`) keeps one presentation path.

## 2. iPad layout for the new interface

- **[V]** The app targets iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`, `PoliVerse.xcodeproj/project.pbxproj:474,504,521`), and NewUI is on by default (`PoliVerse/App/RootView.swift:9`).
- **[V]** `NewRootView` sets no tab view style (`NewRootView.swift:80-112`). A grep for `sidebarAdaptable` in `PoliVerse/NewUI` finds nothing. The spec asks for it (`docs/information-architecture.md:124`).
- **[V]** The API is `SidebarAdaptableTabViewStyle` (iOS 18.0): https://developer.apple.com/documentation/swiftui/sidebaradaptabletabviewstyle. On iOS 27, `toolbarMinimizationBehavior(_:for:)` (iOS 27.0, https://developer.apple.com/documentation/swiftui/view/toolbarminimizationbehavior(_:for:)) is new next to the `tabBarMinimizeBehavior` that `NewRootView.swift:109` uses. Updates/SwiftUI also adds a `prominent` tab role and toolbar `visibilityPriority`, both relevant when the bar has to shrink on a narrow width.
- **[J]** `NewDestination` already lists every place in one enum (`NewDestination.swift:6-8`), so a sidebar can be generated from it. The Personalizza overlay and the single-page panel need a separate check at iPad widths.

## 3. Retire or freeze the old interface

- **[V]** `RootView` still switches between `NewRootView` and `MainTabView` (`RootView.swift:26-30`). The comment says NewUI is "on by default on this branch" (`:7-8`).
- **[V]** The newer screens (course hub `CoursesPage`, glass exam page) are NewUI-first, and recent commits touch only NewUI or shared views (`git log` `1d9d410`…`631ecf2`).
- **[J]** This is not a feature, but it multiplies the cost of every feature above: each routing, badge or sheet change has two shells to respect. Deciding "NewUI only on `main`" and then deleting `MainTabView`/`HomeView` would be a precondition for ranks 1, 2 and 5. This can wait until `feature/cerca` merges.

## 4. Exam-day Live Activity

- **[V]** A lecture Live Activity already exists. The student starts it by hand, it is never started from the background, and there is no push server (`PoliVerse/Services/LiveActivityController.swift:6-11`, `Activity.request` at `:62`). Its attributes describe a lecture (`Shared/LectureActivity.swift:10-17`).
- **[V]** The academic intelligence layer doc proposes a "Live Activity 'giorno d'esame' con aula e countdown (avvio manuale)" (`docs/academic-intelligence-layer.md`, §22 "Funzionalità future", and the §13 table).
- **[V]** The exam data (date, room, enrolment) is in `ExamSession`, shown by `ExamDetailView.swift:153` (`sittingPanel`).
- **[V]** ActivityKit reference: https://developer.apple.com/documentation/activitykit/activity. `request(attributes:content:pushType:style:alertConfiguration:start:)` schedules an activity to start at a given time (iOS 26.0, https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:style:alertconfiguration:start:)). With it, "remind me on exam morning" works without a push server. The ActivityKit Updates page lists nothing new for iOS 27.
- **[J]** The cheap version generalises the attributes, or adds a second `ActivityAttributes` type, and puts a "Sto andando" button on the exam page. Timing is right: the exams in the upcoming session are the student's first high-stakes use.

## 5. App Entities for courses, exams and rooms

- **[V]** The six App Shortcuts are screen-level: timetable, free rooms, career, exam updates, next exam and materials (`PoliVerse/App/AppShortcuts.swift:9-39`). `OpenMaterialsIntent` opens Corsi, not a specific course (`NewDestination.swift:112`, `.weBeep → .courses`).
- **[V]** Spotlight indexing uses `CSSearchableItem` directly (`PoliVerse/Services/SpotlightIndex.swift:57,129`), so Siri and Shortcuts cannot use the indexed items as parameters.
- **[V]** `IndexedEntity` connects App Entities to Spotlight (iOS 18.0): https://developer.apple.com/documentation/appintents/indexedentity
- **[V]** iOS 27 additions from Updates/App Intents: entities, intents and enums can conform to an app schema in the "app schema domains" (https://developer.apple.com/documentation/appintents/app-schema-domains) to integrate with Apple Intelligence. `SyncableEntity` (iOS 27.0, https://developer.apple.com/documentation/appintents/syncableentity) marks identifiers as stable across devices. Course codes and `c_appello` are already stable ids (`docs/academic-intelligence-layer.md:26`).
- **[?]** Whether any schema domain fits education data. I didn't read the domain list.
- **[J]** "Apri Analisi 2", "Aula libera vicino all'edificio 3" and "Quando è l'appello di Fisica" become possible. The deep-link route has to reach a course, which means extending `NewRoute` (`NewDestination.swift:94-118`) beyond whole places.

## 6. Official corrections viewer

- **[V]** The app decodes `hasCorrezioni` (`PoliVerse/Models/Career.swift:165,224`). The exam page then only says "Elaborato corretto consultabile sui Servizi Online." (`PoliVerse/Features/Career/ExamDetailView.swift:211-214`).
- **[V]** The official bundle calls `GET /v1/prove/correzioni/{c_appello}` (a list) and `GET /v1/prove/correzione/{id}` with `responseType: blob` (`docs/polimi-api-research.md:384-386`). The response shapes are marked INFERRED (`:392-393`).
- **[?]** Whether the blob is a PDF, and whether it holds anyone else's data. `academic-intelligence-layer.md` open question 5 asks this too.
- **[J]** It is a read, so it fits the "no writes to the university system" line in `ExamDetailView.swift:216-217`. Show it in QuickLook, and don't cache it beyond the session unless the student saves it.

## 7. Enrolment eligibility, read-only

- **[V]** Today the exam page says enrolment happens in Servizi Online (`ExamDetailView.swift:216-220`). The Oggi/notification path already detects when enrolment opens (`PoliVerse/Models/ExamUpdate.swift:403-408`).
- **[V]** `GET /v1/check/iscriz/{a}/{b}/{c}` ("enrolment eligibility check") and `GET /v1/check/generiche` ("blocking messages") exist in the bundle (`docs/polimi-api-research.md:376-377`). Their messages have the shape `{messaggio, tipo, tipo_messaggio, esito}` (`:390-391`).
- **[V]** Blocker: `iae` answers Code 6 while the service is closed to the student, and this should be neither retried nor re-authenticated (`docs/endpoint-status.md:199-224`).
- **[J]** "Puoi iscriverti" or "Bloccato: tasse non pagate", followed by the official link, removes the trip to the website that only ends in an error. It's cheaper and safer than rank 11.

## 8. On-device notice summaries (Foundation Models)

- **[V]** Course notices, forums and syllabus are now in the course hub (commits `86ec020`, `76b6367`, `34ba3c6`). WeBeep forum calls are at `WeBeepAPI.swift:98-127`.
- **[V]** The academic intelligence layer doc proposes a "Riassunto 'cosa cambia per me' delle comunicazioni docente (Foundation Models, on-device)" (§22). It limits the model to an optional fallback that never decides links (§0 table, row "Approccio raccomandato", `docs/academic-intelligence-layer.md:28`). Whether the model handles Italian is open question 11.
- **[V]** API: `LanguageModelSession` (iOS 26.0, https://developer.apple.com/documentation/foundationmodels/languagemodelsession). A grep finds no `FoundationModels` import in the app. iOS 27 adds `DynamicProfile` and model-specific error types such as `LanguageModelError` (Updates/Foundation Models; https://developer.apple.com/documentation/foundationmodels/languagemodelerror). With a 27 target, use the new errors to tell "model unavailable" apart from a failed request.
- **[J]** Scope it to one visible "Riassumi" action on long notices, and hide it when the model is unavailable. Nothing leaves the device, which fits the privacy position in that doc.

## 9. Exam export to Calendar

- **[V]** EventKit export already exists (`PoliVerse/Services/CalendarExporter.swift`, `PoliVerse/Features/Career/AddToCalendarSheet.swift`). The timetable goes into its own calendar (commit `4dd3135`).
- **[V]** `academic-intelligence-layer.md` §22 lists "Esportazione appelli su Calendario (EventKit write-only)". Apple: https://developer.apple.com/documentation/eventkit/ekeventstore/requestwriteonlyaccesstoevents(completion:)
- **[?]** Whether `AddToCalendarSheet` already accepts an exam. I found it under `Features/Career`, but did not trace its callers into the new glass exam page. Check before building.

## 10. Real field names for `/v1/notifications`

- **[V]** The endpoint works, but the only response seen was an empty array (2026-09-11). Fields are read from candidate name lists, and the plan is to narrow them once a real payload arrives (`docs/endpoint-status.md:122-145`). The shape is logged without values (`PoliVerse/Services/NoticeService.swift:80`).
- **[J]** This is S work, but it waits on an account with a notification. It belongs on the owner's checklist more than on the roadmap.

## 11. In-app enrolment, withdrawal and refusing a mark

- **[V]** Endpoints in the bundle: `POST /v1/iscriz/{a}/{b}/{c}` with `{cRisposta, cRispostaAteneo}`, `DELETE /v1/iscriz/{id}`, `PATCH /v1/esito/rifiuta/{id}` (`docs/polimi-api-research.md:378-387`).
- **[V]** The code deliberately does not do this: "Enrolment is a write against the real university system: the app points at the official services instead." (`ExamDetailView.swift:216-217`). A refusable mark is only labelled (`PoliVerse/Features/Career/CareerView.swift:436-437`, `ExamDetailView.swift:206-209`).
- **[V]** The academic intelligence layer doc finds no explicit permission for unofficial clients and recommends asking ASICT in writing (`docs/academic-intelligence-layer.md:26`, open question 7).
- **[J]** This is the most valuable feature on the list, and it should not be built without an owner decision and a real-account test plan. A wrong refusal can't be undone. Ranks 6 and 7 cover most of the value with reads only.

---

## Efficiency work

**[V]** Starting point: most of the speed plan in `docs/metrickit-performance.md` (Phase 2, `:924-945`) has landed:

- `@concurrent` JSON decode (`PoliVerse/Services/BackgroundJSON.swift:12-20`), used by 11 services including `PoliMiAPI`, `CareerService` and `WeBeepAPI`.
- Room and map placement off the main thread (`RoomsService.swift:131,168`, `MapPlacement.swift:44-82`, commit `77ed1b1`).
- Coalesced `reloadTimelines(ofKind:)` (`PoliVerse/Services/WidgetReloader.swift:7,46`).
- Per-service load windows: 60 s for free rooms, 900 s for career, courses and news, 3600 s for WeBeep updates (`FreeRoomsService.swift:70`, `CareerService.swift:53`, `CourseService.swift:40`, `NewsService.swift:26`, `WeBeepService.swift:36`). This is what `docs/data-freshness.md:279-291` recommended.
- Cached formatters (`Notice.swift:130,161`, `RoomBooking.swift:188`) and a `RegexCache`.
- Keychain off the launch path (`docs/lazy-loading.md:155-176`).
- The iOS 27 MetricKit/StateReporting pipeline, with on-device report storage (`PerformanceMonitor.swift`, `ReportArchive.swift`, commit `993c95f`).
- UI performance tests (`PoliVerseUITests/PerformanceTests.swift:44-93`).

**[V]** On launch, the local trace found nothing of the app's own code before the first UI. "The next real measurement has to come from a device" (`docs/lazy-loading.md:190-240`).

So the remaining work is mostly about **measuring the interface that actually ships (NewUI)**. There is little left to optimise blind.

| # | Item | Why | Effort | Blockers | Evidence |
|---|------|-----|--------|----------|----------|
| E1 | Report NewUI tab state to StateReporting | NewUI is the default, but only `MainTabView` reports tabs, and the allowed labels are the old tabs, so field hangs and hitches in NewUI arrive unattributed | S | none | `PerformanceStates.swift:30,35-43`; `RootView.swift:83-85`; nothing in `PoliVerse/NewUI` |
| E2 | Point the UI performance tests at NewUI | The hitch test taps the "Calendario" tab, which NewUI doesn't have; the launch arguments don't choose a shell, and NewUI is the default | S | decide which screens are hot in NewUI (Oggi day swipe, Personalizza, Cerca) | `PerformanceTests.swift:33-38,70-79`; `RootView.swift:9`; `NewRootView.swift:80-90` |
| E3 | Raise the target to 27 and delete the fallback paths | One MetricKit pipeline, one reorder path, less code on hot views | S | owner decision (see "Deployment target") | `project.pbxproj:394`; table above |
| E4 | Measure Personalizza and the glass/shader rendering on a device | 20 `glassEffect`/shader sites in NewUI plus a Metal file; only animation tests exist, no hitch metric | M | a real device (the simulator over-states, `lazy-loading.md:226-240`) | `PoliVerse/NewUI/Customize/TodayShaders.metal`; `PoliVerseUITests/CustomizeAnimationTests.swift` |
| E5 | Cache remote images with `asyncImageURLSession(_:)` | `AsyncImage` in News and the profile avatar refetches with the default session | S | iOS 27 target | `NewsView.swift:87`, `ProfileAvatar.swift:46`; API iOS 27.0: https://developer.apple.com/documentation/swiftui/view/asyncimageurlsession(_:) |
| E6 | First device baseline from Organizer / `scripts/asc-performance.py` | The routine is written, but no field numbers are recorded in the repo | S (no code) | a TestFlight/App Store build with users | `docs/field-performance.md:20-60`; `metrickit-performance.md:694-706` (Phase 0) |
| E7 | Refresh more services in the background | The background task refreshes only agenda, career and reminders; widgets for free rooms and deadlines depend on the app running | M | `BGAppRefreshTask` runs when the system decides | `docs/data-freshness.md:99-107`; `BackgroundRefresh.swift:21,44-45`; https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask |
| E8 | Day-swipe network cost on Oggi | `.task(id: shell.day)` runs on every day change. Outside the loaded window, `ensureLoaded` forces a fetch, so each far jump costs a request. Check the window size against the ±60-day stepper | S | none | `NewRootView.swift:95`; `AgendaService.swift:175-185` |
| E9 | Once-a-minute tick on the root view | `now` is updated every 60 s on `NewRootView`, which re-evaluates the whole tab tree to move the accessory on | S | measure first (E1/E4) | `NewRootView.swift:21-22,96-101` |

Notes per item:

- **E1 [V]** `PerformanceStates.tabs` is `["home", "webeep", "calendar", "career", "search"]` (`PerformanceStates.swift:30`), and anything else is reported as no state (`:35-37`). NewUI's tab values are `today, courses, career, search` (`NewDestination.swift:13-15`). The fix is small: report `shell.selection` from `NewRootView`, and add the NewUI labels, or replace the old ones if the old UI goes (feature rank 3). Apple: https://developer.apple.com/documentation/statereporting
- **E2 [?]** I didn't run the tests. Given the launch arguments, I expect `testCalendarWeekPagingHitches` to fail to find its button, or to measure the old UI only if something else switches it.
- **E3 [V]** Apple's launch guidance is unchanged in substance: https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time. The repo already concluded that iOS 27 brings no public launch API (`docs/lazy-loading.md:144-152`). Raising the target removes code, not launch time.
- **E4 [J]** The "What to watch" table (`docs/metrickit-performance.md:981-994`) sets a hitch target of < 5 ms/s. Nothing in the repo records Personalizza against it. Apple: https://developer.apple.com/documentation/xcode/improving-app-responsiveness
- **E7 [J]** Keep the window per service. Free rooms change at lecture boundaries (`data-freshness.md:283-287`), so the background task should fetch them only when a free-rooms widget is installed.
- **Not recommended [V]:** JSON decoding at launch (1.28 ms, `lazy-loading.md:161-167`), dyld (the simulator artefact, `:226-232`), and an upload backend for MetricKit (deferred as a privacy decision, `docs/field-performance.md:95-108`).

---

## Unfinished or placeholder work already in the app

- **[V]** Scadenze and In arrivo rows don't open anything (`TodaySectionView.swift:198`, `opens: nil`).
- **[V]** `TodayLanding` has a no-op `onAddSticker = {}` and `onEdit = { _ in }` in one initialiser (`PoliVerse/NewUI/Shared/TodayLanding.swift:56-57`). This is probably the preview or read-only path [?].
- **[V]** The current-class accessory shows only a placeholder on iOS 26.0 and needs 26.1 (`PoliVerse/NewUI/Shared/CurrentClassAccessory.swift:90`).
- **[V]** `RootView` still carries the old shell (`RootView.swift:26-30`); see rank 3.
- **[V]** The design board `design/profile` has variants (`Pass.dc.html` "Variante · Carta", `Poster`, `Essenziale`; `design/profile/canvas.json:5`). Only the QR contact page is in code (`PoliVerse/NewUI/Profile/ProfilePages.swift:51`, `ProfileView.swift:118`). I did not check which variant the owner chose [?].
- **[V]** The design board `design/in-arrivo` compares "2a retro" and "2b sotto" for the shape picker (`design/in-arrivo/canvas.json:110,118`). `SectionFormPicker.swift` exists, but I did not check which option was built [?].
- **[V]** The WeBeep login end-to-end checks listed as "still unverified" (`docs/webeep.md:127-139`) have no later note saying they were done [?].
- **[V]** The response shape of `/v1/base/counters` is unverified (`docs/endpoint-status.md:456-467`).

## Blocked by endpoints

- **[V]** A staff directory can't be built: `/v1/rubrica` and similar paths return 404, and `maps_rest /struttura/{personaId}` needs an id the app never sees (`docs/endpoint-status.md:246-259`). Teacher search stays assembled from courses and exams.
- **[V]** Live room occupancy for everyone: `ws_aule` is staff-only (`docs/endpoint-status.md:383`). The public `maps_rest` occupancy works (`:332`), but `/spazi/impegni` answers 500 (`:386-388`).
- **[V]** Some things can't be done while `iae` answers "Utente non abilitato Code: 6" (between sessions, `docs/endpoint-status.md:199-224`): anything about exams (ranks 6, 7, 11) can't be tested then.
- **[V]** Push-driven notifications or Live Activity updates would need a server. None is planned ("There is no server, and none is planned", `docs/data-freshness.md:293-300`).
- **[V]** There is no ICS export of the timetable from the Politecnico (`docs/doability-2026-09-14.md`, §1, "Nessun export ICS/iCal"). The app builds its own events instead.
- **[V]** Hosts that moved: `polimiapp…/me/polimi/{m}` is gone (`docs/endpoint-status.md:266`).

## Ideas without evidence

These are not grounded in code, docs or Politecnico pages. Treat them as prompts, not findings.

- Apple Wallet student card (suggested by the "Carta" profile variant). It needs a signing certificate and a server, and the Politecnico would have to accept it.
- Canteen menus, library seat booking, tuition fees (tasse) and ISEE deadlines. I found no endpoint for any of them in `docs/polimi-api-research.md`.
- A watchOS companion (no target in the project).
- Study groups or sharing a timetable with classmates beyond the QR contact card.
- Personal statistics ("tempo medio tra appello ed esito"). This is listed in `academic-intelligence-layer.md` §22 with no user demand shown.

## Open questions for the owner

1. Is NewUI going to be the only interface on `main`? If yes, when can `MainTabView`/`HomeView` go? (Rank 3 gates ranks 1, 2 and 5.)
2. Does iPad matter for the first release, or should `TARGETED_DEVICE_FAMILY` drop to iPhone only?
3. Are writes to `iae` (enrolment, refusing a mark) ever in scope? Has anyone contacted ASICT, as `academic-intelligence-layer.md` open question 7 suggests?
4. Can an account with a correction document (`hasCorrezioni = true`) and a non-empty `/v1/notifications` be used to capture shapes?
5. Which profile variant and which In arrivo shape-picker option (2a or 2b) are final?
6. Is Foundation Models acceptable even though it only runs on Apple Intelligence devices, so part of the students won't get the feature?
7. When will `IPHONEOS_DEPLOYMENT_TARGET` move from 26.0 to 27.0? Until it does, every iOS 27 API above needs an `#available` path, and the owner's "targets iOS 27" is not true of the build (`project.pbxproj:394`).
8. Which Xcode builds releases? The Xcode 27 `@State` macro behaviour applies whatever the target is.
