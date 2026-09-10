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
| Timetable / calendar | Implemented against `/agenda/api/me/{matricola}/events` |
| Career / grades | Implemented — mean, CFU, exam sittings, published marks |
| Search | Across courses, agenda and exam sittings |

The app ships with **mock data on by default** so every screen renders without
a network. Turn it off in Settings to use a real account.

Courses are cached to Application Support, so the app opens with content and
refreshes behind it. Tokens are never cached there — they live in the Keychain.

## Requirements

- Xcode 27, iOS 26 SDK
- Swift 6 (strict concurrency, `MainActor` default isolation)
- No third-party dependencies

## Test

```
xcodebuild test -project PoliVerse.xcodeproj -scheme PoliVerse \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

24 tests covering the parts that are easy to get wrong and hard to notice:
timezone-less timestamp parsing across CET and CEST, refresh coalescing under
concurrency, exam status mapping, authcode extraction, and the cache's refusal
to round-trip a favourite.

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
PoliVerseTests/   unit tests, mirroring Services/ and Models/
```

The Xcode project uses synchronized folder groups, so adding a `.swift` file
anywhere under `PoliVerse/` picks it up with no project-file edit and no merge
conflict.

## Notes on the API

The Politecnico has no public API. What the app talks to is the private backend
behind the official app, documented in [docs/polimi-auth.md](docs/polimi-auth.md),
including where our approach differs from PoliFemo's and why.
