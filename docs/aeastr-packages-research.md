# Aeastr packages: what could help PoliVerse's design (iOS 26 target)

Researched 2026-09-14. Repo list: `gh repo list Aeastr` (https://github.com/Aeastr?tab=repositories). PoliVerse targets iOS 26.0, so anything that only backports an iOS 26 API is not worth adding.

Where Package.swift or the license is cited, the URL is `https://github.com/Aeastr/<repo>/blob/main/Package.swift` and the license comes from the GitHub repo API (`license.spdx_id`). Stars and last push come from `gh repo list` on the research date.

Where PoliVerse stands today: its design system is plain SwiftUI. `Theme` has adaptive brand and accent colours with WCAG contrast checked by hand, plus `cardBackground` (`PoliVerse/DesignSystem/Theme.swift`). `RootView` already uses the iOS 18+ `Tab` API with a `.search` role (`PoliVerse/App/RootView.swift:70-77`). Home is a `ScrollView`/`LazyVStack` with a horizontal shelf (`PoliVerse/Features/Home/HomeView.swift:38,324`). The app has 22 `.sheet`, 3 `.contextMenu` and 1 `.fullScreenCover`. It uses no `glassEffect` or zoom transitions yet. The Home redesign exploration is in `design/home/` (hero lecture card, week strip, wallet stack, ticket exam card, shelves, rings).

## Summary: ranked recommendations

| # | Repo | What it gives | Where in PoliVerse | iOS 26 overlap | License | Maintenance |
|---|------|---------------|--------------------|----------------|---------|-------------|
| 1 | [Portal](https://github.com/Aeastr/Portal) (`PortalHeaders` only) | Scroll-driven header that flows into the nav bar, like Music or Photos | Hero lecture card or course header in `CourseDetailView` / `ExamDetailView` | Partial. Apple gives you the pieces (`onScrollGeometryChange`, `backgroundExtensionEffect`, `scrollEdgeEffectStyle`) but no ready-made "header flows into title" component | MIT | push 2026-08-14, 1100★ |
| 2 | [Garnish](https://github.com/Aeastr/Garnish) | WCAG luminance and contrast maths, auto-contrasting text colour | Replace the hand-tuned `Theme.onAccent` and the accent pairs; text on course-tinted wallet/ticket cards | None. SwiftUI has `Color.resolve(in:)` but no contrast API | MIT | 2026-01-29, 239★ |
| 3 | [AdaptiveDimensions](https://github.com/Aeastr/AdaptiveDimensions) | `scaledFrame`, `scaledPadding`, scaled spacing and corner radius | Progress rings, week-strip cells, `Theme.cardCorner` under Dynamic Type | Partial. `@ScaledMetric` does the same job one property at a time | MIT | 2026-01-29, 49★ |
| 4 | [Loupe](https://github.com/Aeastr/Loupe) (debug builds only) | Render/recompute visualisers, layout grids, concentric-corner guide | Performance and layout checks during the Home redesign | None (dev tooling) | MIT | 2026-01-29, 640★ |
| 5 | [SettingsKit](https://github.com/Aeastr/SettingsKit) | Declarative, searchable settings screens | A future settings/preferences screen | None (`Form` does it by hand) | MIT | 2026-01-29, 282★ |

Everything else is either superseded, relies on private API, or has nothing to do with PoliVerse (see [Do not adopt](#do-not-adopt)).

---

## Per-repo analysis

### Portal
- **What it is:** three targets. `PortalTransitions` animates an element between navigation contexts using a floating overlay (iOS 17+). `PortalHeaders` does flowing scroll headers (iOS 18+). `_PortalPrivate` mirrors views through the private `_UIPortalView`. Source: https://github.com/Aeastr/Portal#readme
- **Platforms and license:** `.iOS(.v17)`. Depends on `Aeastr/Chronicle` and `Aeastr/UIPortalBridge`. MIT. Source: https://github.com/Aeastr/Portal/blob/main/Package.swift
- **Fit:** the redesign's hero lecture card and the course/exam detail headers could collapse into the navigation title. That is the one piece Apple doesn't ship as a component.
- **Apple overlap:**
  - `PortalTransitions` is **superseded** for push and sheet presentations. Use `matchedTransitionSource(id:in:)` with `.navigationTransition(.zoom(sourceID:in:))`, which supports interactive dismissal (https://developer.apple.com/documentation/swiftui/view/matchedtransitionsource(id:in:), https://developer.apple.com/documentation/swiftui/view/navigationtransition(_:)). A tab-to-tab flight is the only case Apple doesn't cover, and PoliVerse doesn't need it.
  - `PortalHeaders` overlaps **partially**. You can build it from `onScrollGeometryChange` (https://developer.apple.com/documentation/swiftui/view/onscrollgeometrychange(for:of:action:)), `backgroundExtensionEffect()` (https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect()) and `scrollEdgeEffectStyle` (https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)).
- **Risks:** the package declares all three targets, so the Package.swift dependency on the private-API bridge (UIPortalBridge) is resolved even if you only link `PortalHeaders`. Worth checking whether that code gets linked at all (see open questions). The README says it is on major version 4 with breaking API changes. The small amount of header code could reasonably be copied into PoliVerse instead of taking the dependency.

### Garnish
- **What it is:** WCAG 2.1 relative luminance, contrast ratios, `contrastingColor(_:against:)`, `contrastingShade(of:)` and `hasGoodContrast`. Source: https://github.com/Aeastr/Garnish#readme
- **Platforms and license:** `.iOS(.v14)`, `.macOS(.v14)`. Depends on `Aeastr/Chronicle`. MIT. Source: https://github.com/Aeastr/Garnish/blob/main/Package.swift
- **Fit:** `Theme.swift` records contrast ratios that were computed by hand ("Every pair clears 4.5:1"). Garnish could enforce this in `PoliVerseTests` and pick label colours for course-tinted wallet and ticket cards.
- **Apple overlap:** none. `Color.resolve(in:)` returns the components (https://developer.apple.com/documentation/swiftui/color/resolve(in:)), but nothing computes contrast.
- **Risks:** it pulls in the Chronicle logging dependency. The maths is about 30 lines, so a test-only helper is a reasonable alternative.

### AdaptiveDimensions
- **What it is:** frame, padding, spacing and corner-radius modifiers that scale with Dynamic Type relative to a text style. Source: https://github.com/Aeastr/AdaptiveDimensions#readme
- **Platforms and license:** iOS 14, macOS 11, watchOS 7, tvOS 14, visionOS 1. No dependencies. MIT. Source: https://github.com/Aeastr/AdaptiveDimensions/blob/main/Package.swift
- **Fit:** fixed sizes in rings, week-strip day cells and the 26pt card corner.
- **Apple overlap:** partial. `@ScaledMetric(relativeTo:)` covers it (https://developer.apple.com/documentation/swiftui/scaledmetric). The package is only a convenience layer. On iOS 26, `ConcentricRectangle` also handles nested corner radii (https://developer.apple.com/documentation/swiftui/concentricrectangle).
- **Risks:** low. Also low value, so `@ScaledMetric` is probably enough.

### Loupe
- **What it is:** `.debugRender()`, `.debugCompute()`, layout, grid and position guides, and an iOS 26 `VisualCornerInsetGuide` for ConcentricRectangle. Source: https://github.com/Aeastr/Loupe#readme
- **Platforms and license:** iOS 17, macOS 14. MIT. Source: https://github.com/Aeastr/Loupe/blob/main/Package.swift
- **Fit:** checking re-renders while building the redesign's shelves and stacked cards, next to the existing MetricKit work (`docs/metrickit-performance.md`).
- **Apple overlap:** none as an in-view overlay. Instruments' SwiftUI template covers profiling (https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance).
- **Risks:** it must stay out of release builds. Wrap calls in `#if DEBUG` and don't link it into shipping configurations.

### SettingsKit
- **What it is:** a declarative `SettingsContainer`/`SettingsGroup` hierarchy with built-in search and several styles. Source: https://github.com/Aeastr/SettingsKit#readme
- **Platforms and license:** iOS 17, macOS 14. MIT. Source: https://github.com/Aeastr/SettingsKit/blob/main/Package.swift
- **Fit:** only if PoliVerse grows a large settings area. A small one is simpler as a native `Form`.
- **Apple overlap:** none as a package. `Form` plus `.searchable` does the same by hand (https://developer.apple.com/documentation/swiftui/form).
- **Risks:** it is opinionated about layout, and its styles may not follow iOS 26 grouped/glass appearance updates.

### UniversalGlass
- **What it is:** shims such as `universalGlassEffect`, `.universalGlass()` button styles and `UniversalGlassEffectContainer` that "defer to Apple's implementation" on iOS 26. Source: https://github.com/Aeastr/UniversalGlass#readme
- **Platforms and license:** iOS 17, macOS 13. It is installed from the `main` branch with no tagged version. GitHub detects no license (the `/license` API returns 404). Sources: https://github.com/Aeastr/UniversalGlass/blob/main/Package.swift, https://github.com/Aeastr/UniversalGlass
- **Apple overlap:** **superseded**. With an iOS 26 target, use `glassEffect(_:in:)` (https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)), `GlassEffectContainer` (https://developer.apple.com/documentation/swiftui/glasseffectcontainer) and `.buttonStyle(.glass)` (https://developer.apple.com/documentation/swiftui/primitivebuttonstyle/glass) directly.

### FullScreenSheet
- **What it is:** a full-screen presentation you can pull down to dismiss. It has a public target and a private-API (Apple Music style) target. Source: https://github.com/Aeastr/FullScreenSheet#readme
- **Platforms and license:** `.iOS(.v18)`. Depends on `Aeastr/Obfuscate` (pinned exact). MIT. Source: https://github.com/Aeastr/FullScreenSheet/blob/main/Package.swift
- **Apple overlap:** mostly **superseded**. A zoom `navigationTransition` on `fullScreenCover` dismisses interactively (https://developer.apple.com/documentation/swiftui/view/navigationtransition(_:)). `.presentationSizing(.page)` and detents cover large sheets (https://developer.apple.com/documentation/swiftui/view/presentationsizing(_:)).

### MenuWithAView
- **What it is:** accessory views on `.contextMenu` through the private `_UIContextMenuAccessoryView`. The README warns that App Store submissions using it are at your own risk. Source: https://github.com/Aeastr/MenuWithAView#readme
- **Platforms and license:** iOS 16. MIT. Source: https://github.com/Aeastr/MenuWithAView/blob/main/Package.swift
- **Apple overlap:** partial. `contextMenu(menuItems:preview:)` offers a public custom preview (https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:preview:)). Private API also conflicts with App Review Guideline 2.5.1 (https://developer.apple.com/app-store/review/guidelines/#software-requirements).

### GlowGetter
- **What it is:** a glow effect. The public target uses a Metal overlay. The private target uses a `CAFilter` EDR filter, which the README says may be rejected in review. Source: https://github.com/Aeastr/GlowGetter#readme
- **Platforms and license:** iOS 15. Depends on `Aeastr/Obfuscate`. MIT. Source: https://github.com/Aeastr/GlowGetter/blob/main/Package.swift
- **Fit:** decorative only, for example a "live now" lecture accent. Low value.
- **Apple overlap:** partial. `.shadow`, `.blur` and `visualEffect`/shaders (https://developer.apple.com/documentation/swiftui/view/visualeffect(_:)) cover a soft glow without HDR.

### UIPortalBridge
- A wrapper around the private `_UIPortalView`. The README warns it may be rejected in App Store review. iOS 17, MIT. Source: https://github.com/Aeastr/UIPortalBridge#readme. **Do not adopt** (Guideline 2.5.1).

### UniversalOverlays
- Window-level overlays above the whole app with touch pass-through. iOS 17, MIT. Source: https://github.com/Aeastr/UniversalOverlays#readme
- **Fit:** could host a global toast (for example `DemoModeBanner`), but `tabViewBottomAccessory` (https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)) or `.overlay` on `RootView` does the job without a separate window.

### NotchMyProblem
- Lays out content around the notch or Dynamic Island. iOS 13, MIT. Source: https://github.com/Aeastr/NotchMyProblem#readme
- **Fit:** none. PoliVerse uses standard navigation chrome and safe areas.

### Conditionals
- Fluent modifiers gated on OS version. iOS 16 / macOS 13, MIT. Source: https://github.com/Aeastr/Conditionals#readme
- **Superseded for PoliVerse:** with a single iOS 26 floor there is nothing to branch on.

### SwiftEmoji
- An emoji grid, search and index. iOS 17 / macOS 14, MIT. Source: https://github.com/Aeastr/SwiftEmoji#readme
- **Fit:** none, since PoliVerse has no emoji picker.

### Chronicle
- A logging wrapper over `os.Logger`. iOS 13, depends on `apple/swift-log`, MIT. Source: https://github.com/Aeastr/Chronicle#readme
- Not a design package, and `Logger` (https://developer.apple.com/documentation/os/logger) already covers it.

### SwiftMacros, SwiftShortcuts, CursorBounds, TextInBalance, GlyphMeThat, SwiftUI-AdaptiveImageGlyph
- **SwiftMacros:** general macros that depend on swift-syntax, which slows builds. Source: https://github.com/Aeastr/SwiftMacros
- **SwiftShortcuts:** Shortcuts-related tooling that depends on Conditionals and argument-parser. Source: https://github.com/Aeastr/SwiftShortcuts#readme
- **CursorBounds:** macOS-only caret position. Source: https://github.com/Aeastr/CursorBounds
- **TextInBalance:** has no Package.swift. SwiftUI already offers balanced wrapping through `Text.LineStyle`/`lineLimit` and iOS 26 text layout options. Source: https://github.com/Aeastr/TextInBalance
- **GlyphMeThat:** archived. Source: https://github.com/Aeastr/GlyphMeThat
- **SwiftUI-AdaptiveImageGlyph:** a sample app. It is superseded by the iOS 26 `TextEditor` with `AttributedString` rich text (https://developer.apple.com/documentation/swiftui/texteditor).
- None of these fit PoliVerse.

---

## Do not adopt

| Repo | Reason |
|------|--------|
| UniversalGlass | Backports iOS 26 glass. PoliVerse targets iOS 26, so use `glassEffect`/`GlassEffectContainer` directly. It also has no detected license and no tagged release. |
| Conditionals | Only useful with several OS floors. |
| Portal `PortalTransitions` and `_PortalPrivate` | Zoom `navigationTransition` replaces the transitions, and the private target uses private API. |
| FullScreenSheet | Zoom transition, `presentationSizing` and detents cover it. The private target is risky. |
| MenuWithAView, UIPortalBridge, GlowGetterPrivate | Private API, which risks App Store rejection under Guideline 2.5.1. |
| UniversalOverlays | `tabViewBottomAccessory` or an overlay covers PoliVerse's needs. |
| NotchMyProblem, SwiftEmoji, CursorBounds, SwiftShortcuts, SwiftMacros | Wrong problem or wrong platform. |
| GlyphMeThat, SwiftUI-AdaptiveImageGlyph, TextInBalance | Archived, a demo, or no package, and superseded by iOS 26 text APIs. |

Nothing in Aeastr's repos covers the redesign's wallet stack, ticket card, week strip or progress rings. Build those natively with `Gauge`/`Circle().trim`, `ScrollView(.horizontal)` with `scrollTargetBehavior(.viewAligned)` (https://developer.apple.com/documentation/swiftui/view/scrolltargetbehavior(_:)), and custom `Shape`s.

## Open questions
1. Does SPM link any `UIPortalBridge` code into the app when only `PortalHeaders` is used? Both Portal and UIPortalBridge are resolved as dependencies of the package. Check the linked binary with `nm` before adopting.
2. Is Garnish worth a runtime dependency, or only as a test-time check on `Theme` accents? A ~30-line WCAG helper in `PoliVerseTests` may be better.
3. UniversalGlass has no LICENSE that GitHub detects. This is irrelevant if it isn't adopted, but confirm before anyone reuses its code.
4. The Apple documentation URLs above follow Apple's standard symbol-path format but were not individually fetched during this pass. Spot-check the less common ones (`backgroundextensioneffect()`, `primitivebuttonstyle/glass`) before quoting them elsewhere.
