# WWDC26: opportunità per PoliVerse

Ricerca del 3 novembre 2026. Fonti primarie Apple e confronto con il codice
alla baseline `89f35328`; nessun codice modificato durante la ricerca. Le proposte sono valutazioni per PoliVerse,
non benefici misurati. **WWDC26 identifica la conferenza, non iOS 26**: diverse
API presentate appartengono a iOS/iPadOS 27. Il progetto attuale ha già target 27.
Le stime di impegno sono relative: piccolo, medio, grande; non preventivi.

## Scelta consigliata

Le priorità seguenti sono una valutazione progettuale, non una graduatoria Apple.

| Opportunità | Tipo | Priorità proposta | Impegno |
| --- | --- | --- | --- |
| Profiling dei percorsi reali | Strumenti/metodo presentati a WWDC26 | Alta | Medio |
| AppIntentsTesting sugli intent esistenti | Nuovo framework | Alta | Medio |
| Evaluations sui riassunti già presenti | Nuovo framework | Alta | Piccolo/medio |
| Verificare sottotitoli AVKit sulle lezioni in inglese | Novità di sistema, spesso automatica | Alta | Piccolo |
| Trasferire più materiali locali con drag/drop | Nuove API su una capacità precedente | Media | Medio/grande |
| Migliorare suggerimenti e filtri di Cerca | Best practice presentate, non API interamente nuove | Media | Piccolo/medio |
| Ricerca conversazionale con SpotlightSearchTool | Nuova integrazione | Pilota | Grande |
| Siri contestuale con schemi compatibili | Evoluzione dell’integrazione esistente | Studio preliminare | Medio/grande |
| NowPlaying esplicito per le registrazioni | Nuovo framework, valutare copertura AVKit | Condizionata | Medio |
| PaperKit per appunti sui materiali | Nuove aperture del modello, framework precedente | Futuro | Grande |

MetricKit moderno, cache immagini, riordino di Oggi e riassunti Foundation Models
sono già presenti: il lavoro utile è completarli o misurarli, non introdurli di nuovo.

## SwiftUI, prestazioni e interazioni

### 1. Misurare i percorsi lenti con gli strumenti aggiornati — priorità alta

