# Testing and QA

Three kinds of test, three schemes. All of them run on sample data: no
account, no network, the same payload every time. A test that talks to the
Politecnico's servers is a test of the Politecnico's servers.

| Scheme | Target | What it is for |
| --- | --- | --- |
| `PoliVerse` | `PoliVerseTests` | Unit tests. Fast, run on every change. |
| `PoliVerseUI` | `PoliVerseUITests` | Functional UI tests, Debug. Navigation, search, lifecycle, accessibility audits. |
| `PoliVersePerformance` | `PoliVerseUITests` | Launch, hitch and signpost measurements, Release, plus the Personalizza walkthrough. Minutes long; kept out of the ordinary test action. |

## Running

```
# Unit tests
xcodebuild test -project PoliVerse.xcodeproj -scheme PoliVerse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Functional UI tests
xcodebuild test -project PoliVerse.xcodeproj -scheme PoliVerseUI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Measurements — set baselines in Xcode's test report, per device
xcodebuild test -project PoliVerse.xcodeproj -scheme PoliVersePerformance \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Set `POLIVERSE_UI_SHOTS` to a folder to have every UI-test screenshot written
there as well as attached to the report:

```
POLIVERSE_UI_SHOTS=/tmp/poliverse-shots xcodebuild test -scheme PoliVerseUI …
```

## The suites

| Suite | Target | What it walks |
| --- | --- | --- |
| `ShellNavigationUITests` | UI | The four tabs, every place in Cerca, the profile and Impostazioni, the single page's panel |
| `SearchUITests` | UI | Cerca: field, results, empty state, cleared query |
| `ContentScreensUITests` | UI | A course opened from Corsi, Carriera's three sections, Oggi scrolled |
| `CalendarAndRoomsUITests` | UI | The week strip paged and brought back, Aule libere's filters |
| `LayoutSwitchUITests` | UI | Tabs ↔ pagina unica from Impostazioni, and the sheet closing on the change |
| `OnboardingUITests` | UI | The first run on the sample-data route, and that it is not shown twice |
| `SignedOutUITests` | UI | No account and no sample data: the login screen and its disclaimer |
| `LifecycleUITests` | UI | Rotation, return from the background, a second launch, a fresh install |
| `AccessibilityAuditUITests` | UI | Xcode's audit per screen, and at AX5 |
| `ScreenshotSweepUITests` | UI | A picture of every screen, in both layouts and at AX5 — for checking by eye |
| `CustomizeAnimationTests` | UI | Personalizza from start to finish, with a screenshot per step |
| `PerformanceTests` | UI | Launch, agenda load, hitches, CPU and memory |

## How the UI tests launch the app

Every UI test goes through `PoliVerseUITestCase`, which launches with sample
data on, onboarding done, the new interface, and Italian:

```
-useMockData <true/> -hasCompletedOnboarding <true/> -usesNewInterface <true/>
-appLayout tabs -AppleLanguages (it) -AppleLocale it_IT
```

These are read from the argument domain of `UserDefaults`, so the app carries
no test-only code. The booleans are written as plist values because `Session`
reads them with `as? Bool`, which a bare `YES` — a string in that domain —
does not satisfy. Because the app runs in Italian, the labels the tests look
for are the Italian ones.

`makeApp(layout:textSize:)` also takes
`-UIPreferredContentSizeCategoryName`, which is how the accessibility suite
runs the app at AX5.

## Accessibility audits

`AccessibilityAuditUITests` runs Xcode's automated audit — the same one the
Accessibility Inspector runs by hand — over each screen:
missing labels, labels that repeat their trait, hit regions under 44×44,
contrast, clipped text at large sizes, and elements the audit cannot reach.

`.contrast` and `.textClipped` read rendered pixels, so on Oggi they flag the
app's own papers and stickers, which are pictures by design. Those two run
only in `testTodayContrastAndClipping`, which records what it finds — with a
screenshot — instead of failing. Everything else is a failure, per screen,
named by screen.

## Identifiers

UI tests find things by accessibility identifier wherever the label is not
stable. The ones the shell relies on:

| Identifier | What |
| --- | --- |
| `tab-today`, `tab-courses`, `tab-career`, `tab-search` | Each tab's own screen |
| `place-<id>`, `panel-<id>` | A place in Cerca's list, and in the single page's panel |
| `search-list`, `search-empty` | Cerca's list, and its "nothing found" state |
| `settings-list`, `settings-close` | Impostazioni, and the button that closes it |
| `bar-profile`, `bar-settings`, `today-customize` | The buttons in Oggi's bar |
| `settings-layout` | The tabs ↔ pagina unica picker |
| `onboarding-primary`, `onboarding-skip`, `onboarding-demo`, `onboarding-back` | The first run's controls |

Adding a screen means adding an identifier to its root and a row to
`ShellNavigationUITests`, so no route can go unwalked.

## What a new test should look like

- One behaviour per test, named for the behaviour and not for the method.
- Sample data only; no clock of its own beyond a fixed date.
- Unit tests use Swift Testing (`@Suite`, `@Test`, `#expect`); UI tests use
  XCTest, which is where `XCUIApplication` lives.
- A network test stubs `URLProtocol` and keys its answers by something unique
  to the test, so the suite stays parallel.
