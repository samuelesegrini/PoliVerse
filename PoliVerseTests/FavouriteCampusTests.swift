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

    @Test("An unknown or missing favourite falls back to the first campus")
    func fallsBack() {
        #expect(FavouriteCampus.resolve("Lecco", among: ["Milano Leonardo", "Milano Bovisa"]) == "Milano Leonardo")
        #expect(FavouriteCampus.resolve(nil, among: ["Milano Leonardo"]) == "Milano Leonardo")
        #expect(FavouriteCampus.resolve(nil, among: []) == nil)
    }
}
