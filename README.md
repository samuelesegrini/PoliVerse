# PoliVerse

An unofficial SwiftUI app for Politecnico di Milano students — courses,
materials, timetable and career in one place.

Not affiliated with or endorsed by Politecnico di Milano.

## Status

Rebuilt from scratch in 2026. The 2023 prototype was a single unmerged branch
containing a home-screen mockup with hardcoded data and no networking; its
history is not carried forward.

| Area | State |
| --- | --- |
| PoliMi OAuth login | Implemented, needs testing against a live account |
| Token storage + refresh | Implemented (Keychain, serialised refresh) |
| Course list | Implemented against `/rest/v1/insegn` |
| WeBeep materials | UI complete, backend unresolved — see [docs](docs/polimi-auth.md#webeep--unresolved) |
| Timetable | Not started (endpoint known) |
| Career / grades | Not started (endpoint known) |
| Search | Courses only |

The app ships with **mock data on by default** so every screen renders without
a network. Turn it off in Settings to use a real account.

## Requirements

- Xcode 27, iOS 26 SDK
- Swift 6 (strict concurrency, `MainActor` default isolation)
- No third-party dependencies

## Build

```
open PoliVerse.xcodeproj
```

or

```
xcodebuild -project PoliVerse.xcodeproj -scheme PoliVerse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Layout

```
PoliVerse/
  App/            entry point, root routing, tab bar
  DesignSystem/   theme, reusable cards
  Models/         domain types + wire DTOs, kept separate
  Services/       OAuth, token store, API client, per-feature services
  Features/       one folder per tab
```

The Xcode project uses synchronized folder groups, so adding a `.swift` file
anywhere under `PoliVerse/` picks it up with no project-file edit and no merge
conflict.

## Notes on the API

The Politecnico has no public API. What the app talks to is the private backend
behind the official app, documented in [docs/polimi-auth.md](docs/polimi-auth.md),
including where our approach differs from PoliFemo's and why.
