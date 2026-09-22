import Foundation

/// The study plan: every teaching, passed or not, with the arithmetic a student asks of
/// it.
///
/// The Politecnico has endpoints for the average and the target, and ``CareerModel``
/// reads the official target from them. The arithmetic here is still done on the device,
/// because answering “what if I get 28 in the rest?” has to be instant while a slider
/// moves, and it is a weighted mean over data already in hand.
///
/// A value type, so it needs no session, no network and no actor to answer and can be
/// tested directly.
///
/// ## What counts
///
/// Only teachings with a numeric mark enter an average. A pass/fail teaching carries
/// credits but no mark, and counting it as zero would wreck every average it appears
/// in. Honours count as 30, since they sit on top of a full mark.
nonisolated struct StudyPlan: Sendable, Equatable {
    /// The plan's teachings, passed and pending.
    let exams: [LibrettoExam]

    /// The teachings carrying a numeric mark, which are the only ones an average is computed
    /// over.
    private var graded: [LibrettoExam] {
        exams.filter { ($0.grade ?? 0) > 0 }
    }

    /// The teachings passed, pass/fail ones included.
    var passed: [LibrettoExam] { exams.filter(\.isPassed) }
    /// The teachings still to sit.
    var pending: [LibrettoExam] { exams.filter { !$0.isPassed } }

    /// Credits already earned.
    var earnedCFU: Int { passed.reduce(0) { $0 + ($1.cfu ?? 0) } }
    /// Credits still to earn.
    var remainingCFU: Int { pending.reduce(0) { $0 + ($1.cfu ?? 0) } }
    /// Credits in the whole plan.
    var totalCFU: Int { earnedCFU + remainingCFU }

    /// Credits actually behind the average — less than ``earnedCFU`` whenever the plan holds
    /// a pass/fail teaching.
    private var gradedCFU: Int { graded.reduce(0) { $0 + ($1.cfu ?? 0) } }

    /// The credit-weighted average of the marks recorded so far.
    ///
    /// Falls back to a plain mean when no credits are recorded anywhere, rather than
    /// reporting nothing. `nil` when there are no marks at all.
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

    /// The base degree mark out of 110, rounded.
    ///
    /// An estimate: thesis points, honours and any bonus the school applies are not
    /// derivable from the libretto. `nil` when there are no marks.
    var baseDegreeMark: Int? {
        weightedMean.map { Int((($0 / 30) * 110).rounded()) }
    }

    /// The average needed across everything still to sit, to finish on a target.
    ///
    /// Returns a figure above 30 when the target is out of reach rather than clamping: a
    /// clamped 30 would read as “get top marks and you are fine”. Use ``isReachable(_:)``
    /// for the yes-or-no question.
    ///
    /// - Parameter target: The final average wanted.
    /// - Returns: The average needed, or `nil` when there is nothing left to sit.
    func requiredAverage(for target: Double) -> Double? {
        guard remainingCFU > 0 else { return nil }
        let doneWeight = (weightedMean ?? 0) * Double(gradedCFU)
        let totalWeight = target * Double(gradedCFU + remainingCFU)
        return (totalWeight - doneWeight) / Double(remainingCFU)
    }

    /// Whether a target average is still attainable.
    ///
    /// - Parameter target: The final average wanted.
    /// - Returns: `true` when the required average is at most 30. With nothing left to sit,
    ///   whether the current average already meets the target.
    func isReachable(_ target: Double) -> Bool {
        guard let needed = requiredAverage(for: target) else {
            return (weightedMean ?? 0) >= target
        }
        return needed <= 30
    }

    /// What the average becomes if everything left is passed at one mark.
    ///
    /// - Parameter grade: The mark to assume.
    /// - Returns: The projected average. The current average when nothing is left to sit,
    ///   and `nil` when there is nothing to project from.
    func projectedMean(assuming grade: Double) -> Double? {
        guard remainingCFU > 0 else { return weightedMean }
        guard let mean = weightedMean else {
            return gradedCFU == 0 && !exams.isEmpty ? grade : nil
        }
        let doneWeight = mean * Double(gradedCFU)
        return (doneWeight + grade * Double(remainingCFU))
            / Double(gradedCFU + remainingCFU)
    }

    /// Each marked teaching in the order it was sat, with the weighted average as it stood
    /// once that mark was recorded.
    ///
    /// This is what a student means by how they are doing: not the marks, which bounce, but
    /// the line they add up to. Each step recomputes the average over everything up to that
    /// point, so every value is the same arithmetic as ``weightedMean`` and the last is that
    /// figure exactly.
    ///
    /// Only dated marks take part: an exam with no date has no place on a time axis.
    var progression: [(exam: LibrettoExam, mean: Double)] {
        let dated = graded
            .filter { $0.date != nil }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        return dated.indices.compactMap { index in
            guard let mean = StudyPlan(exams: Array(dated[...index])).weightedMean else { return nil }
            return (exam: dated[index], mean: mean)
        }
    }

    /// The most recently sat teaching carrying a numeric mark.
    ///
    /// Undated marks are excluded: “most recent” is a question about time.
    var lastGraded: LibrettoExam? {
        graded
            .filter { $0.date != nil }
            .max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    /// How far the weighted average moved when ``lastGraded`` was recorded.
    ///
    /// Which way an average is going is the most interesting thing about it, and a student
    /// cannot get that from a number alone. Both sides are computed by the same arithmetic
    /// as ``weightedMean``, so the difference is honest even where it is a tenth off the
    /// official figure.
    ///
    /// `nil` until there are two marks to have moved between.
    var meanDelta: Double? {
        guard let last = lastGraded else { return nil }
        let before = StudyPlan(exams: exams.filter { $0.id != last.id })
        guard let previous = before.weightedMean, let current = weightedMean else { return nil }
        return current - previous
    }

    /// The group name for everything still to sit, which has no academic year to be grouped
    /// under.
    static let pendingGroup = String(localized: "Da sostenere")

    /// The plan grouped for display: what is left first, then the academic years the rest was
    /// sat in, newest first.
    ///
    /// Years come from ``LibrettoExam/academicYear(calendar:)``, which reads them off the
    /// date of the sitting. Within a year, the newest sitting leads and undated teachings
    /// sort by name at the end.
    ///
    /// What is left leads rather than trailing, since it is the only group with anything to
    /// do in it.
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

    /// The weighted average of one slice of a plan, for a year's own line.
    ///
    /// - Parameter exams: The teachings to average.
    /// - Returns: The average, or `nil` when none carries a mark.
    static func mean(of exams: [LibrettoExam]) -> Double? {
        StudyPlan(exams: exams).weightedMean
    }

    /// Credits earned in one slice of a plan.
    ///
    /// - Parameter exams: The teachings to total.
    /// - Returns: The credits of those passed.
    static func earnedCFU(of exams: [LibrettoExam]) -> Int {
        exams.filter(\.isPassed).reduce(0) { $0 + ($1.cfu ?? 0) }
    }
}

/// What a study plan is for, from `GET {libretto}/testatapiano/{matricola}`.
///
/// The payload's shape is not confirmed, so every field is optional and read across
/// candidate names: the header is decoration around the teaching list, and a missing
/// field must not cost the screen. The payload's shape is logged in debug builds.
///
/// ``degreeCode`` and ``planCode`` matter beyond display: they are the manifesto's own
/// keys, which make finding the programme exact rather than inferred from a name.
nonisolated struct StudyPlanHeader: Sendable, Equatable, Codable {
    /// The degree course's name.
    let course: String?
    /// The plan's academic year, as the service writes it.
    let year: String?
    /// The orientation or curriculum within the course.
    let track: String?
    /// The credits the plan totals.
    let totalCFU: Int?
    /// `k_corso_la`, the manifesto's key for the degree course.
    var degreeCode: String? = nil
    /// `k_indir`, the manifesto's key for the plan within it.
    var planCode: String? = nil
    /// `tipoCorso`, for example “LAUREA DI PRIMO LIVELLO”, which tells a bachelor's from a
    /// master's of the same name. The careers list says only “Studente”.
    var level: String? = nil
    /// The degree course's English name, where the service sends one.
    var englishCourse: String? = nil

    /// ``year`` as the manifesto keys it — `"2025"` for `"2025/26"` — or `nil` when it does
    /// not begin with four digits.
    var yearCode: String? {
        guard let prefix = year?.prefix(4), prefix.count == 4, prefix.allSatisfy(\.isNumber) else { return nil }
        return String(prefix)
    }

    /// Reads a header out of a decoded payload, trying candidate key spellings for each
    /// field.
    ///
    /// - Parameter value: The payload, as an object or the first element of an array.
    /// - Returns: `nil` when nothing readable was found, which is not a header.
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

    /// Creates a header directly, for tests and previews.
    ///
    /// - Parameters:
    ///   - course: The degree course's name.
    ///   - year: The plan's academic year.
    ///   - track: The orientation within the course.
    ///   - totalCFU: The credits the plan totals.
    init(course: String?, year: String?, track: String?, totalCFU: Int?) {
        self.course = course
        self.year = year
        self.track = track
        self.totalCFU = totalCFU
    }
}
