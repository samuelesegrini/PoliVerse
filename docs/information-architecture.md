# Information architecture — proposta di ristrutturazione

Documento di ricerca (15/09/2026). Nessun codice modificato. Fonti: il codice del repo
(autorità sui dati) e le Human Interface Guidelines / documentazione SwiftUI su
developer.apple.com (lette dal JSON pubblico delle pagine il 15/09/2026). Le citazioni sono
frasi brevi; ogni affermazione di linea guida riporta l'URL.

Legenda: **[V]** verificato nel codice o nella pagina Apple; **[I]** dedotto.

---

## 0. Struttura adottata nella nuova interfaccia

Aggiornato il 15/09/2026, dopo la revisione in `docs/newui-information-architecture-review.md`.
Dove questa sezione e le sezioni successive non coincidono, vale questa: il resto del documento
è la ricerca da cui si è partiti.

**Una domanda per scheda** (aggiornato il 24/09/2026). Ogni informazione ha una sola casa; le
altre schede ci portano con un collegamento, senza ripeterla.

| Scheda | Domanda | Casa di |
| --- | --- | --- |
| Oggi | Cosa devo fare oggi, e adesso? | lezione in corso e orario del giorno, scadenze WeBeep, calendario completo (pulsante nella barra) |
| Corsi | Cosa c'è di nuovo nei miei corsi? | in cima il corso con più novità (non quello della lezione), preferiti e tutti i corsi |
| Carriera | Dove sono, e cosa scade? | iscrizioni e voti da decidere, media e libretto, piano di studi, simulazione, Manifesto e orario personalizzato («Offerta didattica») |
| Cerca | Dov'è, chi è, dove lo trovo? | la ricerca, le ricerche recenti, Campus (aule libere, mappa, aule), i docenti, Notizie e Notifiche |

La lezione in corso sopra le schede resta la sola presenza del «adesso» fuori da Oggi. I tipi di
risultato di Cerca sono chip con il loro conteggio sopra i risultati, non una riga della pagina
prima della ricerca.

**Tab (4 + ricerca).** Oggi, Corsi, Carriera, Cerca. L'elenco dei luoghi è uno solo, `NewDestination`
(`PoliVerse/Features/Shell/NewDestination.swift`); ogni luogo sta nella scheda della sua domanda e
un ingresso da fuori (Siri, Controlli, notifiche) lo apre lì:

| Luogo | Nei tab | Nella pagina unica |
| --- | --- | --- |
| Corsi | tab Corsi | riga del pannello |
| Carriera | tab Carriera, con il badge delle novità | riga del pannello |
| Calendario | dalla barra di Oggi | riga del pannello |
| Piano di studi | dal menu di Carriera | riga del pannello |
| Aule libere, Mappa, Notizie, Notifiche | righe di Cerca | righe del pannello |
| Ricerca (`SearchView`) | tab Cerca | riga «Cerca» in cima al pannello |

**Profilo da ogni root.** La foto nella barra di Oggi, Corsi, Carriera e Cerca apre Impostazioni
già sulla pagina Profilo; le pagine del profilo (contatto, foto, carriera) sono push, non sheet.
Esci sta solo in Impostazioni.

**Barra di Oggi.** Profilo (nascondibile), Impostazioni (sempre), il giorno (nascondibile),
Personalizza (sempre). Impostazioni e Personalizza non si possono nascondere: sono la strada
per tornarci.

**Oggi.** Le righe di lezioni, lezione in corso ed esami aprono il loro dettaglio in sheet
(`EventDetailView`, `ExamDetailView`); le scadenze WeBeep non hanno ancora una schermata.
La lezione in corso sopra i tab (o nel pannello) apre anch'essa il dettaglio; su Oggi non compare
se lo stile in uso mostra già la sezione «Lezione in corso».
L'agenda si carica attorno al giorno mostrato.

**Ingressi da fuori.** Siri, Comandi rapidi, Centro di Controllo e notifiche passano da
`AppShellDuties` (`PoliVerse/App/AppShellDuties.swift`), condiviso dalle due interfacce, insieme a
Spotlight, promemoria e banner dei dati di esempio. Nella nuova interfaccia `NewRoute` sceglie il
tab, o apre il pannello della pagina unica sul luogo.

**Personalizza.** Un solo punto di conferma per azione: nell'editor «Fine» salva lo stile, nella
galleria ✓ lo usa, «Chiudi» lascia la pagina sullo stile che già usa (salvare proprio quello
cambia subito la pagina). «Annulla» chiede prima di scartare modifiche.
Le pagine del pannello tornano indietro con il pulsante di sistema e cambiano lo stile mentre si
tocca; l'emoji keyboard degli sticker è una pagina del pannello, non uno sheet sopra. Uno stile
si elimina tenendo premuta la sua scheda (resta sempre almeno uno stile).

