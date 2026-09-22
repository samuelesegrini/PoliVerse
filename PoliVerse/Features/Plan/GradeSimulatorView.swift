import SwiftUI

/// "What do I need in the next exams to finish on 27?"
///
/// The arithmetic runs on the device — see ``StudyPlan`` — so the numbers move
/// with the slider instead of waiting on a round trip. The one thing that does
/// go to the Politecnico is saving a target, and that happens on an explicit
/// button, never from the slider.
struct GradeSimulatorView: View {
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career

    /// The final average the student is aiming at, which the required average is computed
    /// from.
    /// The mark the student assumes for everything still to sit, which the projection is
    /// computed from.
    @State private var target: Double = 27
    @State private var assumed: Double = 27
    @State private var saving = false
    /// The value that actually reached the Politecnico, not merely "a save
    /// happened": stepping the target past a saved one must stop the button
    /// claiming the new figure is stored.
    @State private var savedTarget: Double?
    /// A refused write, said out loud — this is the one thing the app sends
    /// to Servizi Online, and a silent failure here is indistinguishable
    /// from a button that was never pressed.
    @State private var saveFailed = false

    /// The libretto's arithmetic, which every figure here comes from.
    private var plan: StudyPlan { career.studyPlan }

    /// The view's content.
    var body: some View {
        List {
            Section {
                PageHero(symbol: "function", title: Text("Simulazione media"), summary: Text("Prova i voti che verranno"))
                    .listHeader()
            }
            current

            if plan.remainingCFU > 0 {
                targetSection
                projectionSection
            } else {
                Section {
                    Text("Non ci sono esami rimasti nel piano: la media è quella finale.")
                        .foregroundStyle(.secondary)
                }
                .lookRow()
            }
        }
        .lookList()
        .navigationTitle("Simulazione media")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await career.load()
            // Start from the target the Politecnico already holds, where there
            // is one — the point is to continue the student's own plan, not to
            // propose a number out of nowhere.
            if let official = career.officialTarget, official > 17 {
                target = official
            } else if let mean = plan.weightedMean {
                target = (mean + 0.5).rounded()
            }
            assumed = min(max(target, 18), 30)
        }
    }

    /// Where the student stands now: the weighted average, the credits, and the degree mark
    /// it implies.
    private var current: some View {
        Section {
            LabeledContent("Media attuale",
                           value: plan.weightedMean.map { String(format: "%.2f", $0) } ?? "—")
            LabeledContent("CFU acquisiti",
                           value: "\(plan.earnedCFU)\(plan.totalCFU > 0 ? " / \(plan.totalCFU)" : "")")
            if let mark = plan.baseDegreeMark {
                LabeledContent("Voto di laurea base", value: "\(mark)/110")
            }
        } header: {
            Text("Oggi")
        } footer: {
            Text("Il voto di laurea è una stima da media e CFU: punti di tesi ed eventuale lode non sono ricavabili dal libretto.")
        }
        .lookRow()
    }

    /// The target average, the average it would require across what is left, and whether that
    /// is attainable — with a button to save the target back to Servizi Online.
    private var targetSection: some View {
        Section {
            Stepper(value: $target, in: 18...30, step: 0.5) {
                LabeledContent("Obiettivo", value: String(format: "%.1f", target))
            }

            if let needed = plan.requiredAverage(for: target) {
                let reachable = plan.isReachable(target)
                LabeledContent("Ti serve una media di") {
                    Text(String(format: "%.2f", needed))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(reachable ? Color.green : Color.red)
                }
                if !reachable {
                    // Said outright rather than clamped to 30. A clamped
                    // figure reads as "get top marks and you're fine", which
                    // would be false.
                    Label("Fuori portata: servirebbe più di 30 nei \(plan.remainingCFU) CFU rimasti.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            let isSaved = savedTarget == target
            Button {
                Task {
                    saving = true
                    saveFailed = false
                    if await career.saveTarget(target) {
                        savedTarget = target
                    } else {
                        savedTarget = nil
                        saveFailed = true
                    }
                    saving = false
                }
            } label: {
                if saving {
                    ProgressView()
                } else {
                    Label(isSaved ? "Obiettivo salvato" : "Salva su Servizi Online",
                          systemImage: isSaved ? "checkmark.circle" : "square.and.arrow.up")
                }
            }
            .disabled(saving || isSaved)

            if saveFailed {
                Label("Non è stato possibile salvare l'obiettivo. Riprova, o impostalo dai Servizi Online.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Obiettivo")
        } footer: {
            Text(career.officialTarget.map {
                "Obiettivo attuale sui Servizi Online: \(String(format: "%.1f", $0))."
            } ?? "Salvando, l'obiettivo viene registrato anche sui Servizi Online del Politecnico.")
        }
        .lookRow()
        .onChange(of: target) { saveFailed = false }
    }

    /// What the average and the degree mark become if everything left is passed at the
    /// assumed mark.
    private var projectionSection: some View {
        Section {
            Stepper(value: $assumed, in: 18...30, step: 1) {
                LabeledContent("Se prendo", value: "\(Int(assumed)) in tutti i rimanenti")
            }
            if let projected = plan.projectedMean(assuming: assumed) {
                LabeledContent("Media finale",
                               value: String(format: "%.2f", projected))
                LabeledContent("Voto di laurea",
                               value: "\(Int(((projected / 30) * 110).rounded()))/110")
            }
        } header: {
            Text("Proiezione")
        } footer: {
            Text("\(plan.pending.count) esami da sostenere, \(plan.remainingCFU) CFU.")
        }
        .lookRow()
    }
}

// MARK: - Previews

#Preview("Simulazione media") {
    GradeSimulatorView().previewInNavigation()
}
