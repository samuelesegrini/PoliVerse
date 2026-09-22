# Widgets and Live Activities

What PoliVerse shows without being opened.

## Overview

The widgets are a separate target, and they never talk to the Politecnico.

![The app writes snapshots into the app-group OfflineStore; the widgets and the Live Activity only read from it.](widget-dataflow)

Everything they draw was written by the app into ``OfflineStore``, an app-group
container, so a timeline can be built without waking the app and without a
token. When the app learns something new it writes a snapshot and asks
WidgetKit to reload — see ``WidgetReloader``.

> Important: That is the whole contract. A widget never fetches, never holds a
> token, and never blocks on the app being alive. A widget that finds nothing
> in the store draws the sample data, so a freshly placed widget is never
> blank.

### The widgets

``PoliVerseWidgetBundle`` declares them all.

| Widget | Shows | Reads |
|---|---|---|
| ``NextLectureWidget`` | the next lesson, its room, the countdown | ``WidgetAgenda`` |
| ``TodayWidget`` | the day's lessons, exams and deadlines | ``WidgetAgenda`` |
| ``CareerWidget`` | the average and the credits | ``WidgetCareer`` |
| ``FreeRoomsWidget`` | which rooms are free now, by campus | ``OfflineStore`` |

``FreeRoomsWidget`` is configurable through ``FreeRoomsConfiguration`` and
``CampusOptions``, and its ``RefreshFreeRoomsIntent`` lets a tap ask for a
fresh count — "free now" goes stale in minutes, so a timeline alone is not
enough. ``WidgetPreviewData`` supplies the gallery previews.

### Control Center and the Lock Screen

``TimetableControl``, ``CareerControl`` and ``FreeRoomsControl`` are
`ControlWidget`s: a button in Control Center or on the Lock Screen that opens
the app at one place.

> Note: Where a control lands is an ``AppDestination``, which ``NewRoute``
> turns into a screen. The same destinations serve Siri, Shortcuts, a
> notification and a control — so a new way in is one case, not four.

### Live Activities

``LectureLiveActivity`` puts the lesson in progress on the Lock Screen and in
the Dynamic Island, counting down to its end.
``LectureActivityAttributes`` is its shared attribute type, compiled into both
targets; ``LectureActivityView`` draws it. ``LiveActivityController`` in the app
starts, updates and ends the activity as the day moves.

> Tip: The controller does nothing at all when the student has not allowed Live
> Activities, and the same lesson still appears inside the app above the tab
> bar as ``CurrentClassAccessory``. Neither path assumes the other ran.

### Intents and Shortcuts

``PoliVerseShortcuts`` registers what Siri can be asked for, and
``ExamUpdatesIntent`` answers "any news on my exams" from ``UpdateFeed``'s own
records rather than by fetching.

## Topics

### The bundle
- ``PoliVerseWidgetBundle``
- ``WidgetKind``
- ``WidgetReloader``

### Home-screen widgets
- ``NextLectureWidget``
- ``TodayWidget``
- ``CareerWidget``
- ``FreeRoomsWidget``
- ``FreeRoomsConfiguration``
- ``RefreshFreeRoomsIntent``

### Reading the app's data
- ``OfflineStore``
- ``WidgetAgenda``
- ``WidgetCareer``
- ``WidgetPreviewData``

### Controls
- ``TimetableControl``
- ``CareerControl``
- ``FreeRoomsControl``

### Live Activities
- ``LectureLiveActivity``
- ``LectureActivityAttributes``
- ``LiveActivityController``
- ``CurrentClass``
- ``CurrentClassAccessory``

### Ways in from outside
- ``AppDestination``
- ``NewRoute``
- ``PoliVerseShortcuts``
- ``ExamUpdatesIntent``
