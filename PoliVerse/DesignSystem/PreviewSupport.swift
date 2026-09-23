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
    /// The sample session, with ``Session/useMockData`` on, so previews are offline and
    /// identical every time.
    static let session: Session = {
        let session = Session()
        session.useMockData = true
        return session
    }()

    /// The sample update feed.
    static let updates = UpdateFeed()
    /// The notification model. Nothing is scheduled in a preview.
    static let notifications = NotificationModel()
    /// The sample WeBeep model.
    static let weBeep = WeBeepModel(session: session, feed: updates)
    static let recordings = RecordingsModel(account: session)
    /// The sample course list.
    static let courses = CourseModel(account: session, enrolments: weBeep)
    /// The sample timetable.
    static let agenda = AgendaModel(account: session)
    /// The sample academic record.
    static let career = CareerModel(account: session, feed: updates)
    /// The sample notifications.
    static let notices = NoticeModel(account: session)
    /// The sample news.
    static let news = NewsModel(account: session)
    /// The sample enrolments.
    static let careers = CareersModel(account: session)
    /// The sample room catalogue, seeded and told not to fetch: the maps service is
    /// unauthenticated and has no sample path of its own.
    static let rooms = RoomsModel(preview: Classroom.samples())
    /// The sample room occupancy, seeded and told not to fetch.
    static let freeRooms = FreeRoomsModel(catalogue: rooms, preview: RoomSchedule.samples(on: .now))
    /// The sample room equipment, seeded and told not to fetch.
    static let facilities = RoomFacilitiesModel(preview: RoomFacility.samples())
    /// The sample campus map, seeded and told not to fetch.
    static let campusMap = CampusMapModel(
        catalogue: rooms, freeRooms: freeRooms, preview: MapPin.samples())
    /// The download model. Nothing is fetched in a preview.
    static let downloads = FileDownloadModel()
    /// The CIE router, with nothing pending.
    static let cieID = CieIDRouter()
    /// Live reachability, which a preview reports as available.
    static let network = NetworkMonitor()
    /// The change queue, which a preview leaves empty.
    static let pending = PendingChanges(account: session, network: network)
    /// The Manifesti catalogue.
    static let manifesti = ManifestiModel()
    /// The timetable cart.
    static let cart = TimetableCart()
    /// The study programme model. Under sample data it locates nothing.
    static let programmes = StudyProgrammeModel(manifesti: manifesti, account: session, career: career)
    /// The sample personal timetable.
    static let personalTimetable = PersonalTimetableModel(cart: cart, agenda: agenda, preview: PersonalTimetable.sample)
    /// The Live Activity controller, with none running.
    static let liveActivity = LiveActivityController()
    /// Its own defaults suite, so opening a preview cannot mark the real
    /// install's onboarding as done.
    static let spid = SPIDCatalogue(
        defaults: UserDefaults(suiteName: "preview-spid") ?? .standard)
    /// Which way in was used last, in its own defaults suite.
    static let loginMemory = LoginMethodMemory(
        defaults: UserDefaults(suiteName: "preview-login") ?? .standard)
    /// Where the first run has got to, in its own defaults suite.
    static let onboarding = OnboardingState(
        defaults: UserDefaults(suiteName: "preview-onboarding") ?? .standard)
    /// Which release's notes were shown, pinned to one version and in its own defaults
    /// suite.
    static let whatsNew = WhatsNewState(
        current: "2.0", defaults: UserDefaults(suiteName: "preview-whats-new") ?? .standard)
    /// The data status, which a sample session reports as sample data.
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

/// Injecting the sample environment into a preview.
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
            .environment(PreviewEnvironment.recordings)
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
            .environment(PreviewEnvironment.whatsNew)
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
