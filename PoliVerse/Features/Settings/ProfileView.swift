import SwiftUI

/// The student's profile: who they are to the Politecnico and how the app
/// reaches it.
///
/// Nothing here is about how the studies are going — averages, credits,
/// results and exams belong to Carriera. Name, codes and email come from the
/// university account and cannot be edited; only the photo's look can.
struct ProfileView: View {
    @Environment(Session.self) private var session
    @Environment(CareerModel.self) private var career
    @Environment(CareersModel.self) private var careers
    @Environment(WeBeepModel.self) private var weBeep
    @Environment(LoginMethodMemory.self) private var loginMemory
    @Environment(\.openURL) private var openURL

    @AppStorage(AvatarShape.storageKey) private var shape: AvatarShape = .circle
    @State private var page: ProfilePage?
    @State private var copied: String?

    enum ProfilePage: String, Identifiable {
        case contact, photo, career
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                actions
                    .padding(.top, 20)

                if let student = session.student {
                    codes(student)
                        .padding(.top, 30)
                }

                if careers.hasChoice {
                    careerList
                        .padding(.top, 26)
                }

                access
                    .padding(.top, 26)

                ProfileGroup("Forma della foto") {
                    AvatarShapePicker(student: session.student, selection: $shape)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 8)
                }
                .padding(.top, 26)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .navigationTitle("Profilo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if session.student != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Condividi contatto", systemImage: "square.and.arrow.up") { page = .contact }
                }
            }
        }
        .navigationDestination(item: $page) { page in
            switch page {
            case .contact:
                if let student = session.student { ContactPage(student: student) }
            case .photo:
                PhotoPage(student: session.student)
            case .career:
                CareerPage()
            }
        }
        .sensoryFeedback(.success, trigger: copied) { _, new in new != nil }
        .task {
            // The course of study under the name comes with the career data;
            // the load is windowed, so a recent one is not repeated.
            async let careerData: Void = career.load()
            async let careerList: Void = careers.load()
            _ = await (careerData, careerList)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            ProfileAvatar(student: session.student, size: 112)
                .padding(.bottom, 12)
            Text(session.student?.fullName ?? String(localized: "Ospite"))
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    /// "Laurea Magistrale · Ingegneria Informatica", from whichever of the two
    /// the Politecnico sent. The careers list sometimes says only "Studente",
    /// which adds nothing under a student's name.
    private var subtitle: String? {
        let kind = careers.current?.kind.flatMap { $0.localizedCaseInsensitiveCompare("Studente") == .orderedSame ? nil : $0 }
        let parts = [kind, career.planHeader?.course].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if session.student != nil {
                QuickAction(title: "Codice QR", systemImage: "qrcode") { page = .contact }
            }
            QuickAction(title: "Posta", systemImage: "envelope") { openMail() }
            QuickAction(title: "Foto", systemImage: "person.crop.circle") { page = .photo }
        }
    }

    /// The Politecnico's mail is Microsoft 365: the Outlook app when it is
    /// installed, Outlook on the web otherwise.
    private func openMail() {
        openURL(URL(string: "ms-outlook://")!) { accepted in
            if !accepted { openURL(URL(string: "https://outlook.office.com/mail/")!) }
        }
    }

    // MARK: - Codes

    private func codes(_ student: Student) -> some View {
        ProfileGroup("Codici", footer: "Tocca un codice per copiarlo. Arrivano dal tuo account del Politecnico.") {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    CodeCell(label: "Matricola", value: student.matricola, copied: copied == student.matricola) {
                        copy(student.matricola)
                    }
                    Divider()
                    CodeCell(label: "Codice persona", value: student.personCode, copied: copied == student.personCode) {
                        copy(student.personCode)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                Divider().padding(.leading, 18)

                Button { copy(student.email) } label: {
                    HStack(spacing: 12) {
                        Text("Email")
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text(student.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: copied == student.email ? "checkmark" : "doc.on.doc")
                            .font(.footnote)
                            .foregroundStyle(.tint)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(.horizontal, 18)
                    .frame(minHeight: 52)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Copia")
            }
        }
    }

    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        withAnimation(.snappy) { copied = value }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copied == value { withAnimation(.snappy) { copied = nil } }
        }
    }

    // MARK: - Careers

    private var careerList: some View {
        ProfileGroup("Carriere", footer: "Carriera mostra la carriera scelta qui.") {
            VStack(spacing: 0) {
                ForEach(Array(careers.careers.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 68) }
                    Button { page = .career } label: {
                        CareerRow(career: item, isCurrent: item.matricola == session.student?.matricola)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Access

    private var access: some View {
        ProfileGroup("Accesso") {
            VStack(spacing: 0) {
                ServiceRow(title: "Politecnico", systemImage: "lock.fill", tint: Theme.brand) {
                    if let method = loginMemory.remembered() {
                        Text(method.profileLabel)
                    }
                }
                Divider().padding(.leading, 62)
                ServiceRow(title: "WeBeep", systemImage: "books.vertical.fill", tint: .orange) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(weBeep.isAuthenticated ? Color.green : Color(.systemGray3))
                            .frame(width: 8, height: 8)
                        Text(weBeep.isAuthenticated ? "Collegato" : "Non collegato")
                    }
                }
            }
        }
    }
}

// MARK: - Pieces

/// A titled card in the grouped style: small caps title, the content on the
/// secondary background, an optional footnote under it.
struct ProfileGroup<Content: View>: View {
    let title: LocalizedStringKey
    var footer: LocalizedStringKey? = nil
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .lookCard(cornerRadius: Theme.cardCorner)
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }
}

