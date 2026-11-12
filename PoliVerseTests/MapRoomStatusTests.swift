import Foundation
import Testing
@testable import PoliVerse

@Suite("Stato delle aule nella nuova mappa")
struct MapRoomStatusTests {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { day.addingTimeInterval(minutes * 60) }
    private func booking(_ from: Double, _ to: Double, _ title: String? = nil) -> RoomBooking {
        RoomBooking(id: "a-\(from)", start: at(from), end: at(to), title: title)
    }

    @Test("Senza prenotazioni lette lo stato è sconosciuto, mai libero")
    func unknown() {
        #expect(MapRoomStatus.of(nil, at: at(0), dayEnd: at(600)) == .unknown)
        #expect(!MapRoomStatus.unknown.isFree)
    }

    @Test("Libera fino alla prossima prenotazione")
    func freeUntilNext() {
        let status = MapRoomStatus.of([booking(120, 240)], at: at(0), dayEnd: at(600))
        #expect(status == .free(until: at(120)))
        #expect(status.isFree)
    }

    @Test("Libera per il resto della giornata quando non c'è altro")
    func freeAllDay() {
        #expect(MapRoomStatus.of([booking(0, 60)], at: at(90), dayEnd: at(600)) == .free(until: nil))
        #expect(MapRoomStatus.of([booking(700, 760)], at: at(90), dayEnd: at(600)) == .free(until: nil))
    }

    @Test("Occupata fino alla fine delle lezioni attaccate")
    func busyJoined() {
        let bookings = [booking(0, 105, "Fisica I"), booking(115, 210), booking(300, 360)]
        #expect(MapRoomStatus.of(bookings, at: at(30), dayEnd: at(600)) == .busy(until: at(210), what: "Fisica I"))
    }

    @Test("I conteggi concordano col numero, e zero è nessuna")
    func counts() {
        let it = Locale(identifier: "it_IT")
        #expect(MapCounts.rooms(1, locale: it) == "1 aula")
        #expect(MapCounts.rooms(12, locale: it) == "12 aule")
        #expect(MapCounts.rooms(0, locale: it) == "nessuna aula")
        #expect(MapCounts.floors(1, locale: it) == "1 piano")
        #expect(MapCounts.floors(4, locale: it) == "4 piani")
        #expect(MapCounts.free(1, of: 4, locale: it) == "1 libera su 4")
        #expect(MapCounts.free(3, of: 11, locale: it) == "3 libere su 11")
        #expect(MapCounts.free(0, of: 4, locale: it) == "nessuna libera su 4")
        #expect(MapCounts.freeNow(1, locale: it) == "1 libera ora")
    }

    // MARK: The room's sentence

    private let it = Locale(identifier: "it_IT")
    private func clock(_ minutes: Double) -> String { at(minutes).formatted(.dateTime.hour().minute().locale(it)) }
    private func lesson(_ from: Double, _ to: Double, _ title: String) -> MapOwnLesson {
        MapOwnLesson(title: title, interval: DateInterval(start: at(from), end: at(to)))
    }
    private func sentence(_ bookings: [RoomBooking]?, own: [MapOwnLesson] = [], now: Double) -> (text: String, tone: MapRoomTone) {
        MapRoomSentence.make(bookings: bookings, own: own, now: at(now), dayEnd: at(720), locale: it)
    }

    @Test("Prenotazioni sconosciute: stato non disponibile")
    func sentenceUnknown() {
        #expect(sentence(nil, now: 0) == ("Stato non disponibile", .unknown))
    }

    @Test("Occupata da un corso, poi libera fino alla prossima")
    func sentenceBusyThenFree() {
        let result = sentence([booking(0, 120, "Fisica I"), booking(240, 300)], now: 60)
        #expect(result.tone == .busy)
        #expect(result.text == "**Occupata** da Fisica I fino alle **\(clock(120))**, poi **libera** fino alle **\(clock(240))**.")
    }

    @Test("Occupata e poi la tua lezione subito dopo")
    func sentenceBusyThenMine() {
        let result = sentence([booking(0, 120), booking(130, 230)], own: [lesson(130, 230, "Analisi II")], now: 60)
        #expect(result.text == "**Occupata** fino alle **\(clock(120))**, poi **la tua lezione di Analisi II**.")
    }

    @Test("Occupata e poi libera per il resto della giornata")
    func sentenceBusyThenRestOfDay() {
        #expect(sentence([booking(0, 120)], now: 60).text == "**Occupata** fino alle **\(clock(120))**, poi **libera** per il resto della giornata.")
    }

    @Test("C'è la tua lezione adesso")
    func sentenceMineNow() {
        let result = sentence([booking(0, 120)], own: [lesson(0, 120, "Analisi II")], now: 60)
        #expect(result == ("C'è **la tua lezione di Analisi II** fino alle **\(clock(120))**.", .mine))
    }

    @Test("Libera ancora per poco, al singolare e al plurale")
    func sentenceFreeShortly() {
        #expect(sentence([booking(61, 120)], now: 60).text == "**Libera** ancora per **1 minuto**, poi **occupata** fino alle **\(clock(120))**.")
        #expect(sentence([booking(80, 120, "Fisica I")], now: 60).text == "**Libera** ancora per **20 minuti**, poi **Fisica I** fino alle **\(clock(120))**.")
        #expect(sentence([booking(80, 120)], own: [lesson(80, 120, "Analisi II")], now: 60).text == "**Libera** ancora per **20 minuti**, poi **la tua lezione di Analisi II**.")
    }

    @Test("Libera fino alla prossima prenotazione, o per il resto del giorno")
    func sentenceFree() {
        #expect(sentence([booking(240, 300)], now: 60) == ("**Libera** fino alle **\(clock(240))**.", .free))
        #expect(sentence([booking(240, 300)], own: [lesson(240, 300, "Analisi II")], now: 60).text == "**Libera** fino alle **\(clock(240))**, poi **la tua lezione di Analisi II**.")
        #expect(sentence([booking(0, 30)], now: 60).text == "**Libera** per il resto della giornata.")
        #expect(sentence([], now: 800).text == "**Libera**: niente in programma fino a domani.")
    }

    @Test("In grassetto solo le parti importanti")
    func sentenceBold() {
        let styled = MapRoomSentence.styled("**Occupata** fino alle **12:15**, poi **libera**.")
        #expect(String(styled.characters) == "Occupata fino alle 12:15, poi libera.")
        let bold = styled.runs.filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
            .map { String(styled[$0.range].characters) }
        #expect(bold == ["Occupata", "12:15", "libera"])
    }
}
