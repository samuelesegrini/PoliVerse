import Foundation

/// Turns Manifesti pages into values.
///
/// Kept apart from the networking so it can be tested against saved markup,
/// which is the only way to test a scraper honestly: the fixtures in the test
/// suite are real fragments taken from the live service.
nonisolated enum ManifestoParser {
    // MARK: - Search results

    /// Rows of a `RicercaPerInsegnamentoPublic` result page.
    ///
    /// The link is the identity: it carries `k_corso_la`, `k_indir`,
    /// `idItemOfferta` and `idRiga`, and no combination of the visible columns
    /// substitutes for them.
    static func searchResults(_ html: String) -> [ManifestoTeaching] {
        var found: [ManifestoTeaching] = []
        var seen: Set<String> = []

        for row in HTMLScraper.rows(in: html) {
            guard
                let linkCell = row.first(where: {
                    $0.localizedCaseInsensitiveContains("EVN_DETTAGLIO_RIGA_MANIFESTO")
                }),
                let href = HTMLScraper.href(in: linkCell),
                let code = HTMLScraper.queryValue("codDescr", in: href),
                let courseCode = HTMLScraper.queryValue("k_corso_la", in: href)
            else { continue }

            let cells = row.map(HTMLScraper.text)
            let name = HTMLScraper.text(linkCell).nonEmpty
                ?? cells.first { $0.count > 6 && $0 != code } ?? code

            let teaching = ManifestoTeaching(
                code: code,
                name: name,
                courseCode: courseCode,
                planCode: HTMLScraper.queryValue("k_indir", in: href),
                idItemOfferta: HTMLScraper.queryValue("idItemOfferta", in: href),
                idRiga: HTMLScraper.queryValue("idRiga", in: href),
                semester: HTMLScraper.queryValue("semestre", in: href),
                year: HTMLScraper.queryValue("aa", in: href),
                credits: cells.compactMap(credits(from:)).first,
                school: nil,
                degreeCourse: cells.first { $0.contains("(") && $0.count > 12 })

            // The same teaching appears once per module row; keep the first.
            guard seen.insert(teaching.id).inserted else { continue }
            found.append(teaching)
        }
        return found
    }

    // MARK: - Teaching detail

    static func detail(_ html: String, code: String) -> ManifestoDetail? {
        let context = HTMLScraper.section("Contesto", in: html).map(HTMLScraper.cardPairs) ?? []
        let scheda = HTMLScraper.section("Scheda Insegnamento", in: html)
        let facts = scheda.map(HTMLScraper.cardPairs) ?? []

        let name = facts.first { $0.label.localizedCaseInsensitiveContains("Denominazione") }?.value
            ?? HTMLScraper.cardValue("Denominazione Insegnamento", in: html)
            ?? code
        let summary = facts.first {
            $0.label.localizedCaseInsensitiveContains("Programma sintetico")
        }?.value

        guard !context.isEmpty || !facts.isEmpty else { return nil }

        return ManifestoDetail(
            code: HTMLScraper.cardValue("Codice Identificativo", in: html) ?? code,
            name: name,
            context: context,
            // The programme is prose and gets its own presentation, so it is
            // not repeated among the key/value rows.
            facts: facts.filter {
                !$0.label.localizedCaseInsensitiveContains("Programma sintetico")
                    && !$0.label.localizedCaseInsensitiveContains("Denominazione")
                    // The SSD heading sits in the card as a label whose
                    // "value" is the table header; the table is read apart.
                    && !$0.label.localizedCaseInsensitiveContains("Settori Scientifico")
            },
            summary: summary,
            ssd: ssd(html),
            modules: modules(html, teachingCode: HTMLScraper.cardValue("Codice Identificativo", in: html) ?? code,
                             teachingName: name),
            languages: languages(html))
    }

    /// The SSD table: attività formativa, code, description, credits.
    static func ssd(_ html: String) -> [ManifestoSSD] {
        HTMLScraper.rows(in: html).compactMap { row in
            let cells = row.map(HTMLScraper.text)
            // An SSD code is the giveaway: letters, a slash, two digits
            // (`MAT/05`, `ING-INF/05`), or since the 2024 reform letters, a dash, two
            // digits and a letter (`IINF-05/A`). Nothing else looks like it.
            guard
                let index = cells.firstIndex(where: {
                    $0.range(of: "^([A-Z]{2,7}(-[A-Z]{2,4})?/[0-9]{2}|[A-Z]{2,7}-[0-9]{2}/[A-Z])$", options: .regularExpression) != nil
                })
            else { return nil }
            return ManifestoSSD(
                code: cells[index],
                name: index + 1 < cells.count ? cells[index + 1] : "",
                credits: cells.compactMap(credits(from:)).last,
                kind: index > 0 ? cells[index - 1].nonEmpty : nil)
        }
    }

    /// The module table, which is where the scaglioni and the lecturers live.
    ///
    /// - Parameters:
    ///   - teachingCode: the teaching's own code, for the single row of a
    ///     teaching with one module — that row has no code column.
    static func modules(_ html: String, teachingCode: String? = nil, teachingName: String? = nil) -> [ManifestoModule] {
        var found: [ManifestoModule] = []
        for row in HTMLScraper.rows(in: html) {
            guard row.count >= 4 else { continue }
            let cells = row.map(HTMLScraper.text)
            let teacherCells = row.filter {
                $0.localizedCaseInsensitiveContains("RicercaPerDocentiPublic")
            }

            // A module row is identified by its six-digit teaching code; a
            // single-module teaching's row has none, but has its teachers.
            let codeIndex = cells.firstIndex(where: {
                $0.range(of: "^[0-9]{6}$", options: .regularExpression) != nil
            })
            let code: String
            let name: String
            let beforeDetails: ArraySlice<String>
            if let codeIndex {
                code = cells[codeIndex]
                name = cells.dropFirst(codeIndex + 1).first { $0.count > 5 } ?? ""
                beforeDetails = cells[..<codeIndex]
            } else if let teachingCode, !teacherCells.isEmpty,
                      let teacherIndex = row.firstIndex(where: { $0.localizedCaseInsensitiveContains("RicercaPerDocentiPublic") }) {
                code = teachingCode
                name = teachingName ?? ""
                beforeDetails = cells[..<teacherIndex]
            } else {
                continue
            }

            // The bracket is the pair of short uppercase cells before the
            // code — "A" and "ZZZZ" in the common single-bracket case.
            let bounds = beforeDetails.filter {
                $0.range(of: "^[A-Z]{1,5}$", options: .regularExpression) != nil
            }
            // A row without a code is the teaching's own only when it carries
            // a full bracket: other tables link teachers too.
            guard codeIndex != nil || bounds.count == 2 else { continue }

            found.append(ManifestoModule(
                code: code,
                name: name,
                teachers: teacherCells.flatMap(self.teachers(in:)),
                credits: cells.compactMap(credits(from:)).first,
                period: cells.first { $0.contains("sem") || $0.contains("trim") },
                language: row.lazy.compactMap(language(in:)).first,
                scaglioneFrom: bounds.first,
                scaglioneTo: bounds.count > 1 ? bounds[1] : nil,
                syllabusID: row.compactMap(syllabusID(in:)).first))
        }
        return found
    }

    /// The language flag in one cell of a module row, if it has one.
    static func language(in cell: String) -> TeachingLanguage? {
        HTMLScraper.firstMatch(#"flags/([a-z]{2})\.png"#, in: cell, group: 1).flatMap(TeachingLanguage.init(flag:))
    }

    /// The languages flagged in the page's rows, in order and without repeats.
    ///
    /// Only data cells (`ElementInfoCard2`) count: the legend at the side of
    /// the page shows both flags in `ElementInfoCard1` cells, and reading it
    /// would call every teaching bilingual.
    static func languages(_ html: String) -> [TeachingLanguage] {
        var found: [TeachingLanguage] = []
        for groups in HTMLScraper.matches(#"<td[^>]*ElementInfoCard2[^>]*>\s*<img[^>]*flags/([a-z]{2})\.png"#, in: html) {
            guard let language = groups.first.flatMap(TeachingLanguage.init(flag:)),
                  !found.contains(language) else { continue }
            found.append(language)
        }
        return found
    }

    /// `c_classe` from the syllabus link the page hides behind an icon.
    static func syllabusID(in cell: String) -> String? {
        guard cell.localizedCaseInsensitiveContains("id_servizio=178"),
              let href = HTMLScraper.href(in: cell)
        else { return nil }
        return HTMLScraper.queryValue("c_classe", in: href)
    }

    static func teachers(in cell: String) -> [ManifestoTeacher] {
        HTMLScraper.matches("<a[^>]*href=\"([^\"]*k_doc=[^\"]*)\"[^>]*>(.*?)</a>", in: cell)
            .compactMap { groups in
                guard groups.count >= 2 else { return nil }
                let name = HTMLScraper.text(groups[1])
                guard !name.isEmpty else { return nil }
                return ManifestoTeacher(
                    name: name,
                    kDoc: HTMLScraper.queryValue("k_doc", in: groups[0].replacingOccurrences(
                        of: "&amp;", with: "&")))
            }
    }

    // MARK: - Syllabus

    /// `SchedaPublic.do` — titled cards, each read for what it holds.
    ///
    /// Every section starts with a `TitleInfoCard` cell. The prose ones stay
    /// prose; the summary, the exam list, the books, the hours and the
    /// language are read as data, because that is how they are used.
    static func syllabus(_ html: String) -> Syllabus {
        let clean = html
            .replacingOccurrences(of: "(?s)<style[^>]*>.*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "(?s)<script[^>]*>.*?</script>", with: "", options: [.regularExpression, .caseInsensitive])

        var syllabus = Syllabus(sections: [])
        var sections: [(title: String, body: String)] = []
        let cards = titledCards(clean)

        for (title, body) in cards {
            let key = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
            if key.hasPrefix("risorse bibliografiche") {
                continue   // the legend of the book icons
            } else if key.hasPrefix("scheda riassuntiva") {
                readSummary(body, into: &syllabus)
            } else if key.hasPrefix("modalita di valutazione") {
                // The first list is the service's own ("Prova scritta
                // obbligatoria…"); lists further down are the teacher's prose
                // and stay in the notes.
                let firstList = body.range(of: "(?s)<ul[^>]*>.*?</ul>", options: [.regularExpression, .caseInsensitive])
                let official = firstList.map { String(body[$0]) } ?? ""
                syllabus.assessment = HTMLScraper.matches("<li[^>]*>(.*?)</li>", in: official)
                    .compactMap { $0.first.map(HTMLScraper.text) }.filter { !$0.isEmpty }
                var rest = body
                if let firstList { rest.removeSubrange(firstList) }
                syllabus.assessmentNotes = HTMLScraper.text(rest).nonEmpty
                if let notes = syllabus.assessmentNotes { sections.append((title, notes)) }
            } else if key.hasPrefix("bibliografia") {
                syllabus.books = books(body)
                if syllabus.books.isEmpty, let text = HTMLScraper.text(body).nonEmpty { sections.append((title, text)) }
            } else if key.hasPrefix("software") {
                syllabus.software = HTMLScraper.text(body).nonEmpty
            } else if key.hasPrefix("forme didattiche") {
                readForms(body, into: &syllabus)
            } else if key.hasPrefix("informazioni in lingua inglese") {
                readEnglish(body, into: &syllabus)
            } else if let text = HTMLScraper.text(body).nonEmpty {
                sections.append((title, text))
            }
        }

        // Fallback for markup without titled cards: the known headings, in
        // document order, over the page's text.
        if cards.isEmpty {
            let known = ["Obiettivi dell'insegnamento", "Risultati di apprendimento attesi",
                         "Argomenti trattati", "Prerequisiti",
                         "Modalità di valutazione", "Bibliografia"]
            let plain = HTMLScraper.text(clean)
            var cursor = plain.startIndex
            var pending: (String, String.Index)?
            for heading in known {
                guard let range = plain.range(
                    of: heading, options: [.caseInsensitive], range: cursor..<plain.endIndex)
                else { continue }
                if let (title, start) = pending {
                    let body = String(plain[start..<range.lowerBound])
                    if let trimmed = body.nonEmpty { sections.append((title, trimmed)) }
                }
                pending = (heading, range.upperBound)
                cursor = range.upperBound
            }
            if let (title, start) = pending,
               let trimmed = String(plain[start...]).nonEmpty {
                sections.append((title, trimmed))
            }
        }
        syllabus.sections = sections
        return syllabus
    }

    /// Title and raw body of each card, in page order.
    private static func titledCards(_ html: String) -> [(String, String)] {
        let pattern = #"<td[^>]*class="TitleInfoCard"[^>]*>(.*?)</td>(.*?)(?=<td[^>]*class="TitleInfoCard"|\z)"#
        return HTMLScraper.matches(pattern, in: html).compactMap { groups in
            guard groups.count >= 2, let title = HTMLScraper.text(groups[0]).nonEmpty else { return nil }
            return (title, groups[1])
        }
    }

    private static func readSummary(_ body: String, into syllabus: inout Syllabus) {
        for (label, value) in HTMLScraper.cardPairs(in: body) {
            let key = label.lowercased()
            if key == "cfu" {
                syllabus.credits = Double(value.replacingOccurrences(of: ",", with: "."))
            } else if key.hasPrefix("tipo insegnamento") {
                syllabus.teachingType = value.nonEmpty
            }
        }
        if let teachersCell = HTMLScraper.firstMatch(
            #"Docenti[^<]*</td>\s*<td[^>]*>(.*?)</td>"#, in: body, group: 1) {
            syllabus.teachers = teachers(in: teachersCell)
        }
        // The degree-course table: course, plan, from, to, teaching.
        syllabus.brackets = HTMLScraper.rows(in: body).compactMap { row in
            guard row.count == 5,
                  row[4].range(of: "[0-9]{6}", options: .regularExpression) != nil
            else { return nil }
            let cells = row.map(HTMLScraper.text)
            guard let degree = cells[0].nonEmpty else { return nil }
            return SyllabusBracket(degreeCourse: degree, from: cells[2].nonEmpty, to: cells[3].nonEmpty)
        }
    }

    /// Books, split at each entry's required/optional icon.
    static func books(_ body: String) -> [SyllabusBook] {
        let pattern = #"<img[^>]*title="Risorsa bibliografica (obbligatoria|facoltativa)"[^>]*>(.*?)(?=<img[^>]*title="Risorsa bibliografica|\z)"#
        return HTMLScraper.matches(pattern, in: body).compactMap { groups in
            guard groups.count >= 2 else { return nil }
            let entry = groups[1]
            guard let title = HTMLScraper.firstMatch("<b[^>]*>(.*?)</b>", in: entry, group: 1)
                .map(HTMLScraper.text)?.nonEmpty else { return nil }
            let authors = HTMLScraper.firstMatch("<i[^>]*>(.*?)</i>", in: entry, group: 1).map(HTMLScraper.text)?.nonEmpty
            let url = HTMLScraper.firstMatch(#"<a[^>]*href="(https?://[^"]+)""#, in: entry, group: 1)
                .flatMap { URL(string: $0.replacingOccurrences(of: "&amp;", with: "&")) }
            // What follows the title, without the link and the separator.
            let after = entry.components(separatedBy: "</b>").dropFirst().joined(separator: "</b>")
            let details = HTMLScraper.text(after
                .replacingOccurrences(of: "(?s)<a[^>]*>.*?</a>", with: "", options: [.regularExpression, .caseInsensitive]))
                .trimmingCharacters(in: CharacterSet(charactersIn: ", ").union(.whitespacesAndNewlines))
                .nonEmpty
            return SyllabusBook(authors: authors, title: title, details: details, url: url,
                                isRequired: groups[0].lowercased() == "obbligatoria")
        }
    }

    private static func readForms(_ body: String, into syllabus: inout Syllabus) {
        for row in HTMLScraper.rows(in: body) {
            let cells = row.map(HTMLScraper.text)
            guard cells.count >= 2, let minutes = minutes(cells[1]) else { continue }
            let label = cells[0].lowercased()
            if label.contains("totale ore didattica assistita") {
                syllabus.assistedMinutes = minutes
            } else if label.contains("studio autonomo") {
                syllabus.selfStudyMinutes = minutes
            } else if minutes > 0 {
                syllabus.teachingForms.append(TeachingForm(name: cells[0], minutes: minutes))
            }
        }
    }

    /// `hh:mm` as minutes.
    private static func minutes(_ value: String) -> Int? {
        let parts = value.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    private static func readEnglish(_ body: String, into syllabus: inout Syllabus) {
        if body.localizedCaseInsensitiveContains("bandiera_inglese") {
            syllabus.language = .english
        } else if body.localizedCaseInsensitiveContains("bandiera_italiana") {
            syllabus.language = .italian
        }
        let text = HTMLScraper.text(body).lowercased()
        let offered: [(String, EnglishSupport)] = [
            ("slides in lingua inglese", .slides),
            ("libri di testo", .books),
            ("sostenere l'esame in lingua inglese", .exam),
            ("supporto didattico in lingua inglese", .tutoring),
        ]
        syllabus.englishSupport = offered.filter { text.contains($0.0) }.map(\.1)
    }

    // MARK: - Bits

    /// A credit figure: `10.0`, `5,0`, `2.5`. Rejects anything else numeric,
    /// so a six-digit teaching code never becomes a credit value.
    static func credits(from cell: String) -> Double? {
        guard cell.range(of: "^[0-9]{1,2}[.,][0-9]$", options: .regularExpression) != nil
        else { return nil }
        return Double(cell.replacingOccurrences(of: ",", with: "."))
    }
}
