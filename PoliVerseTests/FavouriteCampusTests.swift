import Testing
@testable import PoliVerse

/// Aule libere opens where the student is, and never on a campus the catalogue
/// no longer lists.
@Suite("Favourite campus")
struct FavouriteCampusTests {
    @Test("The favourite wins when the catalogue knows it")
    func favouriteWins() {
        #expect(FavouriteCampus.resolve("Milano Bovisa", among: ["Milano Leonardo", "Milano Bovisa"]) == "Milano Bovisa")
    }

    @Test("A site opens on its biggest campus")
    func siteOpensOnItsCampus() {
        let campuses = ["Via Durando", "Via La Masa", "Piazza Leonardo da Vinci 32"]
        let main = { (site: String) in site == "Milano Bovisa" ? "Via La Masa" : nil }
        #expect(FavouriteCampus.resolve("Milano Bovisa", among: campuses, mainCampus: main) == "Via La Masa")
        #expect(FavouriteCampus.resolve("Via Durando", among: campuses, mainCampus: main) == "Via Durando")
    }

    @Test("An unknown or missing favourite falls back to the first campus")
    func fallsBack() {
        #expect(FavouriteCampus.resolve("Lecco", among: ["Milano Leonardo", "Milano Bovisa"]) == "Milano Leonardo")
        #expect(FavouriteCampus.resolve(nil, among: ["Milano Leonardo"]) == "Milano Leonardo")
        #expect(FavouriteCampus.resolve(nil, among: []) == nil)
    }
}
