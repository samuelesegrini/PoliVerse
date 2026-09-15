import SwiftUI

/// The day at a glance, drawn in the student's ``TodayStyle``. Shared by the
/// Oggi tab, the single page and Personalizza, which shows it with its
/// editable zones outlined.
struct TodayLanding: View {
    enum Zone: String, Identifiable, CaseIterable {
        case greeting, date, upcoming, timetable, background
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .greeting: "Saluto"
            case .date: "Data"
            case .upcoming: "In arrivo"
            case .timetable: "Orario"
            case .background: "Sfondo"
            }
        }
    }

    let day: Date
    let style: TodayStyle
    var editing = false
    var onEdit: (Zone) -> Void = { _ in }

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: editing ? 32 : 24) {
            VStack(alignment: .leading, spacing: editing ? 24 : 8) {
                if style.showsGreeting || editing {
                    zone(.greeting) {
                        Text("Buona giornata!")
                            .font(.headline)
                            .opacity(style.showsGreeting ? 1 : 0.35)
                    }
                }
                zone(.date) {
                    VStack(alignment: .leading, spacing: -18) {
                        Text(day.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(locale))
                            .replacingOccurrences(of: "/", with: "."))
                        Text(day.formatted(.dateTime.weekday(.abbreviated).locale(locale)).uppercased())
                    }
                    .font(style.dateFont.font(size: 72, weight: style.weight))
                    .foregroundStyle(style.dateAccent.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.interpolate)
                }
            }

            if style.showsUpcoming || editing {
                zone(.upcoming) { placeholder("In arrivo", "checklist", height: 110, hidden: !style.showsUpcoming) }
            }
            if style.showsTimetable || editing {
                zone(.timetable) { placeholder("Orario", "calendar.day.timeline.left", height: 220, hidden: !style.showsTimetable) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, editing ? 24 : 12)
        .animation(.snappy, value: style)
    }

    /// In Personalizza each zone gets a thin outline, and a tap opens its
    /// editor — the Lock Screen's way of splitting the page into small pieces.
    @ViewBuilder
    private func zone<Content: View>(_ zone: Zone, @ViewBuilder content: () -> Content) -> some View {
        if editing {
            Button { onEdit(zone) } label: {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(-10)
            .accessibilityLabel(Text(zone.title))
            .accessibilityHint("Modifica")
        } else {
            content()
        }
    }

    private func placeholder(_ title: LocalizedStringKey, _ icon: String, height: CGFloat, hidden: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            RoundedRectangle(cornerRadius: 28)
                .fill(.quaternary.opacity(0.5))
                .frame(height: height)
                .overlay { Image(systemName: icon).font(.largeTitle).foregroundStyle(.tertiary) }
        }
        .opacity(hidden ? 0.35 : 1)
    }
}
