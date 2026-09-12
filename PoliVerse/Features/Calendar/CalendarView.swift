import SwiftUI

/// Lectures, exams and deadlines, one day at a time with a scrubbable week strip.
struct CalendarView: View {
    @Environment(AgendaService.self) private var agenda
    @Environment(\.locale) private var locale

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
        case all = "Tutto"
        case lectures = "Lezioni"
        case deadlines = "Scadenze"
        var id: String { rawValue }

        func matches(_ event: AgendaEvent) -> Bool {
            switch self {
            case .all: true
            case .lectures: event.kind == .lecture
            case .deadlines: event.kind == .deadline || event.kind == .exam
            }
        }
    }

    private var calendar: Calendar { PoliMiDate.romeCalendar }

    private var dayEvents: [AgendaEvent] {
        agenda.events(on: selectedDay).filter(filter.matches)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                weekStrip
                Picker("Filtro", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 10)
                .background(Color(.systemBackground))
                Divider()
                dayList
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Calendario")
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

    private var weekStrip: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    withAnimation { shiftWeek(by: -1) }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Settimana precedente")

                Spacer()

                Text(monthTitle)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())

                Spacer()

                Button {
                    withAnimation { shiftWeek(by: 1) }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Settimana successiva")
            }
            .padding(.horizontal)

            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { day in
                    dayCell(day)
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let hasEvents = !agenda.events(on: day).filter(filter.matches).isEmpty

        return Button {
            withAnimation(.snappy(duration: 0.2)) { selectedDay = day }
        } label: {
            VStack(spacing: 4) {
                Text(weekdaySymbol(day))
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Theme.onAccent.opacity(0.85) : .secondary)
                Text(dayNumber(day))
                    .font(.callout.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? Theme.onAccent : (isToday ? Theme.brand : .primary))
                Circle()
                    .fill(isSelected ? Theme.onAccent : Theme.brand)
                    .frame(width: 5, height: 5)
                    .opacity(hasEvents ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.brand)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 12).fill(Theme.brand.opacity(0.12))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Day list

    @ViewBuilder
    private var dayList: some View {
        if agenda.isLoading && agenda.events.isEmpty {
            Spacer()
            ProgressView()
            Spacer()
        } else if dayEvents.isEmpty {
            ContentUnavailableView {
                Label(filter == .lectures ? "Nessuna lezione" : "Niente in programma",
                      systemImage: "calendar")
            } description: {
                Text(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)).capitalized)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    if let message = agenda.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.15), in: .rect(cornerRadius: 14))
                            .foregroundStyle(.orange)
                    }

                    ForEach(dayEvents) { event in
                        Button { selectedEvent = event } label: { EventRow(event: event) }
                            .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Date helpers

    private var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

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

    private func weekdaySymbol(_ day: Date) -> String {
        day.formatted(.dateTime.weekday(.abbreviated).locale(locale)).uppercased()
    }

    private func dayNumber(_ day: Date) -> String {
        day.formatted(.dateTime.day().locale(locale))
    }

    private func shiftWeek(by weeks: Int) {
        guard let shifted = calendar.date(byAdding: .weekOfYear, value: weeks, to: weekStart) else { return }
        weekStart = shifted
        // Keep the selection on the same weekday in the new week.
        if let offset = calendar.dateComponents([.day], from: Self.startOfWeek(for: selectedDay), to: selectedDay).day,
           let newSelection = calendar.date(byAdding: .day, value: offset, to: shifted) {
            selectedDay = newSelection
        }
    }

    private static func startOfWeek(for date: Date) -> Date {
        let calendar = PoliMiDate.romeCalendar
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }
}

// MARK: - Row

private struct EventRow: View {
    let event: AgendaEvent
    @Environment(\.locale) private var locale

    private var accent: Color {
        switch event.kind {
        case .lecture: Theme.brand
        case .exam: .red
        case .deadline: .orange
        case .news: .blue
        case .custom: .purple
        }
    }

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

                    if let room = event.roomAcronym ?? event.room {
                        Label(room, systemImage: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let room = event.room, room != event.roomAcronym {
                    Text(room)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay {
            // Ongoing events get a ring so "where am I supposed to be" is
            // answerable at a glance.
            if event.isOngoing() {
                RoundedRectangle(cornerRadius: 16)
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
        ForEach(MockData.agendaEvents(around: .now).prefix(4)) { EventRow(event: $0) }
    }
    .previewEnvironment()
}