private struct QuickAction: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(height: 24)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity, minHeight: 64)
            .lookCard(cornerRadius: 22)
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}

private struct CodeCell: View {
    let label: LocalizedStringKey
    let value: String
    let copied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.footnote)
                        .foregroundStyle(.tint)
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(value)
        .accessibilityHint("Copia")
    }
}

struct CareerRow: View {
    let career: Career
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "graduationcap.fill")
                .font(.body)
                .foregroundStyle(isCurrent ? Theme.onAccent : .secondary)
                .frame(width: 36, height: 36)
                .background(isCurrent ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color(.systemGray5)),
                            in: .rect(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(career.kind ?? String(localized: "Carriera"))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityLabel("In uso")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .contentShape(.rect)
    }

    private var detail: String {
        [career.matricola, career.status].compactMap { $0 }.joined(separator: " · ")
    }
}

private struct ServiceRow<Value: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let tint: Color
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: .rect(cornerRadius: 9, style: .continuous))
            Text(title)
            Spacer(minLength: 8)
            value
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }
}

/// The three photo shapes side by side, the chosen one ringed.
struct AvatarShapePicker: View {
    let student: Student?
    @Binding var selection: AvatarShape

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AvatarShape.allCases) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.snappy) { selection = option }
                } label: {
                    VStack(spacing: 8) {
                        ProfileAvatar(student: student, size: 58, shape: option)
                            .padding(6)
                            .overlay {
                                Circle()
                                    .strokeBorder(Theme.brand, lineWidth: 2.5)
                                    .opacity(isSelected ? 1 : 0)
                            }
                        Text(option.label)
                            .font(.footnote.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

extension PoliMiLoginMethod {
    /// How the profile names the way in: "SPID · Aruba", "CIE", "Password".
    var profileLabel: String {
        switch self {
        case .password: String(localized: "Password")
        case .spid(let provider): "SPID · \(provider.name)"
        case .cie: "CIE"
        case .eidas: "eIDAS"
        case .eduGAIN: "eduGAIN"
        }
    }
}

#Preview("Profilo") {
    NavigationStack { ProfileView() }.previewEnvironment()
}