### Glossario

| Parola | Significa | Non usare per |
| --- | --- | --- |
| **Flavor** | la personalità di tutta l'app, salvata nella galleria di Personalizza. I **classici** si cambiano in ogni parte; gli **speciali** (Giocherelloso, Blueprint) hanno forme proprie nelle pagine e solo poche regolazioni loro | «stile», «tema» |
| **Colore** | il colore scelto; l'app ne ricava accento ed extra, che si possono cambiare a mano | «Flavor» per i colori |
| **Icona** | l'icona dell'app nella Home: una **Forma** (Orbita, Giorno, Vicino, Speciali) e, per Giorno e Vicino, un colore | «tema» per le icone |
| **Aspetto** | sistema, chiaro, scuro, contrasto, tinto | i Flavor salvati, l'aspetto delle sezioni |
| **Carta** | su cosa è stampata la pagina — una carta (liscia, millimetrata, da disegno, puntinata) **oppure** una decorazione nel tuo colore — più la grana | la superficie delle sezioni |
| **Superficie** | come è disegnata una sezione (vetro, pieno, bagliore…) | la carta |
| **Data** | il blocco della data; la sua **Forma** è come è composta | «Widget», che nell'app sono i widget della Home |
| **Sezioni** | la pagina che ordina, nasconde e aggiunge le sezioni | «Layout» |
| **Disponi** | trascinare sezioni e sticker sulla pagina | — |
| **Disposizione** | tab o pagina unica, in Impostazioni | la forma della data |
| **Schede** | i tab dell'app | le sezioni di Oggi |
| **Nascondi** | togliere dalla pagina una sezione o il saluto, che tengono le impostazioni | sticker e foto |
| **Rimuovi** | togliere sticker, foto o accessorio | sezioni |
| **Chiudi** | lasciare uno sheet o la galleria senza cambiare nulla | salvare |
| **Fine** | salvare le modifiche fatte | chiudere senza salvare |

---

## 1. Sintesi della raccomandazione

Oggi: 5 tab — Home, WeBeep, Calendario, Carriera, Cerca (`PoliVerse/App/RootView.swift:67-76`) [V].
Il problema non è il numero, ma il **taglio**: due tab mostrano la stessa lista corsi con
destinazioni diverse, e metà delle funzioni (piano, manifesto, orario personalizzato,
simulatore, mappa, aule) vive come scorciatoia nella landing della ricerca.

Proposta (4 tab + search tab, sidebarAdaptable su iPad):

| Tab | Icona | Root | Perché |
| --- | --- | --- | --- |
| **Oggi** | `sun.max` | dashboard: prossima lezione, novità esami non lette, scadenze, prossimo appello | È la ragione delle visite brevi (vedi `CareerView.swift:171-172`: "the reason most visits happen") |
| **Corsi** | `books.vertical` | lista unica dei corsi (ex Home grid + WeBeep) → hub del corso | Un solo posto per materiali/forum/syllabus/appelli di un corso |
| **Calendario** | `calendar` | agenda settimanale (lezioni, esami, scadenze) | Invariato, alta frequenza |
| **Carriera** | `graduationcap` | appelli, esiti/libretto, media, piano di studi, simulatore, manifesto | Tutto ciò che riguarda il percorso, non il singolo corso |
| **Cerca** (role `.search`) | `magnifyingglass` | landing con Aule libere, Mappa, Docenti + ricerca globale | Scoperta + luoghi/persone |

Motivazioni principali:
- Il tab bar serve "to support navigation, not to provide actions" e conviene pesare ogni tab
  contro "the need for people to frequently access each section"
  — https://developer.apple.com/design/human-interface-guidelines/tab-bars
- Su iPad, default "five or fewer" per continuità tra compact e regular, con sidebar per
  "a wider set of navigation options" — https://developer.apple.com/design/human-interface-guidelines/tab-bars
- Search come tab dedicato in coda: "A tab bar can include a dedicated search tab at the trailing end"
  — https://developer.apple.com/design/human-interface-guidelines/tab-bars
- "Aim to make your app's content searchable through a single location"
  — https://developer.apple.com/design/human-interface-guidelines/searching
- Impostazioni e Notifiche PoliMi escono dalla Home e diventano un sheet profilo (avatar), non un tab.

---

## 2. Inventario dei dati

