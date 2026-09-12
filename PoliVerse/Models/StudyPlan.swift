import Foundation

/// The study plan: every teaching, passed or not, with the arithmetic a
/// student actually asks of it.
///
/// The Politecnico has endpoints for this — `/sequenzamedia/{matricola}`,
/// `/mediaobiettivo/{matricola}`, `/simulazionemedia/insegnsenzavoto/{matricola}`
/// — and ``CareerService`` reads the official target from them. The
/// arithmetic below is still done on the device: answering "what if I get 28
/// in the rest?" has to be instant while a slider moves, and it is a weighted
/// mean over data already here.
nonisolated struct StudyPlan: Sendable, Equatable {
    let exams: [LibrettoExam]

    /// Exams with a numeric mark. Pass/fail teachings carry CFU but no mark,
    /// and counting them as zero would wreck every average they appear in.
    private var graded: [LibrettoExam] {
        exams.filter { ($0.grade ?? 0) > 0 }
    }

    var passed: [LibrettoExam] { exams.filter(\.isPassed) }
    var pending: [LibrettoExam] { exams.filter { !$0.isPassed } }

    var earnedCFU: Int { passed.reduce(0) { $0 + ($1.cfu ?? 0) } }
    var remainingCFU: Int { pending.reduce(0) { $0 + ($1.cfu ?? 0) } }
    var totalCFU: Int { earnedCFU + remainingCFU }

    /// CFU actually behind the average — less than ``earnedCFU`` whenever the
    /// plan contains a pass/fail teaching.
    private var gradedCFU: Int { graded.reduce(0) { $0 + ($1.cfu ?? 0) } }

    /// The weighted mean. `30L` counts as 30: honours sit on top of a full
    /// mark, and scoring them higher inflates every average containing one.
    var weightedMean: Double? {
        guard gradedCFU > 0 else {
            // No CFU recorded anywhere: fall back to a plain mean rather than
            // dividing by zero and reporting nothing.
            guard !graded.isEmpty else { return nil }
            return Double(graded.reduce(0) { $0 + ($1.grade ?? 0) }) / Double(graded.count)
        }
        let total = graded.reduce(0.0) { $0 + Double(($1.grade ?? 0) * ($1.cfu ?? 0)) }
        return total / Double(gradedCFU)
    }

    /// The base degree mark, `mean / 30 × 110`, rounded.
    ///
    /// An estimate and labelled as one: thesis points, honours and any
    /// bonus the school applies are not derivable from the libretto.
    var baseDegreeMark: Int? {
        weightedMean.map { Int((($0 / 30) * 110).rounded()) }
    }

    /// The average needed across everything still to sit, to finish on
    /// `target`.
    ///
    /// Returns a figure above 30 when the target is out of reach rather than
    /// clamping: a clamped 30 reads as "get top marks and you're fine", which
    /// would be a lie. Use ``isReachable(_:)`` to ask the yes/no question.
    func requiredAverage(for target: Double) -> Double? {
        guard remainingCFU > 0 else { return nil }
        let doneWeight = (weightedMean ?? 0) * Double(gradedCFU)
        let totalWeight = target * Double(gradedCFU + remainingCFU)
        return (totalWeight - doneWeight) / Double(remainingCFU)
    }

    func isReachable(_ target: Double) -> Bool {
        guard let needed = requiredAverage(for: target) else {
            return (weightedMean ?? 0) >= target
        }
        return needed <= 30
    }

    /// What the mean becomes if everything left is passed at `grade`.
    func projectedMean(assuming grade: Double) -> Double? {
        guard remainingCFU > 0 else { return weightedMean }
        guard let mean = weightedMean else {
            return gradedCFU == 0 && !exams.isEmpty ? grade : nil
        }
        let doneWeight = mean * Double(gradedCFU)
        return (doneWeight + grade * Double(remainingCFU))
            / Double(gradedCFU + remainingCFU)
    }

    /// The plan grouped for display, newest year first.
    var byYear: [(year: String, exams: [LibrettoExam])] {
        Dictionary(grouping: exams) { $0.year ?? "Altro" }
            .map { (year: $0.key, exams: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.year > $1.year }
    }
}

/// `GET {libretto}/testatapiano/{matricola}` — what the plan is *for*.
///
/// Shape unconfirmed, so every field is optional and read across candidate
/// names; the header is decoration around the exam list, and a missing field
/// must not cost the screen.
nonisolated struct StudyPlanHeader: Sendable, Equatable {
    let course: String?
    let year: String?
    let track: String?
    let totalCFU: Int?

    init?(value: JSONValue) {
        guard let fields = value.objectValue ?? value.arrayValue?.first?.objectValue else {
            return nil
        }
        course = fields.firstValue([
            "descrizione_corso", "desc_corso", "corso", "nome_corso",
            "descrizione", "cds",
        ]).flatMap(Notice.text(from:))
        year = fields.firstValue([
            "aa", "anno_accademico", "aa_piano", "anno",
        ]).flatMap(Notice.text(from:))
        track = fields.firstValue([
            "orientamento", "percorso", "indirizzo", "track", "curriculum",
        ]).flatMap(Notice.text(from:))
        totalCFU = fields.firstValue([
            "cfu_totali", "cfu", "crediti", "totale_cfu",
        ])?.intValue

        // Nothing readable at all is not a header.
        if course == nil && year == nil && track == nil && totalCFU == nil {
            return nil
        }
    }

    init(course: String?, year: String?, track: String?, totalCFU: Int?) {
        self.course = course
        self.year = year
        self.track = track
        self.totalCFU = totalCFU
    }
}
