import SwiftUI
import UIKit

/// The facts of a course, drawn as the course page is: its numbers in the
/// look's typeface, who teaches it and how to reach them, how the exam works,
/// the prove in itinere with their dates on a rail, and the codes to copy.
struct CourseInfoView: View {
    let course: Course

    @Environment(ManifestiModel.self) private var manifesti
    @Environment(StudyProgrammeModel.self) private var programmes
    @Environment(CareerModel.self) private var career
    @Environment(AgendaModel.self) private var agenda
    @Environment(UpdateFeed.self) private var feed
    @Environment(\.locale) private var locale
    @AppStorage(TodayStyle.storageKey) private var style = TodayStyle()
    @Environment(\.colorScheme) private var scheme

    private var ramp: CourseRamp { CourseRamp(course: course, style: style, scheme: scheme) }

    @State private var syllabus: Syllabus?
    @State private var pickTeachers: String?
    @State private var pickBracket: String?
    @State private var loading = true
    @State private var copied: String?

    private var accent: Color { Theme.accent(for: course) }

    /// Inside a card, rows keep off its edge; on a bare page they meet it.
    private var cardPadding: CGFloat { style.material.hasCard ? 14 : 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                hero
                facts
                teacher
                exam
                partialExams
                identifiers
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Informazioni")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: copied)
        .task {
            await agenda.load(around: .now)
            let pick = await programmes.pick(teachingCode: course.teachingCode, name: course.name,
                                             yearCode: course.academicYearStart, courseID: course.id)
            // Only from the student's own plan: the catalogue-wide fallback
            // may be another degree course, with other lecturers.
            if let pick, pick.matchesDegree {
                let module = pick.module
                if !pick.teachers.isEmpty { pickTeachers = pick.teachers.joined(separator: ", ") }
                if let from = module.scaglioneFrom, let to = module.scaglioneTo, from != "A" || to != "ZZZZ" {
                    pickBracket = "\(from) – \(to)"
                }
            }
            if let id = pick?.module.syllabusID { syllabus = await manifesti.syllabus(for: id) }
            loading = false
        }
    }

    // MARK: - Facts

    /// The subject's tile, the course and its teacher.
    private var hero: some View {
        let name = pickTeachers ?? course.teacher
        return CoursePageHero(
            tiles: [HeroTile(id: "subject", symbol: SubjectSymbol.symbol(for: course.name), colour: ramp.main)],
            placeholder: HeroTile(id: "empty", symbol: "info.circle", colour: ramp.main),
            title: Text(course.name),
            summary: name == "—" ? nil : Text(name),
            mode: ramp.mode)
    }

    /// Credits, semester and year on one strip, the numbers large.
    private var facts: some View {
        GlanceStrip(items: [
            course.cfu > 0 ? .init(id: "cfu", value: "\(course.cfu)", label: String(localized: "CFU")) : nil,
            course.semester != "—" ? .init(id: "semester", value: course.semester, label: String(localized: "semestre")) : nil,
            course.academicYear != "—"
                ? .init(id: "year", value: course.academicYear, label: String(localized: "anno accademico")) : nil,
        ].compactMap { $0 }, tint: ramp.main.color)
    }

    // MARK: - Teacher