Frequenza: A = più volte al giorno, M = settimanale / in sessione d'esame, B = poche volte l'anno. [I] salvo nota.

| Dominio | Posizione attuale | Freq. | Casa proposta | Presentazione | Linea guida |
| --- | --- | --- | --- | --- | --- |
| Agenda / orario (lezioni, esami, scadenze) | Tab Calendario (`Features/Calendar/CalendarView.swift:40-72`); "Oggi" in Home (`Features/Home/HomeView.swift:52-58`); widget Oggi/Prossima lezione (`PoliVerseWidgets/TodayWidget.swift:65-71`, `NextLectureWidget.swift:75-81`) | A | Tab Calendario; estratto in Oggi; widget | Lista per giorno; dettaglio evento in **sheet medium** | Sheet per "a simple task" + medium detent per "progressive disclosure" — https://developer.apple.com/design/human-interface-guidelines/sheets |
| Dettaglio evento + Live Activity "sto andando" | Sheet da Calendario (`CalendarView.swift:72`, `EventDetailView.swift:11`); avvio manuale (`Services/LiveActivityController.swift:1-6`) | A | Invariato | Sheet; Live Activity | "tasks and events that have a defined beginning and end" — https://developer.apple.com/design/human-interface-guidelines/live-activities |
| Corsi (PoliMi + WeBeep) | Griglia Home (`HomeView.swift:70-91`) → `CourseDetailView`; lista tab WeBeep (`Features/WeBeep/WeBeepView.swift:73,168`) → `CourseMaterialsView` | A | Tab Corsi (lista unica, preferiti in testa, filtro anno/origine in menu) | **List** (testo) → push hub | "Prefer displaying text in a list or table"; collection per contenuti a immagini — https://developer.apple.com/design/human-interface-guidelines/lists-and-tables, https://developer.apple.com/design/human-interface-guidelines/collections |
| Hub corso (lezioni, appelli, "In breve", novità) | `Features/Home/CourseDetailView.swift:60-122` | A/M | Tab Corsi → push | Push; sezioni con disclosure | "hide details until they're relevant" — https://developer.apple.com/design/human-interface-guidelines/disclosure-controls |
| Materiali WeBeep | `Features/WeBeep/CourseMaterialsView.swift:97-127` (ricerca locale, anteprima in sheet) | A in sessione | Hub corso → push | Push lista; anteprima file **full screen** | Full-screen modal per contenuti "in-depth" — https://developer.apple.com/design/human-interface-guidelines/modality |
| Forum / Annunci | `Features/WeBeep/CourseForumView.swift:54,112` da hub (`CourseDetailView.swift:278,290`) | M | Hub corso → push | Push lista → push thread | Liste per gerarchia — https://developer.apple.com/design/human-interface-guidelines/lists-and-tables |
| Syllabus / info corso | `Features/Manifesti/SyllabusView.swift:314-317` (4 sheet), `Features/Home/CourseInfoView.swift` | B | Hub corso → push | Push; scelte piano/scaglione in sheet singolo | "Display only one sheet at a time" — https://developer.apple.com/design/human-interface-guidelines/sheets |
| Appelli e iscrizione | Segmento "Appelli" Carriera (`Features/Career/CareerView.swift:212-226`); hub corso (`CourseDetailView.swift:73-90`); Home "Prossimo esame" (`HomeView.swift:60-64`) | M (A in sessione) | Carriera → Appelli; estratto in Oggi e hub | Lista → **push** `ExamDetailView` (non sheet: contiene navigazione) | Evitare "a hierarchy of views within a modal task" — https://developer.apple.com/design/human-interface-guidelines/modality |
| Novità esami (feed) | Carriera Riepilogo (`CareerView.swift:173-208`), badge sul tab (`RootView.swift:72-74`), hub corso (`CourseDetailView.swift:96-110`), `ExamUpdatesView` push | A in sessione | Oggi (non lette in testa) + badge sul tab Oggi; lista completa in Carriera | Lista; notifiche locali | Badge "Reserve badges for critical information" — https://developer.apple.com/design/human-interface-guidelines/tab-bars; notifiche "concise, informative" — https://developer.apple.com/design/human-interface-guidelines/notifications |
| Libretto / esiti / media / base 110 / CFU | Carriera Riepilogo/Esiti (`CareerView.swift:102-169`); widget Carriera (`PoliVerseWidgets/CareerWidget.swift:50-56`) | M | Carriera root | Stat + lista; grafici Swift Charts eventuali | Dati prominenti, assi secondari — https://developer.apple.com/design/human-interface-guidelines/charts |
| Simulatore media | Carriera (`CareerView.swift:57-65`), Piano (`Features/Plan/StudyPlanView.swift:40-41`), landing Cerca (`Features/Search/SearchView.swift:162-163`) | B/M | Carriera → push (uno solo) | Push | Un solo percorso chiaro [I] |
| Piano di studi | Carriera (`CareerView.swift:48-56`), landing Cerca (`SearchView.swift:147-148`) | B | Carriera → push | Lista per anno | Liste — https://developer.apple.com/design/human-interface-guidelines/lists-and-tables |
| Manifesto degli studi / catalogo | Solo landing Cerca (`SearchView.swift:152-153`) → `ManifestiView` | B | Carriera → sezione "Offerta didattica" | Push + `searchable` locale | Ricerca locale ammessa "for apps with clearly distinct sections" — https://developer.apple.com/design/human-interface-guidelines/searching |
| Orario personalizzato (carrello) | Solo landing Cerca (`SearchView.swift:157-158`) | B (inizio semestre) | Carriera → Offerta didattica; oppure azione in Calendario | Push; flusso a step in sheet large | "For complex or prolonged user flows, consider alternatives to sheets" — https://developer.apple.com/design/human-interface-guidelines/sheets |
| Docenti | Risultati Cerca → `TeacherDetailView` (`SearchView.swift:170-185`) | M | Cerca; link dall'hub corso | Push | — |
| Aule, aule libere, planimetrie | Landing Cerca → `RoomsView` → `FreeRoomsView` (`Features/Search/RoomsView.swift:26-43`); widget Aule libere (`PoliVerseWidgets/FreeRoomsWidget.swift:97-105`) | A (tra lezioni) | Cerca landing (voce in testa); widget | Push; planimetria full screen (`FloorPlanView.swift:41`) | "Choose the standard tab style to provide suggestions, promote discovery" — https://developer.apple.com/design/human-interface-guidelines/search-fields |
| Mappa campus | Landing Cerca, `RoomsView.swift:27`; pin in sheet (`Features/Map/CampusMapView.swift:58-59`) | M | Cerca landing | Push mappa; edificio in sheet con detent | Sheet non modale su iOS — https://developer.apple.com/design/human-interface-guidelines/sheets |
| Notizie PoliMi | Fondo Home (`HomeView.swift:96`, `Features/News/NewsView.swift:133-151`) | B | Oggi (in fondo) + Cerca | Lista → push | Contenuto scorrevole in fondo, come già motivato in `HomeView.swift:93-95` |
| Avvisi (Notices) | Sheet dalla toolbar Home (`HomeView.swift:124-129`) con push interno (`Features/Notices/NoticesView.swift:9,50`) | M | Oggi → push lista (non sheet) | Push | Evitare navigazione in modale — https://developer.apple.com/design/human-interface-guidelines/modality |
| Carriere (più matricole) | Impostazioni (`Features/Auth/SettingsView.swift:20-21`), banner (`Features/Auth/CareerMismatchBanner.swift:18-19`) | B | Sheet profilo; menu nel titolo di Carriera | Menu | Menu per "options" contestuali — https://developer.apple.com/design/human-interface-guidelines/menus |
| Impostazioni, notifiche, WeBeep, dati, diagnostica | Push dall'avatar Home (`HomeView.swift:106-110`, `SettingsView.swift`) | B | Sheet profilo raggiungibile da ogni root | Sheet large con NavigationStack a percorso singolo | "provide a single path through the hierarchy" — https://developer.apple.com/design/human-interface-guidelines/modality |
| Onboarding / login | `RootView.swift:10-21`, `Features/Onboarding/` | una tantum | Invariato | Flusso a step | "fast, fun, and optional" — https://developer.apple.com/design/human-interface-guidelines/onboarding |
| Siri / Shortcuts / Controlli | `PoliVerse/App/AppShortcuts.swift:8-43`, `PoliVerseWidgets/ControlWidgets.swift:12-36`, routing `RootView.swift:43-51` | M | Invariati, ma con deep link al punto esatto | App Intents | — |
| Spotlight | `Services/SpotlightIndex.swift`, indicizzazione `RootView.swift:112-119` | M | Invariato + esiti/appelli apribili | Systemwide search | "Make your app's content searchable in Spotlight" — https://developer.apple.com/design/human-interface-guidelines/searching |

