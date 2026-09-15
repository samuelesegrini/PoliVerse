import SwiftUI

/// A linear, scrolling row of days that drops down from the date in Oggi's
/// navigation bar.
///
/// Two months either side of today are enough for a timetable; the row opens
/// centred on the day being shown and closes when a day is picked.
struct DayStrip: View {
    @Binding var day: Date
    var onPick: () -> Void = {}

    @Environment(\.locale) private var locale

    private let calendar = PoliMiDate.romeCalendar

    private var days: [Date] {
        let today = calendar.startOfDay(for: .now)
        return (-60...60).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(day.formatted(.dateTime.month(.wide).year().locale(locale)).capitalized)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
                Spacer()
                if !calendar.isDateInToday(day) {
                    Button("Oggi") { pick(.now) }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 18)

            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 6) {
                        ForEach(days, id: \.self) { date in
                            cell(date)
                                .id(calendar.startOfDay(for: date))
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 12)
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .onAppear { reader.scrollTo(calendar.startOfDay(for: day), anchor: .center) }
            }
            .frame(height: 64)
        }
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .animation(.snappy, value: day)
    }

    private func cell(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: day)
        let today = calendar.isDateInToday(date)
        let weekend = calendar.isDateInWeekend(date)
        return Button { pick(date) } label: {
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).locale(locale)).prefix(3).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.onAccent.opacity(0.85)) : AnyShapeStyle(weekend ? .tertiary : .secondary))
                Text(date.formatted(.dateTime.day().locale(locale)))
                    .font(.title3.weight(selected || today ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.onAccent) : today ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
            .frame(width: 44, height: 60)
            .background {
                if selected {
                    Capsule().fill(.tint)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func pick(_ date: Date) {
        day = date
        onPick()
    }
}

#Preview("Striscia giorni") {
    @Previewable @State var day = Date.now
    DayStrip(day: $day)
        .padding()
        .tint(Theme.brand)
}
