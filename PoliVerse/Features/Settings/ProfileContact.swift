import CoreImage
import CoreImage.CIFilterBuiltins
import CoreTransferable
import UniformTypeIdentifiers

/// What the profile shares with a classmate: a name and the university email,
/// as a contact card.
///
/// The matricola and the codice persona are left out on purpose. They identify
/// the student to the Politecnico's services, and a classmate has no use for
/// them.
nonisolated struct ProfileContact: Equatable, Sendable {
    let firstName: String
    let lastName: String
    let email: String

    init(firstName: String, lastName: String, email: String) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
    }

    init(student: Student) {
        self.init(firstName: student.firstName, lastName: student.lastName, email: student.email)
    }

    var fullName: String { "\(firstName) \(lastName)" }

    /// vCard 3.0, which Contacts and every scanner read. Lines end in CRLF as
    /// the format requires.
    var vCard: String {
        [
            "BEGIN:VCARD",
            "VERSION:3.0",
            "N:\(Self.escaped(lastName));\(Self.escaped(firstName));;;",
            "FN:\(Self.escaped(fullName))",
            "EMAIL;TYPE=INTERNET:\(email)",
            "ORG:Politecnico di Milano",
            "END:VCARD",
        ].joined(separator: "\r\n")
    }

    /// The card as a QR code in Politecnico blue, one module per `scale`
    /// pixels. Nil only if Core Image cannot render it.
    func qrCode(scale: CGFloat = 12) -> CGImage? {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(vCard.utf8)
        generator.correctionLevel = "M"

        let colours = CIFilter.falseColor()
        colours.inputImage = generator.outputImage
        colours.color0 = CIColor(red: 0, green: 0.2, blue: 0.32)
        colours.color1 = CIColor(red: 1, green: 1, blue: 1)

        guard let output = colours.outputImage?
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
    }
}

extension ProfileContact: Transferable {
    nonisolated static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .vCard) { contact in
            Data(contact.vCard.utf8)
        }
        .suggestedFileName { $0.fullName }
    }
}
