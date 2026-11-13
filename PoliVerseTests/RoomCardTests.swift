import Foundation
import Testing
@testable import PoliVerse

@Suite("Scheda dell'aula in Cerca")
struct RoomCardTests {
    private let rome = TimeZone(identifier: "Europe/Rome")!
    private let it = Locale(identifier: "it_IT")

    /// 13 November 2026 at a time of day in Rome.
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = rome
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: hour, minute: minute))!
    }

    private var day: DateInterval { DateInterval(start: at(8), end: at(20)) }

    private func booking(_ from: Date, _ to: Date, _ title: String? = nil) -> RoomBooking {
        RoomBooking(id: "b-\(from.timeIntervalSince1970)", start: from, end: to, title: title)
    }

    // MARK: - Floors

    @Test("I nomi dei piani del catalogo diventano come li dice uno studente")
    func floorNames() {
        #expect(RoomWording.floor(name: "Primo", code: nil) == "primo piano")
        #expect(RoomWording.floor(name: "Secondo", code: nil) == "secondo piano")
        #expect(RoomWording.floor(name: "Terzo", code: nil) == "terzo piano")
        #expect(RoomWording.floor(name: "Terra", code: nil) == "piano terra")
        #expect(RoomWording.floor(name: "Rialzato", code: nil) == "piano rialzato")
        #expect(RoomWording.floor(name: "Seminterrato", code: nil) == "seminterrato")
        #expect(RoomWording.floor(name: "Primo Interrato", code: nil) == "primo interrato")
        #expect(RoomWording.floor(name: "Terra Soppalco", code: nil) == "soppalco del piano terra")
        #expect(RoomWording.floor(name: "Primo piano", code: nil) == "primo piano")
        #expect(RoomWording.floor(name: "Piano terra", code: nil) == "piano terra")
    }

    @Test("Senza nome, il piano si legge dal codice")
    func floorFromCode() {
        #expect(RoomWording.floor(name: nil, code: "MIA0103001") == "primo piano")
        #expect(RoomWording.floor(name: nil, code: "MIA0103000") == "piano terra")
        #expect(RoomWording.floor(name: nil, code: "MIA010300S") == "seminterrato")
        #expect(RoomWording.floor(name: "", code: "MIA0103002") == "secondo piano")
        #expect(RoomWording.floor(name: nil, code: "MIA010300V") == nil)
        #expect(RoomWording.floor(name: nil, code: nil) == nil)
    }

    @Test("Edificio e piano separati da una virgola, senza punti in mezzo")
    func location() {
        let room = Classroom(id: "3.1.2", capacity: 96, buildingCode: "MIA0103", floorCode: "MIA0103001",
                             buildingName: "Edificio 3", floorName: "Primo", campusName: "Via Golgi",
                             accessibleSeats: 2, roomCode: "MIA0103001019")
        #expect(RoomWording.location(of: room) == "Edificio 3, primo piano")
        #expect(RoomWording.floorOfBuilding(room) == "primo piano dell'Edificio 3")
        #expect(RoomWording.facts(of: room) == "96 posti, 2 accessibili, primo piano dell'Edificio 3")
        #expect(!RoomWording.location(of: room).contains("·"))
    }

    @Test("Posti e posti accessibili concordano col numero")
    func seatCounts() {
        #expect(RoomWording.seats(1, locale: it) == "1 posto")
        #expect(RoomWording.seats(96, locale: it) == "96 posti")
        #expect(RoomWording.accessibleSeats(1, locale: it) == "1 accessibile")
        #expect(RoomWording.accessibleSeats(2, locale: it) == "2 accessibili")
    }

    // MARK: - Status

    @Test("Libera fino alla prossima lezione, con quanto manca e il suo nome")
    func freeUntilLesson() {
        let bookings = [booking(at(10), at(12), "Fisica I"), booking(at(14, 15), at(16), "Analisi 1")]
        let text = RoomStatusText.make(bookings: bookings, now: at(12, 45), day: day, locale: it, timeZone: rome)
        #expect(text.tone == .free)
        #expect(text.headline == "Libera ora")
        #expect(text.until == "fino alle 14:15")
        #expect(text.compact == "Libera fino alle 14:15")
        #expect(text.detail == "Ancora 1 h 30 min prima di Analisi 1")
        // 1 h 30 min left of a 2 h 15 min spell that began at 12:00.
        #expect(abs((text.remaining ?? 0) - 90.0 / 135.0) < 0.001)
    }

    @Test("Le durate si scrivono in ore e minuti")
    func spans() {
        #expect(RoomStatusText.span(45 * 60) == "45 min")
        #expect(RoomStatusText.span(60 * 60) == "1 h")
        #expect(RoomStatusText.span(90 * 60) == "1 h 30 min")
        #expect(RoomStatusText.span(20) == "1 min")
    }

    @Test("Senza un nome, la prossima è una prenotazione")
    func freeUntilUntitled() {
        let text = RoomStatusText.make(bookings: [booking(at(13), at(14))], now: at(12, 30), day: day,
                                       locale: it, timeZone: rome)
        #expect(text.detail == "Ancora 30 min prima della prossima prenotazione")
    }

    @Test("Libera per il resto della giornata")
    func freeAllDay() {
        let text = RoomStatusText.make(bookings: [booking(at(8), at(10))], now: at(16), day: day,
                                       locale: it, timeZone: rome)
        #expect(text.compact == "Libera per il resto della giornata")
        #expect(text.until == "per il resto della giornata")
        #expect(text.detail == nil)
    }

    @Test("Occupata fino alla fine, con cosa c'è")
    func busy() {
        let text = RoomStatusText.make(bookings: [booking(at(12), at(14, 15), "Fisica I")], now: at(13), day: day,
                                       locale: it, timeZone: rome)
        #expect(text.tone == .busy)
        #expect(text.headline == "Occupata")
        #expect(text.until == "fino alle 14:15")
        #expect(text.compact == "Occupata fino alle 14:15")
        #expect(text.detail == "Fisica I")
        #expect(text.remaining == nil)
    }

    @Test("Prenotazioni sconosciute: mai libera")
    func unknown() {
        let text = RoomStatusText.make(bookings: nil, now: at(12), day: day, locale: it, timeZone: rome)
        #expect(text.tone == .unknown)
        #expect(text.compact == "Stato non disponibile")
        #expect(!text.compact.contains("Libera"))
        let loading = RoomStatusText.make(bookings: nil, isLoading: true, now: at(12), day: day,
                                          locale: it, timeZone: rome)
        #expect(loading.tone == .unknown)
        #expect(loading.remaining == nil)
    }

    @Test("Fuori dall'orario delle lezioni non si dice nulla")
    func outsideDay() {
        let text = RoomStatusText.make(bookings: [], now: at(22), day: day, locale: it, timeZone: rome)
        #expect(text.tone == .unknown)
        #expect(text.compact == "Fuori dall'orario delle lezioni")
    }

    // MARK: - Photos

    @Test("L'indice delle foto tiene solo le aule con una foto")
    func photoIndex() {
        let json = """
        [{"sigla":"3.1.2","csiv":"MIA0103001019","idfoto":"48651","capienza":"160"},
         {"sigla":"3.1.4","csiv":"MIA0103001021","idfoto":"0"},
         {"sigla":"3.0.1","csiv":"MIA0103000001","idfoto":null},
         {"sigla":"X","csiv":"","idfoto":"12"},
         {"sigla":"Y","csiv":"MIA0103000002"}]
        """
        let index = RoomPhotos.index(from: Data(json.utf8))
        #expect(index == ["MIA0103001019": "48651"])
        #expect(RoomPhotos.index(from: Data("not json".utf8)).isEmpty)
    }

    @Test("Il link firmato si legge dal testo della risposta")
    func signedLink() {
        let link = "https://docmanager.polimi.it/documentimanager/downloadHttps?id_documento=48651&cah=024317&__pj0=0&__pj1=3fb4"
        #expect(RoomPhotos.signedURL(from: Data(link.utf8))?.absoluteString == link)
        #expect(RoomPhotos.signedURL(from: Data("\(link)\n".utf8))?.absoluteString == link)
        #expect(RoomPhotos.signedURL(from: Data("\"\(link)\"".utf8))?.absoluteString == link)
        #expect(RoomPhotos.signedURL(from: Data("".utf8)) == nil)
        #expect(RoomPhotos.signedURL(from: Data("<html>errore</html>".utf8)) == nil)
        #expect(RoomPhotos.signedURL(from: Data("http://docmanager.polimi.it/x".utf8)) == nil)
        #expect(RoomPhotos.linkURL(for: "48651").absoluteString
                == "https://onlineservices.polimi.it/maps_rest/rest/syncro/rooms/foto/48651")
    }
}
