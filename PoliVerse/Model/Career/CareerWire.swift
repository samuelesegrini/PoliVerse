import Foundation

/// The shapes the Politecnico's career services send, and nothing else.
///
/// Kept apart from the types the rest of the app reasons about because the
/// endpoints move without notice (`docs/endpoint-status.md`). When one of them
/// changes shape, this file changes and nothing else does.

nonisolated struct GradeBookDTO: Decodable, Sendable {
    struct ExamStats: Decodable, Sendable {
        let planned: Int?
        let subscribed: Int?
        let given: Int?
    }

    let mean: Double?
    let given_cfu: Int?
    let planned_cfu: Int?
    /// Present on the old endpoint; the official app does not read it from the
    /// new one, so treat it as optional and fill the counts from
    /// ``ExamCountersDTO`` instead.
    let exam_stats: ExamStats?

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

/// `GET {iae}/v1/base/counters` — how many exams the student is signed up for
/// and how many results have been published.
///
/// Read straight off the official app's exams card:
///
/// ```js
/// children: v.num_iscriz   // IOEPOLIMI_EXAMS_ISCRIZ
/// children: v.num_esiti    // IOEPOLIMI_EXAMS_SOSTEN
/// ```
nonisolated struct ExamCountersDTO: Decodable, Sendable {
    let num_iscriz: Int?
    let num_esiti: Int?
}

nonisolated struct ExamDTO: Decodable, Sendable {
    struct ActiveSubscription: Decodable, Sendable {
        let c_iscriz: Int?
        let verb_esito: String?
        let verb_esito_number: Int?
        let verb_positivo: String?
        let xverbEsito: String?
        let hasEsito: Bool?
        let rifiutabile: Bool?
        var hasCorrezioni: Bool? = nil
    }

    let c_appello: Int
    let d_app: String?
    let ora_ok: String?
    let d_apertura: String?
    let d_chiusura: String?
    let numIscrittiAppello: Int?
    let descTipoAppello: String?
    let xaula: String?
    let iscrizioneAttiva: ActiveSubscription?
    let iscrizioniAperte: Bool?

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

/// `GET {libretto}/elencoinsegnamenti/{matricola}`
///
/// The response is an object, not an array, and the server has already done
/// the split this screen wants:
///
/// ```json
/// {"daSostenere": [...], "sostenuti": [...]}
/// ```
nonisolated struct LibrettoResponse: Decodable, Sendable {
    let sostenuti: [LibrettoEntryDTO]?
    let daSostenere: [LibrettoEntryDTO]?

    /// Passed first, then pending — each already flagged by which list it came
    /// from, which is more reliable than inferring it from the fields.
    var allExams: [LibrettoExam] {
        (sostenuti ?? []).compactMap { $0.toExam(passed: true) }
            + (daSostenere ?? []).compactMap { $0.toExam(passed: false) }
    }
}

/// One row of the libretto.
///
/// Shape confirmed against a real account:
///
/// ```json
/// {"id_riga":47314209,"descrizione":"ALGORITMI E PRINCIPI DELL'INFORMATICA",
///  "descrizione_eng":"ALGORITHMS AND PRINCIPLES OF COMPUTER SCIENCE",
///  "stato_esame":"S","stato_esame_desc":"SUPERATO","cfu_conv_parz":0,
///  "posins":"E","posins_desc":"Effettivo",
///  "data_esame":1750197600000,"data_esame_string":null,"voto_esame":…}
/// ```
nonisolated struct LibrettoEntryDTO: Decodable, Sendable {
    /// The row's own identity. There is no course code in this payload, so
    /// this is what makes a row unique.
    let id_riga: LooseInt?
    let c_insegn: String?
    let descrizione: String?
    let descrizione_eng: String?
    let voto_esame: LooseInt?
    /// `"S"` for honours.
    let lode: String?
    /// The plain credit count is not always present; several spellings appear
    /// across these endpoints, so try each rather than lose the value.
    let cfu: LooseInt?
    let cfu_conv_parz: LooseInt?
    let crediti: LooseInt?
    /// **Epoch milliseconds**, not a date string. `data_esame_string` is the
    /// textual form and is usually null.
    let data_esame: LooseDouble?
    let data_esame_string: String?
    let stato_esame: String?
    let stato_esame_desc: String?
    let posins: String?

    private var creditValue: Int? {
        for candidate in [cfu?.value, crediti?.value, cfu_conv_parz?.value] {
            if let candidate, candidate > 0 { return candidate }
        }
        return nil
    }

    private var examDate: Date? {
        if let millis = data_esame?.value, millis > 0 {
            return Date(timeIntervalSince1970: millis / 1000)
        }
        return data_esame_string.flatMap(PoliMiDate.parse)
    }

    /// - Parameter passed: which of the server's two lists this row came from.
    ///   More reliable than inferring it, since a pass/fail teaching carries no
    ///   numeric mark.
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

/// `GET {libretto}/testatapiano/{matricola}` — the plan's header.
nonisolated struct LibrettoHeaderDTO: Decodable, Sendable {
    let mediaAttuale: LooseDouble?
    let cfuRegistrati: LooseInt?
    let cfuPianificati: LooseInt?
    let cfuLaurea: LooseInt?
    let descrizioneCDL: String?
}

/// An integer that may arrive as a number or a string.
///
/// These endpoints are inconsistent about it — `voto_esame` is compared
/// numerically in the official app but the plan header sends several numbers
/// quoted. Being strict here loses the whole row for a formatting choice.
nonisolated struct LooseInt: Decodable, Sendable, Hashable {
    let value: Int?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = Int(double) }
        else if let string = try? container.decode(String.self) {
            value = Int(string) ?? Int(Double(string.replacingOccurrences(of: ",", with: ".")) ?? .nan)
        } else { value = nil }
    }
}

nonisolated struct LooseDouble: Decodable, Sendable, Hashable {
    let value: Double?

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
