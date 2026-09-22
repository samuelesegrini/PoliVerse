import SwiftUI

/// The day on the wrist: what is on now, what is left of today, and the next
/// exam.
///
/// Three states, and it says which it is in rather than showing an empty list
/// for all three: nothing received yet, a day that is not today, and today.
/// A stale snapshot is shown with its date rather than hidden — the last thing
/// known is more use on a wrist than a blank screen, as long as it does not
/// pretend to be current.
struct WatchTodayView: View {
    /// The link to the phone.
    @Environment(WatchBridge.self) private var bridge
    /// The locale dates are formatted in.
    @Environment(\.locale) private var locale

    /// The view's content.
    var body: some View {
        NavigationStack {
            List {
                switch bridge.snapshot {
                case nil:
                    waiting
                case let snapshot?:
                    if !snapshot.covers(.now) { staleNotice(snapshot) }
                    if snapshot.entries.isEmpty {
                        Text("Niente in programma.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Section("Oggi") {
                            ForEach(snapshot.entries) { row($0, now: .now) }
                        }
                    }
                    if let name = snapshot.nextExamName {
                        Section("Prossimo esame") { nextExam(name, on: snapshot.nextExamDate) }
                    }
                    if let mean = snapshot.mean {
                        Section("Carriera") { career(mean: mean, cfu: snapshot.earnedCFU) }
                    }
                }
            }
            .navigationTitle("PoliVerse")
        }
    }

    /// What is shown before the phone has sent anything.
    ///
    /// Names the cause, because "apri PoliVerse sull'iPhone" is something the
    /// reader can act on and a spinner is not.
    private var waiting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nessun dato ancora.")
                .font(.headline)
            Text("Apri PoliVerse sull'iPhone: l'orario arriva da lì.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    /// The line that says the day on screen is not today.
    ///
    /// - Parameter snapshot: The snapshot being shown.
    /// - Returns: The notice.
    private func staleNotice(_ snapshot: WatchSnapshot) -> some View {
        Label(snapshot.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale)),
              systemImage: "clock.arrow.circlepath")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    /// One lecture or exam.
    ///
    /// - Parameters:
    ///   - entry: The entry.
    ///   - now: The moment to judge "in corso" at.
    /// - Returns: The row.
    private func row(_ entry: WatchSnapshot.Entry, now: Date) -> some View {
        let isOn = entry.start <= now && now < entry.end
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: entry.isExam ? "pencil.and.list.clipboard" : "person.bubble")
                    .font(.caption2)
                    .foregroundStyle(entry.isExam ? .red : .accentColor)
                Text(entry.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
            }
            HStack(spacing: 4) {
                Text(entry.start.formatted(.dateTime.hour().minute().locale(locale)))
                if let room = entry.room, !room.isEmpty {
                    Text("· \(room)").lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if isOn {
                Text("Adesso · fino alle \(entry.end.formatted(.dateTime.hour().minute().locale(locale)))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// The next sitting.
    ///
    /// - Parameters:
    ///   - name: The teaching.
    ///   - date: When it is, when known.
    /// - Returns: The row.
    private func nextExam(_ name: String, on date: Date?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.footnote.weight(.semibold)).lineLimit(2)
            if let date {
                Text(date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The average and the credits.
    ///
    /// - Parameters:
    ///   - mean: The weighted average out of 30.
    ///   - cfu: Credits earned.
    /// - Returns: The row.
    private func career(mean: Double, cfu: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Media").font(.caption2).foregroundStyle(.secondary)
                Text(mean, format: .number.precision(.fractionLength(2)))
                    .font(.footnote.weight(.semibold))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("CFU").font(.caption2).foregroundStyle(.secondary)
                Text("\(cfu)").font(.footnote.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Oggi") {
    WatchTodayView()
        .environment(WatchBridge.shared)
}
