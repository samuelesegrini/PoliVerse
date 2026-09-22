# Architecture

How the app is put together, from the services it reads to the screens it draws.

## Overview

PoliVerse is one app target with a widget extension beside it, and both are
built from the same three layers.

![The three layers of the app target, the widget extension, and the Shared types compiled into both.](layers)

**Model** holds everything that is not a view: the ``Store`` pipeline that
talks to the Politecnico's services, the types those services answer with, and
the `@Observable` models the screens read. Nothing here imports a screen.

**Features** holds the screens, grouped by what a student is doing rather than
by type: `Shell` is the app's frame, `Home` its courses, `Career` the libretto
and the sittings, `Customize` the look, and so on. A feature reads the models
from the SwiftUI environment and writes back through them.

**DesignSystem** holds what every screen shares: ``Theme``, the card and row
surfaces, the freshness bar, and the preview helpers.

> Important: The `Shared` folder sits outside all three, and its types are
> compiled into *both* targets. That is the only way the widgets see anything:
> ``OfflineStore`` is an app-group container the app writes snapshots into and
> the widgets read, so neither target has to know about the other.

### The frame

``PoliVerseApp`` builds the environment — one instance of each model — and
hands it to ``RootView``, which chooses between the two layouts the student can
pick in Impostazioni.

| Layout | What is on screen | Everything else |
|---|---|---|
| **Tabs** (``AppLayout/tabs``) | Oggi, Corsi, Carriera, Cerca | listed in Cerca |
| **Pagina unica** (``AppLayout/singlePage``) | Oggi alone, no tab bar | in a bottom panel, as Maps does it |

Both reach the same places, described once in ``NewDestination`` so the two
layouts cannot drift apart.

> Note: ``ShellState`` is owned by ``RootView``, *above* both layouts. The day
> being shown, the navigation paths and the sheets over the app therefore
> survive a change of layout — presented from inside a layout instead,
> switching between them in Impostazioni would tear down the view that owns the
> sheet and close it mid-change.

### Where a screen's data comes from

A screen never fetches. It reads an `@Observable` model and calls `load()` from
a `.task`:

```swift
struct NewsView: View {
    @Environment(NewsModel.self) private var news

    var body: some View {
        List { /* … */ }
            .task { await news.load() }
            .refreshable { await news.load(force: true) }
    }
}
```

The model asks its ``Store``, which reads the cache, answers at once with
whatever it has, and refreshes behind that. <doc:DataLayer> follows one request
the whole way down.

### What the student can change

Almost every surface in the app is drawn from ``TodayStyle``, the look the
student builds in Personalizza: one ``Flavor`` becomes the whole palette, and
the typeface, the material of the cards and the lighting travel with it.
<doc:Customisation> explains how.

> Tip: When adding a screen, reach for `lookCard(cornerRadius:)`,
> `lookList()` and ``LookHeading`` rather than fixed colours and system
> materials. A page that ignores the look reads as one borrowed from another
> app.

## Topics

### The frame
- ``PoliVerseApp``
- ``RootView``
- ``ShellState``
- ``NewDestination``
- ``AppLayout``
- ``TodayTab``
- ``SinglePagePanel``

### Shared across targets
- ``OfflineStore``
- ``AppDestination``
- ``WidgetKind``
- ``AgendaEvent``
- ``CareerSnapshot``

### Further reading
- <doc:DataLayer>
- <doc:Authentication>
- <doc:Customisation>
- <doc:WidgetsAndActivities>
- <doc:Diagnostics>