---

## 3. Struttura dei tab e alberi di navigazione

```
TabView (style .sidebarAdaptable)
├─ Oggi                          NavigationStack
│  ├─ [toolbar] avatar → sheet Profilo
│  ├─ Adesso / prossima lezione  → sheet Evento (medium/large)
│  ├─ Novità esami non lette     → push ExamDetail
│  ├─ Scadenze (consegne WeBeep) → push Materiali del corso
│  ├─ Prossimo appello           → push ExamDetail
│  ├─ Avvisi                     → push NoticesList → push NoticeDetail
│  └─ Notizie (3)                → push NewsList → push NewsDetail
├─ Corsi                         NavigationStack
│  ├─ [toolbar] Menu filtro: anno, origine (piano / altra carriera / a scelta), nascosti
│  └─ Corso (hub)                push
│     ├─ Materiali   → push (ricerca locale) → anteprima full screen
│     ├─ Annunci     → push → thread
│     ├─ Forum       → push → thread
│     ├─ Appelli     → push ExamDetail
│     ├─ Syllabus    → push (scelta piano/scaglione in sheet)
│     └─ Info corso / Docenti → push TeacherDetail
├─ Calendario                    NavigationStack
│  ├─ [toolbar] Oggi, Menu filtro (Tutto/Lezioni/Scadenze)
│  └─ Evento → sheet (azioni: aggiungi al calendario, Live Activity, apri corso = chiudi + deep link)
├─ Carriera                      NavigationStack
│  ├─ [titolo] Menu carriera (se più matricole)
│  ├─ Riepilogo: media, base 110, CFU
│  ├─ Appelli     → push ExamDetail → push Corso
│  ├─ Esiti       → push ExamDetail
│  ├─ Novità esami (tutte) → push
│  ├─ Piano di studi → push → Simulatore
│  ├─ Simulatore media → push
│  └─ Offerta didattica
│     ├─ Manifesto  → push → ManifestoDetail
│     └─ Orario personalizzato → push
└─ Cerca (Tab role .search)      NavigationStack
   ├─ Landing: Aule libere, Mappa, Aule, Docenti recenti, ricerche recenti
   └─ Risultati per scope → push al dettaglio proprio di ogni tipo
```

