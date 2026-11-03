# Personalizzazione: comportamento e verifica

La galleria conserva carosello, anteprime e transizioni. Scorrere seleziona una
anteprima locale; il look attivo cambia soltanto con «Usa look», con il tap sulla
scheda centrale o con il segno di spunta «Salva e usa» nell’editor.
Chiudi e Annulla non applicano l’anteprima.

## Vocabolario e responsabilità

- **Look**: configurazione salvata di Oggi e dell’aspetto dell’app (`TodayStyle`).
- **Colori**: palette `Flavor`, distinta dal look completo.
- **Stile speciale**: ricetta Blueprint o Giocherelloso, applicata anche alle
  composizioni delle quattro pagine principali.
- **Sezione**: blocco di contenuto di Oggi, con vincoli e impostazioni proprie.

`LookLibrary` conserva ordine, identità e selezione. `LookEditingSession`
conserva bozza, originale, cronologia e snapshot delle sottoattività; le viste
compatta e ampia presentano lo stesso comportamento. I controlli App fanno
parte dell’editor condiviso: non esiste più un secondo percorso dopo la creazione.
Le impostazioni delle sezioni usano `SectionSettings` sia nel dock sia nella
scheda con anteprima, conservando i campioni dei materiali.

## Inventario di parità

| Capacità | Ingresso | Dato / regola | Verifica |
| --- | --- | --- | --- |
| Preset, copia, foto, casuale, pagina vuota | Nuovo look | Configurazione iniziale | Walkthrough e preset |
| Colori, luce, carta, motivo, grana | Gruppi dell’editor | Campi TodayStyle | TodayStyle / Flavor / LookPart |
| Data, carattere, peso, dimensioni, allineamento | Data | Vincoli e impostazioni esistenti | LookPart e walkthrough |
| Saluto e testo personale | Saluto | Limiti esistenti | TodayStyle e walkthrough |
| Foto e sticker | Accessorio / manipolazione diretta | Fino a tre foto e sei sticker; coordinate proporzionali | TodayStickers e walkthrough |
| Ordine, visibilità e impostazioni locali | Sezioni / tap sulla pagina | Forme per tipo, limite elementi, materiale ereditato | TodaySections / SectionForm |
| App abbinata, icona, tinta e barra | App nell’editor | AppLook e fallback precedenti | AppLook e walkthrough |
| Applicazione parziale dei preset | Menu visibile e contestuale della miniatura | ThemeSlice | LookPart |
| Reset e annulla/ripeti | Editor e strumenti | EditHistory, inclusi burst di 0,8 s | LookPart / EditHistory |
| Eliminazione e recupero | Gesto/menu e Annulla | Identità originale e selezione precedente | LookLibrary / LookPersistence |
| Presentazione speciale per pagina | Stile speciale | SpecialPage + SpecialPresentation | 32 combinazioni di persistenza |

## Salvataggio e compatibilità

Il documento della libreria resta nella chiave `todayStyleLibrary`, con versione 2,
identificativi UUID, configurazioni dei look e identità del look attivo. I vecchi
record separati da newline vengono migrati preservando ordine e selezione.
Il look attivo resta disponibile anche nella chiave storica `todayStyle`;
`todayStyleSelection` è mantenuta per compatibilità. Anche l’onboarding conserva
ora le identità quando modifica il look attivo.

Modifica e rinomina conservano l’identità; nuove copie ricevono UUID nuovi.
Un documento futuro o non leggibile viene preservato senza riscritture, con
un messaggio che consente di chiudere la galleria. Le anteprime non usano più
il JSON della configurazione come identità SwiftUI.

«Salva nella libreria» è disponibile per look nuovi o non attivi e non cambia
l’app. Il segno di spunta salva e applica. L’icona è richiesta soltanto per
un’applicazione esplicita o per il cambio dell’attivo conseguente a eliminazione
e recupero; un errore dell’icona non annulla il look e il tentativo successivo
rimane disponibile. macOS mantiene l’icona del bundle.

## Presentazioni speciali

Ogni pagina — Oggi, Corsi, Carriera, Cerca — può essere Caratteristica oppure
Essenziale. L’assenza del nuovo campo mantiene il disegno precedente. Campi
sconosciuti o non validi vengono ignorati per pagina, senza scartare le altre scelte.

- Giocherelloso essenziale mantiene biglietti e scaffali, senza inclinazioni,
  ombre decorative o separatori tratteggiati.
- Blueprint essenziale mantiene tavole, indicatori e diagrammi informativi,
  senza griglia e tratteggi ornamentali.
- Le impostazioni globali di inclinazione/griglia restano salvate; il controllo
  risulta inattivo per la pagina in anteprima quando è Essenziale.
- Movimento ridotto e uso ridotto delle risorse prevalgono sulla decorazione.
- Le ricette non possono scegliere rappresentazioni di un altro stile.

«Converti in classico» modifica la bozza corrente: conserva colori e caratteri,
ma abbandona le composizioni speciali; non promette di creare una copia.

## Misurazione

La baseline dedicata congelata è di **14.488 righe fisiche**: Customize Swift,
Flavors Swift, shader Metal e LookPage/TodayLanding/TodaySectionView/TodayBar.
Sono state individuate altre 158 righe di regioni nelle pagine funzionali.
Il conteggio finale include il nuovo codice di produzione anche fuori da quelle
cartelle. Test e questo documento sono conteggiati separatamente.

Il taglio del 30% resta subordinato alla parità: non eliminare opzioni, ricette,
migrazioni o animazioni della galleria per raggiungerlo. Il risultato misurato e
le verifiche eseguite sono riportati nel resoconto della consegna.

