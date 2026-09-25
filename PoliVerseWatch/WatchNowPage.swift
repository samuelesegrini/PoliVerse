import SwiftUI

/// The first page: the lecture on now, or the next one, as large as the
/// screen allows.
///
/// Redrawn every minute by the timeline rather than by a timer of its own, so
/// the page flips from "tra poco" to "adesso" to the next lecture with the
/// app in the background and the wrist down. The countdowns inside it tick by
/// themselves.
struct WatchNowPage: View {
    /// What the phone last sent.
    let snapshot: WatchSnapshot
    /// Moves to the agenda page. Bound to Double Tap.
    let showAgenda: () -> Void

    /// The link to the phone, for whether a refresh is under way.
    @Environment(WatchBridge.self) private var bridge

    /// The view's content.
    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let entry = snapshot.current(at: now)
            content(entry, now: now)
                .containerBackground(tint(entry).gradient, for: .tabView)
                .navigationTitle(title(entry, now: now))
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                if bridge.isRefreshing {
                    ProgressView()
                        .accessibilityLabel("Aggiornamento dall'iPhone")
                }
                Spacer()
                Button("Giornata", systemImage: "list.bullet", action: showAgenda)
                    // Pinch twice to see the rest of the day, hands full.
                    .handGestureShortcut(.primaryAction)
            }
        }
    }

    /// The page for an entry, or for a day with nothing left.
    ///
    /// - Parameters:
    ///   - entry: The entry on now or next, if any.
    ///   - now: The moment being drawn.
    /// - Returns: The content.
    @ViewBuilder
    private func content(_ entry: WatchSnapshot.Entry?, now: Date) -> some View {
        if let entry {
            NavigationLink(value: entry.id) {
                hero(entry, now: now)
            }
            .buttonStyle(.plain)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text("Niente in programma")
                    .font(.headline)
                Text(snapshot.covers(now)
                     ? "Le lezioni dei prossimi giorni sono finite."
                     : "Apri PoliVerse sull'iPhone per aggiornare l'orario.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The entry, large.
    ///
    /// - Parameters:
    ///   - entry: The entry.
    ///   - now: The moment being drawn.
    /// - Returns: The hero.
    private func hero(_ entry: WatchSnapshot.Entry, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title)
                .font(.title3.weight(.semibold))
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            if let room = entry.room, !room.isEmpty {
                Label(room, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if entry.isOn(at: now) {
                ProgressView(timerInterval: entry.start...entry.end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    Text("Finisce alle \(entry.end.formatted(date: .omitted, time: .shortened))")
                }
                .tint(.white)
            } else {
                startLabel(entry, now: now)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// When an entry not yet under way begins: a live countdown in the last
    /// hour, the time before that.
    ///
    /// - Parameters:
    ///   - entry: The entry.
    ///   - now: The moment being drawn.
    /// - Returns: The label.
    @ViewBuilder
    private func startLabel(_ entry: WatchSnapshot.Entry, now: Date) -> some View {
        if entry.start.timeIntervalSince(now) < 3600 {
            HStack(spacing: 4) {
                Text("Tra")
                Text(timerInterval: now...entry.start, countsDown: true)
                    .monospacedDigit()
            }
            .font(.title3.weight(.bold))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.start.formatted(.dateTime.hour().minute()))
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                if !Calendar.current.isDate(entry.start, inSameDayAs: now) {
                    Text(entry.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The page's title, which says what the hero is.
    ///
    /// - Parameters:
    ///   - entry: The entry on now or next, if any.
    ///   - now: The moment being drawn.
    /// - Returns: The title.
    private func title(_ entry: WatchSnapshot.Entry?, now: Date) -> LocalizedStringKey {
        guard let entry else { return "PoliVerse" }
        if entry.isOn(at: now) { return entry.isExam ? "Esame in corso" : "Adesso" }
        return entry.isExam ? "Prossimo esame" : "Prossima"
    }

    /// The background's colour: red for an exam, the accent otherwise.
    ///
    /// - Parameter entry: The entry on now or next, if any.
    /// - Returns: The colour.
    private func tint(_ entry: WatchSnapshot.Entry?) -> Color {
        entry?.isExam == true ? .red : .accentColor
    }
}

/// One entry, in full.
struct WatchEntryDetail: View {
    /// The entry.
    let entry: WatchSnapshot.Entry

    /// The view's content.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label(entry.isExam ? "Esame" : "Lezione",
                      systemImage: entry.isExam ? "pencil.and.list.clipboard" : "person.bubble")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(entry.isExam ? .red : .accentColor)
                Text(entry.title)
                    .font(.headline)
                Divider()
                Label {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(entry.start.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        Text("\(entry.start.formatted(date: .omitted, time: .shortened))–\(entry.end.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "clock")
                }
                if let room = entry.room, !room.isEmpty {
                    Label(room, systemImage: "mappin.and.ellipse")
                }
                TimelineView(.everyMinute) { context in
                    if entry.isOn(at: context.date) {
                        ProgressView(timerInterval: entry.start...entry.end, countsDown: false)
                            .tint(entry.isExam ? .red : .accentColor)
                    }
                }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(entry.isExam ? "Esame" : "Lezione")
    }
}
