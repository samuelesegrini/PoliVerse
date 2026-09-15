import SwiftUI

/// A linear day stepper that drops down from the date in Oggi's navigation
/// bar: the highlight stays fixed in the middle, the days scroll under it,
/// and whichever day stops in the middle is the one shown.
///
/// Two months either side of today are enough for a timetable.
struct DayStrip: View {
    @Binding var day: Date

    @Environment(\.locale) private var locale
    /// The day under the fixed highlight while scrolling.
    @State private var centred: Date?

    private let calendar = PoliMiDate.romeCalendar
    private let cellWidth: CGFloat = 50

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
                    Button("Oggi") { withAnimation(.snappy) { centred = calendar.startOfDay(for: .now) } }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 18)

            GeometryReader { proxy in
                ZStack {
                    // The fixed highlight; the days pass underneath it.
                    Capsule()
                        .fill(.tint)
                        .frame(width: cellWidth - 6, height: 62)

                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            ForEach(days, id: \.self) { date in
                                cell(date)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $centred, anchor: .center)
                    // Room for the first and last day to reach the middle.
                    .contentMargins(.horizontal, (proxy.size.width - cellWidth) / 2, for: .scrollContent)
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0), .init(color: .black, location: 0.15),
                            .init(color: .black, location: 0.85), .init(color: .clear, location: 1),
                        ], startPoint: .leading, endPoint: .trailing)
                    }
                }
            }
            .frame(height: 64)
        }
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .sensoryFeedback(.selection, trigger: centred)
        .onAppear { centred = calendar.startOfDay(for: day) }
        .onChange(of: centred) { _, new in
            if let new, !calendar.isDate(new, inSameDayAs: day) { day = new }
        }
        .animation(.snappy, value: day)
    }

    private func cell(_ date: Date) -> some View {
        let selected = centred.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        let today = calendar.isDateInToday(date)
        let weekend = calendar.isDateInWeekend(date)
        return Button { withAnimation(.snappy) { centred = date } } label: {
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).locale(locale)).prefix(3).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.onAccent.opacity(0.85)) : AnyShapeStyle(weekend ? .tertiary : .secondary))
                Text(date.formatted(.dateTime.day().locale(locale)))
                    .font(.title3.weight(selected || today ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(selected ? AnyShapeStyle(Theme.onAccent) : today ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            }
            .frame(width: cellWidth, height: 64)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview("Striscia giorni") {
    @Previewable @State var day = Date.now
    DayStrip(day: $day)
        .padding()
        .tint(Theme.brand)
}
