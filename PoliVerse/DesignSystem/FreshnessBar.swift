import SwiftUI

/// Says what the screen is showing, when that is not simply "now".
///
/// Silent when online with recent data — a permanent status line is noise
/// people stop reading, which defeats the one moment it matters. It appears
/// when offline, or when what is on screen is old enough that acting on it
/// could mislead: a student looking at a timetable cannot otherwise tell
/// yesterday's from today's, and the difference is turning up to a lecture
/// that moved.
struct FreshnessBar: View {
    let age: TimeInterval?
    @Environment(NetworkMonitor.self) private var network

    private var freshness: Freshness {
        Freshness(age: age, isOnline: network.isOnline)
    }

    var body: some View {
        if let label = freshness.label {
            Label(label, systemImage: network.isOnline ? "clock.arrow.circlepath" : "wifi.slash")
                .font(.caption2)
                .foregroundStyle(network.isOnline ? Color.secondary : .orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(network.isOnline
                            ? AnyShapeStyle(.clear)
                            : AnyShapeStyle(Color.orange.opacity(0.12)))
                .accessibilityLabel(network.isOnline
                                    ? label
                                    : "Senza connessione. \(label)")
        }
    }
}

// MARK: - Previews

#Preview("Online, dati recenti") {
    FreshnessBar(age: 30).previewEnvironment()
}

#Preview("Online, dati vecchi") {
    FreshnessBar(age: 3600 * 30).previewEnvironment()
}

#Preview("Mai scaricati") {
    FreshnessBar(age: nil).previewEnvironment()
}
