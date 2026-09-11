import SwiftUI

struct CareerView: View {
    @Environment(CareerService.self) private var career
    @State private var scope: Scope = .overview

    enum Scope: String, CaseIterable, Identifiable {
        case overview = "Riepilogo"
        case upcoming = "Appelli"
        case results = "Esiti"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            content(career)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Carriera")
            .toolbarTitleDisplayMode(.inlineLarge)
            .task { await career.load() }
            .refreshable { await career.load() }
        }
    }

    @ViewBuilder
    private func content(_ career: CareerService) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Picker("Sezione", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if let message = career.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.15), in: .rect(cornerRadius: 14))
                        .foregroundStyle(.orange)
                }

                if career.gradeBook == .empty && career.sessions.isEmpty && !career.isLoading {
                    ContentUnavailableView("Nessun dato di carriera", systemImage: "chart.bar",
                                           description: Text("I servizi del Politecnico non hanno restituito dati."))
                        .padding(.top, 30)
                }

                switch scope {
                case .overview: overview(career)
                case .upcoming: upcoming(career)
                case .results: results(career)
                }
            }
            .padding()
            .padding(.bottom, 20)
        }
        .overlay {
            if career.isLoading && career.sessions.isEmpty { ProgressView() }
        }
    }

    // MARK: - Overview

    private func overview(_ career: CareerService) -> some View {
        let book = career.gradeBook
        return VStack(spacing: 16) {
            HStack(spacing: 12) {
                StatTile(
                    value: book.mean > 0 ? String(format: "%.2f", book.mean) : "—",
                    label: "Media ponderata",
                    accent: Theme.brand
                )
                StatTile(
                    value: book.mean > 0 ? String(format: "%.0f", book.baseGraduationMark) : "—",
                    label: "Base su 110",
                    accent: .indigo
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Crediti")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(book.earnedCFU) / \(book.plannedCFU) CFU")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: book.progress)
                    .tint(Theme.brand)
                Text("\(Int(book.progress * 100))% del piano di studi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .cardBackground()

            // Labels follow what the fields actually mean upstream:
            // num_esiti is published results, num_iscriz is active enrolments.
            HStack(spacing: 12) {
                StatTile(value: "\(book.examsGiven)", label: "Esiti", accent: .green, compact: true)
                StatTile(value: "\(book.examsSubscribed)", label: "Iscrizioni", accent: .orange, compact: true)
                StatTile(value: "\(book.examsPlanned)", label: "Insegnamenti", accent: .secondary, compact: true)
            }

            if let next = career.upcoming.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prossimo appello")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ExamRow(exam: next)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Upcoming

    @ViewBuilder
    private func upcoming(_ career: CareerService) -> some View {
        if career.upcoming.isEmpty {
            ContentUnavailableView("Nessun appello", systemImage: "calendar.badge.clock",
                                   description: Text("Non ci sono appelli in programma."))
                .padding(.top, 40)
        } else {
            VStack(spacing: 10) {
                ForEach(career.upcoming) { ExamRow(exam: $0) }
            }
        }
    }

    // MARK: - Results

    @ViewBuilder
    private func results(_ career: CareerService) -> some View {
        if career.results.isEmpty {
            ContentUnavailableView("Nessun esito", systemImage: "checkmark.seal",
                                   description: Text("Gli esiti pubblicati appariranno qui."))
                .padding(.top, 40)
        } else {
            VStack(spacing: 10) {
                ForEach(career.results) { ExamRow(exam: $0) }
            }
        }
    }
}

// MARK: - Components

private struct StatTile: View {
    let value: String
    let label: String
    let accent: Color
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(compact ? .title3.weight(.bold) : .largeTitle.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 12 : 18)
        .cardBackground()
    }
}

private struct ExamRow: View {
    let exam: ExamSession
    @Environment(\.locale) private var locale

    private var accent: Color {
        switch exam.status {
        case .graded(let grade): grade.passed ? .green : .red
        case .enrolled: Theme.brand
        case .open: .orange
        case .notYetOpen, .closed: .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                if let grade = exam.grade {
                    Text(grade.display)
                        .font(.title3.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else if let date = exam.date {
                    Text(date.formatted(.dateTime.day().locale(locale)))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text(date.formatted(.dateTime.month(.abbreviated).locale(locale)).uppercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "questionmark")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 48)

            VStack(alignment: .leading, spacing: 5) {
                Text(exam.courseName)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    // With the mark already shown in the gutter, repeating
                    // "Esito disponibile" on every row says nothing. Graded
                    // sittings show when they happened instead.
                    if let grade = exam.grade {
                        Text(grade.passed ? "Superato" : "Non superato")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(accent.opacity(0.15), in: .capsule)
                            .foregroundStyle(accent)

                        if let date = exam.date {
                            Text(date.formatted(.dateTime.month(.wide).year().locale(locale)).capitalized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(exam.status.label)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(accent.opacity(0.15), in: .capsule)
                            .foregroundStyle(accent)

                        if let room = exam.room {
                            Label(room, systemImage: "mappin.and.ellipse")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let closes = exam.enrolmentCloses, exam.status == .open {
                    Text("Iscrizioni entro il \(closes.formatted(.dateTime.day().month(.wide).locale(locale)))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if let grade = exam.grade, grade.refusable {
                    Label("Rifiutabile", systemImage: "arrow.uturn.backward")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let count = exam.enrolledCount, count > 0, exam.grade == nil {
                    Text("\(count) iscritti")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}