**iPhone.** Tab bar in basso su Liquid Glass; valutare `tabBarMinimizeBehavior(.onScrollDown)`
per Corsi e Materiali (liste lunghe). La barra "Oggi" o una lezione in corso può stare in
`tabViewBottomAccessory` — "when the tab bar is collapsed, the accessory displays inline"
(https://developer.apple.com/documentation/swiftui/view/tabviewbottomaccessory(content:)).
Liquid Glass è il livello "for controls and navigation elements", non per il contenuto
(https://developer.apple.com/design/human-interface-guidelines/materials): le card di
`DemoModeBanner`/`FreshnessBar` restano nel content layer.

**iPad.** `.tabViewStyle(.sidebarAdaptable)` ("iPadOS displays a top tab bar that can adapt into a sidebar",
https://developer.apple.com/documentation/swiftui/tabviewstyle/sidebaradaptable). In sidebar,
un `TabSection("Corsi")` elenca i preferiti come tab secondari e un `TabSection("Carriera")`
espone Appelli / Esiti / Piano (https://developer.apple.com/documentation/swiftui/tabsection).
Massimo due livelli: "show no more than two levels of hierarchy in a sidebar"
(https://developer.apple.com/design/human-interface-guidelines/sidebars). Dentro Corsi e
Carriera, in regular width, `NavigationSplitView` lista → dettaglio
(https://developer.apple.com/documentation/swiftui/navigationsplitview), con selezione
persistente (https://developer.apple.com/design/human-interface-guidelines/split-views).
Non esiste una pagina HIG "Inspectors" (URL 404 il 15/09/2026); l'API `inspector` si adatta "to a sheet"
in compact (https://developer.apple.com/documentation/swiftui/view/inspector(ispresented:content:)):
utile su iPad per il dettaglio evento del Calendario e i metadati di un file.

---

## 4. Regole di presentazione per PoliVerse

| Caso | Scelta | Citazione |
| --- | --- | --- |
| Entrare in un oggetto con sotto-navigazione (corso, appello, docente, forum) | **Push** | Tab bar mantiene "the current navigation state within each section" — https://developer.apple.com/design/human-interface-guidelines/tab-bars |
| Oggetto foglia consultato al volo (evento, edificio sulla mappa) | **Sheet** medium+large, con grabber | medium detent "to allow progressive disclosure" — https://developer.apple.com/design/human-interface-guidelines/sheets |
| Compito breve che produce un dato (aggiungi a Calendario, scegli scaglione/piano, login WeBeep) | **Sheet** con Annulla/Fine | "presenting a simple task that they can complete before returning to the parent view" — https://developer.apple.com/design/human-interface-guidelines/sheets |
| Flussi lunghi (orario personalizzato, onboarding) | Push o **full screen** | "For complex or prolonged user flows, consider alternatives to sheets" — https://developer.apple.com/design/human-interface-guidelines/sheets |
| Anteprima PDF / planimetria | **Full screen** | "full-screen modal style for in-depth content" — https://developer.apple.com/design/human-interface-guidelines/modality |
| Mai sheet su sheet | chiudere prima | "Display only one sheet at a time from the main interface" — https://developer.apple.com/design/human-interface-guidelines/sheets |
| Filtri (anno, origine, tipo evento) e cambio carriera | **Menu** in toolbar, non segmented in testa al contenuto | Toolbar per "Actions, or bar items, like buttons and menus"; evitare "overcrowding" — https://developer.apple.com/design/human-interface-guidelines/toolbars |
| Azioni su una riga (preferito, nascondi, silenzia) | **Context menu** + swipe | "a context-menus lets people access a small number of frequently used actions" — https://developer.apple.com/design/human-interface-guidelines/menus |
| Dettagli secondari nell'hub corso / ExamDetail | **DisclosureGroup** | https://developer.apple.com/design/human-interface-guidelines/disclosure-controls |
| Errori di servizio | Alert o `ContentUnavailableView` inline, non notifica | "Use an alert — not a notification — to display an error message" — https://developer.apple.com/design/human-interface-guidelines/notifications |
| Tab senza dati (carriera non abilitata) | Tab visibile + spiegazione | "Don't disable or hide tab bar buttons… explain why" — https://developer.apple.com/design/human-interface-guidelines/tab-bars |

---

## 5. Search tab e ambito globale

Stato: `SearchView` è già `Tab(role: .search)` con `searchable`, scope e suggerimenti
(`Features/Search/SearchView.swift:313-325`) e Spotlight (`:335-341`) [V]. Scope:
Tutto / Didattica / Luoghi / Persone / Contenuti (`SearchView.swift:32-43`).

Proposta:
- Stile **standard tab** con landing, perché la landing ha valore di scoperta (aule libere, mappa):
  "Choose the standard tab style to provide suggestions, promote discovery"
  — https://developer.apple.com/design/human-interface-guidelines/search-fields
- `TabRole.search`: il tab view preferisce "the first tab with this role implement search"
  — https://developer.apple.com/documentation/swiftui/tabrole/search
- Landing: solo luoghi e scoperta (Aule libere, Mappa, Aule, Docenti), **più ricerche recenti
  cancellabili** ("provide a way for people to clear it" — https://developer.apple.com/design/human-interface-guidelines/searching).
  Piano, Manifesto, Orario personalizzato, Simulatore escono dalla landing e vanno in Carriera.
- Scope default ampio ("Default to a broader scope" — https://developer.apple.com/design/human-interface-guidelines/search-fields).
- Ricercabile: corsi, docenti, aule/edifici, appelli ed esiti, eventi di calendario, file WeBeep
  (dei corsi già caricati, come dice il footer `SearchView.swift:262-264`), notizie, avvisi,
  insegnamenti del manifesto. **Ogni risultato deve aprire qualcosa** (vedi §7).
- Ricerche locali restano dove filtrano una sola lista: Materiali (`CourseMaterialsView.swift:97`),
  Aule (`RoomsView.swift:98`), Manifesto (`ManifestiView.swift:52`) — ammesse
  "for apps with clearly distinct sections" (https://developer.apple.com/design/human-interface-guidelines/searching).
- Spotlight: aggiungere appelli/esiti come `CSSearchableItem` apribili (già passati in
  `RootView.swift:118`) e rotta verso ExamDetail.

---

## 6. Oggi: priorità dei contenuti e cosa esce dall'app

Ordine proposto (dall'alto):
1. Stato: `PendingChangesBar`, `CareerMismatchBanner`, `ServiceAuthBanner` (`HomeView.swift:42-50`) — solo se presenti.
2. **Adesso / prossima lezione** (oggi `HomeView.swift:52-58`, max 3).
3. **Novità esami non lette** (spostate da `CareerView.swift:173-208`); badge del feed sul tab Oggi, non su Carriera.
4. **Scadenze** entro 7 giorni (`feed.deadlines`, già usato in `RootView.swift:125`).
5. **Prossimo appello** con finestra iscrizioni (`HomeView.swift:60-64`).
6. Avvisi (voce con conteggio) e Notizie (3, in fondo).

La **griglia corsi esce da Home** (`HomeView.swift:66-91`) e va nel tab Corsi.

Fuori dall'app:
- **Widget**: Oggi, Prossima lezione, Aule libere, Carriera esistono (`PoliVerseWidgets/`). Aggiungere
  "Prossimo appello / novità esami". Widget con "timely content" e "deep links to key areas"
  — https://developer.apple.com/design/human-interface-guidelines/widgets. Oggi nessun widget
  imposta `widgetURL` o `Link` (grep su `PoliVerseWidgets/` vuoto) [V]: il tap apre solo la root.
- **Live Activity**: resta la lezione avviata a mano (`LiveActivityController.swift:1-6`); candidato
  aggiuntivo l'esame del giorno (inizio/fine definiti, <8h) — https://developer.apple.com/design/human-interface-guidelines/live-activities.
  Non mostrare voti sulla Lock Screen: "Avoid displaying sensitive information" (stessa pagina).
- **Notifiche**: esito pubblicato, iscrizioni in chiusura, lezione spostata (già pianificate in
  `RootView.swift:121-126`). Una sola notifica per fatto: "Avoid sending multiple notifications for the same thing"
  — https://developer.apple.com/design/human-interface-guidelines/notifications. In foreground: badge o inserimento nella vista (stessa pagina).

---

## 7. Duplicazioni e vicoli ciechi

### Duplicazioni
| # | Cosa | Dove | Azione |
| --- | --- | --- | --- |
| D1 | Lista corsi con due destinazioni diverse | Home → `CourseDetailView` (`HomeView.swift:80-87,130-132`, `onMaterials` apre comunque l'hub); WeBeep → `CourseMaterialsView` (`WeBeepView.swift:73,168`) | Un tab Corsi → hub; Materiali un livello sotto |
| D2 | Filtro anno ripetuto | `HomeView.swift:66-68` (`YearFilter`), `WeBeepView.swift:10` | Un Menu in toolbar di Corsi |
| D3 | Prossimo esame / appello | `HomeView.swift:60-64`, `CareerView.swift:158-167`, `CourseDetailView.swift:73-80` | Oggi (globale), hub (per corso); rimuovere da Riepilogo Carriera |
| D4 | Feed novità esami in tre estratti | `CareerView.swift:173-208`, `CourseDetailView.swift:96-110`, `ExamUpdatesView` | Estratto su Oggi, filtrato nell'hub, completo in Carriera |
| D5 | Simulatore raggiungibile da tre punti | `CareerView.swift:57-58`, `StudyPlanView.swift:40-41`, `SearchView.swift:162-163` | Solo Carriera (+ Piano) |
| D6 | Piano di studi in due punti | `CareerView.swift:48-49`, `SearchView.swift:147-148` | Solo Carriera |
| D7 | Cambio carriera in due punti | `SettingsView.swift:20-21`, `CareerMismatchBanner.swift:18-19` | Banner ok; aggiungere menu in Carriera, stessa vista |

### Vicoli ciechi
| # | Problema | Riferimento | Fix |
| --- | --- | --- | --- |
| V1 | Risultati di ricerca Aule, In calendario, Appelli, Materiali non sono tappabili | `SearchView.swift:188-199`, `:216-230`, `:233-249`, `:252-265` | Push a `ClassroomDetailView`, sheet Evento, push ExamDetail, anteprima file |
| V2 | Intents `.freeRooms` e `.map` portano alla landing Cerca, non alla vista | `RootView.swift:49` | Path del NavigationStack di Cerca impostato su FreeRooms / Map |
| V3 | `.plan` e `.simulator` aprono la root di Carriera | `RootView.swift:47` | Push programmatico di StudyPlan / GradeSimulator |
| V4 | Widget senza deep link | `PoliVerseWidgets/*.swift` (nessun `widgetURL`) | `widgetURL` per lezione/appello/aula + `onOpenURL` (`PoliVerse/App/PoliVerseApp.swift:176`) |
| V5 | `ExamDetailView` è uno sheet con `NavigationStack` e push verso Corso e Materiali: app nell'app, e Corso dentro sheet dentro hub corso | `ExamDetailView.swift:49,196-200`; aperto come sheet da `CareerView.swift:25`, `CourseDetailView.swift:133`, `ExamUpdatesView.swift:69` | Presentarlo in push; le azioni verso il corso diventano navigazione normale — https://developer.apple.com/design/human-interface-guidelines/modality |
| V6 | Sheet su sheet: `AddToCalendarSheet` sopra `ExamDetailView` sheet | `ExamDetailView.swift:80` | Risolto da V5 — https://developer.apple.com/design/human-interface-guidelines/sheets |
| V7 | Avvisi in sheet con push interno | `HomeView.swift:129`, `NoticesView.swift:9,50` | Push da Oggi |
| V8 | Righe novità senza appello abbinato sono disabilitate senza spiegazione | `CareerView.swift:199-204`; in hub non tappabili `CourseDetailView.swift:99-101` | Aprire il corso o il file che ha generato la novità |
| V9 | Manifesto e Orario personalizzato raggiungibili solo dalla landing di Cerca | `SearchView.swift:152-158` | Carriera → Offerta didattica |
| V10 | Segmented "Riepilogo/Appelli/Esiti" in testa allo scroll mescolato con pulsanti Piano/Simulazione | `CareerView.swift:33-66` | Sezioni di lista con righe push (vedi albero §3) |

---

## 8. Piano di migrazione (passi piccoli)

1. **Deep link unico.** Estendere `AppDestination` con payload (corso, appello, aula) e sostituire
   `selection: String` con un enum + un `NavigationPath` per tab in `PoliVerse/App/RootView.swift`. Fix V2, V3.
2. **Risultati di ricerca tappabili** in `Features/Search/SearchView.swift` (V1).
3. **ExamDetail in push**: rimuovere il `NavigationStack` interno in `Features/Career/ExamDetailView.swift`
   e sostituire `.sheet(item: $selectedExam)` con `navigationDestination` in `CareerView.swift`,
   `CourseDetailView.swift`, `ExamUpdatesView.swift` (V5, V6). Test UI esistenti da aggiornare.
4. **Avvisi in push** (`HomeView.swift:124-129`, `NoticesView.swift`) (V7).
5. **Tab Corsi**: estrarre la griglia da `HomeView.swift` e fondere con `WeBeepView.swift` in un
   `CoursesView` (List, filtri in Menu); destinazione sempre `CourseDetailView` (D1, D2).
   Rinominare `Features/WeBeep/` solo quando vuoto.
6. **Home → Oggi**: riordinare `HomeView.swift` come in §6, spostare il badge dal tab Carriera
   (`RootView.swift:72-74`) a Oggi, estrarre `recentUpdates` da `CareerView.swift:173-208`.
7. **Profilo in sheet**: avatar in toolbar di ogni root apre `SettingsView` in sheet (`HomeView.swift:106-110`).
8. **Carriera in lista**: sostituire segmented e pulsanti (`CareerView.swift:33-66`) con sezioni
   Riepilogo / Appelli / Esiti / Piano / Simulatore / Offerta didattica; spostare Manifesto e
   Orario personalizzato dalla landing Cerca (D5, D6, V9, V10).
9. **Landing Cerca**: tenere solo luoghi/persone + ricerche recenti (`SearchView.swift:135-167`).
10. **iPad**: `.tabViewStyle(.sidebarAdaptable)` + `TabSection` e `NavigationSplitView` in Corsi/Carriera; `inspector` per evento.
11. **Widget deep link** (`widgetURL`) e widget Prossimo appello in `PoliVerseWidgets/` (V4).
12. **Liquid Glass**: `tabBarMinimizeBehavior` su liste lunghe; valutare `tabViewBottomAccessory` per lezione in corso.

Ogni passo è rilasciabile da solo; 1–4 non cambiano i tab.

---

## 9. Domande aperte

1. "Oggi" o "Home" come nome? Il tab label va "single words whenever possible" (https://developer.apple.com/design/human-interface-guidelines/tab-bars): entrambi ok; "Oggi" dichiara il contenuto.
2. Calendario come tab o dentro Oggi? Tenendolo si resta a 5; togliendolo si libera spazio per un tab "Campus" (aule/mappa) fuori dalla ricerca.
3. Il corso di anni passati (WeBeep li mostra per anno) deve stare in Corsi o in Carriera/Libretto?
4. Scadenze WeBeep: Oggi o Calendario (filtro "Scadenze" esistente, `CalendarView.swift:18-22`)? Proposto entrambi con Oggi come estratto.
5. Il badge del feed: esiti pubblicati sono "critical information"? Le sole modifiche d'aula forse no.
6. Live Activity automatica per l'esame del giorno contraddice la scelta manuale di `LiveActivityController.swift:3-6`?
7. Search tab: stile standard (landing) o button appearance? Dipende da quanto restano usate le voci della landing — misurabile con `PerformanceStates.tabSelected` (`RootView.swift:83-85`).
8. Nessuna pagina HIG "Inspectors" trovata: confermare se usare `inspector` su iPad o solo split view.
