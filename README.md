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
| WeBeep materials | Implemented via Moodle web services — see [docs/webeep.md](docs/webeep.md) |
| Timetable / calendar | Implemented against `/agenda/api/me/{matricola}/events` |
| Career / grades | Implemented — mean, CFU, exam sittings, published marks |
| Search | Across courses, agenda and exam sittings |

The app ships with **mock data on by default** so every screen renders without
a network. Turn it off in Settings to use a real account.

Courses are cached to Application Support, so the app opens with content and
refreshes behind it. Tokens are never cached there — they live in the Keychain.

## Design notes

Colours are adaptive and contrast-checked. The brand navy scores 13:1 on white
but only **1.3:1** on the dark-mode background, so every accent has a lighter
dark twin, and text sitting *on* a filled accent flips to near-black in dark
mode rather than staying white (which measured 2.3:1). Worst pair in either
mode is now 4.7:1.

Layout adapts: one column of course cards on iPhone, two on a regular-width
iPad, capped at a readable measure on very wide windows. Course card actions
fall back from a single row to a stacked layout at accessibility text sizes,
where a one-row layout overflowed.

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
