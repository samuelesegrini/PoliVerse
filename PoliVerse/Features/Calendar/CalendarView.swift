import SwiftUI

/// Lectures, exams and deadlines, one day at a time with a scrubbable week strip.
struct CalendarView: View {
    /// The shared ``AgendaModel``, from the environment.
    @Environment(AgendaModel.self) private var agenda
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale

    /// The day being shown, in Rome. Moving past the loaded window fetches more.
    @State private var selectedDay: Date = PoliMiDate.romeCalendar.startOfDay(for: .now)
    /// Which week the strip is showing; moves independently of the selected day
    /// so paging back does not change the selection until the user taps.
    @State private var weekStart: Date = CalendarView.startOfWeek(for: .now)
    @State private var selectedEvent: AgendaEvent?
    @State private var filter: Filter = .all

    /// Which entries to show. The agenda mixes lectures, exams, deadlines and
    /// notices, and "what am I doing today" and "what is due" are different
    /// questions.
    enum Filter: String, CaseIterable, Identifiable {
        /// Everything on the agenda.
        case all = "Tutto"
        /// Lectures only.
        case lectures = "Lezioni"
        /// Deadlines and exam sittings.
        case deadlines = "Scadenze"
        /// The raw value, which is also the filter's name on screen.
        var id: String { rawValue }

        /// Whether an entry belongs in this filter.
        ///
        /// - Parameter event: The agenda entry.
        /// - Returns: `true` when it should be shown.
        func matches(_ event: AgendaEvent) -> Bool {
            switch self {
            case .all: true
            case .lectures: event.kind == .lecture
            case .deadlines: event.kind == .deadline || event.kind == .exam
            }
        }
    }

    /// Rome, so a day means the same day it means on the timetable.
    private var calendar: Calendar { PoliMiDate.romeCalendar }

    /// The selected day's entries, after the filter.
    private var dayEvents: [AgendaEvent] {
        agenda.events(on: selectedDay).filter(filter.matches)
    }

    /// Shown inside a navigation stack that is not its own.
    private let embedded: Bool

    /// Creates the screen.
    ///
    /// - Parameter embedded: `true` when it is already inside a navigation stack.
    init(embedded: Bool = false) {
        self.embedded = embedded
    }

