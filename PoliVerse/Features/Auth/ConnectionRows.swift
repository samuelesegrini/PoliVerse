import SwiftUI

/// The same connection results and repair actions in onboarding and Settings.
struct ConnectionRows: View {
    enum Appearance { case standard, onboarding }
    var appearance: Appearance = .standard
    private var isOnboarding: Bool { appearance == .onboarding }
    @Environment(SessionLinks.self) private var links
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .title3) private var iconWidth = 30.0
    @State private var repairing: SessionLinks.Connection?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(SessionLinks.Connection.allCases) { connection in
                row(connection)
            }
        }
        .sheet(item: $repairing) { connection in
            switch connection {
            case .weBeep:
                WeBeepLoginSheet { links.retry(.weBeep) }
            case .recordings:
                RecordingsSignInSheet { links.retry(.recordings) }
            case .university:
                NavigationStack { PoliMiSignInButton().padding() }
            }
        }
    }

    private func row(_ connection: SessionLinks.Connection) -> some View {
        let status = links[connection]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                if isOnboarding {
                    JourneyAvatar(mark: .symbol(connection.symbol), colours: connection.avatarColours,
                                  side: textSize.isAccessibilitySize ? 50 : 46)
                } else {
                    Image(systemName: connection.symbol)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: iconWidth)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(connection.title)
                        .font(isOnboarding ? .system(.headline, design: .rounded, weight: .heavy) : .headline)
                        .foregroundStyle(isOnboarding ? JourneyInk.ink : .primary)
                    Text((!network.isOnline && status != .connected) ? SessionLinks.Status.offline.title : status.title)
                        .font(isOnboarding ? .system(.subheadline, design: .rounded, weight: .semibold) : .subheadline)
                        .foregroundStyle(isOnboarding ? (status == .connected ? JourneyInk.inkSoft : JourneyInk.ink) : .secondary)
                        .accessibilityIdentifier("connection-\(connection.rawValue)-status")
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !textSize.isAccessibilitySize { accessory(connection, status: status) }
            }
            if textSize.isAccessibilitySize { accessory(connection, status: status) }
        }
        .padding(.horizontal, isOnboarding ? 14 : 16)
        .padding(.vertical, isOnboarding && !textSize.isAccessibilitySize ? 10 : 16)
        .modifier(ConnectionRowSurface(onboarding: isOnboarding, connected: status == .connected,
                                       accessible: textSize.isAccessibilitySize))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connection-\(connection.rawValue)")
    }

    @ViewBuilder
    private func accessory(_ connection: SessionLinks.Connection, status: SessionLinks.Status) -> some View {
        if status == .connecting {
            if isOnboarding {
                ProgressView(value: links.progress(for: connection))
                    .progressViewStyle(JourneyLinkProgressStyle())
                    .accessibilityLabel("Collegamento in corso…")
                    .accessibilityIdentifier("connection-\(connection.rawValue)-progress")
            } else {
                ProgressView()
                    .frame(width: 30, height: 30)
                    .accessibilityLabel("Collegamento in corso…")
            }
        } else if status == .connected {
            if isOnboarding {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(JourneyInk.action))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
        } else {
            Group {
                if isOnboarding {
                    repairButton(connection, status: status)
                        .buttonStyle(JourneyPress())
                        .foregroundStyle(JourneyInk.ink)
                } else {
                    repairButton(connection, status: status)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .frame(minHeight: 44)
            .disabled(!network.isOnline)
            .accessibilityLabel("\(status == .needsSignIn ? String(localized: "Risolvi") : String(localized: "Riprova")) · \(String(localized: connection.title))")
            .accessibilityIdentifier("connection-\(connection.rawValue)-resolve")
        }
    }

    private func repairButton(_ connection: SessionLinks.Connection, status: SessionLinks.Status) -> some View {
        Button {
            if status == .needsSignIn { repairing = connection }
            else { links.retry(connection) }
        } label: {
            Text(status == .needsSignIn ? "Risolvi" : "Riprova")
                .font(isOnboarding ? .system(.subheadline, design: .rounded, weight: .heavy) : nil)
                .frame(minWidth: isOnboarding ? 44 : nil, minHeight: isOnboarding ? 44 : nil)
                .contentShape(.rect)
        }
    }

}

/// The journey uses cream for established connections and a dashed offer for
/// connections still to complete, exactly like its other choices.
private struct ConnectionRowSurface: ViewModifier {
    let onboarding: Bool
    let connected: Bool
    let accessible: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if !onboarding {
            content.background(.background, in: .rect(cornerRadius: 20))
        } else if accessible {
            content.background {
                if connected {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(JourneyInk.cream)
                } else {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.6, dash: [8, 7]))
                        .journeyVibrant()
                }
            }
        } else if connected {
            content.journeyCream()
        } else {
            content.journeyDashed()
        }
    }
}

private extension SessionLinks.Connection {
    var avatarColours: (light: Color, dark: Color) {
        switch self {
        case .university: JourneyFlow.Intent.timetable.colours
        case .weBeep: JourneyFlow.Intent.exams.colours
        case .recordings: JourneyFlow.Intent.recordings.colours
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .university: "Servizi Online"
        case .weBeep: "WeBeep"
        case .recordings: "Archivio registrazioni"
        }
    }

    var symbol: String {
        switch self {
        case .university: "building.columns"
        case .weBeep: "books.vertical"
        case .recordings: "play.rectangle"
        }
    }
}

private extension SessionLinks.Status {
    var title: LocalizedStringResource {
        switch self {
        case .idle: "Da verificare"
        case .connecting: "Collegamento in corso…"
        case .connected: "Collegato"
        case .needsSignIn: "Completa l'accesso"
        case .unavailable: "Non disponibile al momento"
        case .offline: "In attesa della connessione"
        }
    }
}
