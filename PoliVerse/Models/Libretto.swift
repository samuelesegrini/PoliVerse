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

    var isPassed: Bool {
        if let grade { return grade >= 18 }
        // A recorded status with a date and no mark is how pass/fail teachings
        // ("idoneità") appear.
        return date != nil && statusText?.isEmpty == false
    }

    /// `30L` for a mark with honours, matching how the official app renders it.
    var displayGrade: String {
        guard let grade, grade > 0 else { return "—" }
        return hasLode ? "\(grade)L" : String(grade)
    }
}

/// `GET {libretto}/elencoinsegnamenti/{matricola}`
///
/// Field names taken from the official app's own rendering:
///
/// ```js
/// _.stato_esame_desc
/// Im(_.data_esame).format("DD")  …  .format("MMM YYYY")
/// _.voto_esame > 0 ? _.voto_esame : "-",  _.lode === "S" ? "L" : ""
/// ```
nonisolated struct LibrettoEntryDTO: Decodable, Sendable {
    let c_insegn: String?
    let descrizione: String?
    let descrizione_eng: String?
    /// Numeric upstream, but tolerated as a string — see ``LooseInt``.
    let voto_esame: LooseInt?
    /// `"S"` for honours.
    let lode: String?
    let cfu: LooseInt?
    let data_esame: String?
    let stato_esame_desc: String?
    let posins: String?

    func toExam() -> LibrettoExam? {
        guard let c_insegn, let descrizione, !descrizione.isEmpty else { return nil }
        let mark = voto_esame?.value
        return LibrettoExam(
            id: c_insegn,
            name: Course.normalise(descrizione),
            grade: (mark ?? 0) > 0 ? mark : nil,
            hasLode: lode?.uppercased() == "S",
            cfu: cfu?.value,
            date: data_esame.flatMap(PoliMiDate.parse),
            statusText: stato_esame_desc
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
