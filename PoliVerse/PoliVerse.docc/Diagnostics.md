# Diagnostics

What the app records about itself, and where it stays.

## Overview

![What the app records about itself, and the two things that ever cross the device's edge.](diagnostics-map)

> Important: There is no analytics service and no crash reporter. Nothing here
> leaves the device unless the student shares it. What is collected is what
> Impostazioni · Collegamenti can show, and what a bug report can be attached
> to.

### The report

``DiagnosticsCollector`` reads the app's state into a ``DiagnosticsSnapshot``
without touching the network:

| Section | What it says |
|---|---|
| Account | the session's state, the way in last used, and its ``ScopeAudit`` |
| WeBeep | whether it is connected and what it last answered |
| Pending | what the ``ActionQueue`` is holding, and what has been refused |
| Background | whether iOS allows refresh, and how the last run went |
| Device | notifications, Live Activities, low-power mode |
| Performance | what MetricKit has delivered |

``DiagnosticsReport`` turns that into plain text to attach to a report.

> Warning: The matricola is included only if the student asks. A token or a
> password never is — they are stripped even out of an error message that
> quotes one.

``ConnectionProbe`` is the one part that does reach the network.

> Note: A probe asks each service whether it is there, without credentials, and
> counts an answer as reachable **even when it is an error**. It says whether
> the network gets to the Politecnico and how fast, not whether the student's
> data is correct.

### Performance

``PerformanceMonitor`` receives MetricKit's daily payloads: a summary of launch
time, memory and battery, and a report for each hang or crash. ``ReportArchive``
keeps them on disk, ``MetricReportsView`` shows them, and they stay there.
``PerfSignpost`` marks the app's own spans for Instruments, and
``PerformanceStates`` names the states a run can be in.

### Storage

``StorageAudit`` scans what the app is holding — downloaded WeBeep materials by
kind, and the caches and offline records — and ``DataStorageView`` shows it as a
bar with a row per kind.

> Important: Deleting goes through the stores rather than by removing their
> files, so each one also drops what it is holding in memory. An
> ``OfflineStore`` whose folder disappeared underneath it would keep serving
> records the screen has just claimed to have deleted.

### Reading an unexpected payload

When a service answers with something the app cannot decode, ``JSONShape`` and
``PayloadInspector`` describe the *shape* of what arrived rather than its
contents — enough to see what changed without logging a student's data.

> Tip: A screen then says the format was not recognised rather than dressing it
> as an empty list. ``NewsView`` is the example: "nessuna notizia" and "the
> server answered in a format we cannot read" are different facts and must not
> look alike.

### Exam updates

``ExamChangeDetector`` compares what the career service says now against
``ExamWatchState``, the last thing it said, and records an ``ExamUpdate`` for
each real change: a mark published, an enrolment window opening, a room or date
changed.

| Type | Its job |
|---|---|
| ``ExamChangeDetector`` | finds what actually changed |
| ``ExamUpdatePolicy`` | decides which changes are worth a notification |
| ``ExamUpdateLog`` | keeps them |
| ``UpdateFeed`` | what Carriera and the Shortcuts intent read |
| ``MutedCourse`` | stops one course without turning the rest off |

### Freshness

``FreshnessCoordinator`` records, per service, when it last answered and whether
it failed. ``DataStatus`` folds that into the one line the app shows at the
bottom of the screen, by a fixed precedence — sample data first, because then
nothing else on the page is true; then no connection, because it explains the
failures; then any failure. ``FreshnessBar`` draws it.

## Topics

### The report
- ``DiagnosticsCollector``
- ``DiagnosticsSnapshot``
- ``DiagnosticsReport``
- ``DiagnosticsLog``
- ``ConnectionProbe``
- ``ScopeAudit``

### Performance
- ``PerformanceMonitor``
- ``PerformanceStates``
- ``ReportArchive``
- ``PerfSignpost``

### Storage
- ``StorageAudit``

### Unexpected payloads
- ``JSONShape``
- ``PayloadInspector``

### Exam updates
- ``ExamChangeDetector``
- ``ExamUpdate``
- ``ExamUpdatePolicy``
- ``ExamUpdateLog``
- ``ExamWatchState``
- ``UpdateFeed``
- ``MutedCourse``

### Freshness
- ``FreshnessCoordinator``
- ``DataStatus``
- ``FreshnessBar``

### Screens
- ``ConnectionsView``
- ``DataStorageView``
- ``MetricReportsView``
- ``CareerDiagnosticsView``
