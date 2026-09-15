import OSLog
import SwiftUI

/// The pages the profile pushes: the contact to share, the photo, and the
/// choice of career. Each is a short task with one button to finish it.
///
/// Pushed rather than presented: the profile already sits in the settings
/// sheet, and a sheet over a sheet is one layer too many.
private struct ProfilePageScaffold<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 34)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PageTitle: View {
    let title: LocalizedStringKey
    var message: Text? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            if let message {
                message
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Contact

/// The student's name and email as a QR code a classmate can scan, and the
/// same card through the share sheet.
struct ContactPage: View {
    let student: Student

    private var contact: ProfileContact { ProfileContact(student: student) }

    var body: some View {
        let contact = contact
        ProfilePageScaffold {
            VStack(spacing: 0) {
                PageTitle(title: "Il tuo contatto",
                           message: Text("Fallo inquadrare a un compagno per salvare nome ed email."))

                Group {
                    if let code = contact.qrCode() {
                        Image(decorative: code, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "qrcode")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 200, height: 200)
                .padding(18)
                .background(.white, in: .rect(cornerRadius: 30, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 15, y: 10)
                .padding(.top, 22)
                .accessibilityLabel("Codice QR con nome ed email")

                HStack(spacing: 10) {
                    ProfileAvatar(student: student, size: 36)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(student.fullName)
                            .font(.headline)
                        Text(student.email)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 20)
            }
        } footer: {
            VStack(spacing: 10) {
                ShareLink(item: contact, preview: SharePreview(contact.fullName)) {
                    Label("Condividi", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                Text("Matricola e codice persona non sono inclusi.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Photo

/// Where the picture comes from and how it is cut.
struct PhotoPage: View {
    let student: Student?

    @Environment(\.dismiss) private var dismiss
    @AppStorage(AvatarShape.storageKey) private var shape: AvatarShape = .circle
    @AppStorage(AvatarShape.photoKey) private var usesPhoto = true

    private var hasPhoto: Bool { student?.photoURL != nil }

    var body: some View {
        ProfilePageScaffold {
            VStack(spacing: 0) {
                PageTitle(title: "Foto")

                ProfileAvatar(student: student, size: 150)
                    .padding(.top, 18)
                    .animation(.snappy, value: shape)

                // Without a photo there is only one honest answer to show.
                Picker("Origine", selection: hasPhoto ? $usesPhoto : .constant(false)) {
                    Text("Foto del Politecnico").tag(true)
                    Text("Iniziali").tag(false)
                }
                .pickerStyle(.segmented)
                .disabled(!hasPhoto)
                .padding(.top, 26)

                if !hasPhoto {
                    Text("Il Politecnico non ha una tua foto.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }

                AvatarShapePicker(student: student, selection: $shape)
                    .padding(.top, 22)
            }
        } footer: {
            Button { dismiss() } label: {
                Text("Fine").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
    }
}

// MARK: - Career

/// Which matricola the app reads. Changing it takes a fresh sign-in: the
/// Politecnico binds the token to one enrolment.
struct CareerPage: View {
    @Environment(CareersService.self) private var careers
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var chosen: String?
    @State private var working = false
    private let log = Logger(subsystem: "one.wape.PoliVerse", category: "careers")

    private var current: String? { session.student?.matricola }
    private var selection: Career? {
        careers.careers.first { $0.matricola == (chosen ?? current) }
    }

    var body: some View {
        ProfilePageScaffold {
            VStack(spacing: 0) {
                Image(systemName: "graduationcap")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
                    .frame(width: 56, height: 56)
                    .background(Theme.brand.opacity(0.1), in: .rect(cornerRadius: 18, style: .continuous))
                    .padding(.bottom, 12)

                PageTitle(title: "Carriera",
                           message: Text("Hai \(careers.careers.count) matricole. L’app legge i dati di quella che scegli."))

                VStack(spacing: 10) {
                    ForEach(careers.careers) { career in
                        option(career)
                    }
                }
                .padding(.top, 22)
            }
        } footer: {
            VStack(spacing: 10) {
                if let selection, !selection.isActive {
                    Text("Su una carriera chiusa appelli e iscrizioni di solito non rispondono.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let selection, selection.matricola != current {
                    Text("Per cambiare matricola il Politecnico chiede un nuovo accesso.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button { switchCareer(to: selection) } label: {
                        Text("Esci e riaccedi").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(working)
                } else {
                    Button { dismiss() } label: {
                        Text("Fine").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
        }
        .overlay {
            if working { ProgressView().controlSize(.large) }
        }
        // No way out while the switch signs out and back in.
        .navigationBarBackButtonHidden(working)
        .interactiveDismissDisabled(working)
    }

    private func option(_ career: Career) -> some View {
        let isSelected = career.matricola == (chosen ?? current)
        return Button {
            withAnimation(.snappy) { chosen = career.matricola }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(career.kind ?? String(localized: "Carriera"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(career.matricola)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let status = career.status {
                    Text(status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(career.isActive ? Color.green : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background((career.isActive ? Color.green : Color.gray).opacity(0.14), in: .capsule)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(isSelected ? Theme.brand.opacity(0.06) : Color(.secondarySystemBackground),
                        in: .rect(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.brand, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: chosen)
    }

    /// Same order as ``CareerSwitchView``: the favourite is set while the
    /// current token still works, then the app signs out to sign in again.
    private func switchCareer(to career: Career) {
        working = true
        log.notice("Switching career from the profile")
        Task {
            careers.remember(career)
            await careers.markFavourite(career)
            await session.beginCareerRelogin(matricola: career.matricola)
            working = false
            dismiss()
        }
    }
}

#Preview("Contatto") {
    NavigationStack { ContactPage(student: MockData.student) }
        .previewEnvironment()
}

#Preview("Foto") {
    NavigationStack { PhotoPage(student: MockData.student) }
        .previewEnvironment()
}
