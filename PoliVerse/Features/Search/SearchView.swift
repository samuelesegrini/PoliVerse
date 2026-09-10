import SwiftUI

/// Not yet implemented. Intended to search across courses, materials and rooms.
struct SearchView: View {
    @Environment(CourseService.self) private var courses
    @State private var query = ""

    private var results: [Course] {
        query.isEmpty ? [] : courses.courses.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.teacher.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(results) { course in
                NavigationLink(value: course) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(course.name).font(.subheadline.weight(.medium))
                        Text(course.teacher).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Cerca")
            .navigationDestination(for: Course.self) { CourseMaterialsView(course: $0) }
            .searchable(text: $query, prompt: "Corsi, docenti, materiali")
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Cerca", systemImage: "magnifyingglass",
                                           description: Text("Per ora la ricerca copre solo i corsi."))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}
