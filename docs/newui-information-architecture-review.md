# NewUI: information architecture and navigation review

Researched 2026-09-15, on `feature/nuova-struttura` at `d70bd0c`. Read-only: I read the code but did not build or run it. The spec is `docs/information-architecture.md`. Apple guidance comes from the public JSON behind each developer.apple.com page, fetched on the same date. Every page listed below loaded.

Labels: **[V]** verified in code or on an Apple page. **[J]** judgement call. **[?]** not verified.

## Summary

| # | Sev. | Finding | Recommendation |
|---|------|---------|----------------|
| 1 | High | NewUI is the default after sign-in, but it reaches none of the old content screens | Default `usesNewInterface` to `false` (or DEBUG-only) until tabs host the existing views |
| 2 | High | Siri, Controls, notification taps, Spotlight indexing, reminder rescheduling and the demo banner are gone in NewUI | Move these jobs out of `MainTabView` into a wrapper shared by both shells |
| 3 | Medium | Cancel and Done mean different things across Personalizza's levels, and edits are discarded without asking | One commit point, and a confirmation before discarding |
| 4 | Medium | Personalizza stacks up to four presentation layers; Profile opens sheets from inside sheets | Flatten the stack; show one sheet at a time |
| 5 | Medium | The two layouts offer different destinations, and both differ from the spec | Pick one destination list, use it in both layouts, and update the spec |
| 6 | Medium | Five menu items, the panel's search field and the settings search do nothing | Disable them or remove them |
| 7 | Medium | The Barra toggles can hide both routes to Impostazioni and Profilo | Keep one of the two always visible |
| 8 | Medium | The day stepper goes ±60 days, but the agenda is loaded only around today | Load the agenda around `shell.day` when it changes |
| 9 | Medium | Terminology collides: Aspetto, Materiale, Schede, Disposizione/Layout/Disponi, Tema→Flavor, Data→Widget | Settle on a glossary |
| 10 | Low | Duplicated entry points: gear next to the menu's Impostazioni, Profilo as sheet and as push, Esci twice | Keep one of each |
| 11 | Low | Presenting anything from the single page resets the panel; the current class can show twice | Keep panel state in `ShellState` |
| 12 | Low | Stale comment; `-NewUI` bypasses login and makes "Torna all'interfaccia attuale" do nothing; saved looks can't be deleted | Small fixes |

## 1. Top-level structure

- **[V] NewUI is on by default and reaches none of the old content screens.** The flag defaults to `true` outside DEBUG (`PoliVerse/App/RootView.swift:9`, `:26-27`). Corsi, Carriera and Cerca are `ContentUnavailableView` placeholders (`PoliVerse/NewUI/Tabs/CoursesTab.swift:7`, `CareerTab.swift:7`, `SearchTab.swift:10`), and so is every row in the single-page panel (`PoliVerse/NewUI/SinglePage/SinglePageHome.swift:96-99`). A grep of `PoliVerse/NewUI` finds no reference to any of these: `CourseDetailView`, `WeBeepView`, `CourseMaterialsView`, `CalendarView`, `EventDetailView`, `CareerView`, `ExamDetailView`, `ExamUpdatesView`, `StudyPlanView`, `GradeSimulatorView`, `ManifestiView`, `PersonalTimetableView`, `RoomsView`, `FreeRoomsView`, `CampusMapView`, `TeacherDetailView`, `NewsView`, `NoticesView`. The only old screens it still reaches are `SettingsView`, `NotificationSettingsView` and `CareerSwitchView` (`PoliVerse/NewUI/Settings/SettingsSheet.swift:60,65,77`).
- **[V] App-level behaviour lives only in `MainTabView`.** That view handles `AppDestination` routing, pending Control Center destinations, Spotlight indexing, reminder rescheduling, `DemoModeBanner` and the unread badge (`PoliVerse/App/RootView.swift:85,93,101-137`). `NewRootView` does none of these (`PoliVerse/NewUI/NewRootView.swift:31-111`). As a result, intents that call `AppDestination.send()` (`Shared/AppDestination.swift:20-32`) and notification taps (`PoliVerse/Services/NotificationService.swift:141`) open the app and go nowhere. A destination left pending would then fire later if the student switches back to the old UI.
- **[V] NewUI departs from the spec.**
  - The spec has five tabs, including Calendario, with `sun.max` for Oggi and `.sidebarAdaptable` on iPad (`docs/information-architecture.md:21-27,79,124`). NewUI folds Calendario into Oggi (`NewRootView.swift:6-7,84`) and sets no tab view style.
  - The spec says the profile is reachable "da ogni root" (`docs/information-architecture.md:69,253`). `todayBar()` is applied only in `TodayTab.swift:27`.
  - The spec's Oggi rows push to their detail screens (`docs/information-architecture.md:82-87`). `TodaySectionView` has no Button or NavigationLink, and neither does `CurrentClassAccessory` (`PoliVerse/NewUI/Shared/TodaySectionView.swift`, `CurrentClassAccessory.swift:14-57`).
  - The spec puts the unread feed, banners and badge on Oggi (`docs/information-architecture.md:187-189`). None of them appear in NewUI.
