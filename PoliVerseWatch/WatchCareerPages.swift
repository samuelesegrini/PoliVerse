import SwiftUI

/// The sittings ahead, with how many days are left before each.
struct WatchExamsPage: View {
    /// The sittings, soonest first.
    let exams: [WatchSnapshot.Exam]

    /// The view's content.
    var body: some View {
        List(exams) { exam in
            VStack(alignment: .leading, spacing: 3) {
                Text(exam.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                Text(exam.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(countdown(to: exam.date))
                        .font(.caption2.weight(.bold))
                    if exam.isEnrolled {
                        Label("Iscritto", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
        .containerBackground(Color.red.gradient, for: .tabView)
        .navigationTitle("Esami")
    }

    /// How far away a sitting is, in whole days.
    ///
    /// - Parameter date: When it is.
    /// - Returns: "Oggi", "Domani", or "Tra N giorni".
    private func countdown(to date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1: return String(localized: "Oggi")
        case 1: return String(localized: "Domani")
        default: return String(localized: "Tra \(days) giorni")
        }
    }
}

/// The average and the credits, as gauges.
struct WatchCareerPage: View {
    /// What the phone last sent.
    let snapshot: WatchSnapshot

    /// The view's content.
    var body: some View {
        VStack(spacing: 10) {
            if let mean = snapshot.mean {
                Gauge(value: mean, in: 18...30) {
                    Text("Media")
                } currentValueLabel: {
                    Text(mean, format: .number.precision(.fractionLength(1)))
                } minimumValueLabel: {
                    Text("18")
                } maximumValueLabel: {
                    Text("30")
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Gradient(colors: [.orange, .yellow, .green]))
                .scaleEffect(1.4)
                .frame(height: 76)
                .accessibilityLabel("Media")
                .accessibilityValue(Text(mean, format: .number.precision(.fractionLength(2))))

                Text("Base di laurea \((mean * 110 / 30).formatted(.number.precision(.fractionLength(1))))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if snapshot.plannedCFU > 0 {
                Gauge(value: Double(min(snapshot.earnedCFU, snapshot.plannedCFU)),
                      in: 0...Double(snapshot.plannedCFU)) {
                    Text("Crediti")
                } currentValueLabel: {
                    Text("\(snapshot.earnedCFU) di \(snapshot.plannedCFU) CFU")
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(.accentColor)
            } else {
                Text("\(snapshot.earnedCFU) CFU")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(Color.green.gradient.opacity(0.5), for: .tabView)
        .navigationTitle("Carriera")
    }
}
