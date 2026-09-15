import SwiftUI

/// The student's profile: who they are to the Politecnico, how far the degree
/// has come, their marks and milestones — under a header in the layout they
/// pick.
///
/// Name, codes and email come from the university account and cannot be
/// edited here; only the display preferences can.
struct ProfileView: View {
    @Environment(Session.self) private var session
    @Environment(CareerService.self) private var career
    @Environment(CareersService.self) private var careers

    @AppStorage(AvatarShape.storageKey) private var shape: AvatarShape = .circle
    @AppStorage(ProfileLayout.storageKey) private var layout: ProfileLayout = .classic

    private var summary: ProfileSummary {
        ProfileSummary(libretto: career.libretto, gradeBook: career.gradeBook, header: career.planHeader)
    }

    var body: some View {
        let summary = summary
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(summary)
                    .animation(.snappy, value: layout)

                // The dashboard already leads with the numbers.
                if layout != .dashboard {
                    ProfileStatsGrid(summary: summary)
                }

                if summary.marks.count >= 2 {
                    ProfileSection(title: "Andamento", trailing: "Media in arancione") {
                        GradesTrendChart(summary: summary)
                            .padding(14)
                            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
                    }
                }

                if !summary.marks.isEmpty {
                    ProfileSection(title: "Ultimi voti") {
                        RecentGradesList(summary: summary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
                    }
                }

                ProfileSection(title: "Traguardi",
                               trailing: "\(summary.badges.count) di \(ProfileSummary.Badge.allCases.count)") {
                    BadgesShelf(summary: summary)
                }

                if let student = session.student {
                    ProfileSection(title: "Account") {
                        VStack(spacing: 0) {
                            accountRow("Email", student.email, "envelope")
                            Divider().padding(.leading, 44)
                            accountRow("Codice persona", student.personCode, "person.text.rectangle")
                            Divider().padding(.leading, 44)
                            if careers.hasChoice {
                                NavigationLink { CareerSwitchView() } label: {
                                    accountRow("Matricola", student.matricola, "number", chevron: true)
                                }
                                .buttonStyle(.plain)
                            } else {
                                accountRow("Matricola", student.matricola, "number")
                            }
                        }
                        .padding(.horizontal, 14)
                        .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
                        Text("Questi dati arrivano dal tuo account del Politecnico.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .navigationTitle("Profilo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Aspetto", systemImage: "ellipsis") {
                    Picker("Stile", selection: $layout) {
                        ForEach(ProfileLayout.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                    Picker("Forma della foto", selection: $shape) {
                        ForEach(AvatarShape.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
        .task { await careers.load() }
    }

    @ViewBuilder
    private func header(_ summary: ProfileSummary) -> some View {
        switch layout {
        case .classic: ProfileClassicHeader(student: session.student, summary: summary)
        case .card: StudentIDCard(student: session.student, summary: summary).padding(.top, 8)
        case .banner: ProfileBannerHeader(student: session.student, summary: summary)
        case .dashboard: ProfileDashboardHeader(student: session.student, summary: summary).padding(.top, 8)
        }
    }

    private func accountRow(_ label: LocalizedStringKey, _ value: String, _ icon: String, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            if chevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .font(.subheadline)
        .padding(.vertical, 13)
        .contentShape(.rect)
    }
}

#Preview("Profilo · Classico") {
    NavigationStack { ProfileView() }.previewEnvironment()
}