- **[V] The two layouts offer different destinations.** The panel lists Calendario, Aule libere, Mappa and "Dal Politecnico" (`SinglePageHome.swift:77-84`). The tab layout has none of them. Its Cerca tab is the place Apple suggests for discovery content: "Choose the standard tab style to provide suggestions, promote discovery" (https://developer.apple.com/design/human-interface-guidelines/search-fields).

## 2. Placement

- **[V] Placeholder actions look live.**
  - The Aggiungi menu items have empty closures (`PoliVerse/NewUI/Shared/TodayBar.swift:80-81`), and so do Orario, Corsi and Docenti in the profile menu (`TodayBar.swift:107-109`).
  - The panel's search `TextField` writes to a `query` nothing reads (`SinglePageHome.swift:52,60`).
  - `SettingsSheet` is `.searchable`, but its `query` filters nothing (`SettingsSheet.swift:14,99`).
  - Apple: "Show people when a menu item is unavailable" (https://developer.apple.com/design/human-interface-guidelines/menus).
- **[V] Settings can become unreachable.** The Barra page toggles both Profilo and Impostazioni (`PoliVerse/NewUI/Customize/ZoneEditor.swift:291-292`), and those are the only two routes to Settings (`TodayBar.swift:41,113`). If both are hidden, the way back is ••• → Personalizza → Personalizza → Barra. The page's footer even says so (`ZoneEditor.swift:298`). That path is also the only route to sign-out, the layout switch and the old-UI switch.
- **[V] Duplicated entry points.**
  - The gear and the menu's "Impostazioni" sit side by side (`TodayBar.swift:39-43,113`).
  - `ProfileView` opens as a sheet from the menu (`NewRootView.swift:56-65`) and as a push from Settings (`SettingsSheet.swift:23-37`).
  - Esci appears in both Settings and Profilo (`SettingsSheet.swift:93`, `PoliVerse/NewUI/Settings/ProfileView.swift:54`).
  - The rows "WeBeep" and "Sviluppo e diagnostica" open the same old `SettingsView` (`SettingsSheet.swift:64-66,76-77`).
- **[J] The ••• menu is thin.** It has two items (`TodayBar.swift:86-91`), and Aggiungi also has two. Apple suggests "a minimum of three items" for a pull-down (https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons) and a More menu "only … if you really need it" (https://developer.apple.com/design/human-interface-guidelines/toolbars). "Vai a oggi" repeats the stepper's "Oggi" button (`PoliVerse/NewUI/Tabs/DayStrip.swift:31`). That leaves Personalizza as the menu's only unique item.
- **[V] The day stepper outruns the data.** It spans ±60 days (`DayStrip.swift:18-21`). NewUI loads the agenda only with `load(around: .now)` (`NewRootView.swift:99`), which covers −7 days to +1 month (`PoliVerse/Services/AgendaService.swift:70-71,170`). Nothing reloads when `shell.day` changes, so later days show an empty Oggi.
- **[J] The stepper is a popover on iPhone.** It is forced to stay a popover in compact width (`TodayBar.swift:66`). Apple says "Avoid displaying popovers in compact views" (https://developer.apple.com/design/human-interface-guidelines/popovers). The API does allow it (https://developer.apple.com/documentation/swiftui/view/presentationcompactadaptation(_:)).

## 3. Flow and modality

- **[V] Personalizza is four layers deep.**
  1. An overlay gallery (`NewRootView.swift:39-41`).
  2. A `fullScreenCover` editor with a zoom transition (`PoliVerse/NewUI/Customize/CustomizeOggi.swift:81-86`).
  3. The bento sheet, which can't be dismissed interactively (`CustomizeOggi.swift:344-350`). Inside it, pages push two levels: Layout → a section's page (`ZoneEditor.swift:410`).
  4. A sticker picker sheet on top of that sheet (`PoliVerse/NewUI/Customize/BentoPanel.swift:84-89`), plus `PhotosPicker` (`ZoneEditor.swift:118,362`).

  Profilo also opens sheets from inside a sheet (`ProfileView.swift:73`). Apple: "Display only one sheet at a time" (https://developer.apple.com/design/human-interface-guidelines/sheets). Apple: "provide a single path through the hierarchy" (https://developer.apple.com/design/human-interface-guidelines/modality). **[J]** A full-screen editor fits "a multistep task like … editing a photo" (same modality page). The extra sheets on top of it are the part to cut.
- **[V] Cancel and Done are inconsistent.**
  - In the editor, Fine saves the look and makes it the active one immediately (`CustomizeOggi.swift:250-257,271-276`). The gallery's Annulla then only moves the carousel back (`CustomizeOggi.swift:287-294`), so it can't undo that edit.
  - The editor's Annulla discards the draft without asking (`CustomizeOggi.swift:357`). While arranging, Annulla leaves both levels at once, but Fine leaves only arranging (`CustomizeOggi.swift:361-368`).
  - On a panel page, Fine only goes back to the bento and saves nothing (`ZoneEditor.swift:77-79`, `BentoPanel.swift:74-79`), and it sits next to a Back button.
  - Apple says Done means "completing a task or explicitly saving changes", and advises "getting confirmation before closing" when content could be lost (https://developer.apple.com/design/human-interface-guidelines/sheets, https://developer.apple.com/design/human-interface-guidelines/modality).
- **[V] How presentations are deferred.** `ShellState.present` stores the action. That hides the panel, and the action runs in `onDismiss` (`PoliVerse/NewUI/Shared/ShellState.swift:38-57`, `TodayTab.swift:42-45`). The API does call `onDismiss` "when dismissing the sheet" (https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:)). **[?]** If a pending action is stored before the panel is actually on screen, for example during the layout animation, `onDismiss` never fires. Nothing would open and the panel would not come back. I could not test this without running the app.

## 4. Terminology

All **[V]** unless marked.

- **"Aspetto"** has three meanings. It names a saved look (`CustomizeOggi.swift:114,172`), the light/dark tile (`ZoneEditor.swift:34`) and "Aspetto delle sezioni" (`ZoneEditor.swift:408`).
- **"Materiale"** means paper on one page (`ZoneEditor.swift:31`) and card material in the section picker (`ZoneEditor.swift:449`). Card material itself lives under "Schede" (`ZoneEditor.swift:33`). On top of that, "Materiali" means WeBeep files in the panel (`SinglePageHome.swift:77`).
- **"Schede"** means cards in Personalizza, but tabs in "in schede separate" (`PoliVerse/NewUI/Shared/AppLayout.swift:21`) and "La scheda Carriera" (`ProfileView.swift:202`). The layout picker itself says "Tab" (`AppLayout.swift:14`).
- **Layout words overlap.** "Disposizione" names both the app layout (`SettingsSheet.swift:51`) and the date layout (`ZoneEditor.swift:519`). There are also "Layout" (`ZoneEditor.swift:37`) and "Disponi" (`CustomizeOggi.swift:337`, `BentoPanel.swift:59`).
- **Zone labels don't match the pages they open** (`PoliVerse/NewUI/Shared/TodayLanding.swift:29-33` vs `ZoneEditor.swift:18-24`):
  - "Tema" opens Flavor, not Decorazione.
  - "Data" opens "Widget", a word the app already uses for Home Screen widgets.
  - "Barra e colore" opens "Barra", which has only toggles (`ZoneEditor.swift:289-299`).
- **Close and remove verbs vary.** Close appears as "Chiudi" (text, `NewRootView.swift:61`), "Chiudi" with an xmark (`SettingsSheet.swift:102`), "Fine" and "Usa". Remove appears as "Togli" (`TodayLanding.swift:302`) and "Rimuovi" (`TodayLanding.swift:199`). **[J]**

## 5. Switching layout

- **[V] What survives:** the day, the sheets and the panel detent all live in `ShellState` above both layouts (`ShellState.swift:11-31`). Settings closes before the animation runs (`NewRootView.swift:43-55`).
- **[V] What is lost:** switching to the single page forces the selection to Oggi (`NewRootView.swift:76`). The panel's search text and its pushed row are local `@State`/`NavigationStack` inside the sheet (`SinglePageHome.swift:52,55`). The sheet closes on every `present` call, so opening the day popover, for example, resets the panel. **[J]** This follows from the view being torn down, but I did not observe it at runtime.
- **[V] The current class moves.** With tabs it is the bottom accessory, and the panel row replaces it on the single page (`NewRootView.swift:98`, `SinglePageHome.swift:70-74`). Three presets also add a "Lezione in corso" section (`PoliVerse/NewUI/Customize/TodayStyle.swift:215,278,317`), so the class appears twice. Hiding the accessory needs iOS 26.1 (https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(isenabled:content:)). On 26.0, "Nessuna lezione oggi" stays visible (`CurrentClassAccessory.swift:83-91`).
- **[V] Bar customisation behaves the same in both layouts.** Both use `todayBar()` from `TodayTab`. Gallery cards leave out the tab bar on the single page (`CustomizeOggi.swift:199`), but they don't draw the panel either.

## 6. Code vs docs and commits

- **[V] Stale comment.** `NewRootView.swift:11-12` says "Not wired into the app yet". Commit `f0690c9` and `RootView.swift:26-27` say otherwise.
- **[V] `-NewUI` skips login and onboarding** (`PoliVerse/App/PoliVerseApp.swift:154`). Under that flag, "Torna all'interfaccia attuale" (`SettingsSheet.swift:81-84`) does nothing.
- **[V] Saved looks can't be deleted.** Personalizza starts with nine presets (`TodayStyle.swift:352-355`, commit `c2c61c2`). The only removal in `CustomizeOggi.swift` drops a new look that was cancelled before saving (`:261-268`).
- **[V] Intent matches for Personalizza.** Commit `f3886c9` says Personalizza opens only from Oggi, and it does (`TodayBar.swift:89`).

## Not verified

- Runtime behaviour: the deferral race above, the navigation bar on pushed panel pages, and iPad layout.
- Whether career and deadline data for Oggi's sections arrives at launch. NewUI loads only the agenda. `FreshnessCoordinator.revalidate` runs every load when the app becomes active (`PoliVerse/Services/FreshnessCoordinator.swift:94-117`), which probably covers it.
- How `.searchTabSelection` interacts with a placeholder tab. The API says the previous tab is "reselected" when search is dismissed (https://developer.apple.com/documentation/swiftui/tabsearchactivation/searchtabselection).

## Open questions for the owner

1. Is Calendario deliberately merged into Oggi? If so, update `docs/information-architecture.md` §1 and §3, and remove Calendario from the panel.
2. Should the single page and the tabs expose exactly the same destinations?
3. Should `usesNewInterface` default to `true` outside DEBUG before Corsi, Carriera and Cerca exist?
4. In Personalizza, should the editor's Fine commit the look, or should only the gallery's ✓ ("Usa") commit it?
5. Should the bar keep a guaranteed route to Impostazioni?
6. Which name is canonical for each pair: Aspetto or Look, Schede or Tab, Materiale or Carta?
