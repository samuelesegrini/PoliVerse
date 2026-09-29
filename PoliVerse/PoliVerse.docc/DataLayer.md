# The data layer

One request, from the screen that asks for it to the service that answers.

## Overview

Every piece of data on screen comes through the same pipeline, so a screen
never has to know whether it is looking at a cached answer, a fresh one, or a
change the student made while offline.

### Resource, Loader and Query

A ``Resource`` describes one kind of data: how to fetch it, for which key, how
long an answer stays good, whether it is written to disk, and what it looks
like under sample data. Its `fetch` is `@concurrent`, so decoding and parsing
run off the main actor. A ``Loader`` — one actor per resource — does the rest
the same way for every resource:

1. **joins** a request already in flight for the same key, so eight callers
   cost one request and a second caller waits instead of being turned away;
2. **keeps** what came back for the resource's lifetime, per account, and
   serves it without asking again;
3. **warms** keys about to be needed at `.utility`, raised to the caller's
   priority when someone then asks for them;
4. **restores** the offline copy once per account before the network answers,
   and drops a restore that a fresh fetch overtook.

A ``Query`` is the `@MainActor` `@Observable` handle a view reads for one key:
the value, whether it is loading, the error, and its age. It assigns only what
changed, so a refresh that brings the same answer redraws nothing. The area
models hold queries and loaders underneath and keep their own API.

Freshness is recorded in ``DataStatus`` and with the
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
| ``Loader`` | joining the same request in flight twice, and keeping the answer | whatever the caller uses |

``PoliMiAPI`` resolves hosts through ``ServiceDirectory`` rather than
hard-coding them, so a change on the Politecnico's side needs no release, and
turns a failure into something a screen can show.

> Tip: The agenda's weeks, a room's occupancy and a teaching's scheda are asked
> for many times at once. Through a ``Loader`` the same work is never started
> twice, contiguous weeks go out as one request, and an answer already in hand
> is reused.

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

With `useMockData` on, every resource answers from its `sample(_:)` rather
than from the network; public data, the same for everyone, is fetched as usual.

> Note: Every fixture is derived from a single ``SampleDegree``, so the
> timetable, the libretto, the materials and the widgets all describe one
> coherent student rather than four unrelated ones. Nothing reaches the
> Politecnico while the sample data is on, and the app says so on every screen.

## Topics

### The pipeline
- ``Resource``
- ``Loader``
- ``Query``
- ``Compute``
- ``DataStatus``
- ``FreshnessCoordinator``

### The network
- ``HTTP``
- ``PoliMiAPI``
- ``PublicHTTP``
- ``ServiceDirectory``
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
