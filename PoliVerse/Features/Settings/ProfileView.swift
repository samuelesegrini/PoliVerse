import SwiftUI

/// The student's profile: who they are to the Politecnico and how the app
/// reaches it.
///
/// Nothing here is about how the studies are going — averages, credits,
/// results and exams belong to Carriera. Name, codes and email come from the
/// university account and cannot be edited; only the photo's look can.
struct ProfileView: View {
    /// The shared ``Session``, from the environment.
    @Environment(Session.self) private var session
    /// The shared ``CareerModel``, from the environment.
    @Environment(CareerModel.self) private var career
    /// The shared ``CareersModel``, from the environment.
    @Environment(CareersModel.self) private var careers
    /// The shared ``WeBeepModel``, from the environment.
    @Environment(WeBeepModel.self) private var weBeep
    /// The shared ``LoginMethodMemory``, from the environment.
    @Environment(LoginMethodMemory.self) private var loginMemory
    /// Opens a link outside the app.
    @Environment(\.openURL) private var openURL

    /// The shape the avatar is cut to, which the photo page changes.
    @AppStorage(AvatarShape.storageKey) private var shape: AvatarShape = .circle
    /// The profile page pushed, if any.
    @State private var page: ProfilePage?
    /// The code just copied, which its cell confirms for a moment.
    @State private var copied: String?

    /// A page pushed from the profile.
    enum ProfilePage: String, Identifiable {
        /// The contact card, the photo settings, and the choice of enrolment.
        case contact, photo, career
        /// The page's identity, which is its raw value.
        var id: String { rawValue }
    }

    /// The view's content.
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

    /// The student's card, with the name and what the student is enrolled in,
    /// which turns over to the contact's QR code.
    private var header: some View {
        VStack(spacing: 12) {
            StudentCard(student: session.student, subtitle: subtitle)
                .frame(maxWidth: 420)
            Text("Tocca la tessera per girarla")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
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

    /// The row of quick actions: the QR card, the photo, and the university mailbox.
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

    /// The matricola and the codice persona, each copied on a tap.
    ///
    /// - Parameter student: The signed-in student.
    /// - Returns: The card.
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

    /// Puts a code on the pasteboard and confirms it for a moment.
    ///
    /// - Parameter value: The code to copy.
    private func copy(_ value: String) {
        UIPasteboard.general.string = value
        withAnimation(.snappy) { copied = value }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copied == value { withAnimation(.snappy) { copied = nil } }
        }
    }

    // MARK: - Careers

    /// Every enrolment on the account, with the one in use marked.
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

    /// How the student signs in to each service, and where to change it.
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
    /// The card's title.
    let title: LocalizedStringKey
    /// A footnote under the card, if any.
    var footer: LocalizedStringKey? = nil
    /// The content this view wraps.
    @ViewBuilder var content: Content

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - title: The card's title.
    ///   - footer: A footnote under it, if any.
    ///   - content: The card's content.
    init(_ title: LocalizedStringKey, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    /// The view's content.
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

/// One of the square buttons under the header.
private struct QuickAction: View {
    /// What the button is called.
    let title: LocalizedStringKey
    /// Its SF Symbol.
    let systemImage: String
    /// What the tap does.
    let action: () -> Void

    /// The view's content.
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

/// One code, copied on a tap, confirming for a moment afterwards.
private struct CodeCell: View {
    /// What the code is.
    let label: LocalizedStringKey
    /// The code itself.
    let value: String
    /// True while the cell is confirming the copy.
    let copied: Bool
    /// Copies the code.
    let action: () -> Void

    /// The view's content.
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

/// One enrolment: its kind, its matricola and status, and a mark when it is the one in use.
struct CareerRow: View {
    /// The enrolment this row is about.
    let career: Career
    /// True when this is the enrolment the app is reading.
    let isCurrent: Bool

    /// The view's content.
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

    /// The line under the kind: the matricola and the enrolment's status.
    private var detail: String {
        [career.matricola, career.status].compactMap { $0 }.joined(separator: " · ")
    }
}

/// One service and how the student signs in to it.
private struct ServiceRow<Value: View>: View {
    /// The service's name.
    let title: LocalizedStringKey
    /// Its SF Symbol.
    let systemImage: String
    /// The symbol's colour.
    let tint: Color
    /// The `value` this view draws.
    @ViewBuilder var value: Value

    /// The view's content.
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
    /// The student whose picture is drawn in each shape.
    let student: Student?
    /// The shape chosen, which the picker writes.
    @Binding var selection: AvatarShape

    /// The view's content.
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

/// How the profile names a way in.
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
