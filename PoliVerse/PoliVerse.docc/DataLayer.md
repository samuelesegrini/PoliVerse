# The data layer

One request, from the screen that asks for it to the service that answers.

## Overview

Every piece of data on screen comes through the same pipeline, so a screen
never has to know whether it is looking at a cached answer, a fresh one, or a
change the student made while offline.

![A load through the Store pipeline, what happens when it fails, and how a write goes the other way.](store-pipeline)

### Source and Store

A ``Source`` describes one kind of data: where it is cached, how to fetch it,
and how to decode it. ``Store`` drives it. A `load()` on a store:

1. reads the cache and publishes it at once, so the screen has something to
   draw on the first frame;
2. decides whether a refresh is due, from the ``LoadWindow`` the source asks
   for;
3. fetches, decodes, writes the cache, and publishes the result;
4. records what happened in ``DataStatus`` and with the
   ``FreshnessCoordinator``, so the app can say how old what it is showing is.

> Important: A failed refresh never clears what is already there. The cached
> answer stays on screen and the failure is reported beside it — an empty
> screen says less than a stale one with a date on it.

### The network

``HTTP`` is the one door out. ``PoliMiAPI`` wraps the Politecnico's own
services on top of it, and the table below is the whole of the outward surface:

| Type | What it is for | Credentials |
|---|---|---|
| ``PoliMiAPI`` | the Politecnico's authenticated services | the token ``TokenStore`` holds |
| ``PublicHTTP`` | the services that need no account | none |
| ``ConnectionProbe`` | asking a service whether it is there at all | none |
| ``ResourceLoader`` | de-duplicating the same request in flight twice | whatever the caller uses |

``PoliMiAPI`` resolves hosts through ``ServiceDirectory`` rather than
hard-coding them, so a change on the Politecnico's side needs no release, and
turns a failure into something a screen can show.

> Tip: ``ResourceLoader`` sits in front of the requests that are asked for many
> times at once — a room's occupancy, a teaching's scheda. The same work is
> never started twice, and an answer already in hand is reused.

### Writing

A change the student makes — a course marked as a favourite, an enrolment —
does not wait for the network:

```swift
// Recorded before the request, so the list shows the tap immediately.
optimistic.set(favourite: wanted, for: course.id)
Task {
    if await enrolments.setFavourite(wanted, moodleID: moodleID) {
        optimistic.clear(favouriteFor: course.id)   // the server is the truth again
    } else {
        pending.enqueue(.favourite(course.id, wanted))   // send it when the network is back
    }
}
```

``PendingChanges`` applies the change at once through ``OptimisticFlags``, so
the screen updates under the finger, and queues the real request in the
``ActionQueue``.

> Warning: The queue stops after ``ActionQueue/maxAttempts`` refusals rather
> than retrying forever. What is queued and what has been refused is shown in
> Impostazioni · Collegamenti, because a change that will never be sent must
> not look like one that simply has not been sent yet.

### Offline, and the widgets

``OfflineStore`` is an app-group container holding the snapshots the widgets
read: the day's agenda, the career, the free rooms. The app writes them
whenever it learns something new; the widgets only ever read. Because it is an
app group and not a shared process, a widget's timeline can be built without
waking the app. See <doc:WidgetsAndActivities>.

### Sample data

With `useMockData` on, every source answers from the fixtures in
`Model/Samples` rather than from the network.

> Note: Every fixture is derived from a single ``SampleDegree``, so the
> timetable, the libretto, the materials and the widgets all describe one
> coherent student rather than four unrelated ones. Nothing reaches the
> Politecnico while the sample data is on, and the app says so on every screen.

## Topics

### The pipeline
- ``Source``
- ``Store``
- ``LoadWindow``
- ``DataStatus``
- ``FreshnessCoordinator``

### The network
- ``HTTP``
- ``PoliMiAPI``
- ``PublicHTTP``
- ``ServiceDirectory``
- ``ResourceLoader``
- ``ConnectionProbe``

### Writing
- ``PendingChanges``
- ``ActionQueue``
- ``PendingAction``
- ``OptimisticFlags``

### Across targets
- ``OfflineStore``

### Sample data
- ``SampleDegree``
- ``FixtureHTTP``
