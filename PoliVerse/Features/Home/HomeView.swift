import SwiftUI

struct HomeView: View {
    @Environment(Session.self) private var session
    @Environment(CourseService.self) private var courses
    @Environment(AgendaService.self) private var agenda
    @Environment(CareerService.self) private var career
    @Environment(NoticeService.self) private var notices
    @Environment(NewsService.self) private var news
    @Environment(CareersService.self) private var careers
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.locale) private var locale

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedCourse: Course?
    @State private var showingNotices = false
    @State private var year: String?

    /// One column on iPhone, two on a regular-width iPad. Full-width cards on
    /// a 13" iPad leave a stripe of dead space between the title and buttons.
    private var columns: [GridItem] {
        sizeClass == .regular
            ? [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
            : [GridItem(.flexible())]
    }

    private var shownCourses: [Course] {
        courses.courses(in: year)
    }

    private var todayEvents: [AgendaEvent] {
        agenda.events(on: .now).filter { $0.end > .now }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    greeting

                    PendingChangesBar()

                    CareerMismatchBanner()

                    if session.serviceAuthorizationFailed {
                        ServiceAuthBanner()
                    } else if let message = courses.errorMessage {
                        banner(message)
                    }

                    if !todayEvents.isEmpty {
                        section("Oggi", count: todayEvents.count) {
                            ForEach(todayEvents.prefix(3)) { event in
                                NextUpCard(event: event)
                            }
                        }
                    }

                    if let nextExam = career.enrolled.first {
                        section("Prossimo esame", count: 0) {
                            ExamSummaryCard(exam: nextExam)
                        }
                    }

                    if courses.academicYears.count > 1 {
                        YearFilter(years: courses.academicYears, selection: $year)
                    }

                    section("I tuoi corsi", count: shownCourses.count) {
                        if courses.isLoading && courses.courses.isEmpty {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: Theme.cardCorner)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .frame(height: 150)
                                    .redacted(reason: .placeholder)
                            }
                        } else {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(shownCourses) { course in
                                    CourseCard(
                                        course: course,
                                        onOpen: { selectedCourse = course },
                                        onFavourite: { courses.toggleFavourite(course) },
                                        onMaterials: { selectedCourse = course },
                                        onHide: { courses.toggleHidden(course) }
                                    )
                                }
                            }
                        }
                    }

                    // Last on the screen: the student's own timetable,
                    // exams and courses come first, and news is the part
                    // they can scroll past without missing anything.
                    NewsHighlights()
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .top, spacing: 0) { FreshnessBar(age: courses.age) }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { avatar }
                        .accessibilityLabel("Profilo e impostazioni")
                }
            }
            .refreshable {
                // Nothing to fetch without a network, and five sequential
                // round trips that cannot succeed leave the spinner hanging
                // while the user watches. What is on screen is the cache, and
                // the bar above already says so.
                guard network.isOnline else { return }
                await courses.load(force: true)
                await agenda.load(around: .now, force: true)
                await career.load(force: true)
                await notices.load(force: true)
                await news.load(force: true)
            }
            .task {
                await courses.load()
                await agenda.load(around: .now)
                await career.load()
                // Last: the bell is the least urgent thing on this screen, and
                // an endpoint whose shape is still unconfirmed should not
                // delay the content that is known to work.
                await notices.load()
                await news.load()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NoticesToolbarButton(isPresented: $showingNotices)
                }
            }
            .sheet(isPresented: $showingNotices) { NoticesView() }
            .navigationDestination(item: $selectedCourse) { course in
                CourseDetailView(course: course)
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greetingText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let student = session.student {
                Text(student.firstName)
                    .font(.title.weight(.bold))
                    .fontDesign(.rounded)
            }
        }
        .padding(.top, 4)
    }

    private var greetingText: String {
        let hour = PoliMiDate.romeCalendar.component(.hour, from: .now)
        switch hour {
        case 0..<13: return "Buongiorno"
        case 13..<18: return "Buon pomeriggio"
        default: return "Buonasera"
        }
    }

    private var avatar: some View {
        Circle()
            .fill(Theme.brand.gradient)
            .frame(width: 32, height: 32)
            .overlay {
                Text(session.student?.initials ?? "?")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.onAccent)
            }
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String, count: Int, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .fontDesign(.rounded)
                if count > 0 {
                    Text("\(count)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            content()
        }
    }

    private func banner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.15), in: .rect(cornerRadius: 14))
            .foregroundStyle(.orange)
    }
}

