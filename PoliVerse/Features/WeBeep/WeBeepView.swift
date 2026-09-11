import SwiftUI

/// Tab-level entry point: pick a course, then see its materials.
struct WeBeepView: View {
    @Environment(CourseService.self) private var courses
    @Environment(Session.self) private var session
    @Environment(WeBeepService.self) private var weBeep

    @State private var showingLogin = false

    /// WeBeep is the source of the course list, so when it is not connected the
    /// list is empty for a reason the user can actually fix — say so rather
    /// than showing a bare "no courses".
    private var needsLogin: Bool {
        !session.useMockData && !weBeep.isAuthenticated
    }

    var body: some View {
        NavigationStack {
            List(courses.courses) { course in
                NavigationLink(value: course) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Theme.accent(for: course))
                            .frame(width: 6, height: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name).font(.subheadline.weight(.medium)).lineLimit(2)
                            Text(course.teacher).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("WeBeep")
            .navigationDestination(for: Course.self) { CourseMaterialsView(course: $0) }
            .task { await courses.load() }
            .overlay {
                if needsLogin {
                    ContentUnavailableView {
                        Label("Collega WeBeep", systemImage: "books.vertical")
                    } description: {
                        Text("WeBeep usa un accesso separato da quello dei servizi d'ateneo. Serve una sola volta.")
                    } actions: {
                        Button("Accedi a WeBeep") { showingLogin = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if courses.courses.isEmpty && !courses.isLoading {
                    ContentUnavailableView("Nessun corso", systemImage: "books.vertical",
                                           description: Text("Non risultano corsi attivi su WeBeep."))
                }
            }
            .sheet(isPresented: $showingLogin) {
                WeBeepLoginSheet { await courses.load() }
            }
        }
    }
}
