import SwiftUI
import WidgetKit

/// Media, CFU and the next exam — the three numbers a student checks without
/// wanting to open anything.
struct CareerEntry: TimelineEntry {
    /// The moment this entry describes.
    let date: Date
    /// The career figures the app last wrote, or `nil` when none have been written.
    let snapshot: CareerSnapshot?
    /// Seconds since they were written.
    let age: TimeInterval?
    /// Whether anyone is signed in.
    let signedIn: Bool

    /// Raised on the day before an exam and the day of it.
    var relevance: TimelineEntryRelevance? {
        guard let exam = snapshot?.nextExamDate, exam > date,
              exam.timeIntervalSince(date) < 36 * 3600 else { return nil }
        return .init(score: 0.6, duration: exam.timeIntervalSince(date))
    }
}

/// Builds the timeline from the career snapshot.
///
/// A career changes when a result is published, which is neither frequent nor
/// predictable, so there is nothing to anticipate: one entry, an occasional refresh, and
/// the app reloads the timeline the moment it learns something new.
struct CareerProvider: TimelineProvider {
    /// Representative figures, for the widget gallery and for redaction.
    ///
    /// - Parameter context: WidgetKit's context.
    /// - Returns: The placeholder entry.
    func placeholder(in context: Context) -> CareerEntry {
        CareerEntry(date: .now, snapshot: .preview, age: 0, signedIn: true)
    }

    /// The career as it stands now.
    ///
    /// - Parameters:
    ///   - context: WidgetKit's context.
    ///   - completion: Handed the entry.
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

    /// One entry, read from the career snapshot.
    ///
    /// - Returns: The entry.
    private func entry() -> CareerEntry {
        let cached = WidgetCareer.load()
        return CareerEntry(date: .now, snapshot: cached?.value, age: cached?.age,
                           signedIn: WidgetAgenda.isSignedIn)
    }
}

/// The one place the widgets read the cached career figures.
enum WidgetCareer {
    /// The cached figures and the age of the cache.
    ///
    /// - Returns: The snapshot, or `nil` when signed out or nothing has been written.
    static func load() -> (value: CareerSnapshot, age: TimeInterval)? {
        guard let matricola = SharedAccount.matricola,
              let slot = OfflineStore(groupIdentifier: OfflineStore.groupIdentifier)
                  .load(CareerSnapshot.self, as: CareerSnapshot.cacheName, account: matricola)
        else { return nil }
        return (slot.value, slot.age)
    }
}

/// The career widget, on the Home Screen and the Lock Screen. Tapping it opens the
/// career.
struct CareerWidget: Widget {
    /// The declaration's content.
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

/// Draws one ``CareerEntry``, in whichever family is asked for.
struct CareerView: View {
    /// The figures to draw.
    let entry: CareerEntry
    /// The widget family being drawn.
    @Environment(\.widgetFamily) private var family

    /// The view's content.
    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    /// The circular Lock Screen accessory: the average in a progress ring.
    private var circular: some View {
        Gauge(value: entry.snapshot?.progress ?? 0) {
            Image(systemName: "graduationcap")
        } currentValueLabel: {
            Text(mean).minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
    }

    /// The rectangular Lock Screen accessory: average, credits and the next sitting.
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

    /// The small Home Screen family: the average, the credits and the next sitting.
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

    /// Credits earned out of credits planned.
    private var creditsLine: String {
        guard let snapshot = entry.snapshot else { return "—" }
        return "\(snapshot.earnedCFU) / \(snapshot.plannedCFU) CFU"
    }
}

/// Representative figures, for the gallery and for previews.
extension CareerSnapshot {
    /// Only for the placeholder the system renders before real data exists.
    static var preview: CareerSnapshot {
        CareerSnapshot(mean: 27.43, earnedCFU: 114, plannedCFU: 180,
                       examsGiven: 18, examsPlanned: 28,
                       nextExamName: "Fisica Sperimentale",
                       nextExamDate: .now.addingTimeInterval(86400 * 9))
    }
}
