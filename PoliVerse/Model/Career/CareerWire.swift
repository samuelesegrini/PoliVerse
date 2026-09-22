import Foundation

// The shapes the Politecnico's career services send, and nothing else.
//
// Kept apart from the types the rest of the app reasons about because the
// endpoints move without notice (`docs/endpoint-status.md`). When one of them
// changes shape, this file changes and nothing else does.

/// The aggregate figures as `GET {app}/v1/io-e-polimi/{matricola}` sends them.
nonisolated struct GradeBookDTO: Decodable, Sendable {
    /// The exam counters, where the payload carries them.
    struct ExamStats: Decodable, Sendable {
        /// Exams the study plan contains.
        let planned: Int?
        /// Sittings the student is enrolled in.
        let subscribed: Int?
        /// Exams with a recorded result.
        let given: Int?
    }

    /// The credit-weighted average, out of 30.
    let mean: Double?
    /// Credits already earned.
    let given_cfu: Int?
    /// Credits the study plan totals.
    let planned_cfu: Int?
    /// The exam counters. Absent from the current endpoint, so the counts come from
    /// ``ExamCountersDTO`` instead.
    let exam_stats: ExamStats?

    /// Converts the payload into a ``GradeBook``, treating every missing figure as zero.
    ///
    /// - Returns: The grade book.
    func toGradeBook() -> GradeBook {
        GradeBook(
            mean: mean ?? 0,
            earnedCFU: given_cfu ?? 0,
            plannedCFU: planned_cfu ?? 0,
            examsPlanned: exam_stats?.planned ?? 0,
            examsSubscribed: exam_stats?.subscribed ?? 0,
            examsGiven: exam_stats?.given ?? 0
        )
    }
}

/// How many sittings the student is enrolled in and how many results have been
/// published, from `GET {iae}/v1/base/counters`.
nonisolated struct ExamCountersDTO: Decodable, Sendable {
    /// Sittings enrolled in.
    let num_iscriz: Int?
    /// Results published.
    let num_esiti: Int?
}

/// One exam sitting, as the exams endpoint nests it under a teaching.
nonisolated struct ExamDTO: Decodable, Sendable {
    /// The student's own enrolment in this sitting, present only when they enrolled.
    struct ActiveSubscription: Decodable, Sendable {
        /// The enrolment's identifier.
        let c_iscriz: Int?
        /// The recorded outcome, as text.
        let verb_esito: String?
        /// The recorded outcome as a number, where it has one.
        let verb_esito_number: Int?
        /// Upstream's pass flag, `"S"` for a pass.
        let verb_positivo: String?
        /// The outcome as it is meant to be displayed.
        let xverbEsito: String?
        /// Whether a result has been published.
        let hasEsito: Bool?
        /// Whether the mark may still be refused.
        let rifiutabile: Bool?
        /// Whether the marked script can be inspected. Filled in by ``CareerSource`` from a
        /// separate call rather than by this payload.
        var hasCorrezioni: Bool? = nil
    }

    /// The sitting's identifier.
    let c_appello: Int
    /// The sitting's date, without a time.
    let d_app: String?
    /// The sitting's time of day, sent separately from the date.
    let ora_ok: String?
    /// When the enrolment window opens.
    let d_apertura: String?
    /// When the enrolment window closes.
    let d_chiusura: String?
    /// How many students are enrolled.
    let numIscrittiAppello: Int?
    /// The sitting's type, which is what names a partial exam.
    let descTipoAppello: String?
    /// The room, once published.
    let xaula: String?
    /// The student's own enrolment, when they enrolled.
    let iscrizioneAttiva: ActiveSubscription?
    /// Whether the enrolment window is currently open.
    let iscrizioniAperte: Bool?

    /// Converts the payload into an ``ExamSession``.
    ///
    /// The status is decided in order: a published result becomes
    /// ``ExamStatus/graded(_:)``, an enrolment ``ExamStatus/enrolled``, an open window
    /// ``ExamStatus/open``, a window whose opening is still ahead
    /// ``ExamStatus/notYetOpen``, and anything else ``ExamStatus/closed``.
    ///
    /// A pass is read from upstream's own flag, or from a mark of at least 18, rather
    /// than by parsing the outcome text — which can be a number, `"SUPERATO"`,
    /// `"IDONEO"` or `"30 e lode"`. The date and the time arrive in separate fields and
    /// are combined here.
    ///
    /// - Parameters:
    ///   - courseName: The teaching's name, title-cased on the way in.
    ///   - courseCode: The teaching's code.
    ///   - teacher: The examining lecturer.
    /// - Returns: The sitting.
    func toSession(courseName: String, courseCode: String, teacher: String?) -> ExamSession {
        let subscription = iscrizioneAttiva
        let status: ExamStatus

        if let subscription, subscription.hasEsito == true {
            // "positivo" is upstream's own pass flag; trust it over parsing the
            // mark text, which can be "SUPERATO", "IDONEO", "30 e lode", …
            let passed = (subscription.verb_positivo ?? "").uppercased().hasPrefix("S")
                || (subscription.verb_esito_number ?? 0) >= 18
            status = .graded(
                ExamGrade(
                    value: subscription.verb_esito_number,
                    text: subscription.xverbEsito ?? subscription.verb_esito ?? "—",
                    passed: passed,
                    refusable: subscription.rifiutabile ?? false
                )
            )
        } else if subscription != nil {
            status = .enrolled
        } else if iscrizioniAperte == true {
            status = .open
        } else if let opens = d_apertura.flatMap(PoliMiDate.parse), opens > .now {
            status = .notYetOpen
        } else {
            status = .closed
        }

        // The sitting's date and its time arrive in separate fields.
        var when = d_app.flatMap(PoliMiDate.parse)
        if let base = when, let time = ora_ok, !time.isEmpty {
            when = PoliMiDate.applying(time: time, to: base) ?? base
        }

        return ExamSession(
            id: c_appello,
            courseName: Course.normalise(courseName),
            courseCode: courseCode,
            teacher: teacher?.capitalized,
            date: when,
            room: xaula?.isEmpty == false ? xaula : nil,
            enrolmentOpens: d_apertura.flatMap(PoliMiDate.parse),
            enrolmentCloses: d_chiusura.flatMap(PoliMiDate.parse),
            enrolledCount: numIscrittiAppello,
            kind: descTipoAppello,
            status: status,
            hasCorrections: subscription?.hasCorrezioni ?? false
        )
    }
}

