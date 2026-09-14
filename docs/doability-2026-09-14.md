# Fattibilità: sette richieste (14/09/2026)

Documento di ricerca, non di implementazione. Nessun codice modificato.
Legenda: **[V]** verificato (codice letto, richiesta HTTP eseguita il 14/09/2026, sorgente Moodle letto);
**[I]** dedotto (ragionevole ma non provato).

Richieste HTTP eseguite con `curl` contro `onlineservices.polimi.it` senza credenziali (servizi pubblici),
con un nome fittizio ("Rossi Mario") per il carrello.

---

## 1. Orario personalizzato interamente nativo

### Stato attuale
- `PersonalTimetableView` guida già nativamente scaglione, conteggio e svuotamento
  (`PoliVerse/Features/Manifesti/PersonalTimetableView.swift:18-74`), ma la griglia è una
  `WKWebView` sulla pagina del Politecnico (`:76-90`, `:96-118`). Il commento in testa (`:3-16`)
  motiva la scelta: "le celle sono vuote finché gli orari non sono pubblicati". **Per il 2026/27
  non è più vero** (vedi sotto) [V].
- L'aggiunta di un insegnamento avviene solo dalla scheda del manifesto
  (`ManifestoDetailView.swift:75` → `ManifestiService.addToTimetable`), e senza scelta della sezione:
  `section` è sempre `""` (`ManifestiService.swift:253-260`) [V].
- Lo stato è sul server, legato al cookie `JSESSIONID` in un jar dedicato
  (`ManifestiService.swift:46-53`). La web view riceve una copia dei cookie (`PersonalTimetableView.swift:103-110`):
  se la sessione scade, la pagina chiede di nuovo il nome — probabile origine del "devo reinserire il nome" [I].
- Endpoint già documentati in `docs/manifesti.md` ("Personalised timetable").

### Flusso HTTP osservato [V]
| Passo | Richiesta | Risposta |
| --- | --- | --- |
| Apri sessione | `GET ManifestoPublic.do?evn_gointrocarrello=evento&aa=2026&lang=IT` | HTML, imposta `JSESSIONID` |
| Scaglione | `POST ManifestoPublic.do` `evn_setcognome=…&cognome=Rossi+Mario&aa=2026&lang=IT&c_accordo=` | HTML "Cognome e nome impostato: Rossi Mario" |
| Sezioni di un insegnamento | `GET ManifestoPublic.do?evn_showsezioni=evento` + `aa,k_cf,k_corso_la,k_indir,codDescr,ac_ins,idItemOfferta,idGruppo,idRiga` | frammento HTML con radio `sel_sezione` = `"<semestre>_<nomeSezione>"` (dal JS `show_sezioni` nella pagina di dettaglio) |
| Aggiungi | `POST ManifestoPublic.do?EVN_ADDCART=EVENTO` `aa,k_corso_la,k_indir,codDescr,ac_ins,semestre,sezione` | **XML**: `<success><num-ins-cart>1</num-ins-cart><desc-ins-add>Aggiunto…</desc-ins-add></success>` |
| Rimuovi / svuota | `EVN_DELCART` / `evn_eliminacarrello` | XML / HTML |
| Griglia | `GET GestioneCarrelloPublic.do?EVN_DEFAULT=evento&aa=2026&lang=IT` (75 KB, 1,6 s) | HTML "sinottico": righe `td.data` (giorno), `td.dove` (aula + link `idaula`), `td.slot` con `colspan` in quarti d'ora |
| **Orario testuale** | `GET GestioneCarrelloPublic.do?evn_default=EVENTO&tab_selected=2&sel_semestre=1&sel_aa=2026&lang=IT` | HTML con righe esplicite: *"052496 - ALGORITHMS AND PARALLEL COMPUTING (Docente: …) Periodo: 1° semestre Inizio lezioni: 14/09/2026 Fine lezioni: 23/12/2026 — Lunedì dalle 08:15 alle 10:15 in aula 3.1.4 (Milano Città Studi - … Edificio 3 - Piano Primo)"* |

