import SwiftUI

struct HomeView: View {
    @Environment(Session.self) private var session
    @Environment(CourseService.self) private var courses
    @Environment(AgendaService.self) private var agenda
    @Environment(CareerService.self) private var career
    @Environment(\.locale) private var locale

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedCourse: Course?

    /// One column on iPhone, two on a regular-width iPad. Full-width cards on
    /// a 13" iPad leave a stripe of dead space between the title and buttons.
    private var columns: [GridItem] {
        sizeClass == .regular
            ? [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
            : [GridItem(.flexible())]
    }

    private var todayEvents: [AgendaEvent] {
        agenda.events(on: .now).filter { $0.end > .now }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    greeting

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

                    section("I tuoi corsi", count: courses.courses.count) {
                        if courses.isLoading && courses.courses.isEmpty {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: Theme.cardCorner)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .frame(height: 150)
                                    .redacted(reason: .placeholder)
                            }
                        } else {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(courses.courses) { course in
                                    CourseCard(
                                        course: course,
                                        onOpen: { selectedCourse = course },
                                        onFavourite: { courses.toggleFavourite(course) },
                                        onMaterials: { selectedCourse = course }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { avatar }
                        .accessibilityLabel("Profilo e impostazioni")
                }
            }
            .refreshable {
                await courses.load()
                await agenda.load(from: .now)
                await career.load()
            }
            .task {
                await courses.load()
                await agenda.load(from: .now)
                await career.load()
            }
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
