# Personalising the app

How one colour becomes the whole app, and how the student rearranges Oggi.

## Overview

Almost nothing in PoliVerse is drawn in a fixed colour. ``TodayStyle`` is the
look the student builds in Personalizza, and every screen reads it: the cards,
the controls, the typefaces and the lighting all come from there, so the app is
recognisably theirs wherever they are.

### Flavor

A look starts from one colour.

![Accent and Extra derived from Main, and the ramp a page hands out its colours from.](flavor-ramp)

``Flavor`` turns it into a palette: Main is the colour itself, and Accent and
Extra are a step and two steps around the wheel from it, unless the student
sets them by hand.

> Note: A grey has no hue to move along, so it only deepens: below 0.12
> saturation ``Flavor`` keeps the hue and lowers the brightness instead.
> Spreading hues around a grey would invent a colour the student deliberately
> did not pick.

Every colour the app draws is checked for contrast before it is used.

| Type | What it gives |
|---|---|
| ``Flavor/Palette`` | the resolved set for one appearance: ground, surface, accent, onAccent |
| ``Flavor/Mode`` | how strongly the page is coloured — `standard`, `contrast`, `tinted` |
| ``FlavorRamp`` | a run of related colours, deepest to palest, across a sixth of the wheel |

``FlavorRamp`` is where a course's colour and a settings page's tiles come
from: a page hands out steps by **position**, so storage by size means deeper
is bigger, the way iCloud's bar steps from dark to light.

> Tip: A Flavor can also be taken from a photo (``Flavor/extract(from:)``) or
> sent to a friend as a short share code (``Flavor/shareCode``).

### The page

``TodayStyle`` holds the rest:

- ``TodayMaterial`` for the cards, a typeface for the date and a design for the
  other text;
- a ``TodaySheet`` — either a paper texture or a decoration in the Flavor's
  colour, **never both**, because two settings that only ever read as one
  question should be asked once;
- ``TodayAppearance``, which decides how the app is lit.

Beside the date sits a ``TodayAccessory``: nothing, stickers placed by hand, a
few words, or a small stack of photos.

> Note: Sticker images live in ``StickerStore`` as files rather than in the
> look itself. A look is a short string in `UserDefaults`, and an image would
> not fit there.

The body of the page is an ordered list of ``TodaySection``s — the lesson now,
what is coming up, the day's timetable, the deadlines, the exams — each with its
own form, density, material and item limit. A kind appears at most once, which
is why ``TodaySection/id`` is the kind itself.

### Personalizza

``CustomizeOggi`` is the screen: a carousel of saved looks, each card a real
page at full size, so the middle card can grow to cover the screen and back
without anything changing at either end.

> Important: ``LookLibrary`` has one commit point per action — saving an edit
> changes a look, using a look makes it the page's. Editing never changes the
> page by itself, so a student can try something without losing what they had.

Under the live page sits ``BentoPanel``, a bento of tiles, each a small preview
of one part of the look opening its controls in place (``CustomizeControls``).
``TodayLanding`` is the page itself, and in Personalizza it comes in two modes:

| Mode | What it does |
|---|---|
| **Editing** | each zone is outlined; a tap opens its controls |
| **Arranging** | sections wiggle, lift and move; stickers follow a finger, a pinch and a twist |

### Everywhere else

```swift
content
    .lookCard(cornerRadius: 26)   // the look's material behind a view
    .lookList()                   // a List spaced as the look's pages are
```

> Warning: `lookControls()` belongs *outside* anything that presents a sheet.
> A sheet's content takes the environment of the view the presentation is
> attached to, so a tint applied under one stops at the sheet's edge and the
> sheet reverts to the system's blue.

## Topics

### Colour
- ``Flavor``
- ``FlavorRamp``
- ``TodayAppearance``

### The look
- ``TodayStyle``
- ``TodayMaterial``
- ``TodaySheet``
- ``TodayPaper``
- ``TodayBackground``
- ``TodaySection``
- ``TodayAccessory``
- ``PlacedSticker``
- ``StickerStore``
- ``TodayBarStyle``

### Personalizza
- ``CustomizeOggi``
- ``LookLibrary``
- ``BentoPanel``
- ``CustomizePage``
- ``CustomizeControls``
- ``SectionFormPicker``
- ``TodayLanding``

### Drawing with it
- ``TodayBackgroundView``
- ``TodaySectionView``
- ``DateHeader``
- ``LookHeading``
- ``LookTitle``
- ``LookChip``