- Nessun export ICS/iCal: nessun `text/calendar` né link `.ics` nelle pagine [V]. Il formato
  "testuale" è però parsabile in modo robusto (regex su "`<giorno> dalle HH:MM alle HH:MM in aula X (<indirizzo>)`") [V].
- Capacità 15 insegnamenti (`maxItemOrario … 15` nel JS della pagina) [V].
- Il manifesto di un corso di studi è navigabile per `k_corso_la` (`ManifestoPublic.do?evn_default=evento&aa=2026&k_corso_la=553`),
  il che permette una lista "tutti gli insegnamenti del mio corso/anno" [V link presente nei risultati; contenuto I].
- Importante per la velocità: le richieste con lo **stesso `JSESSIONID` vengono serializzate dal server**
  (4 dettagli in parallelo: 1,7/3,2/4,6/5,8 s con cookie; ~1,7 s ciascuno senza) [V]. Le operazioni sul carrello
  sono necessariamente sequenziali; le letture di catalogo vanno fatte **senza** cookie (vedi §3).

### Valutazione: **Fattibile**

### Flusso nativo proposto
1. **Chi sei** — nome e cognome precompilati da `session.student` (niente digitazione se loggato); anno accademico.
2. **Corso di studi** — preselezionato da `career.planHeader` (per la magistrale condizionata: scelta esplicita
   del corso, cfr. §5); in alternativa ricerca.
3. **Insegnamenti** — lista nativa degli insegnamenti del corso/anno/semestre, con ricerca per codice o nome,
   multiselezione (contatore "n/15").
4. **Sezione** — solo per insegnamenti con sezioni: sheet con le opzioni di `evn_showsezioni`; di default quella
   dello scaglione.
5. **Riepilogo e conflitti** — l'app fa `setName` → N×`EVN_ADDCART` in sequenza → legge l'orario testuale,
   lo converte in eventi settimanali tra inizio e fine lezioni, evidenzia sovrapposizioni.
