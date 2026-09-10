import SwiftUI

struct HomeView: View {
    @Environment(Session.self) private var session
    @Environment(CourseService.self) private var courses
    @State private var selectedCourse: Course?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if let message = courses.errorMessage {
                        banner(message)
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
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        avatar
                    }
                    .accessibilityLabel("Profilo e impostazioni")
                }
            }
            .refreshable { await courses.load() }
            .task { await courses.load() }
            .navigationDestination(item: $selectedCourse) { course in
                CourseMaterialsView(course: course)
            }
        }
    }

    private var avatar: some View {
        Circle()
            .fill(Theme.brand.gradient)
            .frame(width: 32, height: 32)
            .overlay {
                Text(session.student?.initials ?? "?")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
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
                    Text("\(count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
