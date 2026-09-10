import SwiftUI

/// Tab-level entry point: pick a course, then see its materials.
struct WeBeepView: View {
    @Environment(CourseService.self) private var courses

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
                if courses.courses.isEmpty && !courses.isLoading {
                    ContentUnavailableView("Nessun corso", systemImage: "books.vertical",
                                           description: Text("I corsi appariranno qui dopo l'accesso."))
                }
            }
        }
    }
}
