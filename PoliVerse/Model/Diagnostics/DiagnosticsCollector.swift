import Foundation
import UIKit
import UserNotifications

/// Reads the live services and the system into a ``DiagnosticsSnapshot``.
///
/// The only place that knows where each fact lives. Kept apart from the page, so the
/// page draws plain values and the report writes those same values: a diagnostics screen
/// that read one thing and copied another would be worse than none.
@MainActor
struct DiagnosticsCollector {
    /// Supplies the session state, the token's facts and the service directory.
    let session: Session
    /// Supplies the WeBeep connection and its last failure.
    let weBeep: WeBeepModel
    /// Supplies reachability.
    let network: NetworkMonitor
    /// Supplies the queued and abandoned changes.
    let pending: PendingChanges
    /// Supplies the notification permission and the pending reminders.
    let notifications: NotificationModel
    /// Supplies whether Live Activities are permitted and whether one is showing.
    let liveActivity: LiveActivityController
    /// Supplies the CIE sign-in's state and last error.
    let cieID: CieIDRouter
    /// Supplies how the student signed in last.
    let loginMemory: LoginMethodMemory
    /// Supplies when the background work last ran.
    var log: DiagnosticsLog = .shared

    /// The backends the page lists, in order.
    static let services: [ServiceDirectory.Service] = [.app, .iae, .agenda, .libretto, .wsAule, .weBeep]

    /// Gathers everything the page shows.
    ///
    /// The token's facts and the report archive's summary are read concurrently. The scope
    /// audit is omitted entirely when no token is stored, since there would be nothing to
    /// compare.
    ///
    /// - Parameter probes: Reachability results from a previous ``probe()``, or empty when
    ///   the student has not asked for them.
    /// - Returns: The snapshot.
    func snapshot(probes: [DiagnosticsSnapshot.Probe]) async -> DiagnosticsSnapshot {
        await notifications.refreshAuthorization()
        async let expiresAt = session.tokens.expiresAt
        async let recordedScope = session.tokens.grantedScope
        async let hasToken = session.tokens.hasToken
        async let reports = ReportArchive.shared.summary()

        let scopes: ScopeAudit? = await hasToken
            ? ScopeAudit(current: session.directory.oauth.scope, recorded: await recordedScope)
            : nil
        let summary = await reports
        let nextReminder = notifications.scheduled.map(\.fireDate).filter { $0 > .now }.min()

        return DiagnosticsSnapshot(
            generatedAt: .now,
            device: .init(
                appVersion: Bundle.main.appVersion,
                system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
                model: Self.modelIdentifier,
                language: Locale.preferredLanguages.first ?? Locale.current.identifier,
                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                sharedContainer: FileManager.default
                    .containerURL(forSecurityApplicationGroupIdentifier: OfflineStore.groupIdentifier) != nil,
                online: network.isOnline,
                expensive: network.isExpensive),
            account: .init(
                state: sessionState,
                // `remembered`, not `last`: `last` answers "password" when
                // nothing was recorded, which would name a method never used.
                loginMethod: loginMemory.remembered().map(Self.label(for:)),
                matricola: session.student?.matricola,
                tokenExpiresAt: await expiresAt,
                scopes: scopes,
                profile: session.profileID,
                authorised: !session.serviceAuthorizationFailed,
                cieError: cieID.errorMessage,
                cieAwaiting: cieID.isAwaitingCieID),
            weBeep: .init(
                connected: weBeep.isAuthenticated,
                courses: weBeep.courses.count,
                failure: {
                    if case .failed(let message) = weBeep.state { return message }
                    return nil
                }()),
            services: Self.services.map { service in
                let url = session.directory.baseURL(for: service)
                return .init(name: String(localized: service.title), host: url.host() ?? url.absoluteString)
            },
            addressesFromPolitecnico: session.directory.didLoad,
            probes: probes,
            pending: .init(queued: pending.count, abandoned: pending.failed.map(\.label)),
            background: .init(
                refreshPermission: Self.label(for: UIApplication.shared.backgroundRefreshStatus),
                lastRun: log.lastBackgroundRefresh,
                notifications: Self.label(for: notifications.authorization),
                scheduledReminders: notifications.scheduled.count,
                nextReminder: nextReminder,
                liveActivities: liveActivity.isAvailable,
                liveActivityShowing: liveActivity.currentEventID != nil,
                widgetsKnowAccount: SharedAccount.matricola != nil,
                lastWidgetReload: log.lastWidgetReload,
                spotlightItems: log.lastSpotlightIndex?.count,
                spotlightIndexedAt: log.lastSpotlightIndex?.date),
            performance: .init(
                metricReports: summary.metricCount,
                diagnosticReports: summary.diagnosticCount,
                latest: summary.latest))
    }

    /// Probes every service's base address, WeBeep included.
    ///
    /// - Returns: One result per service, in ``services`` order.
    func probe() async -> [DiagnosticsSnapshot.Probe] {
        let urls = Self.services.map { session.directory.baseURL(for: $0) }
        let results = await ConnectionProbe().probe(urls)
        return zip(Self.services, results).map {
            .init(name: String(localized: $0.title), result: $1)
        }
    }

    // MARK: - Words for system states

    /// Where the session stands, in words. A signed-in session under sample data says so
    /// rather than claiming to be connected.
    private var sessionState: String {
        switch session.state {
        case .loading: String(localized: "In caricamento")
        case .signedOut: String(localized: "Non collegato")
        case .exchangingCode: String(localized: "Accesso in corso")
        case .signedIn: session.useMockData ? String(localized: "Dati di esempio") : String(localized: "Collegato")
        case .failed(let message): String(localized: "Non riuscito: \(message)")
        }
    }

    /// A sign-in method in words, with the provider's name for SPID.
    ///
    /// - Parameter method: The method the student used.
    /// - Returns: The phrase.
    static func label(for method: PoliMiLoginMethod) -> String {
        switch method {
        case .password: String(localized: "Codice persona e password")
        case .spid(let provider): "SPID · \(provider.name)"
        case .cie: "CIE"
        case .eidas: "eIDAS"
        case .eduGAIN: "eduGAIN"
        }
    }

    /// A background-refresh permission in words.
    ///
    /// - Parameter status: What iOS reports.
    /// - Returns: The phrase.
    static func label(for status: UIBackgroundRefreshStatus) -> String {
        switch status {
        case .available: String(localized: "Consentito")
        case .denied: String(localized: "Disattivato")
        case .restricted: String(localized: "Limitato dal sistema")
        @unknown default: String(localized: "Sconosciuto")
        }
    }

    /// A notification permission in words.
    ///
    /// - Parameter status: What iOS reports.
    /// - Returns: The phrase.
    static func label(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: String(localized: "Consentite")
        case .provisional: String(localized: "Consentite in silenzio")
        case .ephemeral: String(localized: "Temporanee")
        case .denied: String(localized: "Disattivate")
        case .notDetermined: String(localized: "Mai chieste")
        @unknown default: String(localized: "Sconosciute")
        }
    }

    /// The hardware identifier, for example `iPhone17,1` rather than “iPhone”: the marketing
    /// name hides exactly the hardware difference a crash can depend on.
    ///
    /// In the simulator the host's architecture is reported instead, so the identifier of
    /// the device being imitated is read from the environment.
    static var modelIdentifier: String {
        // The simulator reports its host's architecture; it says which device
        // it is imitating in the environment instead.
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// The app's version, as the diagnostics report prints it.
extension Bundle {
    /// `CFBundleShortVersionString` with the build number in brackets. See
    /// ``releaseVersion`` for the short version alone.
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
