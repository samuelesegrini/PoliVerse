import SwiftUI

/// Everything the app has noticed about the student's exams, newest first.
///
/// The feed replaces the habit of opening each sitting to see whether anything
/// moved. It says only what official data said, and where it said it.
struct ExamUpdatesView: View {
    @Environment(CareerService.self) private var career
    @Environment(\.locale) private var locale
    @State private var selectedExam: ExamSession?

    private var days: [(Date, [ExamUpdate])] {
        let calendar = PoliMiDate.romeCalendar
        return Dictionary(grouping: career.updates) { calendar.startOfDay(for: $0.detectedAt) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value.sorted { $0.detectedAt > $1.detectedAt }) }
    }

    var body: some View {
        ScrollView {
            if career.updates.isEmpty {
                ContentUnavailableView(
                    "Nessuna novità",
                    systemImage: "bell.badge",
                    description: Text("Quando cambia qualcosa nei tuoi appelli — un'aula, un esito, un appello spostato — lo trovi qui."))
                    .padding(.top, 40)
            } else {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(days, id: \.0) { day, updates in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)).capitalized)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(updates) { update in
                                let sitting = career.sitting(for: update)
                                Button { selectedExam = sitting } label: {
                                    ExamUpdateRow(update: update)
                                }
                                .buttonStyle(.plain)
                                .disabled(sitting == nil)
                            }
                        }
                    }
                }
                .padding()
            }

            // Honest about what this can and cannot see.
            Text("Le novità arrivano dai Servizi Online quando l'app si aggiorna: aprendola, o in background quando iOS lo consente. Email e avvisi su WeBeep non sono inclusi.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Novità esami")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await career.load(force: true) }
        .sheet(item: $selectedExam) { ExamDetailView(exam: $0) }
    }
}

/// One update: what changed, for which course, and when it was seen.
struct ExamUpdateRow: View {
    let update: ExamUpdate
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: update.kind.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(update.kind.tint)
                .frame(width: 28, height: 28)
                .background(update.kind.tint.opacity(0.15), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(update.title)
                    .font(.subheadline.weight(.semibold))
                Text([update.courseName, update.detail].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // §17: every value says where it came from and how sure it is.
                Text([update.sourceLabel, update.confidenceNote].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Text(update.detectedAt.formatted(.relative(presentation: .named).locale(locale)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .accessibilityElement(children: .combine)
    }
}

/// A sitting's timeline, for the detail sheet.
struct ExamTimelineSection: View {
    let exam: ExamSession
    @Environment(CareerService.self) private var career
    @Environment(\.locale) private var locale

    private var entries: [ExamTimelineEntry] {
        ExamTimeline.entries(for: exam, sittings: career.sessions, updates: career.updates, now: .now)
    }

    var body: some View {
        let entries = entries
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cronologia")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        line(entry, isLast: index == entries.count - 1)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()
            }
        }
    }

    private func line(_ entry: ExamTimelineEntry, isLast: Bool) -> some View {
        let tint = entry.update?.kind.tint ?? .secondary
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .strokeBorder(tint, lineWidth: 2)
                    .background(Circle().fill(entry.isFuture ? Color.clear : tint))
                    .frame(width: 12, height: 12)
                    .padding(.top, 3)
                if !isLast {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(entry.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(entry.isFuture ? .secondary : .primary)
                if let detail = entry.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                // Where it came from, and whether it was read or inferred.
                Text(entry.source)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, isLast ? 0 : 14)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

extension ExamUpdate.Kind {
    var tint: Color {
        switch self {
        case .gradePublished, .gradeRecorded: .green
        case .refusalOpened, .roomChanged, .dateChanged: .orange
        case .withdrawn, .unenrolled: .red
        case .roomPublished, .enrolled, .correctionsAvailable: Theme.brand
        case .discovered, .enrolmentOpened: .indigo
        }
    }
}

// MARK: - Previews

#Preview("Novità esami") {
    ExamUpdatesView().previewInNavigation()
}

#Preview("Cronologia appello") {
    ScrollView {
        ExamTimelineSection(exam: MockData.examSessions()[0]).padding()
    }
    .background(Color(.systemGroupedBackground))
    .previewEnvironment()
}
