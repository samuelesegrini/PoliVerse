import SwiftUI

/// Tab-level entry point: pick a course, then see its materials.
struct WeBeepView: View {
    @Environment(CourseService.self) private var courses
    @Environment(Session.self) private var session
    @Environment(WeBeepService.self) private var weBeep

    @State private var showingLogin = false
    @State private var year: String?
    @State private var showingHidden = false

    /// WeBeep is the source of the course list, so when it is not connected the
    /// list is empty for a reason the user can actually fix — say so rather
    /// than showing a bare "no courses".
    private var needsLogin: Bool {
        !session.useMockData && !weBeep.isAuthenticated
    }

    @ViewBuilder
    private func row(_ course: Course) -> some View {
        NavigationLink(value: course) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.accent(for: course))
                    .frame(width: 6, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name).font(.subheadline.weight(.medium)).lineLimit(2)
                    Text(course.academicYear == "—" ? course.teacher : course.academicYear)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if course.isFavourite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
        }
        .swipeActions(edge: .leading) {
            Button(course.isFavourite ? "Rimuovi" : "Preferito",
                   systemImage: course.isFavourite ? "star.slash" : "star") {
                courses.toggleFavourite(course)
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button("Nascondi", systemImage: "eye.slash", role: .destructive) {
                courses.toggleHidden(course)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if courses.academicYears.count > 1 {
                    Section {
                        YearFilter(years: courses.academicYears, selection: $year)
                            .listRowInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                }

                let favourites = courses.courses(in: year).filter(\.isFavourite)
                let others = courses.courses(in: year).filter { !$0.isFavourite }

                if !favourites.isEmpty {
                    Section("Preferiti") {
                        ForEach(favourites) { row($0) }
                    }
                }

                Section(favourites.isEmpty ? "" : "Altri corsi") {
                    ForEach(others) { row($0) }
                }

                if !courses.hiddenOnly.isEmpty {
                    Section {
                        Button {
                            showingHidden = true
                        } label: {
                            Label("Corsi nascosti (\(courses.hiddenOnly.count))",
                                  systemImage: "eye.slash")
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
                // Forced: connecting WeBeep is exactly the moment the held
                // course list stopped being right.
                WeBeepLoginSheet { await courses.load(force: true) }
            }
            .sheet(isPresented: $showingHidden) {
                NavigationStack {
                    List(courses.hiddenOnly) { course in
                        HStack {
                            Text(course.name).font(.subheadline)
                            Spacer()
                            Button("Mostra") { courses.toggleHidden(course) }
                                .buttonStyle(.borderless)
                        }
                    }
                    .navigationTitle("Corsi nascosti")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Chiudi") { showingHidden = false }
                        }
                    }
                    .overlay {
                        if courses.hiddenOnly.isEmpty {
                            ContentUnavailableView("Nessun corso nascosto",
                                                   systemImage: "eye")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("WeBeep") {
    WeBeepView().previewEnvironment()
}