6. **Risultato** — vista settimanale SwiftUI (riusare i componenti dell'Agenda), opzione "Aggiungi al Calendario"
   (EventKit, già usato da `AddToCalendarSheet.swift`) e widget.

Modelli: `PersonalTimetable { year, name, degreeCourse, entries:[Entry] , fetchedAt }`,
`Entry { teachingCode, title, teacher, section?, semester, lessonsStart, lessonsEnd, slots:[Slot] }`,
`Slot { weekday, start, end, room, roomID(idaula), address }`.
Servizio: `PersonalTimetableService` (actor per il carrello, sequenziale) + `PersonalTimetableParser`
(nonisolated, testabile con fixture HTML) + persistenza locale (`OfflineStore`/`DiskCache`) — **il server resta
solo strumento di calcolo**: dopo la sincronizzazione l'orario vive in locale e non dipende dal cookie.

### Rischi
- Scraping di HTML Struts: il markup può cambiare (mitigare con test su fixture e fallback "non riesco a leggere l'orario").
- Scaglione sbagliato con nomi composti (avvertenza del servizio, già ripetuta in UI).
- Cambi d'aula/variazioni non notificati: serve un refresh periodico (es. settimanale) che rigeneri l'orario.

### Domande aperte
- La sezione va chiesta sempre o dedotta dallo scaglione? (dipende da quanti insegnamenti hanno sezioni — da campionare).
- Esportare in Calendario iOS o tenere solo in app?

---

## 2. Passaggio all'orario ufficiale

### Stato attuale
- L'agenda ufficiale arriva da `api.polimi.it/agenda/v1/matricola/{m}/events` (`AgendaService.swift:162`) [V].
- `AgendaEvent` non ha codice insegnamento: solo `title`, orari, aula, `subtype` (`Shared/AgendaEvent.swift:34-50`) [V];
  il match con i corsi è già oggi per nome normalizzato (`CourseDetailView.swift:17-32`) [V].

### Valutazione: **Parzialmente fattibile** (il rilevamento è euristico, non c'è un flag "piano approvato" noto)

### Approccio
- **Rilevamento**: per ogni `Entry` dell'orario personale, cerca nell'agenda ufficiale eventi di tipo lezione
  nella stessa settimana con titolo compatibile (normalizzazione già esistente) *e* stesso giorno/ora ±15 min.
  Stato per insegnamento: `solo personale` → `confermato dall'agenda` (≥2 lezioni combacianti).
- **Dedup in vista**: se confermato, mostra l'evento ufficiale e nascondi quello personale; se l'agenda ha lezioni
  che l'orario personale non ha, mostrale entrambe con badge "ufficiale".
- **Ritiro**: quando tutti (o ≥80%) gli insegnamenti sono confermati → prompt "L'orario ufficiale è arrivato: archivio
  quello personale?". Anche segnale forte: `career.planHeader` / `/v1/insegn` che elenca gli stessi codici [I].
- **Override per corso**: toggle "usa sempre l'orario personale" / "nascondi" per singolo `Entry`
  (utile per insegnamenti fuori piano, uditore, anno successivo).

### Rischi
Titoli diversi tra manifesto (inglese/maiuscolo) e agenda; corsi integrati con più moduli; agenda vuota nei primi
giorni anche dopo l'approvazione (già discusso in `docs/endpoint-status.md`).

### Domande aperte
Esiste un endpoint "stato piano di studi" (presentato/approvato)? Da cercare nel bundle dell'app ufficiale (`docs/polimi-api-research.md` non lo elenca).

---

## 3. Programma lento; Forum e Avvisi introvabili

### Stato attuale — perché il programma è lento [V]
`CourseSyllabusView.task` (`SyllabusView.swift:236-246`) esegue, **solo quando si apre la pagina**:
1. `POST RicercaPerInsegnamentoPublic.do` su tutto l'ateneo (`ManifestiService.swift:152-160`): **1,25 s**, 52 KB.
2. fino a **8** pagine di dettaglio (`pickCandidates = 8`, `:184`), lanciate in un `TaskGroup` (`:169-176`): ~1,7–2 s ciascuna.
3. la scheda (`SchedaPublic.do`): **1,0 s**.

Il collo di bottiglia: la `URLSession` usa il jar con `JSESSIONID` (`:46-53`) e **il server serializza le richieste
della stessa sessione**, quindi il "parallelo" diventa sequenziale: 8 dettagli ≈ 12–14 s, totale 15 s circa [V, misurato].
Inoltre `picks` e i `ResourceLoader` sono solo in memoria (`:62-80`, `:145`) e i POST non sono cacheabili da
`URLCache` → ogni avvio dell'app ripaga tutto [V].

### Ottimizzazioni proposte
1. **Sessione senza cookie** per ricerca, dettaglio e scheda (`httpShouldSetCookies = false`, jar nullo); il jar solo per il
   carrello. Da solo porta i dettagli da ~12 s a ~2 s [V, misurato con curl].
2. **Prefetch** all'ingresso in `CourseDetailView` (`.task` a `:148-151`): avviare `syllabusPick` a bassa priorità, così
   il tap su "Programma" trova il risultato pronto (i `ResourceLoader` condividono già l'in-flight).
3. **Restringere la ricerca**: passare `k_cf`/`sede` dal piano di studi quando noti, e ordinare i candidati mettendo per
   primo il `k_corso_la` del proprio corso: spesso basta 1 dettaglio (early exit invece di leggerne 8).
4. **Cache su disco** della coppia `teachingCode+anno → (syllabusID, degree)` e della `Syllabus` (cambiano al più
   annualmente; TTL 7 giorni + refresh in background, stile `docs/data-freshness.md`).
5. Mostrare subito la scheda in cache con indicatore "aggiornamento…".

### Forum e Avvisi — dove sono oggi [V]
- In UI **non esistono**. Gli avvisi vengono letti solo dal passaggio in background `checkForUpdates`
  (`WeBeepService.swift:255-262`, `AnnouncementDetector.forumInstances` in `Models/Announcement.swift:20-25`) e finiscono
  nel feed "Novità", di cui la pagina corso mostra al massimo 3 elementi (`CourseDetailView.swift:73-90`).
- `loadMaterials` scarta tutti i moduli non-file (`WeBeepService.swift` ~`:185-190`, `guard content.type == "file"`):
  forum, url, compiti non arrivano mai a `CourseMaterialsView`.
- Il forum di discussione (non avvisi) è escluso di proposito dal detector (`Announcement.swift:16-19`).

### Pagina corso come hub — **Fattibile**
Griglia di pulsanti in cima a `CourseDetailView`: **Avvisi** (`mod_forum_get_forum_discussions` sul forum rilevato,
già in `WeBeepAPI.swift:98-106`), **Forum** (altri moduli `modname == "forum"` + `mod_forum_get_discussion_posts` per il
thread [I: non ancora in `WeBeepAPI`]), **Materiali** (esistente), **Programma** (esistente), **Info** (docente, CFU,
modalità d'esame da `ExamFormatSection`), **Appelli** (sezione esistente `:57-71`). Il `core_course_get_contents`
già scaricato per i materiali contiene tutti i moduli: una sola richiesta alimenta Avvisi/Forum/Materiali.
Badge "non letti" dal feed esistente.

Rischi: forum con permessi di sola lettura o gruppi; alcuni docenti usano "Avvisi" come label e non come forum.

---

## 4. Prove in itinere

### Cosa espongono le fonti
- **Scheda insegnamento (pubblica)** [V]: la sezione "Modalità di valutazione" contiene voci standardizzate, es.
  *"Prova scritta obbligatoria, senza prove in itinere"*, *"Prova orale condizionata (a scelta del docente)"*,
  *"Valutazione continua facoltativa"* — già separate dall'app in `assessment` vs `assessmentNotes`
  (`Models/Manifesto.swift:219`, `docs/manifesti.md:94`). Il testo libero del docente spiega (a volte) pesi e
  regole di sostituzione dell'esame.
- **IAE (autenticato)** [V da `docs/polimi-api-research.md` §4c]: `/v1/insegn` con `appelliEsame[]`, ogni appello ha
  `descTipoAppello` (mappato in `ExamSession.kind`, `Models/Career.swift:134,174,222`) ed eventuale
  `iscrizioneAttiva` con esito (`verb_esito`, `verb_positivo`, `rifiutabile`). Se il docente pubblica le prove in itinere
  come appelli con iscrizione, tipo ed esito arrivano qui [I: non osservato un `descTipoAppello` "in itinere"].
- **Agenda**: le prove compaiono come eventi d'esame (esempio nei mock `MockData.swift:200`) [I sui dati reali].
- **WeBeep**: esiti delle prove spesso come PDF/XLSX nei materiali; l'app li legge già (`ResultsFileReader`,
  `WeBeepService.swift:301-320`) [V].
- **Libretto**: registra solo il voto finale verbalizzato; nessun campo per voti parziali [I, da `elencoinsegnamenti`].

### Valutazione: **Parzialmente fattibile**
| Domanda | Risposta |
| --- | --- |
| Il corso prevede prove in itinere? | Sì, dalla scheda (dato strutturato) [V] |
| Le ho sostenute? | Solo se gestite come appello IAE o evento agenda [I] |
| Voto | Da esito IAE o dal file risultati WeBeep (euristico) [I] |
| Come pesano sull'esame | Solo testo libero del docente: mostrabile, non calcolabile in modo affidabile |

### Approccio
Riga "Prove in itinere: sì/no" nella pagina Info del corso (dalla scheda); timeline che unisce appelli IAE con
`kind` contenente "itinere/intermedia/parziale", eventi agenda e file risultati; testo docente citato così com'è.
Nessun calcolo del voto finale.

### Domande aperte
Serve un campione reale di `descTipoAppello` per un corso con prove in itinere (loggare in debug durante il semestre).

---

## 5. WeBeep vs matricola (986617 triennale / 337940 magistrale condizionata)

### Stato attuale [V]
- `core_enrol_get_users_courses` (`WeBeepAPI.swift:90-96`); il modello decodifica solo `id, fullname, shortname,
  startdate, enddate, isfavourite, hidden` (`Models/Moodle.swift:19-27`).
- L'associazione corso PoliMi ↔ Moodle è per codice nel titolo o per nome (`WeBeepService.swift:378-403`).
- Token WeBeep legato al codice persona (`docs/webeep.md:76`); l'app ha già la gestione carriera errata
  (`Features/Auth/CareerMismatchBanner.swift`).

### Cosa dice Moodle [V, sorgente `public/enrol/externallib.php`]
- `core_enrol_get_users_courses` restituisce `idnumber`, `category`, `visible`, `enrolledusercount`, `lastaccess`,
  `startdate/enddate`, ma **nessun campo sul metodo di iscrizione**.
- `core_enrol_get_course_enrolment_methods(courseid)` elenca le *istanze* attive del corso che hanno `get_enrol_info`
  (tipicamente `self`, `guest`, `fee`), non quale metodo ha iscritto l'utente.
- Non esiste una funzione web service standard che dica "utente X iscritto via plugin Y" per uno studente
  (serve `core_enrol_get_enrolled_users` con capability docente) [I da conoscenza del core].

### Valutazione: **Parzialmente fattibile** (euristica, mai certezza)
Un segnale diretto "piano di studi vs autoiscrizione" non c'è. Si può però classificare con buona affidabilità:
1. Decodificare anche `idnumber`, `category`, `lastaccess`. Se `idnumber`/`shortname` codificano codice insegnamento,
   anno e sezione [I: da verificare su un account reale], si confrontano con:
2. i codici del piano/libretto **per ciascuna matricola** (`/elencoinsegnamenti/{matricola}`, `/v1/insegn` per carriera attiva).
3. Classi: **nel piano della carriera attiva** · **nel piano dell'altra carriera** (986617) · **fuori piano**
   (probabile autoiscrizione o anno precedente). Se `core_enrol_get_course_enrolment_methods` mostra un'istanza `self`
   attiva, "fuori piano" diventa "probabile autoiscrizione".
4. UI: filtro nella lista corsi WeBeep + etichetta; override manuale persistente.

### Rischi
Corsi mutuati/integrati con codici diversi; per la magistrale condizionata il piano può non esistere ancora →
tutti "fuori piano" (usare l'orario personale di §1 come fonte secondaria); le chiamate IAE per la carriera non attiva
richiedono lo switch di token (401, cfr. `CareerMismatchBanner`).

### Domande aperte
Formato reale di `idnumber` su WeBeep (serve un dump da debug). Il libretto triennale è leggibile con il token della magistrale?

---

## 6. Lag della mappa campus e caricamento progressivo

### Stato attuale [V]
- `CampusMapView.task` attende `map.load` prima di qualsiasi pin (`CampusMapView.swift:37-40`); `load` attende
  prima l'intero catalogo aule (4 richieste, `RoomsService.swift:71-86`) e poi il geojson (`CampusMapService.swift:66-80`).
- Geojson: 274 KB, 0,4 s [V misurato]; le coordinate sono solo in memoria (`CampusMapService.swift:33`), rifatte a ogni avvio.
- Decodifica: su main actor nel commit, spostata off-main dal file non committato `BackgroundJSON.swift` (diff su
  `CampusMapService.swift:136`) [V]. Il join del catalogo e il raggruppamento dei pin restano sul main actor
  (`RoomsService.swift:88-117`, `CampusMapService.swift:79-90`).
- `RoomsService.init` legge la cache disco in modo sincrono (`RoomsService.swift:47-52`) [V].
- `loadAvailability` è quadratico: per ogni pin `rooms(in:)` filtra tutte le aule e per ogni aula `freeRooms.rooms.contains`
  (`CampusMapService.swift:113-121`) [V].
- `onChange(campus)` rilancia `load` e ricentra con animazione; la posizione iniziale `.automatic` + ricentro animato causa
  un salto di camera [I].

### Valutazione: **Fattibile**

### Approccio
1. Mappa subito con regione di default del campus (coordinate note in app), pin **dopo**.
2. Cache disco di `locations` (edifici non si muovono) + cache aule già esistente ⇒ pin da cache in <100 ms, refresh silenzioso.
3. Streaming: se la cache manca, mostrare i pin appena arriva il geojson usando i nomi edificio, arricchendo il conteggio aule
   quando arriva il catalogo (due fasi invece di un `await` unico).
4. Tutto il lavoro di join/raggruppamento in una funzione `@concurrent` che restituisce `[MapPin]` `Sendable`.
5. `loadAvailability`: pre-indicizzare `Dictionary(grouping:)` e `Set` degli id → O(n).
6. Clustering: SwiftUI `Map` non espone clustering; se i pin crescono servono `MKMapView` + `clusteringIdentifier`
   (https://developer.apple.com/documentation/mapkit/mkannotationview/clusteringidentifier). Con qualche decina di
   edifici oggi non è necessario [I].

### Pattern generale per le sezioni con scraping
"Cache → vista immediata → rete in background → diff": `ResourceLoader` (`Services/ResourceLoader.swift:35`) per dedup e TTL,
`BackgroundJSON`/parser `nonisolated` `@concurrent` per decodifica e parsing HTML, cache su disco con età mostrata
(`docs/data-freshness.md`), sessioni **senza cookie** per le letture pubbliche (vedi §3), prefetch all'ingresso della
schermata padre. Candidati: Manifesti/Programma, Aule libere (150 richieste), Novità, Mappa.

---

## 7. Pianta dell'aula a schermo intero con zoom

### Stato attuale [V]
Il pinch **esiste già**: `ZoomableImage` (`Features/Search/FloorPlanView.swift:47-83`) = `ScrollView([.horizontal,.vertical])`
+ `.gesture(MagnifyGesture())` che ridimensiona il `frame` (zoom 1–6, pulsante "Adatta").
Probabili cause del "non c'è lo zoom" [I, da provare su dispositivo]:
- il `MagnifyGesture` è attaccato con `.gesture` sopra una `ScrollView` il cui pan UIKit compete; il pinch può non essere riconosciuto
  o essere intermittente;
- lo zoom è ancorato in alto a sinistra (non al punto del pinch), cambiando `frame` il contenuto "scappa";
- nessun doppio tap; la vista è una `NavigationLink` push, non un vero full-screen;
- l'immagine è quella di `AsyncImage` a risoluzione di rete ma ridisegnata a ogni cambio di frame.

### Valutazione: **Fattibile**

### Approccio consigliato
`UIViewRepresentable` con `UIScrollView` (`minimumZoomScale`, `maximumZoomScale`, delegate `viewForZooming(in:)`,
doppio tap con `zoom(to:animated:)`, centratura in `scrollViewDidZoom`) contenente un `UIImageView`:
zoom ancorato al pinch, rimbalzo e inerzia di sistema.
Riferimenti Apple: https://developer.apple.com/documentation/uikit/uiscrollview ,
https://developer.apple.com/documentation/uikit/uiscrollviewdelegate/viewforzooming(in:) ,
https://developer.apple.com/documentation/uikit/uiscrollview/zoom(to:animated:).
Presentarla con `.fullScreenCover` + pulsante chiudi. Scaricare l'immagine una volta come `UIImage` (non `Image`).
Alternativa solo SwiftUI: `MagnifyGesture` (https://developer.apple.com/documentation/swiftui/magnifygesture) con
`.simultaneousGesture` e `scaleEffect(anchor:)` calcolato da `startAnchor` — più codice e meno naturale.

---

## Riepilogo prioritizzato

| # | Tema | Fattibilità | Impatto | Sforzo | Priorità |
| --- | --- | --- | --- | --- | --- |
| 3a | Programma lento (sessione senza cookie, prefetch, cache disco) | Fattibile | Alto (15 s → ~2 s) | Basso | **1** |
| 7 | Pianta: `UIScrollView` zoom + full-screen | Fattibile | Medio | Basso | **2** |
| 6 | Mappa progressiva + cache coordinate | Fattibile | Medio | Basso-medio | **3** |
| 1 | Orario personalizzato nativo (parser orario testuale) | Fattibile | Alto, stagionale (ora!) | Medio-alto | **4** |
| 3b | Pagina corso hub con Avvisi/Forum | Fattibile | Alto | Medio | **5** |
| 2 | Transizione verso agenda ufficiale | Parziale | Medio | Medio | 6 (dopo 1) |
| 5 | Classificazione iscrizioni WeBeep | Parziale | Medio | Medio | 7 (serve dump `idnumber`) |
| 4 | Prove in itinere | Parziale | Basso-medio | Basso (solo "sì/no" dalla scheda) | 8 |
