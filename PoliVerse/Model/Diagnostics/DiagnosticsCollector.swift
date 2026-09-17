import Foundation
import UIKit
import UserNotifications

/// Reads the live services and the system into a ``DiagnosticsSnapshot``.
///
/// The only place that knows where each fact lives. Kept apart from the page
/// so the page draws plain values and the report writes the same values: a
/// diagnostics screen that read one thing and copied another would be worse
/// than none.
@MainActor
struct DiagnosticsCollector {
    let session: Session
    let weBeep: WeBeepModel
    let network: NetworkMonitor
    let pending: PendingChanges
    let notifications: NotificationModel
    let liveActivity: LiveActivityController
    let cieID: CieIDRouter
    let loginMemory: LoginMethodMemory
    var log: DiagnosticsLog = .shared

    /// Services in the order the page lists them.
    static let services: [ServiceDirectory.Service] = [.app, .iae, .agenda, .libretto, .wsAule, .weBeep]

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
    func probe() async -> [DiagnosticsSnapshot.Probe] {
        let urls = Self.services.map { session.directory.baseURL(for: $0) }
        let results = await ConnectionProbe().probe(urls)
        return zip(Self.services, results).map {
            .init(name: String(localized: $0.title), result: $1)
        }
    }

    // MARK: - Words for system states

    private var sessionState: String {
        switch session.state {
        case .loading: String(localized: "In caricamento")
        case .signedOut: String(localized: "Non collegato")
        case .exchangingCode: String(localized: "Accesso in corso")
        case .signedIn: session.useMockData ? String(localized: "Dati di esempio") : String(localized: "Collegato")
        case .failed(let message): String(localized: "Non riuscito: \(message)")
        }
    }

    static func label(for method: PoliMiLoginMethod) -> String {
        switch method {
        case .password: String(localized: "Codice persona e password")
        case .spid(let provider): "SPID · \(provider.name)"
        case .cie: "CIE"
        case .eidas: "eIDAS"
        case .eduGAIN: "eduGAIN"
        }
    }

    static func label(for status: UIBackgroundRefreshStatus) -> String {
        switch status {
        case .available: String(localized: "Consentito")
        case .denied: String(localized: "Disattivato")
        case .restricted: String(localized: "Limitato dal sistema")
        @unknown default: String(localized: "Sconosciuto")
        }
    }

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

    /// `iPhone17,1` rather than "iPhone": the marketing name hides exactly the
    /// hardware difference a crash can depend on.
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

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
