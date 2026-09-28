import SwiftUI

/// A linear day stepper, shown in a popover from the date in Oggi's
/// navigation bar: the highlight stays fixed in the middle, the days scroll under it,
/// and whichever day stops in the middle is the one shown.
///
/// Two months either side of today are enough for a timetable.
struct DayStrip: View {
    /// The day shown, which the strip writes as it scrolls.
    @Binding var day: Date

    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale
    /// The day under the fixed highlight while scrolling.
    @State private var centred: Date?

    /// The Politecnico's own calendar, in which the days are counted.
    private let calendar = PoliMiDate.romeCalendar
    /// One day's width, which the scroll view snaps to.
    private let cellWidth: CGFloat = 50

    /// Two months either side of today, which is as far as a timetable reaches.
    ///
    /// Worked out once, when the strip opens: the body runs again for every day
    /// that scrolls under the highlight, and 121 calendar sums each time is work
    /// the answer never needed.
    @State private var days = DayStrip.span(around: .now)
    /// The strip's width, which centres the first and last day under the highlight.
    @State private var width: CGFloat = 0

    /// Two months either side of a day.
    ///
    /// - Parameter now: The day in the middle.
    /// - Returns: The days, in order.
    private static func span(around now: Date) -> [Date] {
        let calendar = PoliMiDate.romeCalendar
        let today = calendar.startOfDay(for: now)
        return (-60...60).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    /// The view's content.
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
                .contentMargins(.horizontal, max(width - cellWidth, 0) / 2, for: .scrollContent)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0), .init(color: .black, location: 0.15),
                        .init(color: .black, location: 0.85), .init(color: .clear, location: 1),
                    ], startPoint: .leading, endPoint: .trailing)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            // The width alone, and only when it changes — not a reader wrapped
            // around the whole scroll view.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        }
        .padding(.vertical, 12)
        .sensoryFeedback(.selection, trigger: centred)
        .onAppear { centred = calendar.startOfDay(for: day) }
        .onChange(of: centred) { _, new in
            if let new, !calendar.isDate(new, inSameDayAs: day) { day = new }
        }
        .animation(.snappy, value: day)
    }

    /// One day: its weekday, its number, and the highlight when it is the one chosen.
    ///
    /// - Parameter date: The day to draw.
    /// - Returns: The cell.
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
