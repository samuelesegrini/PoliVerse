# ``PoliVerse``

A student client for Politecnico di Milano: timetable, career, course
materials, rooms and campus places, in one app that works offline.

## Overview

PoliVerse reads the Politecnico's own services — the Servizi Online API, the
Manifesti degli Studi pages, WeBeep's Moodle instance and the public rooms and
news endpoints — and presents them as a single set of screens, widgets and
Live Activities.

The app is one SwiftUI target plus a widget extension. Three layers divide it:

![The three layers of the app target, the widget extension, and the Shared types compiled into both.](layers)

- **Model** owns data. Each remote service is a ``Source`` behind a ``Store``,
  which adds caching, an offline copy, a load window and a load phase.
  Feature-facing models such as ``CareerModel``, ``CourseModel`` and
  ``AgendaModel`` compose those stores into the shapes screens consume.
- **Features** own screens. Each directory under `Features` is one area of the
  app, and ``ShellState`` routes between them.
- **DesignSystem** owns the shared surfaces, and the ``Theme`` that colours
  them.

The `Shared` types are compiled into both the app and the widget extension, and
``OfflineStore`` is the app-group container both read.

> Note: Read <doc:Architecture> first for how the pieces fit together, then
> <doc:DataLayer> for how a single request travels from a screen to a service
> and back.

### What the app is built on

| Area | Starts at | Article |
|---|---|---|
| Loading and caching | ``Store`` | <doc:DataLayer> |
| Getting in | ``Session`` | <doc:Authentication> |
| The look | ``TodayStyle`` | <doc:Customisation> |
| Outside the app | ``OfflineStore`` | <doc:WidgetsAndActivities> |
| Telling what went wrong | ``DiagnosticsCollector`` | <doc:Diagnostics> |

### Running against sample data

Every ``Source`` must supply ``Source/sample()``, so the whole app renders
without an account. ``Session/useMockData`` turns it on, and
``SampleDegree`` derives the sample career, timetable, courses and materials
from a single fictional degree so that they agree with one another.

> Important: With the sample data on, nothing reaches the Politecnico or
> WeBeep. Every screen says so, and the widgets fall back to the same fixtures
> — so a screenshot taken in this mode is never mistaken for a real career.

## Topics

### Essentials

- <doc:Architecture>
- <doc:DataLayer>
- <doc:Authentication>

### App entry

- ``PoliVerseApp``
- ``RootView``
- ``AppShellDuties``
- ``ShellState``
- ``AppDestination``

### The data layer

- ``Store``
- ``Source``
- ``Env``
- ``Account``
- ``HTTP``
- ``OfflineStore``
- ``LoadWindow``
- ``DataStatus``
- ``FreshnessCoordinator``
- ``PendingChanges``
- ``ActionQueue``
- ``OptimisticFlags``

### Identity and sign-in

- ``Session``
- ``LoginFlow``
- ``LoginStage``
- ``PoliMiOAuth``
- ``PoliMiLoginMethod``
- ``SPIDCatalogue``
- ``CieIDBridge``
- ``TokenStore``
- ``KeychainStore``
- ``OnboardingFlow``
- ``OnboardingState``

### Career

- ``CareerModel``
- ``CareersModel``
- ``Career``
- ``LibrettoExam``
- ``ExamSession``
- ``ExamTimeline``
- ``ExamContext``
- ``PartialExams``
- ``StudyPlan``

### Courses and teaching

- ``CourseModel``
- ``Course``
- ``Teacher``
- ``EnrolmentOverrides``
- ``EnrolmentOrigin``
- ``CourseEnrolments``
- ``SubjectSymbol``
- ``CourseHubBadges``

### Timetable

- ``AgendaModel``
- ``AgendaEvent``
- ``PersonalTimetableModel``
- ``PersonalTimetable``
- ``TimetableCart``
- ``CalendarExporter``

### Study programmes

- ``ManifestiModel``
- ``ManifestoTeaching``
- ``CataloguePage``
- ``CatalogueSelection``
- ``CatalogueField``
- ``ManifestoParser``
- ``StudyProgramme``
- ``StudyProgrammeModel``
- ``StudentRecord``
- ``TeachingRef``
- ``TeachingCodes``

### Course materials

- ``WeBeepModel``
- ``WeBeepAPI``
- ``WeBeepAuth``
- ``WeBeepFile``
- ``Moodle``
- ``AssignmentDeadline``
- ``AssignmentDetector``
- ``AnnouncementDetector``
- ``CourseForum``
- ``FileDownloadModel``
- ``DocumentClassifier``

### Places

- ``RoomsModel``
- ``FreeRoomsModel``
- ``RoomCatalogue``
- ``RoomFacilitiesModel``
- ``CampusMapModel``
- ``Classroom``
- ``RoomOccupancy``
- ``BuildingLocation``
- ``MapPlacement``

### Updates, news and notifications

- ``UpdateFeed``
- ``FeedItem``
- ``ExamUpdate``
- ``ExamUpdatePolicy``
- ``NewsModel``
- ``NoticeModel``
- ``NotificationModel``
- ``NotificationPlan``
- ``ReleaseNotes``
- ``WhatsNewState``

### Home-screen presence

- <doc:WidgetsAndActivities>
- ``WidgetKind``
- ``WidgetReloader``
- ``LiveActivityController``
- ``SpotlightIndex``
- ``BackgroundRefresh``

### Customising Oggi

- <doc:Customisation>
- ``TodayStyle``
- ``Flavor``
- ``TodaySection``
- ``LookLibrary``
- ``PlacedSticker``

### Design system

- ``Theme``
- ``CardSection``
- ``CourseCard``
- ``HeaderFigure``
- ``FreshnessBar``
- ``RootStack``

### Diagnostics

- <doc:Diagnostics>
- ``DiagnosticsCollector``
- ``DiagnosticsReport``
- ``DiagnosticsLog``
- ``ConnectionProbe``
- ``PayloadInspector``
- ``StorageAudit``
- ``ReportArchive``
- ``PerformanceMonitor``
- ``PerfSignpost``