`CustomizationPerformanceTests.testGalleryScrollCost` misura cinque andate e
ritorni equivalenti nella galleria con dati di esempio, CPU, memoria e hitches.
Confrontare Release con Release, sullo stesso modello di simulatore; non usare
il numero di righe come prova di prestazioni. Le build di misura escludono le
icone per evitare che la loro generazione alteri i tempi di preparazione; le
build finali verificano separatamente le risorse complete.

Eseguire la suite `PoliVerse`, il walkthrough `CustomizeAnimationTests`,
`LookApplicationUITests` e la misura nella scheme `PoliVersePerformance`.
Il walkthrough copre le differenze tra scorrere, chiudere e applicare, il ciclo
unico dell’editor, i controlli delle sezioni e il recupero delle eliminazioni.

## Primo passaggio

- Perimetro dedicato: **14.488 → 14.338 righe**, 150 in meno (1,04%).
- Includendo le regioni esterne congelate e le relative modifiche: **14646 → 14502 righe**, riduzione netta **144 (0.98%)**.
- Il **30% non è stato raggiunto**. Sono stati eliminati il percorso App di
  creazione separato e i controlli di sezione duplicati; persistenza robusta e
  presentazioni per pagina introducono nuovo codice. Un taglio ulteriore richiede
  una nuova opportunità concreta, senza sacrificare le capacità confermate.
- Compilazione Mac completa riuscita; **95 test in 11 suite della personalizzazione
  passati su Mac**, oltre al primo passaggio iOS di 29 test mirati.
- Standards e Spec: nessuna segnalazione ancora aperta dopo le correzioni.
- La suite completa iOS si ferma su `SessionLinksTests.swift`, non incluso nella
  modifica, per un callback non escaping salvato in un array.
- I primi walkthrough iOS sono stati disturbati da un’altra sessione sullo stesso
  simulatore; le successive prove hanno incontrato errori di avvio `launchd_sim`.
  Non costituiscono una certificazione di parità visuale o accessibilità.
- La baseline Release ha misurato 1,058 s medi di CPU sul percorso di scorrimento.
  Il confronto finale non è ancora verificato: **nessuna riduzione CPU dichiarata**.

I risultati UI e prestazionali incompleti vanno rieseguiti su un simulatore
stabile prima di considerare chiusa la verifica end-to-end. La registrazione
intermedia non sostituisce questo controllo.

## Secondo passaggio: riduzione conservativa

Il vincolo confermato è conservare anche aspetto e interazioni dell’editor,
oltre alla galleria, anche se il nuovo obiettivo del 20% non viene raggiunto.

- Rimossi la modalità Corsi fittizia di `AppPreview`, senza chiamanti, e
  `FlavorFlowView` con il relativo shader, anch’essi senza utilizzatori.
  Le anteprime Home e Dock, la pagina Oggi e gli effetti effettivamente usati
  restano disponibili.
- I gruppi App riusano `ToolGroup`, con gli stessi spazi, caratteri, note e
  intestazioni accessibili. Il pulsante della libreria è condiviso tra le due
  barre che avevano la stessa implementazione.
- Carta, motivo, carattere della data e materiale condividono selezione e
  animazione delle tessere; conservano anteprime, ordine e identificativi.
  Per aggiungere un selettore equivalente basta specificare valori, scelta,
  etichette e anteprima, senza duplicare il comportamento della selezione.
- Le righe delle sezioni ricevono direttamente `TodayEntry`, eliminando il
  passaggio duplicato dei suoi campi. Contenuto, densità e azioni restano uguali.

| Misura | Prima del secondo passaggio | Dopo |
| --- | ---: | ---: |
| Righe fisiche nel perimetro dedicato | 14.338 | 14.177 |
| Righe non vuote e non occupate soltanto da commenti, stesso perimetro | 10.491 | 10.371 |
| Totale con regioni esterne congelate | 14.502 | 14.341 |

Questo passaggio elimina **161 righe fisiche nette** e **120 righe non vuote
e non occupate soltanto da commenti**. Il secondo conteggio è un indicatore
testuale, non una misura delle istruzioni eseguite. Dalla baseline complessiva
di 14.646 righe, la riduzione è **305 righe, pari al 2,08%**.
Non sono stati spostati componenti fuori dal perimetro per ottenere il risultato.

Il **20% non è raggiunto**: mancano altre 2.625 righe per arrivare a un totale
di 11.716 o inferiore. Le alternative valutate — uniformare gli editor con
controlli nativi o generalizzare layout con comportamenti differenti — non
offrono al momento un taglio dimostrato compatibile con il vincolo visivo.
Non costituiscono modifiche approvate.

I **95 test in 11 suite** della personalizzazione sono stati rieseguiti su Mac
e sono passati. La compilazione Mac è riuscita. La rimozione di codice non
raggiungibile non dimostra un miglioramento delle prestazioni in esecuzione;
restano da completare i confronti visuali e prestazionali descritti sopra.
È riuscita anche la compilazione iOS Simulator per arm64 e x86_64, escludendo
la generazione delle icone; questa prova non verifica le risorse delle icone.

### Standards

Nessun rilievo nella revisione del secondo passaggio: le astrazioni condividono
comportamenti esistenti e le implementazioni eliminate non hanno chiamanti.

### Spec

Nessun rilievo nella revisione del secondo passaggio: azioni, ordine, spaziature,
animazioni, identificativi accessibili e segno di spunta sono conservati nel
codice. Entrambe le revisioni sono statiche; il confronto visuale resta aperto.
