import Foundation

/// Authored, synthetic examples: no student data and no generated reference answers.
nonisolated enum NoticeSummarySamples {
    struct Sample: Sendable {
        let notice: String
        let reference: String
    }
    static let all: [Sample] = [
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio. Questo avviso riguarda gli studenti iscritti
            all’insegnamento corrente. Per il contesto generale restano disponibili la pagina del corso e i
            materiali già condivisi durante le attività didattiche. La comunicazione serve a chiarire le
            informazioni riportate qui sopra; eventuali comunicazioni successive verranno pubblicate nello
            stesso spazio.

            La lezione del 15 novembre si sposta dall’aula A.1.1 all’aula B.2.3. L’orario delle 10:15 resta
            invariato.
            """,
               reference: "Il 15 novembre la lezione delle 10:15 si terrà in B.2.3 anziché A.1.1."),
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.

            La consegna del progetto è prorogata dal 18 al 22 novembre, alle 23:59. Non sono richieste modifiche
            al formato del file.

            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.
            """,
               reference: "La consegna del progetto è prorogata al 22 novembre alle 23:59, con formato invariato."),
        Sample(notice: """
            Contrariamente alla bozza precedente, l’esame non è rinviato: resta confermato per il 20 novembre
            alle 9:00. Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto
            generale restano disponibili la pagina del corso e i materiali già condivisi durante le attività
            didattiche. La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali
            comunicazioni successive verranno pubblicate nello stesso spazio. Questo avviso riguarda gli
            studenti iscritti all’insegnamento corrente. Per il contesto generale restano disponibili la pagina
            del corso e i materiali già condivisi durante le attività didattiche. La comunicazione serve a
            chiarire le informazioni riportate qui sopra; eventuali comunicazioni successive verranno pubblicate
            nello stesso spazio.
            """,
               reference: "L’esame è confermato il 20 novembre alle 9:00 e non è rinviato."),
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio. Questo avviso riguarda gli studenti iscritti
            all’insegnamento corrente. Per il contesto generale restano disponibili la pagina del corso e i
            materiali già condivisi durante le attività didattiche. La comunicazione serve a chiarire le
            informazioni riportate qui sopra; eventuali comunicazioni successive verranno pubblicate nello
            stesso spazio.

            Il ricevimento di martedì è annullato. La nuova data non è ancora stata stabilita e sarà comunicata
            con un altro avviso.
            """,
               reference: "Il ricevimento di martedì è annullato; la nuova data non è ancora definita."),
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.

            Sono disponibili su WeBeep le soluzioni dell’esercitazione 4. Non si tratta dei risultati
            dell’appello.

            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.
            """,
               reference: "Sono disponibili le soluzioni dell’esercitazione 4, non gli esiti dell’appello."),
        Sample(notice: """
            I risultati della prova intermedia sono stati pubblicati nella sezione Risultati. La pubblicazione
            non implica la registrazione del voto in carriera. Questo avviso riguarda gli studenti iscritti
            all’insegnamento corrente. Per il contesto generale restano disponibili la pagina del corso e i
            materiali già condivisi durante le attività didattiche. La comunicazione serve a chiarire le
            informazioni riportate qui sopra; eventuali comunicazioni successive verranno pubblicate nello
            stesso spazio. Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il
            contesto generale restano disponibili la pagina del corso e i materiali già condivisi durante le
            attività didattiche. La comunicazione serve a chiarire le informazioni riportate qui sopra;
            eventuali comunicazioni successive verranno pubblicate nello stesso spazio.
            """,
               reference: "Sono pubblicati gli esiti della prova intermedia; i voti non sono ancora registrati in carriera."),
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio. Questo avviso riguarda gli studenti iscritti
            all’insegnamento corrente. Per il contesto generale restano disponibili la pagina del corso e i
            materiali già condivisi durante le attività didattiche. La comunicazione serve a chiarire le
            informazioni riportate qui sopra; eventuali comunicazioni successive verranno pubblicate nello
            stesso spazio.

            Le iscrizioni al laboratorio aprono il 12 novembre e chiudono il 19 novembre alle 12:00. Non è
            prevista un’iscrizione automatica.
            """,
               reference: "Le iscrizioni al laboratorio saranno aperte dal 12 al 19 novembre alle 12:00 e non sono automatiche."),
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.

            L’attività in aula del 27 novembre è sospesa per manutenzione. La registrazione sarà caricata
            successivamente, senza una data ancora confermata.

            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.
            """,
               reference: "L’attività in aula del 27 novembre è sospesa; il caricamento della registrazione non ha ancora una data confermata."),
        Sample(notice: """
            Per il solo gruppo L2, il laboratorio inizia alle 14:15 anziché alle 13:15. Per L1 l’orario non
            cambia. Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto
            generale restano disponibili la pagina del corso e i materiali già condivisi durante le attività
            didattiche. La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali
            comunicazioni successive verranno pubblicate nello stesso spazio. Questo avviso riguarda gli
            studenti iscritti all’insegnamento corrente. Per il contesto generale restano disponibili la pagina
            del corso e i materiali già condivisi durante le attività didattiche. La comunicazione serve a
            chiarire le informazioni riportate qui sopra; eventuali comunicazioni successive verranno pubblicate
            nello stesso spazio.
            """,
               reference: "Il laboratorio del gruppo L2 inizierà alle 14:15; l’orario di L1 resta invariato."),
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio. Questo avviso riguarda gli studenti iscritti
            all’insegnamento corrente. Per il contesto generale restano disponibili la pagina del corso e i
            materiali già condivisi durante le attività didattiche. La comunicazione serve a chiarire le
            informazioni riportate qui sopra; eventuali comunicazioni successive verranno pubblicate nello
            stesso spazio.

            L’incontro si svolgerà in presenza in D.0.2. Non è disponibile un collegamento online.
            """,
               reference: "L’incontro si terrà in presenza in D.0.2, senza collegamento online."),
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.

            La prova del 3 dicembre sarà online. L’aula indicata nella prima comunicazione non verrà utilizzata.

            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.
            """,
               reference: "La prova del 3 dicembre si terrà online e non nell’aula inizialmente indicata."),
        Sample(notice: """
            La scadenza di giovedì riguarda soltanto la relazione individuale. La consegna del progetto di
            gruppo resta lunedì. Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il
            contesto generale restano disponibili la pagina del corso e i materiali già condivisi durante le
            attività didattiche. La comunicazione serve a chiarire le informazioni riportate qui sopra;
            eventuali comunicazioni successive verranno pubblicate nello stesso spazio. Questo avviso riguarda
            gli studenti iscritti all’insegnamento corrente. Per il contesto generale restano disponibili la
            pagina del corso e i materiali già condivisi durante le attività didattiche. La comunicazione serve
            a chiarire le informazioni riportate qui sopra; eventuali comunicazioni successive verranno
            pubblicate nello stesso spazio.
            """,
               reference: "Giovedì scade soltanto la relazione individuale; il progetto di gruppo resta in consegna lunedì."),
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio. Questo avviso riguarda gli studenti iscritti
            all’insegnamento corrente. Per il contesto generale restano disponibili la pagina del corso e i
            materiali già condivisi durante le attività didattiche. La comunicazione serve a chiarire le
            informazioni riportate qui sopra; eventuali comunicazioni successive verranno pubblicate nello
            stesso spazio.

            Il docente sostituisce il file Capitolo 2 con una versione corretta. Gli esercizi assegnati non
            cambiano.
            """,
               reference: "È disponibile la versione corretta del Capitolo 2; gli esercizi assegnati restano invariati."),
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.

            Il ricevimento passa dal mercoledì al venerdì alle 16:00 a partire dal 1 dicembre. Fino al 30
            novembre resta il vecchio orario.

            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.
            """,
               reference: "Dal 1 dicembre il ricevimento si terrà il venerdì alle 16:00; fino al 30 novembre resta il vecchio orario."),
        Sample(notice: """
            L’appello del 10 gennaio si svolge alle 15:00. Il luogo non è ancora disponibile; non recatevi
            nell’aula riportata nel programma dello scorso anno. Questo avviso riguarda gli studenti iscritti
            all’insegnamento corrente. Per il contesto generale restano disponibili la pagina del corso e i
            materiali già condivisi durante le attività didattiche. La comunicazione serve a chiarire le
            informazioni riportate qui sopra; eventuali comunicazioni successive verranno pubblicate nello
            stesso spazio. Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il
            contesto generale restano disponibili la pagina del corso e i materiali già condivisi durante le
            attività didattiche. La comunicazione serve a chiarire le informazioni riportate qui sopra;
            eventuali comunicazioni successive verranno pubblicate nello stesso spazio.
            """,
               reference: "L’appello del 10 gennaio è alle 15:00; l’aula non è ancora stata comunicata."),
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio. Questo avviso riguarda gli studenti iscritti
            all’insegnamento corrente. Per il contesto generale restano disponibili la pagina del corso e i
            materiali già condivisi durante le attività didattiche. La comunicazione serve a chiarire le
            informazioni riportate qui sopra; eventuali comunicazioni successive verranno pubblicate nello
            stesso spazio.

            Le presentazioni sono anticipate dal 9 all’8 dicembre. Ogni gruppo mantiene il proprio ordine di
            intervento.
            """,
               reference: "Le presentazioni sono anticipate all’8 dicembre, con ordine dei gruppi invariato."),
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.

            È stato corretto un errore nel calendario: la lezione è lunedì 7 dicembre, non martedì 8. L’orario
            resta alle 11:15.

            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.
            """,
               reference: "La lezione è lunedì 7 dicembre alle 11:15, non martedì 8."),
        Sample(notice: """
            L’esercitazione facoltativa non concorre al voto finale. Gli studenti possono usarla come
            autovalutazione senza consegnare file. Questo avviso riguarda gli studenti iscritti all’insegnamento
            corrente. Per il contesto generale restano disponibili la pagina del corso e i materiali già
            condivisi durante le attività didattiche. La comunicazione serve a chiarire le informazioni
            riportate qui sopra; eventuali comunicazioni successive verranno pubblicate nello stesso spazio.
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.
            """,
               reference: "L’esercitazione è facoltativa, non contribuisce al voto e non richiede consegna."),
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio. Questo avviso riguarda gli studenti iscritti
            all’insegnamento corrente. Per il contesto generale restano disponibili la pagina del corso e i
            materiali già condivisi durante le attività didattiche. La comunicazione serve a chiarire le
            informazioni riportate qui sopra; eventuali comunicazioni successive verranno pubblicate nello
            stesso spazio.

            La revisione degli elaborati è aperta a tutti gli iscritti al corso. Non è limitata agli studenti
            che hanno superato la prova.
            """,
               reference: "La revisione degli elaborati è aperta a tutti gli iscritti, anche a chi non ha superato la prova."),
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.

            Non è stato ancora pubblicato un elenco degli ammessi all’orale. Il documento caricato oggi contiene
            soltanto il calendario degli orali.

            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio.
            """,
               reference: "Il documento pubblicato contiene il calendario degli orali, non l’elenco degli ammessi."),
        Sample(notice: """
            The lecture on November 18 moves from room E.1.2 to F.0.4. Its starting time remains 10:15. This
            announcement concerns students enrolled in the current course. The course page and the materials
            already shared during teaching activities remain available for general context. This message
            clarifies the information above; any subsequent announcements will be published in the same course
            space. This announcement concerns students enrolled in the current course. The course page and the
            materials already shared during teaching activities remain available for general context. This
            message clarifies the information above; any subsequent announcements will be published in the same
            course space.
            """,
               reference: "The November 18 lecture moves to F.0.4 and still starts at 10:15."),
        Sample(notice: """
            This announcement concerns students enrolled in the current course. The course page and the
            materials already shared during teaching activities remain available for general context. This
            message clarifies the information above; any subsequent announcements will be published in the same
            course space. This announcement concerns students enrolled in the current course. The course page
            and the materials already shared during teaching activities remain available for general context.
            This message clarifies the information above; any subsequent announcements will be published in the
            same course space.

            The assignment deadline is extended to December 6 at 18:00. No additional registration is required.
            """,
               reference: "The assignment deadline is extended to December 6 at 18:00, with no extra registration required."),
        Sample(notice: """
            This announcement concerns students enrolled in the current course. The course page and the
            materials already shared during teaching activities remain available for general context. This
            message clarifies the information above; any subsequent announcements will be published in the same
            course space.

            The exam has not been cancelled. It remains scheduled for January 12 at 9:30. The room will be
            announced separately.

            This announcement concerns students enrolled in the current course. The course page and the
            materials already shared during teaching activities remain available for general context. This
            message clarifies the information above; any subsequent announcements will be published in the same
            course space.
            """,
               reference: "The exam remains scheduled for January 12 at 9:30; its room has not yet been announced."),
        Sample(notice: """
            La lezione di lunedì si terrà in G.0.1. Monday’s lecture will take place in G.0.1. L’orario resta
            alle 8:15; the starting time remains 8:15. Questo avviso riguarda gli studenti iscritti
            all’insegnamento corrente. Per il contesto generale restano disponibili la pagina del corso e i
            materiali già condivisi durante le attività didattiche. La comunicazione serve a chiarire le
            informazioni riportate qui sopra; eventuali comunicazioni successive verranno pubblicate nello
            stesso spazio. Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il
            contesto generale restano disponibili la pagina del corso e i materiali già condivisi durante le
            attività didattiche. La comunicazione serve a chiarire le informazioni riportate qui sopra;
            eventuali comunicazioni successive verranno pubblicate nello stesso spazio.
            """,
               reference: "La lezione di lunedì si terrà in G.0.1 alle 8:15."),
        Sample(notice: """
            Questo avviso riguarda gli studenti iscritti all’insegnamento corrente. Per il contesto generale
            restano disponibili la pagina del corso e i materiali già condivisi durante le attività didattiche.
            La comunicazione serve a chiarire le informazioni riportate qui sopra; eventuali comunicazioni
            successive verranno pubblicate nello stesso spazio. Questo avviso riguarda gli studenti iscritti
            all’insegnamento corrente. Per il contesto generale restano disponibili la pagina del corso e i
            materiali già condivisi durante le attività didattiche. La comunicazione serve a chiarire le
            informazioni riportate qui sopra; eventuali comunicazioni successive verranno pubblicate nello
            stesso spazio.

            Sono state pubblicate le slide della settimana 5. Week 5 slides are now available. Non sono previsti
            cambiamenti al programma d’esame. The exam syllabus remains unchanged.
            """,
               reference: "Sono disponibili le slide della settimana 5; il programma d’esame resta invariato."),
    ]
}
