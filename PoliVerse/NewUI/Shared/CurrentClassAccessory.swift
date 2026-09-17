import SwiftUI

/// The class happening now, in the tab view's bottom accessory — the bar
/// above the tabs that Music uses for what is playing.
///
/// Expanded above the tab bar it shows the room and a progress bar; when the
/// tab bar collapses on scroll it shrinks inline to the name and time left.
struct CurrentClassAccessory: View {
    let current: CurrentClass

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            HStack(spacing: 12) {
                Image(systemName: current.event.kind == .exam ? "pencil.and.list.clipboard" : "person.bubble")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(current.event.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if placement != .inline {
                        Text(subtitle(now: now))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                if current.isOngoing {
                    Gauge(value: current.progress(at: now)) {
                        EmptyView()
                    } currentValueLabel: {
                        Text(minutesLeft(now: now))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(.accentColor)
                    .scaleEffect(placement == .inline ? 0.55 : 0.7)
                    .frame(width: 34, height: 34)
                } else {
                    Text(current.event.start.formatted(.dateTime.hour().minute().locale(locale)))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .accessibilityElement(children: .combine)
        }
    }

    private func subtitle(now: Date) -> String {
        let room = current.event.room ?? current.event.roomAcronym
        let time = current.isOngoing
            ? String(localized: "Fino alle \(current.event.end.formatted(.dateTime.hour().minute().locale(locale)))")
            : String(localized: "Alle \(current.event.start.formatted(.dateTime.hour().minute().locale(locale)))")
        return [current.isOngoing ? String(localized: "Adesso") : String(localized: "Prossima"), time, room]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func minutesLeft(now: Date) -> String {
        "\(max(Int(current.event.end.timeIntervalSince(now) / 60), 0))′"
    }
}

/// The current class as a button opening the lesson, as its row on Oggi does.
struct CurrentClassButton: View {
    let current: CurrentClass
    @Environment(\.shell) private var shell

    var body: some View {
        Button { shell.present { shell.detail = .event(current.event) } } label: {
            CurrentClassAccessory(current: current)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Shows the accessory only while there is a class.
    func currentClassAccessory(_ current: CurrentClass?) -> some View {
        tabViewBottomAccessory(isEnabled: current != nil) {
            if let current { CurrentClassButton(current: current) }
        }
    }
}