/// Compact "what's next" row for the home screen.
private struct NextUpCard: View {
    let event: AgendaEvent
    @Environment(\.locale) private var locale

    private var accent: Color {
        switch event.kind {
        case .lecture: Theme.brand
        case .exam: .red
        case .deadline: .orange
        case .news: .blue
        case .custom: .purple
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(event.start.formatted(.dateTime.hour().minute().locale(locale)))
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .fixedSize()

            RoundedRectangle(cornerRadius: 3).fill(accent).frame(width: 4, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if let room = event.room ?? event.roomAcronym {
                    Text(room).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if event.isOngoing() {
                Text("Ora")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(accent, in: .capsule)
                    .foregroundStyle(Theme.onAccent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

private struct ExamSummaryCard: View {
    let exam: ExamSession
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "pencil.and.list.clipboard")
                .font(.title2)
                .foregroundStyle(Theme.brand)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(exam.courseName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let date = exam.date {
                    // Rendering date and time in one style yields
                    // "Martedì 22 Settembre Alle Ore 09:00"; compose them.
                    Text("\(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)).capitalized) · \(date.formatted(.dateTime.hour().minute().locale(locale)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let room = exam.room {
                    Label(room, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}


/// Shown when the Politecnico accepts the login but refuses the token for its
/// data services.
///
/// Worth its own banner rather than a generic error: nothing the user does in
/// the app will fix it, and "accedi di nuovo" is the only lever — the same
/// thing the server's own message asks for.
struct ServiceAuthBanner: View {
    @Environment(Session.self) private var session
    @State private var isSigningOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Servizi non autorizzati", systemImage: "lock.trianglebadge.exclamationmark")
                .font(.subheadline.weight(.semibold))
            Text("Il Politecnico ha accettato l'accesso ma non autorizza questa app a leggere corsi, orario e carriera. WeBeep continua a funzionare.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Accedi di nuovo") {
                isSigningOut = true
                Task { await session.signOut() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isSigningOut)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.15), in: .rect(cornerRadius: 16))
    }
}


/// Filters the course list by academic year, mirroring WeBeep's own grouping.
struct YearFilter: View {
    let years: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("Tutti", isOn: selection == nil) { selection = nil }
                ForEach(years, id: \.self) { year in
                    chip(year, isOn: selection == year) {
                        // Tapping the active year clears it, so the filter is
                        // never a one-way door.
                        selection = selection == year ? nil : year
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .background(isOn ? Theme.brand : Color(.secondarySystemGroupedBackground), in: .capsule)
        .foregroundStyle(isOn ? Theme.onAccent : .primary)
    }
}

// MARK: - Previews

#Preview("Home") {
    HomeView().previewEnvironment()
}

#Preview("Componente · Prossima lezione") {
    NextUpCard(event: MockData.agendaEvents(around: .now)[0])
        .padding()
        .previewEnvironment()
}

#Preview("Componente · Prossimo esame") {
    ExamSummaryCard(exam: MockData.examSessions()[0])
        .padding()
        .previewEnvironment()
}

#Preview("Componente · Filtro anno") {
    @Previewable @State var year: String?
    return YearFilter(years: ["2025/26", "2024/25", "2023/24"], selection: $year)
        .padding()
        .previewEnvironment()
}
