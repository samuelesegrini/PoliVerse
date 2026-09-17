import SwiftUI

/// Everything a preview needs to render a view that reads services.
///
/// Almost every screen here pulls two or three `@Environment` services, so
/// without this a preview is a dozen lines of setup and nobody writes one.
/// With it, a preview is `SomeView().previewEnvironment()`.
///
/// The session runs on sample data, so previews are offline, instant and
/// identical every time. The three services that talk to the public maps
/// endpoints — which have no mock path, being unauthenticated — are seeded
/// and told not to fetch, so opening a preview never hits the network.
@MainActor
enum PreviewEnvironment {
    static let session: Session = {
        let session = Session()
        session.useMockData = true
        return session
    }()

    static let updates = UpdateFeed()
    static let notifications = NotificationModel()
    static let weBeep = WeBeepModel(session: session, feed: updates)
    static let courses = CourseModel(session: session, weBeep: weBeep)
    static let agenda = AgendaModel(session: session)
    static let career = CareerModel(session: session, feed: updates)
    static let notices = NoticeModel(session: session)
    static let news = NewsModel(session: session)
    static let careers = CareersModel(session: session)
    static let rooms = RoomsModel(preview: MockData.classrooms())
    static let freeRooms = FreeRoomsModel(catalogue: rooms, preview: MockData.roomSchedules(on: .now))
    static let facilities = RoomFacilitiesModel(preview: MockData.facilities())
    static let campusMap = CampusMapModel(
        catalogue: rooms, freeRooms: freeRooms, preview: MockData.mapPins())
    static let downloads = FileDownloadModel()
    static let cieID = CieIDRouter()
    static let network = NetworkMonitor()
    static let pending = PendingChanges(session: session, network: network)
    static let manifesti = ManifestiModel()
    static let programmes = StudyProgrammeModel(manifesti: manifesti, session: session, career: career)
    static let personalTimetable = PersonalTimetableModel(manifesti: manifesti, agenda: agenda, preview: MockData.personalTimetable)
    static let liveActivity = LiveActivityController()
    /// Its own defaults suite, so opening a preview cannot mark the real
    /// install's onboarding as done.
    static let spid = SPIDCatalogue(
        defaults: UserDefaults(suiteName: "preview-spid") ?? .standard)
    static let loginMemory = LoginMethodMemory(
        defaults: UserDefaults(suiteName: "preview-login") ?? .standard)
    static let onboarding = OnboardingState(
        defaults: UserDefaults(suiteName: "preview-onboarding") ?? .standard)
    static let status = DataStatus(session: session, network: network)
    /// Wired to the same sample services, so a preview's `.task` refreshes
    /// mock data instead of finding an empty list.
    static let freshness: FreshnessCoordinator = {
        let coordinator = FreshnessCoordinator.standard(
            courses: courses, agenda: agenda, career: career,
            notices: notices, news: news, weBeep: weBeep)
        coordinator.status = status
        return coordinator
    }()
}

extension View {
    /// Injects the sample environment. Use on every `#Preview`.
    func previewEnvironment() -> some View {
        environment(PreviewEnvironment.session)
            .environment(PreviewEnvironment.courses)
            .environment(PreviewEnvironment.agenda)
            .environment(PreviewEnvironment.career)
            .environment(PreviewEnvironment.updates)
            .environment(PreviewEnvironment.notifications)
            .environment(PreviewEnvironment.weBeep)
            .environment(PreviewEnvironment.notices)
            .environment(PreviewEnvironment.news)
            .environment(PreviewEnvironment.careers)
            .environment(PreviewEnvironment.rooms)
            .environment(PreviewEnvironment.freeRooms)
            .environment(PreviewEnvironment.facilities)
            .environment(PreviewEnvironment.campusMap)
            .environment(PreviewEnvironment.downloads)
            .environment(PreviewEnvironment.cieID)
            .environment(PreviewEnvironment.network)
            .environment(PreviewEnvironment.pending)
            .environment(PreviewEnvironment.manifesti)
            .environment(PreviewEnvironment.personalTimetable)
            .environment(PreviewEnvironment.programmes)
            .environment(PreviewEnvironment.liveActivity)
            .environment(PreviewEnvironment.freshness)
            .environment(PreviewEnvironment.status)
            .environment(PreviewEnvironment.onboarding)
            .environment(PreviewEnvironment.spid)
            .environment(PreviewEnvironment.loginMemory)
            .tint(Theme.brand)
            // Not pinned: previews render in whatever language the scheme
            // is set to, which is how a translation gets looked at.
    }

    /// The same, wrapped in a navigation stack — for views that expect one
    /// (anything with a title, a toolbar or a `NavigationLink`).
    func previewInNavigation() -> some View {
        NavigationStack { self }.previewEnvironment()
    }
}
