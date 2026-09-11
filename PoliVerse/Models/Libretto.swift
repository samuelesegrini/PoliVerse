import Foundation

/// One teaching in the study plan, with its result if it has been sat.
///
/// This is the libretto — the record of what has actually been passed. It is a
/// different thing from an exam *sitting*: `/v1/insegn` lists sittings still
/// open to register for and is empty once everything is passed, which is
/// exactly when a student most wants to see their results.
nonisolated struct LibrettoExam: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    /// Absent until the exam is sat; also absent for pass/fail teachings.
    let grade: Int?
    let hasLode: Bool
    let cfu: Int?
    let date: Date?
    /// Upstream's own status wording, e.g. "Superato".
    let statusText: String?

    /// Taken from which list the server returned this row in, rather than
    /// inferred from the mark — a pass/fail teaching ("idoneità") is passed
    /// with no numeric mark at all.
    let isPassed: Bool

    /// `30L` for a mark with honours, matching how the official app renders it.
    var displayGrade: String {
        guard let grade, grade > 0 else { return "—" }
        return hasLode ? "\(grade)L" : String(grade)
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
            isPassed: passed
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