/// The answer to `GET {libretto}/elencoinsegnamenti/{matricola}`.
///
/// An object rather than an array: the server has already split the teachings into
/// those passed and those still to sit.
nonisolated struct LibrettoResponse: Decodable, Sendable {
    /// The teachings already passed.
    let sostenuti: [LibrettoEntryDTO]?
    /// The teachings still to sit.
    let daSostenere: [LibrettoEntryDTO]?

    /// Every teaching, passed first and then pending, each flagged by which list it came
    /// from — which is more reliable than inferring it, since a pass/fail teaching
    /// carries no mark.
    var allExams: [LibrettoExam] {
        (sostenuti ?? []).compactMap { $0.toExam(passed: true) }
            + (daSostenere ?? []).compactMap { $0.toExam(passed: false) }
    }
}

/// One row of the libretto.
///
/// ```json
/// {"id_riga":47314209,"descrizione":"ALGORITMI E PRINCIPI DELL'INFORMATICA",
///  "descrizione_eng":"ALGORITHMS AND PRINCIPLES OF COMPUTER SCIENCE",
///  "stato_esame":"S","stato_esame_desc":"SUPERATO","cfu_conv_parz":0,
///  "posins":"E","posins_desc":"Effettivo",
///  "data_esame":1750197600000,"data_esame_string":null,"voto_esame":…}
/// ```
nonisolated struct LibrettoEntryDTO: Decodable, Sendable {
    /// The row's own identifier. There is no course code in this payload, so this is what
    /// makes a row unique when ``c_insegn`` is absent.
    let id_riga: LooseInt?
    /// The teaching's code, where the row carries one.
    let c_insegn: String?
    /// The teaching's Italian name. A row without one is unusable.
    let descrizione: String?
    /// The teaching's English name, which is how a teaching is recognised in the
    /// manifesto when the row has no code.
    let descrizione_eng: String?
    /// The mark, where one is recorded.
    let voto_esame: LooseInt?
    /// `"S"` when the mark carries honours.
    let lode: String?
    /// The credit count, under its plainest spelling.
    let cfu: LooseInt?
    /// A second spelling of the credit count.
    let cfu_conv_parz: LooseInt?
    /// A third spelling of the credit count.
    let crediti: LooseInt?
    /// When the exam was sat, in epoch milliseconds rather than as a date string.
    let data_esame: LooseDouble?
    /// The textual form of the exam date, usually null.
    let data_esame_string: String?
    /// The status code, `"S"` for passed.
    let stato_esame: String?
    /// The status in words, for example `"SUPERATO"`.
    let stato_esame_desc: String?
    /// The teaching's position in the plan, `"E"` for a required one.
    let posins: String?

    /// The credit count, taking the first of the three spellings that carries a positive
    /// number, or `nil` when none does.
    private var creditValue: Int? {
        for candidate in [cfu?.value, crediti?.value, cfu_conv_parz?.value] {
            if let candidate, candidate > 0 { return candidate }
        }
        return nil
    }

    /// When the exam was sat, from the epoch milliseconds where present and from the
    /// textual form otherwise. `nil` when neither is usable.
    private var examDate: Date? {
        if let millis = data_esame?.value, millis > 0 {
            return Date(timeIntervalSince1970: millis / 1000)
        }
        return data_esame_string.flatMap(PoliMiDate.parse)
    }

    /// Converts the row into a ``LibrettoExam``.
    ///
    /// The identity is the teaching code, falling back to the row id and then to the
    /// name. A non-positive mark becomes `nil`, since that is how a pass/fail teaching
    /// arrives.
    ///
    /// - Parameter passed: Which of the server's two lists the row came from. More
    ///   reliable than inferring it, since a pass/fail teaching carries no mark.
    /// - Returns: The teaching, or `nil` when the row has no name.
    func toExam(passed: Bool) -> LibrettoExam? {
        guard let descrizione, !descrizione.isEmpty else { return nil }
        let mark = voto_esame?.value

        return LibrettoExam(
            id: c_insegn ?? id_riga?.value.map(String.init) ?? descrizione,
            name: Course.normalise(descrizione),
            grade: (mark ?? 0) > 0 ? mark : nil,
            hasLode: lode?.uppercased() == "S",
            cfu: creditValue,
            date: examDate,
            statusText: stato_esame_desc?.capitalized,
            isPassed: passed,
            englishName: descrizione_eng
        )
    }
}

