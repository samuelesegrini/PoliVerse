import SwiftUI

/// The study plan: everything in the course, passed or still to sit.
///
/// Built from the libretto, which is the plan with results attached —
/// `/elencoinsegnamenti/{matricola}` returns both halves already split — with
/// the header from `/testatapiano/{matricola}` on top.
struct StudyPlanView: View {
    @Environment(CareerService.self) private var career

    @State private var showPassed = true
    @State private var showPending = true

    private var plan: StudyPlan { career.studyPlan }

    var body: some View {
        List {
            Section {
                PageHero(symbol: "list.bullet.rectangle", title: Text("Piano di studi"),
                         summary: Text("\(plan.earnedCFU) di \(plan.totalCFU) CFU"))
                    .listHeader()
            }
            .glassRow()
            if let header = career.planHeader {
                Section {
                    if let course = header.course {
                        LabeledContent("Corso", value: course)
                    }
                    if let track = header.track {
                        LabeledContent("Orientamento", value: track)
                    }
                    if let year = header.year {
                        LabeledContent("Anno", value: year)
                    }
                }
                .glassRow()
            }

            Section {
                ProgressView(value: Double(plan.earnedCFU),
                             total: Double(max(plan.totalCFU, 1))) {
                    LabeledContent("CFU", value: "\(plan.earnedCFU) / \(plan.totalCFU)")
                }
                LabeledContent("Superati", value: "\(plan.passed.count) esami")
                LabeledContent("Da sostenere", value: "\(plan.pending.count) esami")

                NavigationLink {
                    GradeSimulatorView()
                } label: {
                    Label("Simulazione media", systemImage: "function")
                }
            }
            .glassRow()

            Section {
                Toggle("Superati", isOn: $showPassed)
                Toggle("Da sostenere", isOn: $showPending)
            }
            .glassRow()

            ForEach(shownByYear, id: \.year) { group in
                Section(group.year) {
                    ForEach(group.exams) { exam in
                        PlanRow(exam: exam)
                    }
                }
                .glassRow()
            }

            if shown.isEmpty && !career.isLoading {
                Section {
                    Text(career.examServicesRefused
                         ? "Il Politecnico non abilita il tuo profilo al libretto in questo momento."
                         : "Nessun insegnamento nel piano.")
                        .foregroundStyle(.secondary)
                }
                .glassRow()
            }
        }
        .glassList()
        .navigationTitle("Piano di studi")
        .navigationBarTitleDisplayMode(.inline)
        .task { await career.load() }
        .refreshable { await career.load(force: true) }
    }

    private var shown: [LibrettoExam] {
        plan.exams.filter { exam in
            exam.isPassed ? showPassed : showPending
        }
    }

    private var shownByYear: [(year: String, exams: [LibrettoExam])] {
        StudyPlan(exams: shown).byYear
    }
}

private struct PlanRow: View {
    let exam: LibrettoExam

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exam.name)
                    .font(.subheadline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let cfu = exam.cfu, cfu > 0 {
                        Text("\(cfu) CFU")
                    }
                    if let status = exam.statusText {
                        Text(status.capitalized)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(exam.isPassed ? exam.displayGrade : "—")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(exam.isPassed ? Color.green : Color.secondary)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Previews

#Preview("Piano di studi") {
    StudyPlanView().previewInNavigation()
}

#Preview("Componente · Riga piano") {
    List {
        ForEach(MockData.libretto().prefix(5)) { PlanRow(exam: $0) }
    }
    .previewEnvironment()
}
