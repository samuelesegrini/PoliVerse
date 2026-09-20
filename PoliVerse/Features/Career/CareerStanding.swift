import SwiftUI

/// Where the student has got to, as one card.
///
/// This replaces four: two stat tiles, a credits card and a row of three
/// counters. Between them they put seven figures on screen at near-equal
/// weight — and three of those figures (esiti, iscrizioni, insegnamenti) were
/// the lengths of lists printed further down the same page, which is a
/// database dump rather than information.
///
/// What is left is the one question a student opens Carriera with when they
/// open it for no particular reason: *dove sono arrivato*. The average, which
/// way it moved, the marks behind it, the credits, and what is still to do.
///
/// The degree mark is the exception that proves the point. It used to be a
/// tile the same size as the average — the most emotionally loaded number on
/// the screen, presented as a fact. ``GradeBook/baseGraduationMark`` is a
/// baseline that excludes thesis, timeliness and Erasmus points, so it is now
/// a sentence, it says it is an estimate, and it leads to the simulator where
/// the what-if belongs.
struct CareerStandingCard: View {
    let book: GradeBook
    let exams: [LibrettoExam]
    /// How the average moved with the last recorded mark, where there is one.
    let delta: Double?
    /// Opens the grade simulator.
    let simulate: () -> Void

    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Environment(\.colorScheme) private var scheme
    /// The exam being read on the chart. While there is one, the headline is
    /// that exam rather than the career: the big number is where the eye
    /// already is, so it is where the reading belongs — a callout floating
    /// over a 150-point chart would cover the line it is describing.
    @State private var inspected: MeanPoint?

    private var plan: StudyPlan { StudyPlan(exams: exams) }

    /// The official figure where the service gave one, the libretto's own
    /// arithmetic otherwise — a career loaded from cache without the
    /// aggregate still has marks to average.
    private var mean: Double {
        book.mean > 0 ? book.mean : (plan.weightedMean ?? 0)
    }

    var body: some View {
        let palette = style.palette(scheme)
        VStack(alignment: .leading, spacing: 16) {
            average
            MeanChart(exams: exams, selection: $inspected)
            Divider()
            credits(palette)
            if mean > 0 { estimate }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lookCard()
    }

    // MARK: - The number

    private var average: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(headlineNumber)
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            caption
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.2), value: inspected?.id)
        .accessibilityElement(children: .combine)
    }

    /// The career's average, or — while an exam is being read on the chart —
    /// what the average stood at once that exam was recorded.
    private var headlineNumber: String {
        if let inspected {
            return inspected.mean.formatted(.number.precision(.fractionLength(1)))
        }
        return mean > 0 ? mean.formatted(.number.precision(.fractionLength(1))) : "—"
    }

    @ViewBuilder
    private var caption: some View {
        if let inspected {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: inspected.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                Text("\(inspected.displayGrade) · \(inspected.credits) · \(inspected.date, format: .dateTime.month(.wide).year())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else if let delta, abs(delta) >= 0.05 {
            VStack(alignment: .leading, spacing: 0) {
                Text(delta.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    // Up is the same green as a mark that stands; down is
                    // plain. A falling average is a fact, not a warning, and
                    // the sign already says which way it went.
                    .foregroundStyle(delta > 0 ? AnyShapeStyle(CareerState.passed.tint) : AnyShapeStyle(.secondary))
                Text("dall'ultimo esame")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Media ponderata")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - The credits

    private func credits(_ palette: Flavor.Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(book.earnedCFU) di \(book.plannedCFU) CFU")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Spacer(minLength: 8)
                if let remaining {
                    Text(remaining)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: book.progress)
                .tint(palette.accent)
        }
        .accessibilityElement(children: .combine)
    }

    /// What is left, counted in exams when the libretto is complete enough to
    /// count them, and in credits otherwise.
    ///
    /// The two numbers come from different places: the credits are the
    /// aggregate the Politecnico publishes, the exams are rows in the
    /// libretto. A libretto that has not loaded fully — or a plan whose later
    /// years are not in it yet — would otherwise put "restano 2 esami" next to
    /// "108 di 180 CFU", which is seventy credits of nonsense.
    private var remaining: String? {
        let known = plan.totalCFU
        if book.plannedCFU > 0, known > 0, Double(known) >= Double(book.plannedCFU) * 0.9 {
            let count = plan.pending.count
            return count > 0 ? String(localized: "restano \(count) esami") : nil
        }
        let credits = book.plannedCFU - book.earnedCFU
        return credits > 0 ? String(localized: "restano \(credits) CFU") : nil
    }

    // MARK: - The estimate

    private var estimate: some View {
        Button(action: simulate) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Con questa media ti laurei intorno a ")
                    + Text("\(book.baseGraduationMark > 0 ? Int(book.baseGraduationMark.rounded()) : Int((mean / 30 * 110).rounded())) su 110")
                    .fontWeight(.semibold)
                    + Text(" — stima, senza i punti di tesi")
                Image(systemName: "chevron.forward")
                    .font(.caption2.weight(.semibold))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Apre la simulazione della media")
    }
}

// MARK: - Previews

#Preview("Dove sei") {
    ScrollView {
        CareerStandingCard(book: .sample, exams: LibrettoExam.samples(), delta: 0.3) {}
            .padding(16)
    }
    .previewEnvironment()
}
