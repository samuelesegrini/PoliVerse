import SwiftUI

/// The student's profile: who they are to the Politecnico, and how their
/// picture looks in the app.
///
/// Name, codes and email come from the university account and cannot be
/// edited here; only the display preferences can.
struct ProfileView: View {
    @Environment(Session.self) private var session
    @Environment(CareerService.self) private var career
    @Environment(CareersService.self) private var careers

    @AppStorage(AvatarShape.storageKey) private var shape: AvatarShape = .circle

    var body: some View {
        List {
            Section {
                header
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            if let student = session.student {
                Section {
                    LabeledContent("Nome", value: student.fullName)
                    LabeledContent("Email", value: student.email)
                    LabeledContent("Codice persona", value: student.personCode)
                    if careers.hasChoice {
                        NavigationLink {
                            CareerSwitchView()
                        } label: {
                            LabeledContent("Matricola", value: student.matricola)
                        }
                    } else {
                        LabeledContent("Matricola", value: student.matricola)
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Questi dati arrivano dal tuo account del Politecnico.")
                }
            }

            Section {
                Picker(selection: $shape) {
                    ForEach(AvatarShape.allCases) { Text($0.label).tag($0) }
                } label: {
                    Text("Forma della foto")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Aspetto")
            } footer: {
                Text("Come appare la tua foto nell’app.")
            }
        }
        .navigationTitle("Profilo")
        .navigationBarTitleDisplayMode(.inline)
        .task { await careers.load() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ProfileAvatar(student: session.student, size: 120)
                .padding(.bottom, 6)
            Text(session.student?.fullName ?? String(localized: "Ospite"))
                .font(.title2.weight(.bold))
            if let course = career.planHeader?.course {
                Text(course)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview("Profilo") {
    NavigationStack { ProfileView() }.previewEnvironment()
}
