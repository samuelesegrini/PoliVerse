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
    /// Seconds since the data on screen was fetched, or `nil` when it never was.
    let age: TimeInterval?
    /// The shared ``NetworkMonitor``, from the environment.
    @Environment(NetworkMonitor.self) private var network

    /// The age and the connection together, which decide what the bar says.
    private var freshness: Freshness {
        Freshness(age: age, isOnline: network.isOnline)
    }

    /// The view's content.
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

/// Says that changes are waiting, and what was lost when one could not be
/// sent.
///
/// The queue is invisible when it is working — which is most of the time —
/// and that is deliberate: a badge counting background sync is the app talking
/// about itself. It speaks up for the one case the user has to know about, a
/// change the Politecnico refused three times, because a star that quietly
/// un-stars itself several launches later is worse than being told.
struct PendingChangesBar: View {
    /// The shared ``PendingChanges``, from the environment.
    @Environment(PendingChanges.self) private var pending

    /// The view's content.
    var body: some View {
        if !pending.failed.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(pending.failed.count) modifiche non inviate",
                      systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                ForEach(pending.failed.indices, id: \.self) { index in
                    Text(pending.failed[index].label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Ho capito") { pending.acknowledgeFailures() }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 14))
        } else if pending.count > 0 {
            Label(
                pending.count == 1
                    ? "1 modifica in attesa di connessione"
                    : "\(pending.count) modifiche in attesa di connessione",
                systemImage: "arrow.up.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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

#Preview("Modifiche in attesa") {
    PendingChangesBar().padding().previewEnvironment()
}
