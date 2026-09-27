# A Mac app and a menu bar extra for PoliVerse

Researched 2026-09-26, on `watch-rinnovato` at `80ede46`. Read-only: I read the code, the project file, the entitlements and the repo's docs, and I did not build or run anything. I did not try a macOS build, so the "compiles" statements below come from grepping for symbols whose Apple availability excludes macOS. They are not compiler output.

Method: Apple availability comes from each page's `metadata.platforms` in its developer.apple.com JSON (`https://developer.apple.com/tutorials/data/documentation/<path>.json`), fetched on 2026-09-26. Each URL below is the human-readable form of that page. "What's new" comes from the June 2026 entries on the Updates pages, the macOS 27 release notes, and the WWDC26 session pages and their transcripts. Human Interface Guidelines pages were read from their JSON too. One non-Apple fact, about how CIE sign-in works on a desktop, comes from the Ministry of the Interior's own CIE site, which is the primary source for it. I cite no blogs.

Labels: **[V]** verified in code, in the project file or on a fetched page. **[J]** judgement call. **[?]** not verified.

Updates pages read (June 2026 entries, unless the page has none):
- SwiftUI https://developer.apple.com/documentation/updates/swiftui (it also has a September 2026 section)
- AppKit https://developer.apple.com/documentation/updates/appkit
- App Intents https://developer.apple.com/documentation/updates/appintents
- Foundation Models https://developer.apple.com/documentation/updates/foundationmodels
- MetricKit https://developer.apple.com/documentation/updates/metrickit
- Core Spotlight https://developer.apple.com/documentation/updates/corespotlight
- SwiftData https://developer.apple.com/documentation/updates/swiftdata
- Bundle Resources https://developer.apple.com/documentation/updates/bundleresources
- Xcode https://developer.apple.com/documentation/updates/xcode
- UIKit https://developer.apple.com/documentation/updates/uikit
- No June 2026 entry: WidgetKit (latest is June 2025), ActivityKit (June 2025), AuthenticationServices, Background Tasks, User Notifications, Security, Foundation, Swift.
- macOS 27 release notes https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes, plus the 27.2 beta 2 notes.

---

> **Implemented on `mac-app` (2026-09-27).** The `PoliVerse` target now builds for macOS 27 (`SUPPORTED_PLATFORMS` adds `macosx`, sandbox entitlements in `Config/PoliVerseMac.entitlements`), and so does `PoliVerseWidgets` (`Config/PoliVerseWidgetsMac.entitlements`); the Watch embed is filtered to iOS. What was built, against the plan below:
> - Phase 1: the main `Window` with a `NavigationSplitView` sidebar (`Features/Mac/MacSidebarShell.swift`), a Mac Oggi (`MacTodayView.swift`), `MenuBarExtra` in `.window` style with `isInserted:` (`MenuBarExtraViews.swift`), a `Settings` scene with a Barra dei menu pane, `SMAppService` login item, menu-bar-only mode through the activation policy, `NSBackgroundActivityScheduler` refresh (`BackgroundRefresh.swift`), a Vai menu (`MacAppSupport.swift`), and `kSecUseDataProtectionKeychain` in `KeychainStore`.
> - Phase 2, in part: the widget extension and its three controls build and register on the Mac; App Intents compile unchanged.
> - Replacements: Quick Look (`FilePreview`), a write-only EventKit save (`AddToCalendarSheet`), an `AVPlayerView` window (`RecordingPlayer`), `NSScrollView` magnification (`FloorPlanView`), a Live Activity stub, and the shims in `DesignSystem/PlatformCompatibility.swift`.
> - Found while building: an `@AppStorage` on the `App` struct next to a `MenuBarExtra` loops forever (the status item writes to user defaults), and a `TimelineView` in the extra's label does too; both are avoided in the code.
> - Corsi is a course list beside the selected course (`MacCoursesView.swift`): its materials as a sortable `Table` with Quick Look on the space bar, open on double click, download, Show in Finder and Share in the context menu; the iPhone's course page is one switch away. Lecture, sitting and deadline details open in an `inspector` beside the page (`detailPresentation` in `PlatformCompatibility.swift`), on Oggi and Carriera alike.
> - Not done yet: Handoff, and signing in with a real account on the Mac.

## TL;DR

**Recommended architecture [J]:**

