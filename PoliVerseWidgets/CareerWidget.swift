import SwiftUI
import WidgetKit

/// Media, CFU and the next exam — the three numbers a student checks without
/// wanting to open anything.
struct CareerEntry: TimelineEntry {
    let date: Date
    let snapshot: CareerSnapshot?
    let age: TimeInterval?
    let signedIn: Bool

    /// Raised on the day before an exam and the day of it.
    var relevance: TimelineEntryRelevance? {
        guard let exam = snapshot?.nextExamDate, exam > date,
              exam.timeIntervalSince(date) < 36 * 3600 else { return nil }
        return .init(score: 0.6, duration: exam.timeIntervalSince(date))
    }
}

struct CareerProvider: TimelineProvider {
    func placeholder(in context: Context) -> CareerEntry {
        CareerEntry(date: .now, snapshot: .preview, age: 0, signedIn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (CareerEntry) -> Void) {
        completion(entry())
    }

    /// A career changes when a result is published, which is neither frequent
    /// nor predictable. There is nothing to anticipate, so this asks for an
    /// occasional refresh and relies on the app reloading the timeline the
    /// moment it learns something new.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CareerEntry>) -> Void) {
        completion(Timeline(entries: [entry()],
                            policy: .after(.now.addingTimeInterval(6 * 3600))))
    }

    private func entry() -> CareerEntry {
        let cached = WidgetCareer.load()
        return CareerEntry(date: .now, snapshot: cached?.value, age: cached?.age,
                           signedIn: WidgetAgenda.isSignedIn)
    }
}

enum WidgetCareer {
    static func load() -> (value: CareerSnapshot, age: TimeInterval)? {
        guard let matricola = SharedAccount.matricola,
              let slot = OfflineStore(groupIdentifier: OfflineStore.groupIdentifier)
                  .load(CareerSnapshot.self, as: CareerSnapshot.cacheName, account: matricola)
        else { return nil }
        return (slot.value, slot.age)
    }
}

struct CareerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.career.rawValue, provider: CareerProvider()) { entry in
            CareerView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(AppDestination.career.url)
        }
        .configurationDisplayName("Carriera")
        .description("Media, CFU e prossimo appello.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct CareerView: View {
    let entry: CareerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    private var circular: some View {
        Gauge(value: entry.snapshot?.progress ?? 0) {
            Image(systemName: "graduationcap")
        } currentValueLabel: {
            Text(mean).minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Media \(mean)").font(.headline)
            Text(creditsLine).font(.caption)
            if let name = entry.snapshot?.nextExamName, let date = entry.snapshot?.nextExamDate {
                Text("\(name) · \(date, format: .dateTime.day().month(.abbreviated))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Carriera", systemImage: "graduationcap")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleOnly)

            if let snapshot = entry.snapshot, snapshot.hasResults {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(mean).font(.title.weight(.bold)).monospacedDigit()
                    Text("media").font(.caption2).foregroundStyle(.secondary)
                }
                // The bar carries the same number as the line under it, but it
                // is the part you read without reading — how far along am I.
                ProgressView(value: snapshot.progress)
                    .progressViewStyle(.linear)
                Text(creditsLine).font(.caption2).foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if let name = snapshot.nextExamName, let date = snapshot.nextExamDate {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name).font(.caption2.weight(.medium)).lineLimit(1)
                        Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text(entry.signedIn ? "Nessun dato di carriera" : "Accedi")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// An em dash rather than "0.0": no results yet is not an average of zero.
    private var mean: String {
        guard let snapshot = entry.snapshot, snapshot.hasResults else { return "—" }
        return snapshot.mean.formatted(.number.precision(.fractionLength(2)))
    }

    private var creditsLine: String {
        guard let snapshot = entry.snapshot else { return "—" }
        return "\(snapshot.earnedCFU) / \(snapshot.plannedCFU) CFU"
    }
}

extension CareerSnapshot {
    /// Only for the placeholder the system renders before real data exists.
    static var preview: CareerSnapshot {
        CareerSnapshot(mean: 27.43, earnedCFU: 114, plannedCFU: 180,
                       examsGiven: 18, examsPlanned: 28,
                       nextExamName: "Fisica Sperimentale",
                       nextExamDate: .now.addingTimeInterval(86400 * 9))
    }
}
