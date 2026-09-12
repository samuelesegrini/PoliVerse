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
            },
            summary: summary,
            ssd: ssd(html),
            modules: modules(html))
    }

    /// The SSD table: attività formativa, code, description, credits.
    static func ssd(_ html: String) -> [ManifestoSSD] {
        HTMLScraper.rows(in: html).compactMap { row in
            let cells = row.map(HTMLScraper.text)
            // An SSD code is the giveaway: two to four letters, a slash, two
            // digits. No other column in these pages looks like that.
            guard
                let index = cells.firstIndex(where: {
                    $0.range(of: "^[A-Z]{2,7}/[0-9]{2}$", options: .regularExpression) != nil
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
    static func modules(_ html: String) -> [ManifestoModule] {
        var found: [ManifestoModule] = []
        for row in HTMLScraper.rows(in: html) {
            guard row.count >= 4 else { continue }
            let cells = row.map(HTMLScraper.text)

            // A module row is identified by its six-digit teaching code.
            guard
                let codeIndex = cells.firstIndex(where: {
                    $0.range(of: "^[0-9]{6}$", options: .regularExpression) != nil
                })
            else { continue }

            let teacherCells = row.filter {
                $0.localizedCaseInsensitiveContains("RicercaPerDocentiPublic")
            }
            let teachers = teacherCells.flatMap(self.teachers(in:))

            // The bracket is the pair of short uppercase cells before the
            // code — "A" and "ZZZZ" in the common single-bracket case.
            let bounds = cells[..<codeIndex].filter {
                $0.range(of: "^[A-Z]{1,4}$", options: .regularExpression) != nil
            }

            found.append(ManifestoModule(
                code: cells[codeIndex],
                name: cells.dropFirst(codeIndex + 1).first { $0.count > 5 } ?? "",
                teachers: teachers,
                credits: cells.compactMap(credits(from:)).first,
                period: cells.first { $0.contains("sem") || $0.contains("trim") },
                language: nil,
                scaglioneFrom: bounds.first,
                scaglioneTo: bounds.count > 1 ? bounds[1] : nil,
                syllabusID: row.compactMap(syllabusID(in:)).first))
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

    /// `SchedaPublic.do` — headings and prose, not a card table.
    static func syllabus(_ html: String) -> Syllabus {
        var sections: [(title: String, body: String)] = []

        // Each section is a titled block; the service marks titles with its
        // own class and the body follows until the next one.
        let pattern = "<[^>]*class=\"[^\"]*(?:TitoloScheda|titolo|SectionTitle|BoxTitle)[^\"]*\"[^>]*>(.*?)</[a-z]+>(.*?)(?=<[^>]*class=\"[^\"]*(?:TitoloScheda|titolo|SectionTitle|BoxTitle)|\\z)"
        for groups in HTMLScraper.matches(pattern, in: html) where groups.count >= 2 {
            let title = HTMLScraper.text(groups[0])
            let body = HTMLScraper.text(groups[1])
            guard !title.isEmpty, !body.isEmpty else { continue }
            sections.append((title, body))
        }

        // Fallback: the page varies between schools, so when the classes do
        // not match, fall back to the known headings in document order.
        if sections.isEmpty {
            let known = ["Obiettivi dell'insegnamento", "Risultati di apprendimento attesi",
                         "Argomenti trattati", "Prerequisiti",
                         "Modalità di valutazione", "Bibliografia"]
            let plain = HTMLScraper.text(html)
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
        return Syllabus(sections: sections)
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
