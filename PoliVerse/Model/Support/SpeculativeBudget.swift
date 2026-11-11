import Foundation

/// Whether requests nobody is waiting for may go out now, and how many.
///
/// A speculative request is one sent ahead of the student: a room's bookings an
/// hour before the lecture, the neighbours of the room on screen, a course page
/// about to be needed. Each costs the student data and battery and costs the
/// Politecnico a request, so none is sent in Low Data Mode, on a metered network
/// unless the student allowed it, in Low Power Mode or while the phone is hot, and
/// never more than ``Settings/dailyLimit`` a day.
///
/// Values in, decision out: the device, the settings and today's count are given.
nonisolated struct SpeculativeBudget: Equatable, Sendable {
    /// The state of the phone that decides whether anything may be sent.
    struct Device: Equatable, Sendable {
        /// Low Data Mode is on for the current network.
        var lowData = false
        /// The current network is metered: cellular, or a personal hotspot.
        var metered = false
        /// Low Power Mode is on.
        var lowPower = false
        /// The phone's thermal state.
        var thermal: ProcessInfo.ThermalState = .nominal

        /// The phone as it is now.
        static var current: Device {
            let info = ProcessInfo.processInfo
            let path = NetworkPath.current
            return Device(lowData: path.constrained, metered: path.expensive,
                          lowPower: info.isLowPowerModeEnabled, thermal: info.thermalState)
        }
    }

    /// What the student chose in Impostazioni › Dati e batteria.
    struct Settings: Equatable, Sendable {
        /// Whether the app prepares anything ahead at all.
        var enabled = true
        /// Whether it does so on a metered network too.
        var allowMetered = false
        /// The most speculative requests in a day.
        var dailyLimit = 600

        /// The key of ``enabled`` in the user defaults.
        static let enabledKey = "prefetchEnabled"
        /// The key of ``allowMetered`` in the user defaults.
        static let meteredKey = "prefetchOnCellular"

        /// The settings as stored, with the defaults for what was never set.
        static var stored: Settings {
            let defaults = UserDefaults.standard
            return Settings(enabled: defaults.object(forKey: enabledKey) as? Bool ?? true,
                            allowMetered: defaults.bool(forKey: meteredKey))
        }
    }

    /// Why nothing may be sent, or `nil` when something may.
    enum Refusal: Equatable, Sendable {
        case off, lowData, metered, lowPower, hot, limitReached
    }

    /// Why no speculative request may go out now, or `nil` when one may.
    ///
    /// - Parameters:
    ///   - device: The state of the phone.
    ///   - settings: What the student chose.
    ///   - sentToday: How many were sent today.
    static func refusal(device: Device, settings: Settings, sentToday: Int) -> Refusal? {
        if !settings.enabled { return .off }
        if device.lowData { return .lowData }
        if device.metered && !settings.allowMetered { return .metered }
        if device.lowPower { return .lowPower }
        if device.thermal == .serious || device.thermal == .critical { return .hot }
        if sentToday >= settings.dailyLimit { return .limitReached }
        return nil
    }

    /// How many of some wanted requests may go out now.
    ///
    /// - Parameters:
    ///   - count: How many are wanted.
    ///   - device: The state of the phone.
    ///   - settings: What the student chose.
    ///   - sentToday: How many were sent today.
    /// - Returns: From 0 to `count`: what is left of today's limit, or nothing at all.
    static func allows(_ count: Int, device: Device, settings: Settings, sentToday: Int) -> Int {
        guard refusal(device: device, settings: settings, sentToday: sentToday) == nil else { return 0 }
        return max(0, min(count, settings.dailyLimit - sentToday))
    }
}

/// How many speculative requests went out today, kept across launches.
///
/// The day is the day in Rome, like everything else the app counts.
nonisolated struct SpeculativeCount: Codable, Equatable, Sendable {
    /// The day counted, as `yyyy-MM-dd` in Rome.
    var day: String
    /// How many were sent on it.
    var sent: Int

    /// The key in the user defaults.
    static let key = "speculativeCount"

    /// The count for a moment: the stored one if it is that day's, else zero.
    ///
    /// - Parameters:
    ///   - now: The moment.
    ///   - stored: The count last written.
    static func today(at now: Date, stored: SpeculativeCount?) -> SpeculativeCount {
        let day = PoliMiDate.queryString(now)
        guard let stored, stored.day == day else { return SpeculativeCount(day: day, sent: 0) }
        return stored
    }

    /// The count last written, from the user defaults.
    static var stored: SpeculativeCount? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(SpeculativeCount.self, from: $0) }
    }

    /// Writes the count to the user defaults.
    func store() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// A speculative request that was not sent: the budget refused it.
nonisolated struct SpeculationRefused: LocalizedError, Equatable, Sendable {
    /// Why.
    let reason: SpeculativeBudget.Refusal

    var errorDescription: String? { String(localized: "Preparazione in anticipo non consentita ora.") }
}
