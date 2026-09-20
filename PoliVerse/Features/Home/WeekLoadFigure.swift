import SwiftUI

/// Corsi's figure: the teaching week, a column per day.
///
/// Corsi is the page a student opens to answer "which course am I going to",
/// and the answer has a shape — four hours on Monday, nothing on Friday. That
/// shape is already on the page, scattered through a list of rows as "prossima
/// lezione" times; drawn as seven columns it is one glance.
///
/// Each column is that day's lessons stacked, each lesson in its own course's
/// colour — the same colours the rows below use, so a student reads the figure
/// and the list with the same key. Today's letter is the one in the look's
/// colour, which is what makes the figure about *now* rather than about weeks
/// in general.
struct WeekLoadFigure: View {
    let events: [AgendaEvent]
    let courses: [Course]
    var now: Date = .now

    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Environment(\.colorScheme) private var scheme
    @Environment(\.locale) private var locale

    private var week: [DayLoad] { DayLoad.week(of: now, events: events, courses: courses) }

    var body: some View {
        let week = week
        let peak = week.map(\.hours).max() ?? 0
        // Nothing to draw is not a reason to draw nothing carefully: a week
        // with no lessons in it — the holidays, a plan not yet published —
        // gets no band at all rather than seven empty stubs.
        if peak > 0 {
            HeaderFigure(summary: summary(week)) {
                HStack(alignment: .bottom, spacing: FigureMetrics.gap) {
                    ForEach(week) { day in
                        column(day, peak: peak)
                            .frame(maxWidth: .infinity)
                    }
                }
            } caption: {
                HStack(spacing: FigureMetrics.gap) {
                    ForEach(week) { day in
                        Text(day.letter(locale: locale))
                            .fontWeight(day.isToday ? .bold : .regular)
                            .foregroundStyle(day.isToday ? style.palette(scheme).accent : Color.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// One day: its lessons stacked from the baseline up, tallest day full
    /// height. A day with no lessons keeps its place as a stub, so the week
    /// stays seven days wide and Friday is visibly empty rather than missing.
    private func column(_ day: DayLoad, peak: Double) -> some View {
        VStack(spacing: 2) {
            if day.segments.isEmpty {
                FigureMetrics.markShape
                    .fill(.quaternary)
                    .frame(height: FigureMetrics.minimumMark)
            } else {
                ForEach(day.segments) { segment in
                    FigureMetrics.markShape
                        .fill(segment.colour(fallback: style.palette(scheme).accent))
                        .frame(height: max(FigureMetrics.minimumMark,
                                           FigureMetrics.height * segment.hours / peak))
                }
            }
        }
        .frame(maxWidth: 22)
    }

    private func summary(_ week: [DayLoad]) -> Text {
        let hours = week.reduce(0) { $0 + $1.hours }
        let days = week.count { $0.hours > 0 }
        return Text("\(hours.formatted(.number.precision(.fractionLength(0)))) ore di lezione questa settimana, su \(days) giorni")
    }
}

/// A day of the teaching week, and the lessons in it.
private struct DayLoad: Identifiable {
    let id: Int
    let date: Date
    let isToday: Bool
    let segments: [Segment]

    var hours: Double { segments.reduce(0) { $0 + $1.hours } }

    func letter(locale: Locale) -> String {
        let initial = date.formatted(.dateTime.weekday(.narrow).locale(locale))
        return initial.uppercased()
    }

    /// One lesson: how long it runs, and which course it belongs to.
    struct Segment: Identifiable {
        let id: Int
        let hours: Double
        let course: Course?

        func colour(fallback: Color) -> Color {
            course.map(Theme.accent(for:)) ?? fallback
        }
    }

    /// The seven days of the week containing `date`, each with its lectures.
    ///
    /// Lectures only. An exam or a deadline in the same agenda is not teaching
    /// time, and a figure that mixed them would answer a question nobody asked.
    static func week(of date: Date, events: [AgendaEvent], courses: [Course],
                     calendar: Calendar = PoliMiDate.romeCalendar) -> [DayLoad] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        let today = calendar.startOfDay(for: date)
        let lectures = events.filter { $0.kind == .lecture }

        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let segments = lectures
                .filter { calendar.isDate($0.start, inSameDayAs: day) }
                .sorted { $0.start < $1.start }
                .map { event in
                    Segment(id: event.id,
                            hours: max(event.end.timeIntervalSince(event.start) / 3600, 0.25),
                            course: courses.first { $0.matches(event) })
                }
            return DayLoad(id: offset, date: day,
                           isToday: calendar.isDate(day, inSameDayAs: today),
                           segments: segments)
        }
    }
}

// MARK: - Previews

#Preview("Settimana") {
    VStack(alignment: .leading, spacing: 24) {
        LookHeader("Corsi", subtitle: Text("6 corsi · 2025/26")) {
            WeekLoadFigure(events: AgendaEvent.samples(around: .now), courses: Course.samples)
        }
        Spacer()
    }
    .padding(20)
    .previewEnvironment()
}
