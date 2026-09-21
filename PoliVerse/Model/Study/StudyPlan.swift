import Foundation

/// The study plan: every teaching, passed or not, with the arithmetic a
/// student actually asks of it.
///
/// The Politecnico has endpoints for this — `/sequenzamedia/{matricola}`,
/// `/mediaobiettivo/{matricola}`, `/simulazionemedia/insegnsenzavoto/{matricola}`
/// — and ``CareerModel`` reads the official target from them. The
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

    /// Each graded exam in the order it was sat, with the weighted mean as it
    /// stood once that mark was recorded.
    ///
    /// This is what a student means by "how am I doing": not the marks, which
    /// bounce, but the line they add up to. Each step recomputes the mean over
    /// everything up to that point rather than accumulating a running total,
    /// so every value on it is the same arithmetic as ``weightedMean`` and the
    /// last one is that figure exactly.
    ///
    /// Only dated marks take part: an exam with no date has no place on a time
    /// axis, and putting it at one would be inventing when it happened.
    var progression: [(exam: LibrettoExam, mean: Double)] {
        let dated = graded
            .filter { $0.date != nil }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        return dated.indices.compactMap { index in
            guard let mean = StudyPlan(exams: Array(dated[...index])).weightedMean else { return nil }
            return (exam: dated[index], mean: mean)
        }
    }

    /// The most recently sat exam carrying a numeric mark.
    ///
    /// Undated marks are excluded: "most recent" is a question about time, and
    /// an exam with no date cannot answer it.
    var lastGraded: LibrettoExam? {
        graded
            .filter { $0.date != nil }
            .max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    /// How the weighted mean moved when ``lastGraded`` was recorded.
    ///
    /// The single most interesting thing about an average is which way it is
    /// going, and a student cannot get that from a number on its own — they
    /// would have to remember what it said last month. Both sides are computed
    /// by the same arithmetic as ``weightedMean``, so the difference is honest
    /// even where it is a tenth off the official mean.
    ///
    /// Nil until there are two marks to have moved between.
    var meanDelta: Double? {
        guard let last = lastGraded else { return nil }
        let before = StudyPlan(exams: exams.filter { $0.id != last.id })
        guard let previous = before.weightedMean, let current = weightedMean else { return nil }
        return current - previous
    }

    /// Everything still to sit, which has no year to be grouped under.
    static let pendingGroup = String(localized: "Da sostenere")

    /// The plan grouped for display: what is left first, then the academic
    /// years the rest was sat in, newest first.
    ///
    /// Every group used to be called "Altro", because it grouped by
    /// ``LibrettoExam/year`` and nothing has ever set that field. It now goes
    /// through ``LibrettoExam/academicYear(calendar:)``, which reads the year
    /// off the date of the sitting.
    ///
    /// What is left leads rather than trailing: it is the only group with
    /// anything to do in it.
    var byYear: [(year: String, exams: [LibrettoExam])] {
        Dictionary(grouping: exams) { $0.academicYear() ?? Self.pendingGroup }
            .map { group in
                (year: group.key,
                 exams: group.value.sorted { left, right in
                     // Within a year, newest sitting first; undated by name.
                     switch (left.date, right.date) {
                     case let (l?, r?): return l > r
                     case (nil, nil): return left.name < right.name
                     case (nil, _?): return false
                     case (_?, nil): return true
                     }
                 })
            }
            .sorted { left, right in
                if left.year == Self.pendingGroup { return true }
                if right.year == Self.pendingGroup { return false }
                return left.year > right.year
            }
    }

    /// The weighted mean of one slice of the plan, for a year's own line.
    static func mean(of exams: [LibrettoExam]) -> Double? {
        StudyPlan(exams: exams).weightedMean
    }

    /// Credits earned in one slice.
    static func earnedCFU(of exams: [LibrettoExam]) -> Int {
        exams.filter(\.isPassed).reduce(0) { $0 + ($1.cfu ?? 0) }
    }
}

/// `GET {libretto}/testatapiano/{matricola}` — what the plan is *for*.
///
/// Shape unconfirmed, so every field is optional and read across candidate
/// names; the header is decoration around the exam list, and a missing field
/// must not cost the screen.
nonisolated struct StudyPlanHeader: Sendable, Equatable, Codable {
    let course: String?
    let year: String?
    let track: String?
    let totalCFU: Int?
    /// `k_corso_la` and `k_indir`, if the service sends them: the manifesto's
    /// own keys, which make finding the programme exact. Unconfirmed names,
    /// read leniently; the payload's shape is logged in debug builds.
    var degreeCode: String? = nil
    var planCode: String? = nil
    /// `tipoCorso`, e.g. "LAUREA DI PRIMO LIVELLO": what tells a bachelor's
    /// from a master's of the same name. The careers list only says "Studente".
    var level: String? = nil
    var englishCourse: String? = nil

    /// The plan's academic year as the manifesto keys it: "2025/26" → "2025".
    var yearCode: String? {
        guard let prefix = year?.prefix(4), prefix.count == 4, prefix.allSatisfy(\.isNumber) else { return nil }
        return String(prefix)
    }

    init?(value: JSONValue) {
        guard let fields = value.objectValue ?? value.arrayValue?.first?.objectValue else {
            return nil
        }
        course = fields.firstValue([
            "descrizione_corso", "desc_corso", "descrizioneCDL", "corso", "nome_corso",
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

        level = fields.firstValue(["tipoCorso", "tipo_corso"]).flatMap(Notice.text(from:))
        englishCourse = fields.firstValue(["descrizioneCDL_ENG"]).flatMap(Notice.text(from:))
        let code = { (value: JSONValue) -> String? in
            value.intValue.map(String.init) ?? Notice.text(from: value)
        }
        degreeCode = fields.firstValue(["k_corso_la", "kCorsoLa", "codiceCDL", "codCorsoStudi", "cod_corso"]).flatMap(code)
        planCode = fields.firstValue(["k_indir", "kIndir", "codicePiano", "codPiano", "cod_indirizzo"]).flatMap(code)

        // Nothing readable at all is not a header.
        if course == nil && year == nil && track == nil && totalCFU == nil && degreeCode == nil {
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
