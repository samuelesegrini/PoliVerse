import CoreGraphics
import Foundation
import Testing
@testable import PoliVerse

@Suite("Profile contact")
struct ProfileContactTests {
    private let contact = ProfileContact(firstName: "Samuele", lastName: "Segrini",
                                         email: "samuele.segrini@mail.polimi.it")

    @Test("The card carries the name and the email")
    func carriesNameAndEmail() {
        let card = contact.vCard
        #expect(card.hasPrefix("BEGIN:VCARD\r\nVERSION:3.0\r\n"))
        #expect(card.contains("N:Segrini;Samuele;;;"))
        #expect(card.contains("FN:Samuele Segrini"))
        #expect(card.contains("EMAIL;TYPE=INTERNET:samuele.segrini@mail.polimi.it"))
        #expect(card.hasSuffix("END:VCARD"))
    }

    @Test("The university codes stay out of the card")
    func leavesCodesOut() {
        let card = ProfileContact(student: Student.sample).vCard
        #expect(!card.contains(Student.sample.matricola))
        #expect(!card.contains(Student.sample.personCode))
    }

    @Test("Separators in a name are escaped")
    func escapesSeparators() {
        let card = ProfileContact(firstName: "Anna; Maria", lastName: "De, Rossi", email: "a@b.it").vCard
        #expect(card.contains("N:De\\, Rossi;Anna\\; Maria;;;"))
    }

    @Test("The QR code renders")
    func rendersQRCode() throws {
        let image = try #require(contact.qrCode(scale: 4))
        #expect(image.width == image.height)
        #expect(image.width > 0)
    }

    @Test("No login method is claimed before one is used")
    @MainActor
    func rememberedLoginMethod() throws {
        let defaults = try #require(UserDefaults(suiteName: "ProfileContactTests"))
        defaults.removePersistentDomain(forName: "ProfileContactTests")
        let memory = LoginMethodMemory(defaults: defaults)
        #expect(memory.remembered() == nil)
        memory.remember(.cie)
        #expect(memory.remembered() == .cie)
    }
}