/// The study plan's header, from `GET {libretto}/testatapiano/{matricola}`.
nonisolated struct LibrettoHeaderDTO: Decodable, Sendable {
    /// The current credit-weighted average.
    let mediaAttuale: LooseDouble?
    /// Credits recorded so far.
    let cfuRegistrati: LooseInt?
    /// Credits the plan totals.
    let cfuPianificati: LooseInt?
    /// Credits required for the degree.
    let cfuLaurea: LooseInt?
    /// The degree programme's name.
    let descrizioneCDL: String?
}

/// An integer that may arrive as a number or as a quoted string.
///
/// These endpoints are inconsistent about it, and being strict would lose a whole row
/// over a formatting choice.
nonisolated struct LooseInt: Decodable, Sendable, Hashable {
    /// The parsed integer, or `nil` when the value was neither a number nor a numeric string.
    let value: Int?

    /// Decodes an integer, a double truncated to an integer, or a numeric string with
    /// either decimal separator.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Never; an unrecognised value yields a `nil` ``value``.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = Int(double) }
        else if let string = try? container.decode(String.self) {
            value = Int(string) ?? Int(Double(string.replacingOccurrences(of: ",", with: ".")) ?? .nan)
        } else { value = nil }
    }
}

/// A double that may arrive as a number or as a quoted string, including one written
/// with an Italian decimal comma.
nonisolated struct LooseDouble: Decodable, Sendable, Hashable {
    /// The parsed number, or `nil` when the value was not numeric.
    let value: Double?

    /// Decodes a double, an integer, or a numeric string with either decimal separator.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: Never; an unrecognised value yields a `nil` ``value``.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) { value = double }
        else if let int = try? container.decode(Int.self) { value = Double(int) }
        else if let string = try? container.decode(String.self) {
            // Italian decimal commas appear here.
            value = Double(string.replacingOccurrences(of: ",", with: "."))
        } else { value = nil }
    }
}
