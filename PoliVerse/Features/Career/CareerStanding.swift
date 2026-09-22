import SwiftUI

/// Where the student has got to, as one card.
///
/// One card rather than a grid of tiles, because the card answers the one
/// question a student opens Carriera with when they open it for no particular
/// reason: *dove sono arrivato*. The average, which way it moved, the marks
/// behind it, the credits, and what is still to do. Counts that are only the
/// lengths of lists printed further down the same page are left to those
/// lists.
///
/// The degree mark is a sentence rather than a figure beside the average.
/// ``GradeBook/baseGraduationMark`` is a baseline that excludes thesis,
/// timeliness and Erasmus points, so it says outright that it is an estimate
/// and leads to the simulator where the what-if belongs.
struct CareerStandingCard: View {
    /// The career's aggregate figures, as the service reports them.
    let book: GradeBook
    /// The libretto, which the chart is drawn from and the average falls back to.
    let exams: [LibrettoExam]
    /// How the average moved with the last recorded mark, where there is one.
    let delta: Double?
    /// Opens the grade simulator.
    let simulate: () -> Void

    /// The look in use, which supplies the card's material and colour.
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    /// Whether the interface is in light or dark mode.
    @Environment(\.colorScheme) private var scheme
    /// The day being read on the chart. While there is one, the headline is
    /// that day rather than the career: the big number is where the eye
    /// already is, so it is where the reading belongs — a callout floating
    /// over a 150-point chart would cover the line it is describing.
    ///
    /// A day and not an exam, because two marks recorded on one date cannot be
    /// told apart on a time axis: see ``MeanDay``.
    @State private var inspected: MeanDay?
    /// The headline figure's size, scaled with the reader's text.
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 52

    /// The libretto read as a plan, for the credits and the arithmetic behind the average.
    private var plan: StudyPlan { StudyPlan(exams: exams) }

    /// The official figure where the service gave one, the libretto's own
    /// arithmetic otherwise — a career loaded from cache without the
    /// aggregate still has marks to average.
    private var mean: Double {
        book.mean > 0 ? book.mean : (plan.weightedMean ?? 0)
    }

    /// The view's content.
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

    /// The headline figure and its caption, with the way back to today's average while a day is being inspected.
    private var average: some View {
        // Two rows in one, on purpose. The figure and its caption are set
        // against a shared baseline; the close button is not text and has no
        // baseline of its own, so inside that group it would be aligned by its
        // bottom edge and drag the row's height around with it. It sits in an
        // outer row aligned to the top instead, which is also where it belongs
        // — beside the number, not hanging off the caption.
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                headline
                caption
                Spacer(minLength: 0)
            }
            // The way out of a selection, in the same place every time and
            // sized to be hit. The chart's own hint is a caption nobody
            // reading with VoiceOver or at large text will ever meet.
            if inspected != nil {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { inspected = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Torna alla media attuale")
            }
        }
        .animation(.snappy(duration: 0.2), value: inspected?.id)
    }

    /// The big number: the average, or the day being inspected on the chart.
    private var headline: some View {
        Text(headlineNumber)
            // Scaled, so the page's biggest number stays the page's biggest
            // number when the reader's text grows: at a fixed 52 the section
            // rows under it would eventually overtake it.
            .font(.system(size: headlineSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            // Never scaled down to fit. It had `minimumScaleFactor`, and
            // selecting an exam puts a long name and a close button in the
            // same row: the figure was offered less width and quietly shrank,
            // so the page's headline changed size depending on which exam the
            // finger was on. It keeps its own width now and the caption beside
            // it truncates instead, which is the right way round — the number
            // is the reading, the name is the label.
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
    }

    /// The career's average, or — while an exam is being read on the chart —
    /// what the average stood at once that exam was recorded.
    private var headlineNumber: String {
        if let inspected {
            return inspected.mean.formatted(.number.precision(.fractionLength(1)))
        }
        return mean > 0 ? mean.formatted(.number.precision(.fractionLength(1))) : "—"
    }

    // The caption is aligned by its last baseline against a 52-point figure,
    // so it cannot be padded out to a height common to all three states: a
    // hidden view holding that space still publishes its own text baselines,
    // which would sit the headline on a line that is never drawn. What each
    // state can do is hold its own height, which is what the fixed line limits
    // below are for. The one jump left is entering and leaving a
    // selection — a change of subject on a tap, not jitter under the finger.
    /// The words under the figure: what it is, which way it moved, or which exam the inspected day holds.
    @ViewBuilder
    private var caption: some View {
        if let inspected {
            VStack(alignment: .leading, spacing: 0) {
                // Says outright that the big number is no longer today's
                // average. Without it the headline silently changes meaning.
                //
                // Set exactly as "Media ponderata" is: the two label the same
                // number and swap places under it, so a different size or case
                // would read as the figure itself having changed.
                Text("Media dopo")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                // Every teaching recorded that day, joined. One line, cut
                // where it runs out: wrapping made the block one or two lines
                // deep depending on the exam, so the card changed height as
                // the finger moved along the chart.
                Text(verbatim: inspected.title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text("\(inspected.marks) · \(inspected.credits) · \(inspected.date, format: .dateTime.month(.wide).year())")
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

    /// The credits earned against the credits planned, as a figure and a bar.
    ///
    /// - Parameter palette: The look's colours, which the bar is drawn in.
    /// - Returns: The section.
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

    /// The degree mark out of 110 the average implies, before any thesis points.
    ///
    /// From the grade book where it has one, and from the average shown
    /// otherwise, so the sentence never reads zero while a mark is on screen.
    private var mark: Int {
        book.baseGraduationMark > 0
            ? Int(book.baseGraduationMark.rounded())
            : Int((mean / 30 * 110).rounded())
    }

    /// The baseline degree mark as a sentence, leading to the simulator where the what-if belongs.
    private var estimate: some View {
        Button(action: simulate) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // One interpolated string rather than three `Text`s added
                // together: `Text.+` is deprecated, and interpolation keeps
                // the sentence in one translatable unit besides.
                Text("Con questa media ti laurei intorno a \(Text(verbatim: "\(mark) su 110").fontWeight(.semibold)) — stima, senza i punti di tesi")
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
