import SwiftUI

/// The next few days, one section per day, with what is under way marked.
///
/// A stale snapshot is shown rather than hidden, with when it was sent — the
/// last thing known is more use on a wrist than a blank screen, as long as it
/// does not pretend to be current.
struct WatchAgendaPage: View {
    /// What the phone last sent.
    let snapshot: WatchSnapshot

    /// The link to the phone, for whether a refresh is under way.
    @Environment(WatchBridge.self) private var bridge

    /// The view's content.
    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let days = snapshot.days(from: now)
            List {
                if days.isEmpty {
                    Text("Niente in programma nei prossimi giorni.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(days, id: \.day) { day in
                    Section(header(day.day, now: now)) {
                        ForEach(day.entries) { entry in
                            NavigationLink(value: entry.id) {
                                row(entry, now: now)
                            }
                            // A wash rather than a fill: white text on a
                            // solid accent row fell well under 4.5:1.
                            .listRowBackground(entry.isOn(at: now)
                                ? RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill((entry.isExam ? Color.red : .accentColor).opacity(0.3))
                                : nil)
                        }
                    }
                }
                Section {
                    EmptyView()
                } footer: {
                    if bridge.isRefreshing {
                        Text("Aggiornamento dall'iPhone…")
                    } else {
                        Text("Dall'iPhone \(snapshot.sentAt.formatted(.relative(presentation: .named)))")
                    }
                }
            }
        }
        .navigationTitle("Giornata")
    }

    /// The section title for a day.
    ///
    /// - Parameters:
    ///   - day: The start of the day.
    ///   - now: The moment being drawn.
    /// - Returns: "Oggi", "Domani", or the weekday and date.
    private func header(_ day: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: now) { return String(localized: "Oggi") }
        if calendar.isDateInTomorrow(day) { return String(localized: "Domani") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    /// One lecture or exam.
    ///
    /// - Parameters:
    ///   - entry: The entry.
    ///   - now: The moment to judge "in corso" at.
    /// - Returns: The row.
    private func row(_ entry: WatchSnapshot.Entry, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: entry.isExam ? "pencil.and.list.clipboard" : "person.bubble")
                    .font(.caption2)
                    .foregroundStyle(entry.isExam ? .red : .accentColor)
                Text(entry.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
            }
            HStack(spacing: 4) {
                Text(entry.start.formatted(date: .omitted, time: .shortened))
                if let room = entry.room, !room.isEmpty {
                    Text("· \(room)").lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if entry.isOn(at: now) {
                Text("Adesso · fino alle \(entry.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(entry.isExam ? .red : .accentColor)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
