import Foundation

/// Whether the phone is hot or saving power, which is when work nobody is looking at
/// should wait.
///
/// WWDC26's Power and Performance lab: check `ProcessInfo.thermalState` and back off
/// as it rises. What waits here is the optional work — the WeBeep update sweep, the
/// free-rooms pass run only for the widget, warming rooms and weeks ahead of the
/// student — never what they opened. Each is simply skipped: its own freshness rule
/// runs it on a later pass, once the pressure is gone.
nonisolated enum DevicePressure {
    /// `true` in Low Power Mode, or at a serious or critical thermal state.
    static var isHigh: Bool {
        let info = ProcessInfo.processInfo
        if info.isLowPowerModeEnabled { return true }
        switch info.thermalState {
        case .serious, .critical: return true
        case .nominal, .fair: return false
        @unknown default: return false
        }
    }
}
