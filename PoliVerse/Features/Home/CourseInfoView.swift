import SwiftUI

/// The facts of a course in one place: credits, teacher, how the exam works,
/// and prove in itinere.
struct CourseInfoView: View {
    let course: Course

    @Environment(ManifestiService.self) private var manifesti
    @Environment(StudyProgrammeService.self) private var programmes
    @Environment(Session.self) private var session
    @Environment(CareerService.self) private var career
    @Environment(AgendaService.self) private var agenda
    @Environment(UpdateFeed.self) private var feed
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var syllabus: Syllabus?
    @State private var pickTeachers: String?
    @State private var pickBracket: String?
    @State private var loading = true

    private var partialSittings: [ExamSession] {
        PartialExams.sittings(career.sessions.filter { $0.isOf(courseCode: course.id, courseName: course.name) })
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    /// Agenda exams of this course named as partial exams, matched by title
    /// like the course page's lectures.
    private var partialEvents: [AgendaEvent] {
        let target = course.name.lowercased()
        return PartialExams.agendaEvents(agenda.officialEvents.filter { event in
            // One way only: a generic agenda title ("Esame") must not
            // attach to every course whose name contains it.
            event.title.lowercased().contains(target)
        })
    }

    private var partialResults: [ExamUpdate] {
        PartialExams.resultsFiles(FeedItem.items(from: feed.recent, for: course).map(\.update))
    }

    private var tint: Color { Theme.accent(for: course) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FactTiles(facts: [
                    course.cfu > 0 ? ("\(course.cfu)", String(localized: "CFU")) : nil,
                    course.semester != "—" ? (course.semester, String(localized: "semestre")) : nil,
                    (course.academicYear, String(localized: "anno accademico")),
                ].compactMap { $0 }, tint: tint)

                CardSection("Docente", icon: "person.fill", tint: tint) {
                    let name = pickTeachers ?? course.teacher
                    HStack(spacing: 12) {
                        InitialsAvatar(name: name, tint: tint, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.subheadline.weight(.semibold))
                            if let bracket = pickBracket {
                                Text("Scaglione \(bracket)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    if let email = course.teacherEmail, !email.isEmpty, let url = URL(string: "mailto:\(email)") {
                        CardDivider()
                        Button { openURL(url) } label: {
                            HStack {
                                Label(email, systemImage: "envelope.fill")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(tint)
                    }
                }

                if let code = course.teachingCode {
                    CardSection("Identificativi", icon: "number", tint: tint) {
                        CardRow(label: String(localized: "Codice insegnamento")) {
                            Text(code).monospaced().textSelection(.enabled)
                        }
                    }
                }

                if let syllabus, !syllabus.assessment.isEmpty {
                    CardSection("Esame", icon: "pencil.and.list.clipboard", tint: tint) {
                        ForEach(Array(syllabus.assessment.enumerated()), id: \.offset) { index, item in
                            if index > 0 { CardDivider(inset: 48) }
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(tint).frame(width: 22)
                                Text(item).font(.subheadline)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                        }
                    }
                }

                partialExamsSection
            }
            .padding()
            .padding(.bottom, 20)
        }
        .courseScreen()
        .navigationTitle("Informazioni")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await agenda.load(around: .now)
            let pick = await programmes.pick(teachingCode: course.teachingCode, name: course.name, yearCode: course.academicYearStart, courseID: course.id)
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

    @ViewBuilder
    private var partialExamsSection: some View {
        let policy = syllabus.map { PartialExams.policy(assessment: $0.assessment, notes: $0.assessmentNotes) } ?? .unknown
        let quotes = PartialExams.sentences(in: syllabus?.assessmentNotes)
        CardSection("Prove in itinere", icon: "square.split.2x1.fill",
                    footer: "Dalla scheda dell'insegnamento e dagli appelli. Come le prove contano sul voto lo decide il docente: fa fede il suo testo.",
                    tint: tint) {
            CardBlock {
                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    switch policy {
                    case .offered:
                        policyBadge("Previste", "checkmark.circle.fill", .green)
                    case .none:
                        policyBadge("Non previste", "xmark.circle.fill", .secondary)
                    case .unknown:
                        policyBadge("La scheda non lo dice", "questionmark.circle.fill", .secondary)
                    }
                }
            }
            ForEach(quotes, id: \.self) { quote in
                CardDivider()
                CardBlock {
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3)
                        Text(quote).font(.callout).italic()
                    }
                }
            }
            ForEach(partialEvents) { event in
                CardDivider()
                eventRow(icon: "calendar", title: event.title,
                         subtitle: [event.start.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(locale)),
                                    event.room].compactMap { $0 }.joined(separator: " · "))
            }
            ForEach(partialResults) { update in
                CardDivider()
                eventRow(icon: "tablecells", title: update.newValue ?? "",
                         subtitle: update.lookup?.grade.map { String(localized: "Nel file: \($0) (non ancora ufficiale)") }
                            ?? (update.lookup?.looksLikeResults == true ? String(localized: "Non ho trovato la tua riga nel file") : nil))
            }
            ForEach(partialSittings) { sitting in
                CardDivider()
                eventRow(icon: "pencil.and.list.clipboard", title: sitting.kind ?? "",
                         subtitle: [sitting.date?.formatted(.dateTime.day().month(.wide).year().locale(locale)),
                                    sitting.grade.map { String(localized: "Esito: \($0.display)") } ?? sitting.status.label]
                            .compactMap { $0 }.joined(separator: " · "))
            }
        }
    }

    private func policyBadge(_ title: LocalizedStringKey, _ icon: String, _ color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
    }

    private func eventRow(icon: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

#Preview("Informazioni corso") {
    CourseInfoView(course: MockData.courses[0]).previewInNavigation()
}