1. **A native SwiftUI Mac app, not Mac Catalyst and not "Designed for iPad".** The feature the owner asked for, `MenuBarExtra`, is **macOS-only: it is not available in Mac Catalyst** (platforms: macOS 13.0 only, https://developer.apple.com/documentation/swiftui/menubarextra) **[V]**. The same holds for `Settings`, `SettingsLink`, `Window` and `UtilityWindow` **[V]**, and for AppKit's `NSStatusItem` **[V]**. Apple's guidance for a SwiftUI app is one multiplatform target **[V]** (see §1).
2. **Add a macOS destination to the existing `PoliVerse` target** and set `MACOSX_DEPLOYMENT_TARGET = 27.0`. That keeps one bundle ID (`segrini.samuele.PoliVerse`, `project.pbxproj:671,702`), which universal purchase requires **[V]**. It also matches the iOS 27 floor, so `MetricManager`, StateReporting and `asyncImageURLSession`, which are already used unguarded, need no `#available` **[V]**. macOS 27 runs only on Apple silicon, so nothing is lost there **[V]**.
3. **The "navbar extension" is a SwiftUI `MenuBarExtra` scene in the same app**, with `.menuBarExtraStyle(.window)`, drawn from the same `@Observable` models the iPhone screens read. The app is a regular app (Dock icon, main window). The extra can be removed through `MenuBarExtra(isInserted:)`, and launching at login is opt-in through `SMAppService.mainApp` (§2).
4. **The Mac signs in by itself** through the same `WKWebView` flow, and holds its own token in the data-protection keychain. It does not borrow the iPhone's token: the Politecnico rotates refresh tokens, so two devices sharing one pair would log each other out (§5.10).
5. **Put the existing `PoliVerseWidgets` extension on macOS too**, without the Live Activity. That gives desktop and Notification Center widgets, plus the three existing controls, which on macOS 26+ people can place **in the menu bar** (§2.7, §4).

**Prioritised APIs:**

| Priority | API | macOS | Why |
|---|---|---|---|
| Must | `MenuBarExtra` + `.menuBarExtraStyle(.window)` + `isInserted:` | 13.0 | The feature itself |
| Must | `WindowGroup` + `NavigationSplitView` / `TabView(.sidebarAdaptable)` | 11.0 / 15.0 | The main window; `RootView.swift:385` already applies `.sidebarAdaptable` |
| Must | `Settings` scene, `SettingsLink`, `openSettings`, `openWindow` | 11.0 / 14.0 / 14.0 / 13.0 | Mac settings conventions; opening the main window from the extra |
| Must | `SMAppService.mainApp` | 13.0 | Launch at login, opt-in only (App Review 2.4.5(iii)) |
| Must | `NSBackgroundActivityScheduler` | 10.10 | Stands in for `BGTaskScheduler`, which is **not** on macOS |
| Must | `TimelineView(.everyMinute)`, `Text(timerInterval:)` | 12.0 / 13.0 | Countdowns without refetching |
| Must | `kSecUseDataProtectionKeychain` in `KeychainStore` | 10.15 | Without it, SecItem on macOS goes to the legacy file-based keychain |
| Must | App Sandbox + `network.client` (+ calendars, downloads, user-selected files) | 10.7 | Mac App Store requirement |
| Must | `NSViewRepresentable` for `AuthWebView` | 10.15 | Login is a `UIViewRepresentable` today |
| Should | WidgetKit on macOS (system families), `ControlWidget` in the menu bar and Control Center | 11.0 / 26.0 | Glanceable data plus quick actions; the code already exists |
| Should | App Intents + App Shortcuts, **Spotlight actions on Mac**, `IndexedEntity` | 13.0 / 26 / 15.0 | The entities and intents already exist in `App/` |
| Should | `quickLookPreview`, `.draggable` / `Transferable`, `ShareLink`, `fileExporter` | 11.0 / 13.0 / 13.0 / 11.0 | Materials behaving like files on a Mac |
| Should | `.commands` / `CommandMenu` / `keyboardShortcut`, `FocusedValue` | 11.0 | What a Mac user expects: ⌘R to refresh, ⌘1–4 for sections |
| Should | `NSUbiquitousKeyValueStore` for non-secret settings (look, favourites) | 10.7 | Personalizza following the student to the Mac |
| Should | `MetricManager` + StateReporting | 27.0 / 27.0 | The existing pipeline compiles unchanged at a 27 floor |
| Nice | Foundation Models (`NoticeSummary`), `SpotlightSearchTool` | 26.0 / 27.0 | Already imported; `SpotlightSearchTool` is new in 27 |
| Nice | Handoff (`NSUserActivity`, `SyncableEntity`) | 10.10 / 27.0 | Continue from iPhone to Mac |
| Nice | `UtilityWindow`, `Window`, `defaultLaunchBehavior`, `windowResizability` | 15.0 / 13.0 / 15.0 / 13.0 | A floating "Oggi" window; a mode with no window at launch |
| Nice | `NSStatusItem` + `expandedInterfaceSession` | 27.0 (session) | Only if `MenuBarExtra` isn't enough |

**Surprises [V]:**
- **`BGTaskScheduler` / `BGAppRefreshTask` are not available on native macOS**, only in Mac Catalyst. `NSBackgroundActivityScheduler` takes their place.
- **ActivityKit is not available on native macOS.** `Activity`, `ActivityAttributes` and `ActivityConfiguration` are iOS/iPadOS only. Even so, **the iPhone's Live Activities already appear in the Mac menu bar** (macOS 26), and clicking one opens iPhone Mirroring. PoliVerse's lecture/exam Live Activity should therefore show up on a Mac today with no Mac code.
- **The iPhone's widgets already appear on the Mac desktop** as "remote widgets".
- **Controls do not travel from iPhone to Mac.** On Mac, people place controls "from your macOS app", in Control Center **or as menu bar items**. They are not a glanceable display: no timeline, and they update only on interaction, on an app reload or through a push.
- **Accessory widget families (`accessoryRectangular` / `Circular` / `Inline`) don't exist on macOS**, and `RelevanceConfiguration` (the Watch Smart Stack card) is watchOS-only.
- **`setAlternateIconName` is not on macOS**, so Personalizza's icon picker has no Mac equivalent. **`EKEventEditViewController` (EventKitUI) and `QLPreviewController` are not on macOS** either.
- **macOS 27 hides menu item symbol images by default**, in the menu bar, in context menus and in SwiftUI menus. A `.menu`-style extra with icons will draw no icons unless it opts back in with `.labelStyle(.titleAndIcon)`.
- The HIG says a menu bar extra should show **"a menu — not a popover"** unless the content is too complex for a menu. This is a design decision to make on purpose (§2.2).

---

## Codebase readiness

### What's there today

- **[V]** Targets: `PoliVerse` (iOS app), `PoliVerseWidgets` (app extension), `PoliVerseWatch`, `PoliVerseWatchWidgets`, `PoliVerseTests`, `PoliVerseUITests` (`project.pbxproj:213-354`).
- **[V]** The project-level `SDKROOT = iphoneos` (`:578,637`). `IPHONEOS_DEPLOYMENT_TARGET = 27.0` (`:573,633,756,787`). The Watch targets set `SDKROOT = watchos`, `SUPPORTED_PLATFORMS = "watchsimulator watchos"` and `WATCHOS_DEPLOYMENT_TARGET = 26.0` (`:858-867`). **No `MACOSX_DEPLOYMENT_TARGET`, no `SUPPORTS_MACCATALYST` and no `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD`** appear anywhere in the file. `TARGETED_DEVICE_FAMILY = "1,2"` (`:675,706`).
- **[?]** With `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD` unset, Xcode's default decides whether the iPad build can run on Apple-silicon Macs. Whether the app is offered on the Mac App Store as an iPad app is an App Store Connect setting I can't see.
- **[V]** Swift settings: `SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_STRICT_CONCURRENCY = complete` (`:581-585`).
- **[V]** Entitlements: every target has only `com.apple.security.application-groups = group.segrini.samuele.PoliVerse` (`Config/*.entitlements`). There is no `keychain-access-groups`, no sandbox and no network entitlement. On macOS a sandboxed app needs at least `com.apple.security.app-sandbox` and `com.apple.security.network.client`.
- **[V]** Info.plist: `BGTaskSchedulerPermittedIdentifiers`, the URL schemes `segrini.samuele.PoliVerse` (CIE return) and `poliverse` (Moodle token), `LSApplicationQueriesSchemes` `CIEID`, and `UIBackgroundModes` `fetch`/`audio` (`Config/Info.plist:7-56`). The build settings add `NSCalendarsFullAccessUsageDescription`, `NSSupportsLiveActivities` and iOS orientations (`project.pbxproj:661-666`).
- **[V]** The `PoliVerse` target's build phases include **"Embed Foundation Extensions"** (the widgets) and **"Embed Watch Content"** (`project.pbxproj:215-221`). With a macOS destination on this target, the Watch embed has to be filtered to iOS, and the widget embed has to be the macOS build of the extension.
- **[V]** Synchronized folder groups: `PoliVerse` and `Shared` feed the app target, `Shared` + `PoliVerseWidgets` the widgets, and `Shared` + `PoliVerseWatch` the Watch (`project.pbxproj:98-134,227-230`). A file that must not build for macOS needs a per-file platform filter, or an `#if os(iOS)` wrapper.

### How much is already portable

Grep for iOS-only symbols (UIKit types, `navigationBarTitleDisplayMode`, `topBarLeading/Trailing`, `textInputAutocapitalization`, `keyboardType`, `fullScreenCover`, `tabViewBottomAccessory`, `.page` tab style, `insetGrouped`, `.navigationBar`/`.tabBar` placements, ActivityKit, BackgroundTasks, EventKitUI, `QLPreviewController`, `setAlternateIconName`). Each symbol's availability was checked against its Apple page (§3 table).

| Area | Files | Files with an iOS-only symbol | Notes |
|---|---:|---:|---|
| `PoliVerse/Model` | 158 | 6 (+1, see below) | The model layer imports no SwiftUI **[V]** (`grep "import SwiftUI" PoliVerse/Model` → 0) |
| `PoliVerse/App` | 7 | 0 by symbol, 2 by dependency | `PoliVerseApp.swift`, `AppShellDuties.swift` call Watch/background APIs |
| `PoliVerse/DesignSystem` | 9 | 2 | `Theme.swift` (`UIColor`), `PreviewSupport.swift` (by dependency) |
| `PoliVerse/Features` | 129 | 59 | **33 of the 67 flagged files only use `navigationBarTitleDisplayMode` / `topBarLeading|Trailing`**, which one shim modifier solves |
| `Shared` | 12 | 0 | `WatchBridge.swift` and `LectureActivity.swift` are already wrapped in `#if canImport(...)` |
| `PoliVerseWidgets` | 9 | 3 | Live Activity, previews, accessory families |

- **[V]** Across `PoliVerse/`: 67 of 303 files hit the grep. 33 of those need only the nav-bar shim, which leaves **about 34 files of real work**. 236 files (78%) contain none of these symbols.
- **[J]** That is not the same as "compiles". Some APIs outside the grep will surface at build time. The shape is still clear: the data layer, the `Store` pipeline, the auth logic and the Shared snapshot types are portable. The Features layer needs a Mac pass anyway, for layout reasons.

### Sites that need `#if os(macOS)` or a replacement

**Model / App (the ones that decide the architecture):**

| Site | Problem on macOS | Replacement | Label |
|---|---|---|---|
| `Model/Platform/BackgroundRefresh.swift:1,30-60`; `PoliVerseApp.swift:72,206-231,291` | `BGTaskScheduler` is iOS/Catalyst only (https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler) | `NSBackgroundActivityScheduler` (macOS 10.10) running the same closure (§2.6) | [V] |
| `Model/Platform/LiveActivityController.swift:1`; used by `ExamDetailView.swift:39,79,330-359`, `ConnectionsView.swift:36`, `PreviewSupport.swift:69` | `Activity` is iOS/iPadOS only (https://developer.apple.com/documentation/activitykit/activity) | A macOS stub with `isAvailable == false`. The views already handle "not available" (`ExamDetailView.swift:348,355`) | [V] / [J] |
| `Shared/WatchBridge.swift:1` (whole file inside `#if canImport(WatchConnectivity)`) → `Model/Platform/WatchSync.swift:29`, `PoliVerseApp.swift:215,234-237`, `AppShellDuties.swift:77` | WatchConnectivity: iOS, iPadOS, Catalyst, visionOS, watchOS, no macOS (https://developer.apple.com/documentation/watchconnectivity). `WatchBridge` disappears, and its callers break | `#if os(iOS)` around `WatchSync` and its three call sites | [V] |
| `Model/Identity/CieIDBridge.swift:2`, `CieIDRouter.swift:4,88,99` | `UIApplication.shared.open`; the CieID app hand-off is an iPhone concept | Leave it out of macOS and let the IdP's desktop CIE flow run in the web view (§5.11) | [V] / [J] |
| `Model/Recordings/WebexPlayback.swift:2,174` | `UIApplication.shared.connectedScenes` to find a window | `NSApp.keyWindow`, or a SwiftUI-side anchor | [V] / [J] |
| `Model/Diagnostics/DiagnosticsCollector.swift:60,95` | `UIDevice`, `UIApplication.backgroundRefreshStatus` | `ProcessInfo.operatingSystemVersionString`; drop the refresh-status field | [V] / [J] |
| `Model/Support/KeychainStore.swift:24-72` | No `kSecUseDataProtectionKeychain`, so on macOS SecItem targets the **file-based** keychain, and `kSecAttrAccessible` (`:31`) only has meaning in the data-protection keychain (TN3137) | Add `kSecUseDataProtectionKeychain: true` to every query. It is ignored on iOS, so it can go in unconditionally | [V] |
| `PoliVerseApp.swift:355` `.backgroundTask(.urlSession(...))` | Available on macOS 13 (https://developer.apple.com/documentation/swiftui/backgroundtask/urlsession) | None needed | [V] |
| `Model/Diagnostics/PerformanceMonitor.swift:71`, `PerfSignpost.swift:57`, `PerformanceStates.swift:2-3` | `MetricManager` and StateReporting are macOS 27.0 | None needed at a 27 floor | [V] |
| `Model/Materials/NoticeSummary.swift:2,73,89` | Foundation Models is macOS 26.0 | None needed | [V] |

**Features / DesignSystem (UI adaptation):**

| Site | iOS-only API | Mac equivalent | Label |
|---|---|---|---|
| `DesignSystem/Theme.swift:68-81` | `UIColor { traits in … }` dynamic colour | `NSColor(name:dynamicProvider:)`, or asset-catalogue colours | [V] / [J] |
| `Features/Auth/AuthWebView.swift:28` | `UIViewRepresentable` around `WKWebView` | `NSViewRepresentable` (macOS 10.15); the `WKNavigationDelegate` logic is shared | [V] |
| `Features/Customize/AppLook.swift:2,299-302` | `setAlternateIconName` (iOS/Catalyst only) | None for the app icon. `NSApplication.applicationIconImage` changes only the Dock tile of the running app | [V] / [J] |
| `Features/WeBeep/FilePreview.swift:2,9` | `QLPreviewController` (iOS/Catalyst/visionOS) | `.quickLookPreview(_:)` (macOS 11) | [V] |
| `Features/Career/AddToCalendarSheet.swift:1-9` | `EKEventEditViewController` (EventKitUI, no macOS) | Save through `EKEventStore` with write-only access (macOS 14); `CalendarExporter` already does the rest | [V] |
| `Features/Recordings/RecordingPlayer.swift:1-3,200` | UIKit scene lookup for PiP | `VideoPlayer` (macOS 11) / `AVPlayerView` (macOS 10.9); `AVPictureInPictureController` exists on macOS 10.15 | [V] |
| `Features/Search/FloorPlanView.swift:14,34,63,108` | `UIImage`, `fullScreenCover` (no macOS), `UIScrollView` zoom | `NSImage`, a `Window` or `.sheet`, `MagnifyGesture` / `ScrollView` magnification | [V] / [J] |
| `Features/Customize/StickerViews.swift:2,158-166,224` | `UIImage` cache, emoji keyboard `UIViewRepresentable` | `NSImage`; the Character Viewer (Edit ▸ Emoji & Symbols) replaces the keyboard | [V] / [J] |
| `Features/Customize/ZoneEditor.swift:863-887`, `NewLookGallery.swift:92` | `UIImage` resize via `UIGraphicsImageRenderer` | `ImageRenderer` or Core Graphics | [V] / [J] |
| `Features/Customize/CustomizeOggi.swift:649` | `UIGestureRecognizerRepresentable` (iOS 18 / Catalyst) | `NSGestureRecognizerRepresentable` (macOS 26.0) or a SwiftUI gesture | [V] |
| `Features/Customize/SectionFormPicker.swift:141` | `.tabViewStyle(.page)` (no macOS) | A horizontal `ScrollView` with `.scrollTargetBehavior(.paging)` | [V] / [J] |
| `Features/Home/CoursePageKit.swift:274` | `.insetGrouped` list (iOS/Catalyst/visionOS) | `.inset` or `.sidebar` on macOS | [V] |
| `Features/Shell/CurrentClassAccessory.swift:13,111` | `tabViewBottomAccessory` (iOS/iPadOS/Catalyst 26.1) | Show the current class in the menu bar extra and in a toolbar item | [V] / [J] |
| `Features/Shell/TodayTab.swift:63`, `SinglePageHome.swift:111`, `Customize/BentoPanel.swift:75` | `ToolbarPlacement.tabBar` / `.navigationBar` (no macOS) | `#if os(iOS)`; `toolbarVisibility` itself is on macOS 15 | [V] |
| `Features/Settings/ProfileView.swift:194`, `Home/CourseInfoView.swift:386`, `Settings/ConnectionsView.swift:499`, `Auth/CareerDiagnosticsView.swift:62` | `UIPasteboard.general` | `NSPasteboard.general`, or SwiftUI `.copyable(_:)` (macOS 13) | [V] |
| `Features/Auth/NotificationSettingsView.swift:86` | `UIApplication.openSettingsURLString` | Open System Settings ▸ Notifications | [V] / [?] (the macOS deep link is not documented on the pages I read) |
| `Features/Flavors/BlueprintKit.swift:36-38`, `Onboarding/FeatureTour.swift:714`, `Settings/StudentCard.swift:398` | `UIFont`/`UIFontMetrics`, `UIColor.resolvedColor`, `UIImage(named:)` | `Font.system(.body, design: .monospaced)`; `Color.resolve(in:)`; `NSImage(named:)` | [V] / [J] |
| 5 files: `CourseRecordingsView.swift:212-213`, `SearchView.swift:306`, `ManifestoDetailView.swift:132`, `PersonalTimetableView.swift:355,359`, `ZoneEditor.swift:357,480` | `keyboardType`, `textInputAutocapitalization` | Omit on macOS | [V] |
| 41 files | `navigationBarTitleDisplayMode` (56 uses) | A one-line `View` extension that is a no-op on macOS | [V] |
| 12 files | `.topBarLeading/.topBarTrailing` (22 uses) | `.navigation`, `.primaryAction`, or `.automatic` on macOS | [V] |

Already fine on macOS: `glassEffect` (20 sites, macOS 26), `sensoryFeedback` (15 files, macOS 14), `presentationDetents` / `DragIndicator` / `BackgroundInteraction` / `CornerRadius` (macOS 13-13.3), `tabBarMinimizeBehavior` (`RootView.swift:368`, macOS 26), `sidebarAdaptable` (`RootView.swift:385`, macOS 15), `ShareLink`, `searchable`, `contentMargins`, `PhotosPicker` (macOS 13), `PDFKit`, MapKit `Map` (macOS 11; no user-location use found), `CoreSpotlight`, `UserNotifications`, `WidgetCenter` (macOS 11; `currentConfigurations()` macOS 15) **[V]**.

**Widgets extension:**
- **[V]** `LectureLiveActivity.swift` and `WidgetPreviews.swift` import ActivityKit, so they need an iOS-only filter. The Live Activity entry in `PoliVerseWidgetBundle.swift:19` also needs `#if os(iOS)`.
- **[V]** `supportedFamilies` lists accessory families: `CareerWidget.swift:92`, `FreeRoomsWidget.swift:255`, `NextLectureWidget.swift:113-114`. `accessoryRectangular`, `accessoryCircular` and `accessoryInline` have no macOS availability (https://developer.apple.com/documentation/widgetkit/widgetfamily/accessoryrectangular, …/accessorycircular, …/accessoryinline). `.gaugeStyle(.accessoryCircular)` does exist on macOS 13.
- **[V]** `ControlWidgets.swift` needs no change. `ControlWidget`, `StaticControlConfiguration` and `ControlWidgetButton` are macOS 26.0.
- **[J]** `Shared/AppDestination.swift` (App Intents + SwiftUI), `OfflineStore.swift`, `AgendaEvent.swift` and the snapshot types are Foundation or App Intents code with no platform APIs.

---

## 1. Target strategy

### The four options

| | Native SwiftUI (multiplatform target) | Separate native macOS target | Mac Catalyst | iPad app on Mac ("Designed for iPad") |
|---|---|---|---|---|
| `MenuBarExtra` | **Yes** | **Yes** | **No** (macOS only) | **No** |
| `Settings` / `Window` / `UtilityWindow` scenes | Yes | Yes | No | No |
| `NSStatusItem` | Yes | Yes | No (AppKit only where Catalyst is listed) | No |
| Controls in the Mac menu bar | Yes, from the macOS app | Yes | Catalyst 18 listed [?] where they land | [?] |
| Same bundle ID (universal purchase) | Yes | Yes (set it the same) | Yes (Xcode 11.4+) | Same binary |
| Code sharing | Maximum; `#if os()` inside files | Needs file membership across the synchronized `PoliVerse` group | UIKit code as is | Everything, unchanged |
| Look | Mac controls, Mac menus | Same | iPad idiom or "Optimize for Mac" | iPad in a window |

Evidence:
- **[V]** `MenuBarExtra`: "macOS 13.0" only (https://developer.apple.com/documentation/swiftui/menubarextra). `Settings` macOS 11.0, `SettingsLink` 14.0, `Window` 13.0, `UtilityWindow` 15.0, all without Mac Catalyst (https://developer.apple.com/documentation/swiftui/settings, …/settingslink, …/window, …/utilitywindow). `NSStatusItem` lists only macOS (https://developer.apple.com/documentation/appkit/nsstatusitem).
- **[V]** "Mac apps built with Mac Catalyst can only use AppKit APIs marked as available in Mac Catalyst" (https://developer.apple.com/documentation/uikit/mac-catalyst).
- **[V]** iOS apps on Mac run "unmodified … on Apple silicon with no porting process" and use "the same frameworks and infrastructure that Mac Catalyst apps use". Apple suggests opting out "if you already have a macOS app" (https://developer.apple.com/documentation/apple-silicon/running-your-ios-apps-in-macos).
- **[V]** Apple's recommendation for this situation: "if your existing app uses SwiftUI and you plan to use SwiftUI for the new platform, use one multiplatform target … iOS, iPadOS, macOS, tvOS, and visionOS apps can share a single target. watchOS apps remain in a separate target." The same page shows adding a `MenuBarExtra` inside `#if os(macOS)` in the shared `App` body (https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target).

### Recommendation

- **[J]** Add a **Mac** destination to the `PoliVerse` target. Reasons:
  1. It is the only path that gives `MenuBarExtra` without leaving SwiftUI.
  2. The synchronized `PoliVerse` folder group is shared automatically.
  3. `PoliVerseApp` stays one composition root: its `init()` builds the whole model graph (`PoliVerseApp.swift:87-238`), and the Mac needs exactly that graph.
  4. The bundle ID stays the same for universal purchase.
- **[J]** The `body` becomes, roughly:

```swift
var body: some Scene {
    WindowGroup { RootView() /* .environment(...) as today */ }
    #if os(macOS)
    .commands { PoliVerseCommands() }
    MenuBarExtra(isInserted: $showsMenuBarExtra) { MenuBarPanel() } label: { MenuBarLabel() }
        .menuBarExtraStyle(.window)
    Settings { MacSettingsView() }
    #endif
}
```

  The environment chain on `RootView` (`PoliVerseApp.swift:243-273`) should become one `ViewModifier`, so that the menu bar panel and the settings window receive the same models. Without that, the three scenes would drift apart.
- **[?]** The App Store Connect help page on adding platforms says that macOS builds must be uploaded "from a separate Xcode target", with bundle IDs set to match the iOS app (https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/). The Xcode page above says one multiplatform target is fine. I read these as describing archives (one per platform) rather than project structure, but that is my interpretation. Check it with a first TestFlight upload before committing to either layout.
- **[J]** A separate `PoliVerseMac` target is the fallback. The synchronized `PoliVerse` root group would need membership exceptions for every iOS-only file, and those exceptions are the kind of project-file churn the repo moved to synchronized groups to avoid (`README.md`, "Layout").
- **[J]** Keep the Watch as it is. It is fed by the phone over WatchConnectivity, which has no macOS counterpart.

---

## 2. The menu bar extra

### 2.1 `MenuBarExtra` (SwiftUI)

- **What:** "A scene that renders itself as a persistent control in the system menu bar." `init(isInserted:content:label:)` binds its presence to a setting. An app that is *only* a menu bar extra "will be automatically terminated if the user removes the extra from the menu bar". For "more complex or data rich menu bar extras", Apple points to `.menuBarExtraStyle(.window)`, "a popover-like window".
- **macOS:** 13.0 (scene, styles, `isInserted:` initialisers).
- **Source:** https://developer.apple.com/documentation/swiftui/menubarextra, https://developer.apple.com/documentation/swiftui/scene/menubarextrastyle(_:), https://developer.apple.com/documentation/swiftui/windowmenubarextrastyle, https://developer.apple.com/documentation/swiftui/pulldownmenubarextrastyle **[V]**
- **PoliVerse [J]:** The panel reads `AgendaModel`, `CareerModel`, `UpdateFeed`, `WeBeepModel` and `FreeRoomsModel` from the environment, the same way the Oggi screen does. It never fetches; it calls `load()` like any screen (`Architecture.md`, "Where a screen's data comes from"). Suggested contents, top to bottom:
  1. The current or next lecture: name, room, `Text(timerInterval:)` countdown, and a "Mappa" link to `AppDestination`.
  2. Today's remaining lectures.
  3. The next exam sitting, with its enrolment state.
  4. New WeBeep materials (`UpdateFeed` already classifies them) and assignment deadlines.
  5. Career figures (average, CFU) from `CareerSnapshot`.
  6. A footer with the freshness line (`DataStatus`), "Apri PoliVerse", `SettingsLink` and Esci.
- **The label [J]:** `MenuBarExtra(content:label:)` accepts a view. A short dynamic label ("10:15 · B.2.3", or only a symbol) is possible, but it should stay short, because "if there are too many menu bar extras, the system may hide some" (HIG, below). A setting should choose between "solo icona" and "icona + prossima lezione".

### 2.2 Menu or window: the HIG tension

- **[V]** HIG, "The menu bar" › "Menu bar extras":
  - "Display a menu — not a popover — when people click your menu bar extra. Unless the app functionality you want to expose is too complex for a menu, avoid presenting it in a popover."
  - "Let people — not your app — decide whether to put your menu bar extra in the menu bar."
  - "Avoid relying on the presence of menu bar extras."
  - "Consider using a symbol … The menu bar's height is 24 pt."

  (https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)
- **[V]** macOS 27: "menu bar and context menus present a reduced set of menu item images … By default, SwiftUI now hides all menu item symbol images in most contexts … Use the `labelStyle(_:)` view modifier with the `.titleAndIcon` style" to keep one (macOS 27 release notes, SwiftUI and AppKit sections). Also new in 27: "a `LabeledContent` view used inside a `Menu` maps its value to the platform menu item's subtitle".
- **[J]** PoliVerse's glance is mostly *display*: countdowns, a list, figures. A menu is built for *commands*. That makes `.window` defensible under the HIG's "too complex for a menu" clause. There is still a cheaper, very native `.menu` version: sections of items with `LabeledContent` subtitles ("Analisi 2" · "10:15 · B.2.3"), where each item opens the main window at an `AppDestination`. The style is a one-line switch, so prototype both. The recommendation is `.window` for the default, because it can reuse the existing cards and countdowns. The `isInserted` toggle belongs in Settings and in onboarding.

### 2.3 Agent app or regular app

- **[V]** `LSUIElement`: "whether the app is an agent app that runs in the background and doesn't appear in the Dock" (macOS 10.0, https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement). The `MenuBarExtra` page recommends it for apps that *only* live in the menu bar.
- **[V]** `NSApplication.setActivationPolicy(_:)` (macOS 10.6) switches between regular and accessory at runtime (https://developer.apple.com/documentation/appkit/nsapplication/setactivationpolicy(_:)). `NSApplication.activate()` is macOS 14 (https://developer.apple.com/documentation/appkit/nsapplication/activate()).
- **[J]** PoliVerse is a full app (Corsi, Carriera, Cerca, Personalizza), so **don't set `LSUIElement`**. Ship a regular app with a Dock icon and add a setting, "Mostra solo nella barra dei menu", that switches the activation policy to `.accessory`. Opening the main window from the extra then means `openWindow(id:)` followed by `NSApp.activate()`.

### 2.4 Launch at login: `SMAppService`

- **What:** `SMAppService.mainApp` is "an app service object that corresponds to the main application as a login item". It also exposes `register()`, `unregister()`, `status` and `openSystemSettingsLoginItems()`.
- **macOS:** 13.0 (also Mac Catalyst 16.0).
- **Source:** https://developer.apple.com/documentation/servicemanagement/smappservice, https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp **[V]**
- **Rules [V]:** Mac App Store apps "may not auto-launch or have other code run automatically at startup or login without consent" (App Review Guidelines 2.4.5(iii), https://developer.apple.com/app-store/review/guidelines/).
- **PoliVerse [J]:** A toggle "Apri PoliVerse all'accesso", off by default. It should read `status`, because the student can turn the login item off in System Settings.

### 2.5 `NSStatusItem` (AppKit), when SwiftUI isn't enough

- **What:** "An individual element displayed in the system menu bar". macOS 27 adds `expandedInterfaceDelegate` / `expandedInterfaceSession` ("tracks the lifecycle of the status item's active expanded interface", macOS 27.0).
- **Source:** https://developer.apple.com/documentation/appkit/nsstatusitem, https://developer.apple.com/documentation/appkit/nsstatusitem/expandedinterfacesession **[V]**
- **WWDC26 "Modernize your AppKit app"** covers status-item keyboard navigation and the expanded interface session, then adds: "SwiftUI menu bar extras do a lot of this work for you!" (https://developer.apple.com/videos/play/wwdc2026/289/) **[V]**
- **WWDC26 "Use SwiftUI with AppKit and UIKit"** shows `NSHostingSceneRepresentation` (macOS 26.0) adding a `MenuBarExtra` to an AppKit app. It also recommends a Settings toggle that controls whether the extra is inserted (https://developer.apple.com/videos/play/wwdc2026/272/, https://developer.apple.com/documentation/swiftui/nshostingscenerepresentation) **[V]**
- **PoliVerse [J]:** Not needed. Keep it in reserve for a status-bar *title* that SwiftUI's label can't render, or for right-click behaviour.

### 2.6 Keeping the menu bar fresh

- **[V]** `BGTaskScheduler` and `BGAppRefreshTask` exist on iOS, iPadOS, Mac Catalyst, tvOS and visionOS, **not on macOS** (https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler, …/bgapprefreshtask). SwiftUI's `BackgroundTask.appRefresh` is watchOS-only (https://developer.apple.com/documentation/swiftui/backgroundtask/apprefresh).
- **[V]** `NSBackgroundActivityScheduler` (macOS 10.10) is "a task scheduler suitable for low priority operations". Apple's examples include "periodic content fetches" and "activities occurring in intervals of 10 minutes or more". It has `repeats`, `interval`, `tolerance` and `qualityOfService`, and it does not require an XPC service (https://developer.apple.com/documentation/foundation/nsbackgroundactivityscheduler).
- **[V]** `TimelineView` (macOS 12) with `.everyMinute` (macOS 12) and `Text(timerInterval:…)` (macOS 13) redraw time-based text without new data (https://developer.apple.com/documentation/swiftui/timelineview, https://developer.apple.com/documentation/swiftui/timelineschedule/everyminute, https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:)).
- **[J]** The Mac is usually awake, online and running the app when a menu bar extra is in use. So:
  - Run a `NSBackgroundActivityScheduler` every 15-30 min that calls `FreshnessCoordinator.revalidate()`. It already respects each `LoadWindow` (60 s free rooms, 900 s career/courses, 3600 s WeBeep, per `docs/next-features-research.md`, "Efficiency work"), so a frequent tick costs nothing when nothing is due.
  - Revalidate on wake (`NSWorkspace.didWakeNotification`), and when the panel opens (`.task` or `onAppear` inside the `MenuBarExtra` content).
  - The closure the scheduler calls is `@Sendable`, and with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` it has to hop to the main actor, as `BackgroundRefresh.register` does with `MainActor.assumeIsolated` (`BackgroundRefresh.swift:30-40`). **[?]** I didn't check which queue `schedule(_:)` calls back on.
- **[J]** The existing `NotificationModel.reschedule(...)` covers lecture and exam reminders the same way on macOS (`UNUserNotificationCenter`, macOS 10.14).

### 2.7 Controls in the Mac menu bar and Control Center

- **[V]** "On Mac, people place controls from your macOS app in Control Center or as menu bar items" (https://developer.apple.com/documentation/widgetkit/controls-collection). "In iOS, iPadOS, and macOS, your app can offer controls people place in Control Center. On Mac, people can also place controls on the menu bar as menu bar items" (https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy).
- **[V]** macOS availability: `ControlWidget` 26.0 (https://developer.apple.com/documentation/swiftui/controlwidget), `StaticControlConfiguration` / `ControlWidgetButton` / `ControlWidgetToggle` / `AppIntentControlConfiguration` / `ControlCenter` / `ControlPushHandler` 26.0. The WidgetKit Updates page (June 2025) confirms "controls … in watchOS and macOS".
- **[V]** Controls "don't use timelines". They update "when someone uses them, the app reloads them, or the system receives a remote push notification from APNs" (same strategy page).
- **PoliVerse [J]:** `FreeRoomsControl`, `TimetableControl` and `CareerControl` (`PoliVerseWidgets/ControlWidgets.swift`) come to the Mac menu bar for free once the widget extension builds for macOS. They open the app through `AppDestination.send()` and the app-group hand-off, which is already platform-neutral (`AppShellDuties.swift:37-55`). This is the most modern way to put *PoliVerse buttons* into the menu bar. It can't replace the `MenuBarExtra`: it holds a symbol and a couple of words, not a countdown or a list.

### 2.8 Settings and windows opened from the extra

- **[V]** `SettingsLink` (macOS 14.0) is "a view that opens the Settings scene"; `openSettings` / `OpenSettingsAction` are macOS 14.0; `openWindow` / `OpenWindowAction` are macOS 13.0; `dismissWindow` is macOS 14.0 (https://developer.apple.com/documentation/swiftui/settingslink, …/environmentvalues/opensettings, …/environmentvalues/openwindow, …/environmentvalues/dismisswindow).
- **[J]** A `Settings` scene with tabs (Generale: menu bar, login, Dock; Account: sign-in state, WeBeep; Notifiche; Personalizza) replaces the iPhone's Impostazioni sheet on the Mac.

---

## 3. Scenes, windows and the Mac interface

| API | What it gives PoliVerse | macOS | Source | Label |
|---|---|---|---|---|
| `WindowGroup` | The main window (`RootView`) | 11.0 | https://developer.apple.com/documentation/swiftui/windowgroup | [V] |
| `Window` | A single "Oggi" or "Mappa" window | 13.0 | https://developer.apple.com/documentation/swiftui/window | [V] |
| `UtilityWindow` + `WindowVisibilityToggle` | A floating "Oggi" panel toggled from the View menu | 15.0 / 15.0 | https://developer.apple.com/documentation/swiftui/utilitywindow, …/windowvisibilitytoggle | [V] |
| `Settings` | The Mac settings window | 11.0 | https://developer.apple.com/documentation/swiftui/settings | [V] |
| `NavigationSplitView` | Sidebar (Oggi, Corsi, Carriera, Cerca) → list → detail | 13.0 | https://developer.apple.com/documentation/swiftui/navigationsplitview | [V] |
| `TabView` + `.sidebarAdaptable` | Already applied conditionally (`RootView.swift:385`); on Mac the tabs become a sidebar | 15.0 | https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable | [V] |
| `tabViewCustomization(_:)` | Let the student reorder or hide sidebar sections | 15.0 | https://developer.apple.com/documentation/swiftui/view/tabviewcustomization(_:) | [V] |
| `inspector(isPresented:content:)` | Course or exam details beside the list, instead of sheets | 14.0 | https://developer.apple.com/documentation/swiftui/view/inspector(ispresented:content:) | [V] |
| `toolbar(id:content:)` | User-customisable toolbar | 11.0 | https://developer.apple.com/documentation/swiftui/view/toolbar(id:content:) | [V] |
| `.commands`, `CommandMenu`, `keyboardShortcut` | ⌘R refresh, ⌘1-4 sections, ⌘F Cerca, a "Vai" menu of destinations | 11.0 | https://developer.apple.com/documentation/swiftui/scene/commands(content:), …/commandmenu, …/view/keyboardshortcut(_:modifiers:) | [V] |
| `FocusedValue` / `focusedSceneValue` | Menu commands acting on the selected course or file | 11.0 / 12.0 | https://developer.apple.com/documentation/swiftui/focusedvalue, …/view/focusedscenevalue(_:_:) | [V] |
| `windowStyle`, `windowToolbarStyle`, `windowResizability`, `defaultSize` | Window chrome and sizing | 11.0 / 11.0 / 13.0 / 13.0 | https://developer.apple.com/documentation/swiftui/scene/windowstyle(_:), …/windowtoolbarstyle(_:), …/windowresizability(_:), …/defaultsize(width:height:) | [V] |
| `defaultLaunchBehavior(.suppressed)` | "Menu bar first" mode: no window at launch. "On macOS, this behavior will also be used to determine which scene is presented when clicking on the icon of a running application with no visible windows." | 15.0 | https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior(_:) | [V] |
| `restorationBehavior(_:)` | Don't restore utility windows | 15.0 | https://developer.apple.com/documentation/swiftui/scene/restorationbehavior(_:) | [V] |
| `defaultWindowPlacement`, `windowIdealSize`, `windowLevel` | Place the "Oggi" window; keep it floating | 15.0 | https://developer.apple.com/documentation/swiftui/scene/defaultwindowplacement(_:), …/windowidealsize(_:), …/windowlevel(_:) | [V] |
| `WindowDragGesture`, `windowBackgroundDragBehavior` | Drag a borderless "Oggi" card by its background | 15.0 | https://developer.apple.com/documentation/swiftui/windowdraggesture, …/scene/windowbackgrounddragbehavior(_:) | [V] |
| `containerBackground(_, for: .window)`, `WindowStyle.plain`, `toolbar(removing:)` | Personalizza-tinted windows | 15.0 / 15.0 / 14.0 | https://developer.apple.com/documentation/swiftui/containerbackgroundplacement/window, …/windowstyle/plain | [V] |
| `windowResizeAnchor(_:)` | Resize from a chosen anchor | 26.0 | https://developer.apple.com/documentation/swiftui/view/windowresizeanchor(_:) | [V] |
| `glassEffect`, `GlassEffectContainer`, `Glass.interactive`, `glassEffectID`, `.glass` / `.glassProminent` buttons | The app's 20 glass sites carry over | 26.0 | https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:), …/glasseffectcontainer | [V] |
| `backgroundExtensionEffect()` | Course headers extending under the sidebar or inspector | 26.0 | https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect() | [V] |
| `scrollEdgeEffectStyle`, `ToolbarSpacer`, `ConcentricRectangle` | Liquid Glass toolbars and corners | 26.0 | https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:), …/toolbarspacer, …/concentricrectangle | [V] |
| `appearsActive` | Dim custom chrome in inactive windows (shown in WWDC26 "What's new in SwiftUI") | 10.15 | https://developer.apple.com/documentation/swiftui/environmentvalues/appearsactive | [V] |
| `Table` | The libretto and sittings as a sortable table | 12.0 | https://developer.apple.com/documentation/swiftui/table | [V] |
| `onHover`, `pointerStyle`, `help(_:)` | Hover states and tooltips | 10.15 / 15.0 / 13.0 | https://developer.apple.com/documentation/swiftui/view/pointerstyle(_:), …/view/help(_:) | [V] |

**New in macOS 27 that affects this [V]:**
- `reorderContainer(for:isEnabled:move:)` and `reorderable()` (macOS 27.0). `TodayLanding` already uses the iOS 27 reorder API (see `next-features-research.md`), so it works on the Mac too. https://developer.apple.com/documentation/swiftui/view/reordercontainer(for:isenabled:move:)
- `swipeActionsContainer()` (macOS 27.0); `toolbarMinimizationBehavior(_:for:)` (27.0); `TabRole.prominent` (27.0); `ToolbarContent.visibilityPriority(_:)` (macOS **26.1**). `ToolbarOverflowMenu` and `topBarPinnedTrailing` are **not** on macOS (iOS/Catalyst/visionOS 27 only).
- `asyncImageURLSession(_:)` (27.0). `AppShellDuties.swift:34` already uses it.
- `TabsPickerStyle` (27.0): "on macOS it has a distinct visual appearance", read by VoiceOver as tabs. It fits Carriera's segmented sections. https://developer.apple.com/documentation/swiftui/tabspickerstyle
- `textInputBorderShape(_:)`; the `.bordered` text field style replaces `.roundedBorder` / `.squareBorder` (27.0).
- `ReadableDocument` / `WritableDocument` / `Document`. `FileDocument` is deprecated. Not relevant: PoliVerse is not document-based.
- `dropDestination(for:action:isTargeted:)` is **deprecated in 27.2** on all platforms. Use `dropDestination(for:isEnabled:action:)` (26.0). https://developer.apple.com/documentation/swiftui/view/dropdestination(for:isenabled:action:)
- The old `fileExporter(isPresented:document:contentType:defaultFilename:onCompletion:)` is deprecated in 27.2 in favour of the `WritableDocument` forms.
- Also from the WWDC26 Platforms State of the Union: sidebar icons regain the accent colour, every window has the same tighter corner radius, and macOS 27 supports the "show borders" setting (https://developer.apple.com/videos/play/wwdc2026/102/).
- The Xcode 27 `@State` macro "back-deploys to iOS 17 aligned OSes", so it applies to macOS 14+ as well (macOS 27 release notes, SwiftUI). `next-features-research.md` already flags `ShellState` for this.
- `ArrangementView` (September 2026) is **iOS/iPadOS 27.1 beta only** (https://developer.apple.com/documentation/swiftui/arrangementview).

---

## 4. Widgets on macOS

- **[V]** Mac widgets live "on the desktop and Notification Center" in small, medium, large and extra-large sizes (HIG Widgets, https://developer.apple.com/design/human-interface-guidelines/widgets). Accessory families are iPhone/iPad/Watch-only (strategy table, https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy).
- **[V]** **iPhone widgets already appear on the Mac.** "When people place an iPhone widget on a Mac desktop, the system renders it using iOS font metrics. However, a native Mac app's widgets use macOS font sizing" (https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances). WWDC26 "WidgetKit foundations": "your iOS widgets also show up on macOS as remote widgets" (https://developer.apple.com/videos/play/wwdc2026/277/).
- **[?]** The system requirements for remote widgets (iPhone nearby, same Apple Account) are not stated on the pages I read.
- **[V]** New in macOS 27: `WidgetFamily.systemExtraLargePortrait` (macOS 27.0, https://developer.apple.com/documentation/widgetkit/widgetfamily/systemextralargeportrait).
- **[V]** Interactive widgets: `Button(intent:)` is macOS 14 (https://developer.apple.com/documentation/swiftui/button/init(intent:label:)). `FreeRoomsWidget`'s refresh button (`FreeRoomsWidget.swift:306`) works on Mac.
- **[V]** Configurable widgets: `AppIntentConfiguration` is macOS 14 (`FreeRoomsConfiguration`). `widgetURL` is macOS 11. `WidgetCenter.reloadTimelines(ofKind:)` is macOS 11, so `WidgetReloader` ports unchanged.
- **[V]** `RelevanceConfiguration` is **watchOS 26 only** (https://developer.apple.com/documentation/widgetkit/relevanceconfiguration). The Watch Smart Stack card (`PoliVerseWatchWidgets/WatchRelevantLectureWidget.swift`) has no Mac equivalent. RelevanceKit itself lists macOS 26, but the configuration that consumes it does not.
- **[V]** Rendering modes. WidgetKit's strategy page says that "On Mac, it uses the accented rendering mode". The HIG Widgets table marks Mac "Accented: Not supported" and "Full-color: Desktop and Notification Center". **The two primary sources disagree.** Test both, and keep `widgetAccentedRenderingMode` (macOS 15) correct.
- **[V]** Budget: "a daily budget typically includes from 40 to 70 refreshes … every 15 to 60 minutes" (https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).
- **[V]** Live Activities on the Mac:
  - "Live Activities automatically appear on the Mac in the Menu bar" (ActivityKit Updates, June 2025).
  - "Active Live Activities automatically appear in the Menu bar of a paired Mac using the compact, minimal, and expanded presentations. Clicking the Live Activity launches iPhone Mirroring to display your app." They "remain for up to four hours" after ending, "in the Mac menu bar" (HIG, https://developer.apple.com/design/human-interface-guidelines/live-activities).
  - The strategy table lists Mac Live Activities as "From a paired iPhone".
  - The ActivityKit framework itself has no macOS availability.
- **PoliVerse [J]:**
  - Add a macOS destination to `PoliVerseWidgets` (same folder, same `Shared` group) with `#if os(iOS)` around the Live Activity, its previews and the accessory families. The alternative is a `PoliVerseMacWidgets` target over the same folders with per-file filters.
  - The Mac *app* has to write the `OfflineStore` snapshots itself, because the Mac's app-group container is local to the Mac. It already does this wherever the shared services run (`OfflineStore.swift:77-82`), so no new code is needed.
  - The iPhone's lecture Live Activity will already appear in the Mac menu bar, which covers the "current lecture in the menu bar" wish even before the Mac app exists. Test the compact and minimal presentations for that context.
- **[?]** Whether a Mac with *both* the native widget and the iPhone's remote widget shows them as two entries in the gallery.

---

## 5. System integration

### 5.1 App Intents and Shortcuts

- **[V]** `AppIntent`, `AppEntity`, `AppShortcutsProvider` and `OpenIntent` are macOS 13.0 (https://developer.apple.com/documentation/appintents/appintent, …/appshortcutsprovider). The repo's `PoliVerseShortcuts`, `CourseEntity`/`ExamEntity`/`RoomEntity` with string queries, `ExamDateIntent`, `NextLectureIntent`, `RoomFreeIntent`, `ExamUpdatesIntent` and `NextExamIntent` (`App/AppShortcuts.swift:6`, `App/AppEntities.swift:19-203`, `App/EntityIntents.swift`, `App/ExamUpdatesIntent.swift`), plus the `Open…Intent`s in `Shared/AppDestination.swift:84-153`, use nothing iOS-only.
- **[V]** New in 27 (App Intents Updates, June 2026), all on macOS 27.0:
  - `LongRunningIntent` (for example a full WeBeep sync from Shortcuts)
  - `IntentExecutionTargets` / `allowedExecutionTargets`, to pin intents to the main app or the widget extension, which matters with a new Mac app in the mix
  - `EntityCollection`, `OwnershipProvidingEntity`, `IndexedEntityQuery`
  - `SyncableEntity`, for identifiers "consistent across devices"
  - `AppIntentError(description:)`

  `IntentModes` / `supportedModes` is macOS 26.0. **`RunSystemShortcutIntent` is iOS/iPadOS/Catalyst 27 only.** https://developer.apple.com/documentation/appintents/longrunningintent, …/intentexecutiontargets, …/syncableentity, …/runsystemshortcutintent
- **[V]** Shortcuts automations on Mac: "As long as your intent is available on macOS, they will also be available to use in Shortcuts to run as a part of Automations on Mac" (WWDC25 "Develop for Shortcuts and Spotlight with App Intents", https://developer.apple.com/videos/play/wwdc2025/260/).
- **[V]** WWDC26: "Discover new capabilities in the App Intents framework" (https://developer.apple.com/videos/play/wwdc2026/345/), "Build intelligent Siri experiences with app schemas" (…/240/), "Validate your App Intents adoption with AppIntentsTesting" (…/295/).

### 5.2 Spotlight

- **[V]** **Spotlight on Mac runs app actions.** "You can also now run Shortcuts actions, including your app's actions, right from Spotlight on Mac". The session's best practices are to provide parameter suggestions, implement search, support both background and foreground runs, and "pair background intents with foreground intents" (WWDC25 session 260 above).
- **[V]** `IndexedEntity` is macOS 15.0 (https://developer.apple.com/documentation/appintents/indexedentity). `CSSearchableIndex` is macOS 10.11. `SpotlightIndex.swift` (`Model/Platform/SpotlightIndex.swift:23,74-160`) ports unchanged.
- **[V]** New in 27: `SpotlightSearchTool` makes indexed content available to Foundation Models, and `CSSearchableIndexDescription` handles reindexing. Both are macOS 27.0 (Core Spotlight Updates, https://developer.apple.com/documentation/corespotlight/spotlightsearchtool). **Known issue [V]:** with the on-device model, a `SpotlightSearchTool` created without a configuration overflows the context window. Use `.focused()` (macOS 27 release notes, Core Spotlight).
- **PoliVerse [J]:** The owner's "check things from the menu bar" also works from ⌘-Space: "Prossima lezione", "Quando è l'appello di Fisica", "Aula libera vicino al 3". The intents already exist. Turning `CourseEntity`/`ExamEntity`/`RoomEntity` into `IndexedEntity` (rank 5 in `next-features-research.md`) is worth more on the Mac, because Spotlight is how Mac users launch things.

### 5.3 Siri, Apple Intelligence and Foundation Models

- **[V]** Foundation Models: macOS 26.0; `SystemLanguageModel.supportsLocale(_:)` and `supportedLanguages` macOS 26.0. New in 27: `LanguageModelError`, `PrivateCloudComputeLanguageModel` (macOS 27.0; needs the `com.apple.developer.private-cloud-compute` entitlement, Bundle Resources Updates), `DynamicProfile`, and a new on-device model ("test your prompts", Foundation Models Updates). https://developer.apple.com/documentation/foundationmodels/languagemodelsession, …/privatecloudcomputelanguagemodel
- **[V]** `NoticeSummary.swift` already gates on `SystemLanguageModel.default.availability` (`:73,89`), so it compiles and degrades on Mac.
- **[J]** macOS 27 runs only on Apple silicon (§7), so every Mac that runs the app has the hardware for Apple Intelligence. Whether the feature is *enabled*, and whether Italian is supported, is still a runtime check.
- **[V]** App schema domains (https://developer.apple.com/documentation/appintents/app-schema-domains). **[?]** As in `next-features-research.md` rank 5, I didn't find an education domain.

### 5.4 Notifications

- **[V]** `UNUserNotificationCenter` is macOS 10.14; `.timeSensitive` is macOS 12 (https://developer.apple.com/documentation/usernotifications/unusernotificationcenter). `NotificationModel` and `NotificationRouter` port as they are.
- **[V]** macOS 27.2 beta known issue: after a clean install, some apps might not prompt for notifications (macOS 27.2 release notes).
- **[J]** On the Mac, a lecture reminder can deep-link into the main window, or open the menu bar panel, through `AppDestination`.

### 5.5 Quick Look, files and downloaded materials

- **[V]** `.quickLookPreview(_:)` / `(_:in:)` are macOS 11 (https://developer.apple.com/documentation/swiftui/view/quicklookpreview(_:)). `QLPreviewPanel` (QuickLookUI) is macOS 10.6. `QLPreviewController` is not on macOS.
- **[V]** `fileExporter` / `fileMover` / `fileImporter` are macOS 11. The sandbox extends to user-selected URLs (https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).
- **[J]** On a Mac, WeBeep materials should behave like files:
  - Drag them out to Finder (`.draggable` with a `Transferable` `FileRepresentation`, macOS 13).
  - "Mostra nel Finder" (`NSWorkspace.activateFileViewerSelecting(_:)`, macOS 10.6).
  - "Salva in Download" (downloads entitlement, §6).
  - Space to Quick Look.

  `FileDownloadModel` keeps files in Application Support (`FileDownloadModel.swift:62-63,169-186`), and inside the sandbox that path is the app's container, invisible to the student. That's fine for a cache, but not for "my course notes".

### 5.6 Drag and drop, sharing, Services

- **[V]** `Transferable` (macOS 13), `draggable(_:)` (macOS 13), the new `dropDestination(for:isEnabled:action:)` (macOS 26), `ShareLink` (macOS 13), `NSSharingServicePicker` (macOS 10.8), and `copyable(_:)` (macOS 13.0). New in 27 AppKit: `NSView.beginDraggingSession(items:gesture:source:)`.
- **[J]** A Share extension or a Services-menu provider has no obvious PoliVerse use, since the app never writes to university systems (`docs/writes-to-university-systems.md`). Skip it.

### 5.7 Handoff between iPhone and Mac

- **[V]** "For features like Handoff to work, the system needs to know which types of activities it can deliver to your app … add the `NSUserActivityTypes` key" (https://developer.apple.com/documentation/foundation/nsuseractivity). `isEligibleForHandoff` is macOS 10.11; `appEntityIdentifier` is macOS 15.2. `SyncableEntity` (27.0) is designed "so people can continue a task on another device" (App Intents Updates).
- **[V]** The app already publishes a user activity from `SearchView.swift:290` (`SpotlightIndex.activityType`) and handles `CSSearchableItemActionType` (`:314`). `Info.plist` has no `NSUserActivityTypes`.
- **[J]** Cheap and good: publish an activity for "course open" and "exam open" with the course code / `c_appello`, which are stable ids (`docs/academic-intelligence-layer.md:26`). Then a course open on the iPhone appears in the Mac's Dock, and the other way round.

### 5.8 Settings sync

- **[V]** `NSUbiquitousKeyValueStore` (macOS 10.7) shares settings "among instances of your app running on all of the person's devices". Limits: 1024 keys, 1 MB in total, 1 MB per value (https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore).
- **[J]** Fits `TodayStyle` (looks, selection), favourites and the menu bar preferences. It does **not** fit stickers or custom images (`TodayStickers.swift:179`, Application Support). Those would need CloudKit, or should stay per device.
- **[J]** Don't sync academic data through iCloud. Each device fetches from the Politecnico. A CloudKit mirror of iPhone snapshots would let the Mac work without signing in, but it would put academic records in iCloud and make the Mac only as fresh as the phone's last background run. I'd keep it as an idea, not the plan.

### 5.9 App Groups on macOS

- **[V]** `group.<name>` identifiers work on macOS when they are registered. macOS also accepts `<team id>.<group name>` without registration (https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups, https://developer.apple.com/documentation/xcode/configuring-app-groups).
- **[J]** Keep `group.segrini.samuele.PoliVerse` (`OfflineStore.swift:51`), so the constant is shared. The *container* is still per device: the Mac app writes and the Mac widgets read.
- **[V]** macOS 27: access to *other teams'* app containers and group containers is now "denied by default". That doesn't affect a single team (macOS 27 release notes, System Integrity Protection).

### 5.10 Keychain

- **[V]** On macOS, SecItem "defaults to targeting the file-based keychain. To target the data protection keychain, set the `kSecUseDataProtectionKeychain` attribute or the `kSecAttrSynchronizable` attribute to true". Default to the data-protection keychain because "it behaves consistently across all Apple platforms". Its access groups come from entitlements that "must be authorized by a provisioning profile" (TN3137, https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains). The key "is highly recommended … for all keychain operations" and is ignored on other platforms (https://developer.apple.com/documentation/security/ksecusedataprotectionkeychain).
- **[V]** `KeychainStore` sets `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and no data-protection flag (`KeychainStore.swift:31`).
- **[J]** **Don't share the token between iPhone and Mac** (no `kSecAttrSynchronizable`, and no shared iCloud access group):
  - The Politecnico rotates the refresh token, and `TokenStore` is an actor precisely because "two concurrent refreshes would present a token the other has already invalidated and end the session" (`Authentication.md`, "The Politecnico"; `docs/polimi-auth.md`, "What we changed"). Two *devices* holding one pair is the same race across a network.
  - The items are deliberately `ThisDeviceOnly` (`KeychainStore.swift:6-9`).

  Each device signs in once.
- **[?]** Whether the Politecnico allows two live grants per account (iPhone and Mac at once). The official web app is used from many browsers, which suggests it does, but I didn't test it.

### 5.11 Signing in on the Mac: `WKWebView`, `ASWebAuthenticationSession` and CIE

- **[V]** The login does not mint a token. It loads the real Servizi Online web app in a `WKWebView` and reads `sessionStorage["24344_oauthCredentials"]` (`docs/polimi-auth.md`, "Login: run the official app, take its credential"; `PoliMiAppLoginWebView.swift:258-297`). It uses a persistent `WKWebsiteDataStore(forIdentifier:)` (`LoginWebKit.swift:33-36`).
- **[V]** `WKWebView` is macOS 10.10, `evaluateJavaScript` macOS 10.10, and `WKWebsiteDataStore(forIdentifier:)` **macOS 14.0** (https://developer.apple.com/documentation/webkit/wkwebview, …/wkwebsitedatastore/init(foridentifier:)). SwiftUI's `WebView` + `WebPage` are macOS 26.0 (https://developer.apple.com/documentation/webkit/webview-swift.struct, …/webpage).
- **[J]** The whole approach ports. Only the representable wrapper (`AuthWebView.swift:28`) changes to `NSViewRepresentable`. Moving to `WebView`/`WebPage` would remove the representable on both platforms, but it would also mean re-checking the navigation-policy hooks CIE depends on. That's a separate decision.
- **[V]** `ASWebAuthenticationSession` (macOS 10.15): "In macOS, the system opens the user's default browser if it supports web authentication sessions, or Safari otherwise" (https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession). `Callback.https(host:path:)` is macOS 14.4.
- **[J]** It is still unusable, for the same reason as on iOS: the redirect lands on `polimiapp.polimi.it`, a domain the app doesn't own, and the credential is read from `sessionStorage`, not from a callback (`docs/polimi-auth.md:48-51`).
- **[V]** CIE from a computer, according to the Ministry: either a contactless smart-card reader plus the "CIE software", or "via computer, using a smartphone equipped with an NFC system for reading the CIE, and the 'CieID' app" (https://www.cartaidentita.interno.gov.it/en/useful-info-for-citizens/log-in-with-cie/).
- **[J]** On the Mac, the iPhone trick (intercept, add `sourceApp`, reopen `CIEID://…`, `docs/cie-login.md`) doesn't apply: there is no CieID app to hand off to. Leave `CieIDBridge`/`CieIDRouter` out of macOS and let the IdP's desktop flow run inside the web view (phone + CieID app, or card reader).
- **[?]** Whether the smart-card-reader path works inside a sandboxed `WKWebView` at all. I found no Apple or Ministry page covering it. SPID and username/password should behave as they do in a browser.
- **[J]** The WeBeep token arrives through the `poliverse://` scheme (`WeBeepAuth.swift:24,123`). `onOpenURL` is macOS 11, and the URL types in `Info.plist` apply to macOS apps too, so this should work. Test it first, because macOS routes custom schemes to whichever registered app LaunchServices picks.

### 5.12 Calendar export

- **[V]** `EKEventStore` is macOS 10.8; `requestWriteOnlyAccessToEvents` is macOS 14 (https://developer.apple.com/documentation/eventkit/ekeventstore/requestwriteonlyaccesstoevents(completion:)). **`EKEventEditViewController` is not on macOS** (https://developer.apple.com/documentation/eventkitui/ekeventeditviewcontroller).
- **[V]** A sandboxed app needs `com.apple.security.personal-information.calendars` (sandbox table, https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox).
- **[J]** `CalendarExporter` (`Model/Platform/CalendarExporter.swift`) ports. `AddToCalendarSheet` needs a Mac version: save directly, then offer "Apri Calendario".
- **[?]** Whether the Mac also needs `NSCalendarsFullAccessUsageDescription` (the key comes from `INFOPLIST_KEY_…` build settings, `project.pbxproj:661`). I didn't read a macOS-specific statement.

---

## 6. Data, sandbox and performance

- **[V]** The sandbox container: "The first time the user launches your sandboxed app, the system creates its container — a folder in `~/Library/Containers`". `~/Downloads` and others are symlinked there but need entitlements. The App Sandbox capability "is an App Store requirement for any app that you submit to the Mac App Store" (https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox). From macOS 14, the container is bound to the code signature. A Mac App Store build and an Xcode build of the same app can therefore trigger a permission prompt (https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).
- **[J]** `DiskCache`, `OfflineStore`, `ReportArchive`, `RecordingDownloads` and `TodayStickers` all resolve `applicationSupportDirectory` / `cachesDirectory` / the group container through `FileManager` (`DiskCache.swift:17-18`, `ImageSession.swift:19`, `RecordingDownloads.swift:61`, …). They land in the container automatically, and none hard-codes a path.
- **Entitlements a sandboxed Mac build needs [V]:**
  - `com.apple.security.app-sandbox` (https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.app-sandbox)
  - `com.apple.security.network.client`, for every service and for `WKWebView`
  - `com.apple.security.personal-information.calendars`, for the timetable export
  - `com.apple.security.files.user-selected.read-write`, for "Salva con nome…"
  - `com.apple.security.files.downloads.read-write`, if "Salva in Download" writes directly (https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.downloads.read-write)
  - `com.apple.security.application-groups`, already present
  - A keychain access group through the provisioning profile (§5.10)
- **[V]** Not needed: location (no `CLLocationManager` use found), camera, microphone.
- **[V]** SwiftData: **not used** (no `import SwiftData`), and the JSON file cache works in the sandbox. The June 2026 SwiftData additions (`ResultsObserver`, `HistoryObserver`, `sectionBy`, codable attributes) are not a reason to migrate.
- **[V]** MetricKit: macOS 12; `MetricManager` macOS 27.0, which "replaces `MXMetricManager` and its subscriber protocol" (MetricKit Updates; https://developer.apple.com/documentation/metrickit/metricmanager). StateReporting is macOS 27.0 (https://developer.apple.com/documentation/statereporting). `PerformanceMonitor`, `PerfSignpost`, `PerformanceStates` and `ReportArchive` compile unchanged at a 27 floor. **[J]** Add `menuBarPanel` as a state, and the Mac's sidebar sections as tab states (see `next-features-research.md` E1).
- **[V]** Xcode 27 Organizer adds Insights, Hitches and Storage panes (Xcode Updates). These presumably cover the Mac build as well **[?]**.
- **[V]** Swift 6 concurrency: the project uses the Swift 6.2 default-actor-isolation setting (SE-0466, "Implemented (Swift 6.2)", https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md) and approachable concurrency (SE-0461, nonisolated async functions run on the caller's actor). AppKit callbacks such as `NSBackgroundActivityScheduler`'s block and `NSWorkspace` notifications need the same care as `BackgroundRefresh` (§2.6).
- **[V]** The `DocumentReader`/`DocumentWriter` note in the macOS 27 release notes is a reminder of that rule: under approachable concurrency, "an unannotated `nonisolated` async method runs on the main actor", so use `@concurrent` for off-main work. The repo already does this in `BackgroundJSON.swift` (`next-features-research.md`, "Efficiency work").

---

## 7. Distribution

- **[V]** Mac App Store: apps "must be appropriately sandboxed", must be built with Xcode, "may not auto-launch … at startup or login without consent", and "must use the Mac App Store to distribute updates" (App Review Guidelines 2.4.5(i)-(vii), https://developer.apple.com/app-store/review/guidelines/).
- **[V]** Developer ID outside the store: notarize with `notarytool`. Notarization "is not App Review", but an automated malware and signing check. Gatekeeper finds the ticket online or stapled (https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
- **[V]** Universal purchase: a macOS version "uses the same Apple ID …, SKU, and bundle ID as the iOS app". Separate app records can't be merged. Once two platforms are approved, "your app stays as universal purchase" (https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/).
- **[V]** Apple silicon only:
  - "macOS Tahoe was the final release to support Intel Macs … You can now ship Apple silicon-only binaries on the Mac App Store" (WWDC26 Platforms State of the Union, https://developer.apple.com/videos/play/wwdc2026/102/).
  - macOS 27's Settings lists Intel apps "that will be incompatible with macOS 28.0" (macOS 27 release notes, EcosystemUI).
- **[V]** TestFlight covers "apps, games, and App Clips across Apple platforms" (https://developer.apple.com/testflight/). Xcode 27 adds an easier Xcode Cloud → TestFlight workflow (Xcode Updates).
- **[J]** **The Mac App Store in the same record** is the natural choice: universal purchase, TestFlight, no update mechanism to build, and the sandbox is needed anyway. Developer ID only makes sense for a build that can't be sandboxed, and nothing here requires that.
- **[?]** If the iPad app is currently offered on Apple-silicon Macs through App Store Connect, what happens to those installs when a native macOS version joins the record. The pages I read don't say.

---

## 8. WWDC 2026 / macOS 27 highlights for this app

| Item | Where | macOS | Use in PoliVerse | Label |
|---|---|---|---|---|
| Menu item icons reduced by default; `labelStyle(.titleAndIcon)` to keep one | macOS 27 release notes (SwiftUI, AppKit); HIG Menus change log "June 8, 2026 · Updated guidance for menu item icons" | 27.0 | Menu bar extra in `.menu` style, the Commands menus | [V] |
| `LabeledContent` in a `Menu` → menu item subtitle | macOS 27 release notes | 27.0 | "Analisi 2" / "10:15 · B.2.3" in a `.menu`-style extra | [V] |
| `NSStatusItem.expandedInterfaceSession` + status-item keyboard navigation | AppKit docs; WWDC26 session 289 | 27.0 | Only if the app drops to `NSStatusItem` | [V] |
| `NSHostingSceneRepresentation` (MenuBarExtra from AppKit) | WWDC26 session 272 | 26.0 | Not needed: the app is SwiftUI-first | [V] |
| `NSRefreshController` (pull-to-refresh in `NSScrollView`), `NSControl.Events` | AppKit Updates, macOS 27 release notes | 27.0 | SwiftUI `.refreshable` is the relevant path; noted for completeness | [V] |
| Reorder containers, swipe-action containers | SwiftUI Updates | 27.0 | Oggi reordering works on the Mac too | [V] |
| `TabsPickerStyle`, `textInputBorderShape`, `.bordered` text fields | macOS 27 release notes | 27.0 | Carriera sections; search fields | [V] |
| `asyncImageURLSession`, HTTP-cached `AsyncImage` | SwiftUI Updates | 27.0 | Already used (`AppShellDuties.swift:34`) | [V] |
| `@State` macro (lazy class init), `ContentBuilder` | SwiftUI Updates | back to macOS 14 | Toolchain effect on `ShellState` | [V] |
| `MetricManager`, StateReporting | MetricKit Updates | 27.0 | Existing pipeline, unchanged | [V] |
| `SpotlightSearchTool`, `CSSearchableIndexDescription` | Core Spotlight Updates; WWDC26 "LLM search using Core Spotlight" (…/246/) | 27.0 | "Ask your courses" over the existing index | [V] |
| Foundation Models: new model, `LanguageModelError`, Private Cloud Compute, `DynamicProfile` | Foundation Models Updates | 27.0 | `NoticeSummary` | [V] |
| `LongRunningIntent`, `IntentExecutionTargets`, `SyncableEntity`, `EntityCollection`, `IndexedEntityQuery`, app schemas | App Intents Updates | 27.0 | Spotlight and Shortcuts on the Mac; Handoff | [V] |
| `systemExtraLargePortrait` widgets | WidgetKit docs; WWDC26 session 277 | 27.0 | A tall "settimana" widget on the desktop | [V] |
| Resizable iOS apps in iPhone Mirroring | WWDC26 Platforms State of the Union | iOS 27 | Clicking the Live Activity in the Mac menu bar opens the iPhone app in Mirroring, now resizable | [V] |
| Apple silicon-only Mac App Store binaries | WWDC26 Platforms State of the Union | — | Single-architecture testing | [V] |
| Stricter defaults for other teams' containers | macOS 27 release notes (SIP) | 27.0 | No effect | [V] |
| `com.apple.security.hardened-process.enhanced-security-version` | Bundle Resources Updates | 27 | Optional hardening | [V] |
| WidgetKit and ActivityKit | Updates pages | — | **No June 2026 entries.** macOS widgets and controls are the June 2025 feature set | [V] |

---

## 9. Suggested plan

### Phase 1: a minimal Mac app with a menu bar extra (M-L)

1. Add a Mac destination to the `PoliVerse` target and set `MACOSX_DEPLOYMENT_TARGET = 27.0`. Filter "Embed Watch Content" to iOS. Add sandbox + `network.client` + calendars entitlements for macOS. **[J]**
2. Platform seams in the Model layer: `#if os(iOS)` around `WatchSync` and its three call sites, `CieIDBridge`/`CieIDRouter` and `BackgroundRefresh`. Add a macOS `LiveActivityController` stub (`isAvailable = false`) and a macOS `DiagnosticsCollector` device line. Add `kSecUseDataProtectionKeychain` to `KeychainStore`. **[V]** sites in "Codebase readiness".
3. A `navigationBarTitleDisplayMode` / `topBar*` shim (fixes 33 files at once), then the ~34 files of real UI work, starting with `AuthWebView` → `NSViewRepresentable` and `Theme` colours. **[V]** / **[J]**
4. Scenes: the main `WindowGroup` (sidebar via the existing `.sidebarAdaptable`), a `Settings` scene, and `MenuBarExtra(isInserted:)` in `.window` style with next lecture, today, next exam, new WeBeep files and career figures. Move the environment into one modifier. **[J]**
5. Freshness: `NSBackgroundActivityScheduler` → `FreshnessCoordinator.revalidate()`, a wake notification, and a `TimelineView`/`Text(timerInterval:)` countdown. **[J]**
6. `SMAppService.mainApp` opt-in and the "only in the menu bar" activation-policy toggle. **[J]**
7. Sign-in on the Mac with password/SPID. Test CIE through the desktop flow (§5.11). **[?]**
8. TestFlight for Mac in the same App Store Connect record. **[J]**

### Phase 2: widgets, controls, intents, Spotlight (M)

1. `PoliVerseWidgets` on macOS without the Live Activity or accessory families. Check the font sizing and rendering mode (§4).
2. The three controls in Control Center and the menu bar, which should need no code change.
3. `IndexedEntity` for courses, exams and rooms; Spotlight actions checked on the Mac; `NSUserActivityTypes` + Handoff for course and exam pages.
4. Commands: ⌘R, ⌘1-4, a Vai menu, ⌘F; `FocusedValue` for the selected course or file.
5. Files: `quickLookPreview`, drag to Finder, "Mostra nel Finder", "Salva in Download".

### Phase 3: polish (S-M each)

1. A `UtilityWindow` "Oggi" panel with `windowLevel`; `defaultLaunchBehavior(.suppressed)` for a menu-bar-first mode.
2. `NSUbiquitousKeyValueStore` for looks and preferences; `SyncableEntity` for entities.
3. `Table` views for the libretto and sittings; `inspector` for details; `TabsPickerStyle`.
4. `SpotlightSearchTool` + Foundation Models "chiedi ai tuoi corsi", using `.focused()` with the on-device model.
5. StateReporting states for the Mac shell; an Organizer baseline once there are users.
6. Personalizza on the Mac: Flavors carry over through `TodayStyle`, but the icon picker has no Mac API (`setAlternateIconName` is iOS-only). Offer the Dock tile at most.

---

## Not verified

- **[?]** Whether the project actually builds for macOS after the changes listed. I didn't try a build, and the counts are symbol greps.
- **[?]** The App Store Connect help page's "upload the builds for macOS … from a separate Xcode target" against Xcode's single-multiplatform-target guidance (§1).
- **[?]** What `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD` defaults to when unset, and whether the iPad app is currently on the Mac App Store.
- **[?]** The requirements for remote iPhone widgets and for Live Activities in the Mac menu bar (same Apple Account, iPhone Mirroring availability, proximity). The docs I read state the feature, not the conditions.
- **[?]** The HIG says Mac widgets don't support the accented mode; WidgetKit says Mac uses it (§4).
- **[?]** Which queue `NSBackgroundActivityScheduler` calls back on, and how that interacts with `MainActor` default isolation.
- **[?]** CIE on the Mac: whether the smart-card path works inside a sandboxed `WKWebView`, and whether the phone + CieID path completes inside the embedded view. The official desktop options are verified; their behaviour in an embedded web view is not.
- **[?]** Whether the Politecnico accepts two concurrent grants for one account (iPhone and Mac).
- **[?]** Whether the `poliverse://` WeBeep redirect reaches the sandboxed Mac app reliably when another app has registered the same scheme.
- **[?]** Whether macOS needs `NSCalendarsFullAccessUsageDescription` or a different key for write-only access.
- **[?]** A documented macOS deep link to System Settings ▸ Notifications (replacing `UIApplication.openSettingsURLString`).
- **[?]** Whether a Mac-idiom app with an Icon Composer `.icon` and no alternate icons needs asset-catalogue changes. I didn't read the Icon Composer Mac guidance.
- **[?]** Whether any app schema domain fits education data.
- **[?]** Whether Foundation Models supports Italian on the current model (`supportsLocale` is the runtime check).
- **[?]** What happens to existing iPad-on-Mac installs when a native macOS version joins the record.