    private var teacher: some View {
        let name = pickTeachers ?? course.teacher
        let email = course.teacherEmail?.nonEmpty
        return block(pickTeachers?.contains(",") == true ? "Docenti" : "Docente") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    InitialsAvatar(name: name, tint: accent, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name == "—" ? String(localized: "Docente non indicato") : name)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        if let bracket = pickBracket {
                            Text("Scaglione \(bracket)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let email {
                            Text(email).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                if let email, let url = URL(string: "mailto:\(email)") {
                    HStack(spacing: 10) {
                        Link(destination: url) {
                            Label("Scrivi", systemImage: "envelope")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        Button { copy(email) } label: {
                            Label(copied == email ? "Copiato" : "Copia indirizzo",
                                  systemImage: copied == email ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                    .font(.subheadline.weight(.semibold))
                    .controlSize(.large)
                    .tint(accent)
                }
            }
            .padding(16)
            .lookCard()
        }
    }

    // MARK: - Exam

    @ViewBuilder
    private var exam: some View {
        let assessment = syllabus?.assessment ?? []
        let language = syllabus?.language
        if !assessment.isEmpty || language != nil {
            block("Esame") {
                VStack(spacing: 0) {
                    ForEach(Array(assessment.enumerated()), id: \.offset) { index, item in
                        row(last: index == assessment.count - 1 && language == nil) {
                            NumberTile(number: index + 1, colour: ramp.colour(0, of: 2))
                        } content: {
                            Text(item).font(.subheadline)
                        }
                    }
                    if let language {
                        row(last: true) {
                            CourseRowTile(symbol: "globe", colour: ramp.colour(1, of: 2))
                        } content: {
                            Text(language.taughtIn).font(.subheadline)
                        }
                    }
                }
                .padding(.horizontal, cardPadding)
                .padding(.vertical, cardPadding / 2)
                .lookCard()
            }
        }
    }

    // MARK: - Prove in itinere

    private var partialExams: some View {
        let policy = syllabus.map { PartialExams.policy(assessment: $0.assessment, notes: $0.assessmentNotes) } ?? .unknown
        let quotes = PartialExams.sentences(in: syllabus?.assessmentNotes)
        let dates = timeline
        return VStack(alignment: .leading, spacing: 10) {
            LookHeading("Prove in itinere")
            VStack(alignment: .leading, spacing: 14) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
                } else {
                    policyHeader(policy)
                }
                // The teacher's own words: how the parts count is theirs to say.
                ForEach(quotes, id: \.self) { quote in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3)
                        Text(quote).font(.callout).italic()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !dates.isEmpty {
                    Divider()
                    rail(dates)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lookCard()
            Text("Dalla scheda dell'insegnamento e dagli appelli. Come le prove contano sul voto lo decide il docente: fa fede il suo testo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func policyHeader(_ policy: PartialExams.Policy) -> some View {
        let (title, detail, symbol, tint): (LocalizedStringKey, LocalizedStringKey, String, Color) = switch policy {
        case .offered: ("Previste", "La scheda prevede prove durante il semestre.", "checkmark", .green)
        case .none: ("Non previste", "L'esame si sostiene tutto insieme, a fine corso.", "xmark", .secondary)
        case .unknown: ("La scheda non lo dice", "Controlla gli avvisi del corso o chiedi al docente.", "questionmark", .secondary)
        }
        return HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// One dated thing about the prove in itinere: a sitting, an exam on the
    /// agenda, or a results file.
    private struct Dated: Identifiable {
        let id: String
        let date: Date?
        let symbol: String
        let title: String
        let detail: String?
    }

    private var timeline: [Dated] {
        let sittings = PartialExams.sittings(career.sessions.filter { $0.isOf(courseCode: course.id, courseName: course.name) })
            .map { sitting in
                Dated(id: "sitting-\(sitting.id)", date: sitting.date, symbol: "pencil.and.list.clipboard",
                      title: sitting.kind ?? String(localized: "Appello"),
                      detail: sitting.grade.map { String(localized: "Esito: \($0.display)") } ?? sitting.status.label)
            }
        // One way only: a generic agenda title ("Esame") must not attach to
        // every course whose name contains it.
        let target = course.name.lowercased()
        let events = PartialExams.agendaEvents(agenda.officialEvents.filter { $0.title.lowercased().contains(target) })
            .map { event in
                Dated(id: "event-\(event.id)", date: event.start, symbol: "calendar", title: event.title,
                      detail: [event.start.formatted(.dateTime.hour().minute().locale(locale)), event.room]
                        .compactMap { $0 }.joined(separator: " · "))
            }
        let results = PartialExams.resultsFiles(FeedItem.items(from: feed.recent, for: course).map(\.update))
            .map { update in
                Dated(id: "results-\(update.id)", date: update.detectedAt, symbol: "tablecells",
                      title: update.newValue ?? String(localized: "Risultati"),
                      detail: update.lookup?.grade.map { String(localized: "Nel file: \($0) (non ancora ufficiale)") }
                        ?? (update.lookup?.looksLikeResults == true ? String(localized: "Non ho trovato la tua riga nel file") : nil))
            }
        return (sittings + events + results).sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// Dates down the left, as Oggi's rail: when reads before what.
    private func rail(_ items: [Dated]) -> some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                let isLast = item.id == items.last?.id
                let isPast = (item.date ?? .distantFuture) < .now
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Text(item.date?.formatted(.dateTime.day().locale(locale)) ?? "—")
                            .font(.footnote.weight(.bold))
                            .monospacedDigit()
                        Text((item.date?.formatted(.dateTime.month(.abbreviated).locale(locale)) ?? "").uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 34)
                    VStack(spacing: 0) {
                        Circle()
                            .fill(isPast ? AnyShapeStyle(.tertiary) : AnyShapeStyle(accent))
                            .frame(width: 10, height: 10)
                            .padding(.top, 4)
                        if !isLast {
                            Rectangle().fill(.quaternary).frame(width: 2)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label(item.title, systemImage: item.symbol)
                            .font(.subheadline.weight(.medium))
                            .labelStyle(RailLabelStyle(tint: accent))
                        if let detail = item.detail, !detail.isEmpty {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, isLast ? 0 : 16)
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: false, vertical: true)
                .opacity(isPast ? 0.7 : 1)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Identifiers

    @ViewBuilder
    private var identifiers: some View {
        let codes: [(label: String, value: String)] = [
            course.teachingCode.map { (String(localized: "Codice insegnamento"), $0) },
            course.moodleID.map { (String(localized: "Corso WeBeep"), "\($0)") },
        ].compactMap { $0 }
        if !codes.isEmpty {
            block("Identificativi") {
                VStack(spacing: 0) {
                    ForEach(codes, id: \.label) { code in
                        row(last: code.label == codes.last?.label) {
                            CourseRowTile(symbol: "number", colour: ramp.main)
                        } content: {
                            HStack {
                                Text(code.label).font(.subheadline).foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                Text(code.value).font(.subheadline.weight(.medium)).monospaced()
                                    .textSelection(.enabled)
                                Button { copy(code.value) } label: {
                                    Image(systemName: copied == code.value ? "checkmark" : "doc.on.doc")
                                        .contentTransition(.symbolEffect(.replace))
                                        .foregroundStyle(accent)
                                        .frame(width: 32, height: 32)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Copia \(code.label)"))
                            }
                        }
                    }
                }
                .padding(.horizontal, cardPadding)
                .padding(.vertical, cardPadding / 2)
                .lookCard()
            }
        }
    }

    // MARK: - Building blocks

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        withAnimation(.snappy) { copied = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copied == text { withAnimation(.snappy) { copied = nil } }
        }
    }

    private func block<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LookHeading(title)
            content()
        }
    }

    private func row<Icon: View, Content: View>(last: Bool, @ViewBuilder icon: () -> Icon,
                                                @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                icon()
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 11)
            if !last { Divider().padding(.leading, 42) }
        }
    }
}

/// A step's number in a thin ring, in the course's colour.
private struct NumberTile: View {
    let number: Int
    let colour: Flavor.RGB
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 30

    var body: some View {
        Text("\(number)")
            .font(.system(size: side * 0.46, weight: .semibold, design: .rounded))
            .foregroundStyle(colour.color)
            .frame(width: side * 0.8, height: side * 0.8)
            .overlay { Circle().strokeBorder(colour.color.opacity(0.5), lineWidth: 1.5) }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// The rail's title with its symbol small in the course's colour.
private struct RailLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.caption).foregroundStyle(tint)
            configuration.title
        }
    }
}

#Preview("Informazioni corso") {
    CourseInfoView(course: Course.samples[0]).previewInNavigation()
}