Apple presenta Top Functions e confronto tra registrazioni, strumenti per gli
executor Swift e System Trace: CPU occupata, contesa sull’actor e attesa di I/O
richiedono diagnosi differenti. Un `async` avviato dalla UI non dimostra che il
lavoro pesante sia fuori dal Main Actor.
[WWDC26 — Profile, fix, and verify](https://developer.apple.com/videos/play/wwdc2026/268/).

**Già presente:** `PerfSignpost` misura ripristino, agenda, carriera e refresh;
`PerformanceMonitor` raccoglie metriche e diagnostica. `docs/metrickit-performance.md`
contiene anche misure successive alla ricerca iniziale: le sue prime sezioni
sul vecchio logger non descrivono più il codice corrente.

**Proposta:** registrare in Release apertura e scorrimento di Corsi/materiali,
Cerca e galleria; confrontare gli stessi intervalli su stessi dati e dispositivo.
Intervenire sul caricamento, sulle miniature o sull’I/O soltanto dopo una traccia
che attribuisca il costo. Impegno medio; utilità estesa a tutta l’app. Nessuna
percentuale di miglioramento è deducibile dalla sessione o dalle righe eliminate.

### 2. Estendere le metriche alle fasi della personalizzazione — priorità media

Il nuovo `MetricManager` offre flussi asincroni di report e metriche contestuali
agli stati dichiarati dall’app. Apple raccomanda stati stabili e pochi domini,
evitando di rappresentare ogni evento transitorio.
[WWDC26 — Meet the new MetricKit](https://developer.apple.com/videos/play/wwdc2026/222/).

**Già presente:** `ModernMetricStream`, archivio locale dei report e
`PerformanceStates` per scheda selezionata e dati reali/esempio. La migrazione
al nuovo MetricKit è quindi già stata eseguita.

**Proposta:** se le tracce indicano una differenza utile, aggiungere un dominio
limitato alle fasi galleria/editor, eventualmente distinguendo classico/speciale.
Permetterebbe di leggere gli hitches nel loro contesto, senza un nuovo sistema
di analisi. Impegno piccolo/medio; utilità diagnostica, nessun guadagno runtime
automatico. Conservare l’attuale archiviazione locale e cardinalità limitata.

### 3. Trascinare più materiali locali verso altre app — priorità media

Le nuove API `dragContainer` consentono trascinamenti multipli; configurazione e
anteprime di drag/drop permettono di dichiarare le regole dell’operazione.
`Transferable` esisteva già prima di WWDC26.
[WWDC26 — Build powerful drag and drop in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/271/).

**Già presente:** Oggi usa `.reorderable()` e `.reorderContainer` per le sezioni;
`LookToolView` offre anche riordino con `draggable`/`dropDestination`. Non serve
ripresentare il riordino di Oggi come nuova funzionalità.

**Proposta:** selezionare più materiali già scaricati e trascinarne copie verso
File, Note o un’altra app su iPad/Mac. `CourseMaterialsView` e `FileDownloadModel`
dispongono già di URL locali. Impegno medio/grande: selezione multipla,
rappresentazioni trasferibili e verifica dei file ricevuti dall’app destinataria.
Trasferire file locali, non URL universitari che richiedono la sessione dell’app.
Un eventuale pilota di riordino nativo nell’inspector deve conservare i gesti
e i vincoli della personalizzazione attuale.

### 4. Azioni di scorrimento sui materiali — priorità media

SwiftUI estende le swipe actions oltre `List`, coordinandole tramite
`swipeActionsContainer`. La stessa sessione presenta inizializzazione lazy delle
classi in `@State`, caching HTTP di `AsyncImage` e configurazione della sessione.
[WWDC26 — What’s new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/).

**Proposta:** sui materiali presentati in contenitori personalizzati, rendere
raggiungibili con swipe «Scarica» e «Rimuovi download», mantenendo il menu come
accesso alternativo. Impegno medio; beneficio di accesso alle operazioni locali.
La galleria mantiene i propri gesti.

**Già adottato o da verificare senza riscritture:** `ImageSession.shared`,
installata da `AppShellDuties`, configura già la cache immagini (20 MB RAM,
150 MB disco). Le viste usano già classi in `@State`: il nuovo comportamento
lazy è un vantaggio della toolchain per i casi applicabili, non richiede un
secondo contenitore di stato. Nessuna cache parallela proposta.

### 5. Completare l’accessibilità degli strumenti diretti — priorità alta

La sessione propone scopo, valore, azioni e feedback espliciti; per controlli
complessi mostra azioni personalizzate, passthrough e Direct Touch. Sono
pratiche presentate a WWDC26, non tutte API nate nel 2026.
[WWDC26 — Refine accessibility for custom controls](https://developer.apple.com/videos/play/wwdc2026/220/).

**Già presente:** righelli regolabili, capsule accessibili e azioni degli sticker
per spostamento, dimensione e rotazione. **Proposta:** verificare il percorso
completo con VoiceOver, annunciare i valori attuali dove mancano e offrire una
conferma comprensibile per ogni modifica. Direct Touch va valutato soltanto
quando migliora il compito, conservando le azioni alternative. Impegno medio;
beneficio concreto per gli strumenti più difficili da usare senza gesti visivi.


## Ricerca, Siri e qualità dell’intelligenza

### 6. AppIntentsTesting sugli intent esistenti — priorità alta

Apple introduce un framework che esegue intent, query ed entity attraverso
l’infrastruttura di Siri, Comandi rapidi e Spotlight, verificando anche
indicizzazione e annotazioni delle viste. Usa un bundle UI testing, con app e
runner firmati dallo stesso team, ma non richiede tap o navigazione grafica.
[WWDC26 — AppIntentsTesting](https://developer.apple.com/videos/play/wwdc2026/295/).

**Già presente:** `AppEntities.swift`, `EntityIntents.swift`, `AppShortcuts.swift`
e `SpotlightIndex.swift` offrono corsi, appelli e aule, con query sull’indice
condiviso. Non è emersa un’adozione di AppIntentsTesting nel codice cercato.

**Proposta:** partire da risoluzione di un corso, prossimo appello e aula libera,
poi verificare apertura della destinazione e cancellazione dei dati indicizzati
al cambio account. Il beneficio è affidabilità delle integrazioni, non una
nuova schermata. Impegno medio; verifica preliminare di firma e host dei test.

### 7. Evaluations per i riassunti degli avvisi — priorità alta

Il framework presentato da Apple permette dataset di esempi, metriche
quantitative e valutazioni qualitative del risultato dei modelli. La sessione
suggerisce di iniziare con un insieme piccolo e rappresentativo.
[WWDC26 — Meet the Evaluations framework](https://developer.apple.com/videos/play/wwdc2026/298/).

**Già presente:** `NoticeSummary.swift` usa `LanguageModelSession` sul dispositivo;
`CourseForumView` espone la funzione per avvisi lunghi. I rilevatori di cambiamenti
sono separati dai riassunti generati.

**Proposta:** valutare 20–30 avvisi di esempio con date, cambi aula, negazioni,
rinvii e testo bilingue. Misurare conservazione dei fatti, aggiunte non supportate,
lunghezza e comportamento quando il modello non è disponibile. Le soglie e i
casi attesi sono decisioni di PoliVerse. Impegno piccolo/medio; una buona base
prima di estendere i riassunti o introdurre altra generazione.

### 8. Ricerca conversazionale sui contenuti dell’app — pilota

`SpotlightSearchTool` collega l’indice Core Spotlight a `LanguageModelSession`.
La sessione mostra recupero di contenuti completi tramite un delegate e
personalizzazione della ricerca. La qualità dipende dai contenuti donati.
[WWDC26 — LLM search using Core Spotlight](https://developer.apple.com/videos/play/wwdc2026/246/).

**Già presente:** `SpotlightIndex` indicizza corsi, aule, docenti e appelli con
metadati; non è un indice del testo completo dei PDF. `SearchView` ha ricerca
classica, filtri per tipo e ricerche recenti.

**Proposta:** un primo esperimento su contenuti già indicizzati, mostrando gli
oggetti recuperati accanto alla risposta. Una domanda come «quali materiali
parlano di reti di Petri?» richiede prima estrazione e indicizzazione del testo
dei materiali disponibili, recupero incrementale e gestione del contesto. È un
progetto aggiuntivo, non un risultato ottenuto collegando il solo indice attuale.
Mantenere risultati classici e disponibilità dei modelli come percorsi espliciti.
Impegno grande per il corpus dei materiali; qualità da valutare con esempi reali.

### 9. Siri più contestuale — studio preliminare

La sessione distingue App Entities, App Schemas e risoluzione semantica con
`IndexedEntity`. Gli schemi descrivono concetti e azioni riconosciuti dal sistema;
le sole entità non garantiscono la nuova comprensione di Siri. Query testuali
restano un’alternativa per contenuti non indicizzabili.
[WWDC26 — Build intelligent Siri experiences](https://developer.apple.com/videos/play/wwdc2026/240/).

**Già presente:** domande come «quando è l’appello?» hanno intent dedicati;
le query correnti sono `EntityStringQuery`. **Proposta:** verificare gli schemi
e i domini effettivamente compatibili con materiali/documenti e relative azioni,
poi valutare indicizzazione semantica e contesto della schermata. Un appello
universitario non va dichiarato arbitrariamente un evento di calendario gestito
dall’utente per adattarlo a uno schema. L’esito dello studio potrebbe limitare
l’adozione a una parte dell’app. Impegno medio/grande; ritorno da provare su Siri.

### 10. Rendere Cerca più immediata — priorità media

La sessione di design raccomanda suggerimenti pertinenti al testo digitato,
filtri visibili e contestuali e possibilità di rimuovere le ricerche recenti.
Queste sono best practice presentate a WWDC26, non tutte novità di API.
[WWDC26 — Design intuitive search experiences](https://developer.apple.com/videos/play/wwdc2026/292/).

**Già presente:** ricerche recenti, chip per tipo con conteggi, ricerca ritardata
per evitare lavoro a ogni pressione e stati vuoti. **Proposta:** valutare
completamenti di nomi di corsi/docenti e filtri specifici dei materiali, come
corso e disponibilità offline, conservando la ricerca generale come ingresso.
Impegno piccolo/medio. Prima verificare con un percorso utente quali suggerimenti
accorciano davvero la ricerca; non aggiungere un altro motore di ricerca.

## Registrazioni e possibili espansioni

### 11. Sottotitoli generati e anteprima dello stile — priorità alta di verifica

Apple presenta generazione locale da audio e traduzione da sottotitoli. Nella
sessione, a partire dai sistemi 27, è documentata trascrizione inglese→inglese
e traduzione da sottotitoli inglesi verso più lingue, incluso l’italiano.
Sono supportati HLS e file. I controlli di `AVPlayerViewController` e
`AVPlayerView` offrono automaticamente selezione e anteprima dello stile.
[WWDC26 — Generated subtitles](https://developer.apple.com/videos/play/wwdc2026/256/).

**Già presente:** `RecordingPlayer` usa proprio questi lettori nativi, anche
per i download. **Proposta:** provare una registrazione inglese online e offline
sull’hardware supportato e verificare i menu dei sottotitoli. Potrebbe essere
soprattutto una verifica di capacità già ereditate dal sistema. Non è verificata
la trascrizione automatica dell’audio italiano; non prometterla sulla base della
sessione. Impegno piccolo, subordinato a contenuto, lingue e dispositivo.

### 12. NowPlaying per le registrazioni — priorità condizionata

Il nuovo framework Swift pubblica contenuto e stato di riproduzione nelle
superfici di sistema, con comandi tramite una rappresentazione osservabile.
Comprende anche sessioni remote, che richiedono infrastruttura dedicata.
[WWDC26 — Meet the Now Playing framework](https://developer.apple.com/videos/play/wwdc2026/312/).

**Già presente:** `RecordingPlayer` ha AVKit, metadati di titolo/sottotitolo,
sessione audio e Picture in Picture. Non è emersa un’adozione esplicita di
NowPlaying. **Proposta:** verificare prima i controlli già forniti da AVKit;
adottare una sessione esplicita solo per un’esigenza concreta, ad esempio comandi
o stato aggiuntivo della lezione. Impegno medio. Nessuna nuova infrastruttura
per sessioni su dispositivi remoti è necessaria al caso d’uso attuale.

### 13. PaperKit per appunti sui materiali — possibile evoluzione futura

WWDC26 apre il modello degli elementi del canvas, con accesso ai sottoelementi,
controllo delle interazioni e adornments. PaperKit esisteva già: la novità della
sessione è il controllo più profondo sul canvas.
[WWDC26 — Unwrap PaperKit](https://developer.apple.com/videos/play/wwdc2026/372/).

**Proposta di prodotto:** appunti a penna e annotazioni associate a un materiale.
Richiede scelte su persistenza, esportazione, associazione al file originale e
possibili modifiche del documento sorgente. Impegno grande: amplia il ruolo di
PoliVerse da accesso ai servizi a strumento per studiare. Da scegliere soltanto
se questo ampliamento è desiderato, con un esperimento separato.

## Ordine operativo suggerito

1. Verificare i benefici già disponibili: player/sottotitoli e tracce Instruments.
2. Consolidare ciò che esiste: AppIntentsTesting, valutazioni dei riassunti,
   accessibilità degli strumenti e suggerimenti della ricerca.
3. Scegliere una sola aggiunta visibile: trasferimento multiplo dei materiali
   oppure pilota di ricerca conversazionale.
4. Valutare Siri con schemi compatibili, NowPlaying esplicito e appunti solo
   dopo aver chiarito il bisogno e il vantaggio rispetto alle capacità esistenti.

Nessuna implementazione, modifica ai flussi o misura prestazionale è stata
eseguita per questa ricerca. Le verifiche di adozione riguardano il codice letto
il 3 novembre 2026; la disponibilità operativa va provata sul sistema e dispositivo
scelti prima di trasformare le proposte in un piano di implementazione.


Prima adozione e risultati: [wwdc26-first-adoption.md](wwdc26-first-adoption.md).