    /// The view's content.
    var body: some View {
        RootStack(embedded: embedded) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    weekStrip
                    filters
                    VStack(alignment: .leading, spacing: 10) {
                        LookHeading(verbatim: selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)).capitalized)
                        dayList
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
                .animation(.snappy(duration: 0.25), value: selectedDay)
                .animation(.snappy(duration: 0.25), value: filter)
            }
            .safeAreaInset(edge: .top, spacing: 0) { FreshnessBar(age: agenda.age) }
            .navigationTitle("Calendario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Oggi") {
                        withAnimation {
                            selectedDay = calendar.startOfDay(for: .now)
                            weekStart = Self.startOfWeek(for: .now)
                        }
                    }
                    .disabled(calendar.isDateInToday(selectedDay))
                }
            }
            .task { await agenda.load(around: .now) }
            .refreshable { await agenda.load(around: weekStart, force: true) }
            // Stepping outside the fetched span pulls the next one in, so the
            // calendar is not silently empty a month out.
            .task(id: weekStart) { await agenda.ensureLoaded(covering: weekStart) }
            .sheet(item: $selectedEvent) { EventDetailView(event: $0) }
        }
    }

    // MARK: - Week strip

    /// The week on one glass card: the month with arrows either side, and the
    /// seven days under it, the chosen one filled in the app's tint.
    private var weekStrip: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    withAnimation { shiftWeek(by: -1) }
                } label: {
                    Image(systemName: "chevron.left").frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Settimana precedente")

                Spacer()

                Text(monthTitle)
                    .font(.headline)
                    .contentTransition(.numericText())

                Spacer()

                Button {
                    withAnimation { shiftWeek(by: 1) }
                } label: {
                    Image(systemName: "chevron.right").frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Settimana successiva")
            }

            HStack(spacing: 4) {
                ForEach(weekDays, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .padding(14)
        .lookCard(cornerRadius: 28)
    }

    /// One day of the week strip: its weekday, its number, and a dot when something is on.
    ///
    /// - Parameter day: The day to draw.
    /// - Returns: The cell.
    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let hasEvents = !agenda.events(on: day).filter(filter.matches).isEmpty

        return Button {
            withAnimation(.snappy(duration: 0.2)) { selectedDay = day }
        } label: {
            VStack(spacing: 4) {
                Text(weekdaySymbol(day))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.onAccent.opacity(0.85)) : AnyShapeStyle(.secondary))
                Text(dayNumber(day))
                    .font(.title3.weight(isSelected || isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(Theme.onAccent) : (isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)))
                Circle()
                    .fill(isSelected ? AnyShapeStyle(Theme.onAccent) : AnyShapeStyle(.tint))
                    .frame(width: 5, height: 5)
                    .opacity(hasEvents ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule().fill(.tint)
                } else if isToday {
                    Capsule().strokeBorder(.tint.opacity(0.5), lineWidth: 1.5)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// What to show, as glass chips, as Cerca narrows its results.
    private var filters: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { item in
                    let on = filter == item
                    Button { withAnimation(.snappy) { filter = item } } label: {
                        Text(item.rawValue)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(on ? .regular.tint(Color.accentColor.opacity(0.18)).interactive() : .regular.interactive(),
                                 in: .capsule)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Day list

    /// The selected day's entries in time order, or a line saying there is nothing on.
    @ViewBuilder
    private var dayList: some View {
        if agenda.isLoading && agenda.events.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
        } else {
            if let message = agenda.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
            }
            if dayEvents.isEmpty {
                ContentUnavailableView {
                    Label(filter == .lectures ? "Nessuna lezione" : "Niente in programma", systemImage: "calendar")
                } description: {
                    Text("Un giorno libero.")
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .lookCard()
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(dayEvents) { event in
                        Button { selectedEvent = event } label: { EventRow(event: event,
                            marksOfficial: TimetableMerge.marksOfficial(event, timetable: agenda.personalTimetable)) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Date helpers

    /// The seven days of the week the selected day falls in, Monday first.
    private var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// The month and year of the week on screen.
    private var monthTitle: String {
        guard let last = weekDays.last else { return "" }
        // A week can straddle two months; say so rather than picking one.
        if calendar.isDate(weekStart, equalTo: last, toGranularity: .month) {
            return weekStart.formatted(.dateTime.month(.wide).year().locale(locale)).capitalized
        }
        let first = weekStart.formatted(.dateTime.month(.abbreviated).locale(locale))
        let second = last.formatted(.dateTime.month(.abbreviated).year().locale(locale))
        return "\(first) – \(second)".capitalized
    }

    /// A day's weekday, abbreviated.
    ///
    /// - Parameter day: The day.
    /// - Returns: The abbreviation, in the reader's language.
    private func weekdaySymbol(_ day: Date) -> String {
        day.formatted(.dateTime.weekday(.abbreviated).locale(locale)).uppercased()
    }

    /// A day's number in its month.
    ///
    /// - Parameter day: The day.
    /// - Returns: The number.
    private func dayNumber(_ day: Date) -> String {
        day.formatted(.dateTime.day().locale(locale))
    }

    /// Moves the strip by whole weeks, keeping the weekday, and fetches more of the agenda
    /// when the new week falls outside what is loaded.
    ///
    /// - Parameter weeks: How many weeks to move, negative to go back.
    private func shiftWeek(by weeks: Int) {
        guard let shifted = calendar.date(byAdding: .weekOfYear, value: weeks, to: weekStart) else { return }
        weekStart = shifted
        // Keep the selection on the same weekday in the new week.
        if let offset = calendar.dateComponents([.day], from: Self.startOfWeek(for: selectedDay), to: selectedDay).day,
           let newSelection = calendar.date(byAdding: .day, value: offset, to: shifted) {
            selectedDay = newSelection
        }
    }

    /// The Monday of the week a date falls in, in Rome.
    ///
    /// - Parameter date: Any day of the week.
    /// - Returns: That week's Monday.
    private static func startOfWeek(for date: Date) -> Date {
        let calendar = PoliMiDate.romeCalendar
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }
}

// MARK: - Row

/// One entry of the day: its time, its name, and where it is.
private struct EventRow: View {
    /// The entry this row shows.
    let event: AgendaEvent
    /// Whether to mark the entry as coming from the Politecnico, which matters only while a
    /// personal timetable shares the agenda. See ``TimetableMerge/marksOfficial(_:timetable:)``.
    var marksOfficial = false
    /// The locale dates and numbers are formatted in.
    @Environment(\.locale) private var locale

    /// The colour for this entry's kind.
    private var accent: Color {
        switch event.kind {
        case .lecture: Theme.brand
        case .exam: .red
        case .deadline: .orange
        case .news: .blue
        case .custom: .purple
        }
    }

    /// The view's content.
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(event.start.formatted(.dateTime.hour().minute().locale(locale)))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text(event.end.formatted(.dateTime.hour().minute().locale(locale)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 46, alignment: .trailing)

            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(event.title)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Label(event.kind.label, systemImage: event.kind.icon)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accent.opacity(0.15), in: .capsule)
                        .foregroundStyle(accent)

                    if let room = event.roomLabel {
                        Label(room, systemImage: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // From the personal timetable, not the Politecnico's agenda.
                if event.tags.contains(TimetableMerge.tag) {
                    Label("Orario personalizzato", systemImage: "calendar.badge.plus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if marksOfficial {
                    Label("Ufficiale", systemImage: "checkmark.seal")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }

                // The door code under a named hall — someone who has never been
                // to De Donato still needs the building. Nothing under a row
                // that already is the code.
                if let code = event.roomCode {
                    Text(code)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookCard(cornerRadius: 22)
        .overlay {
            // Ongoing events get a ring so "where am I supposed to be" is
            // answerable at a glance.
            if event.isOngoing() {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(accent, lineWidth: 2)
            }
        }
    }
}

// MARK: - Previews

#Preview("Calendario") {
    CalendarView().previewEnvironment()
}

#Preview("Componente · Riga evento") {
    List {
        ForEach(AgendaEvent.samples(around: .now).prefix(4)) { EventRow(event: $0) }
    }
    .previewEnvironment()
}
