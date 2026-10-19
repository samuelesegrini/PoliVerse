# Banco di prova del 3D — PROTOTYPE

**Domanda:** il campus 3D può aprirsi e muoversi come Apple Mappe, subito e senza scaldare
il telefono? Qui ci sono gli obiettivi, le metriche, gli strumenti per misurarle e il giro
misura → idee → modifica → rimisura fatto il 19/10/2026.

## Obiettivi e metriche

| Obiettivo | Metrica | Traguardo | Dove si misura |
|---|---|---|---|
| Latenza: il campus compare subito | tempo dal lancio al campus disegnato (`trifoglio3d.campus`) | < 1 s su iPhone 15 | `Trifoglio3DPerformanceTests.testTimeToCampus`, `Trifoglio3DLoadTests.testBeforeFirstFrame` |
| | byte, file e forme di collisione letti prima del primo frame | ≤ 1 file, ≤ 40 MB, 0 collisioni | `misura.py`, riga "Primo frame" |
| Latenza: entrare in un edificio non aspetta | tempo per leggere i piani di un edificio | < 300 ms, meno del volo di 1,3 s che lo nasconde | `Trifoglio3DLoadTests.testOneBuilding` |
| Memoria | memoria GPU con il campus fermo | < 160 MB | banco sul telefono (`misura.py` ne dà una stima) |
| | memoria fisica dell'app | < 300 MB | `testStillCampus`, `testWalkAcrossTenBuildings` |
| CPU e batteria | triangoli disegnati a ogni fermata della camera (mediana) | < 400 k | `misura.py`, righe "fermate" |
| | draw call alla fermata campus | < 1100 | `misura.py` |
| | CPU media con il campus fermo | < 15 % | `testStillCampus` |
| Fluidità | scatti durante il volo campus → aula | < 5 ms/s | `testTourToClassroom` |
| Efficienza | peso dei modelli nel bundle / da scaricare | < 60 MB / < 20 MB | `misura.py` |

Nel cloud non c'è Xcode né un iPhone: `misura.py` conta quello che sul telefono diventa tempo,
memoria e batteria (byte, vertici, triangoli disegnati, draw call). I secondi e i megabyte veri
li danno i test XCTest, da far girare sul telefono.

## Il banco sul telefono

Il modo più rapido per avere numeri veri, letti dal dispositivo e non stimati:

1. In Xcode, schema **PoliVerse** (Debug), destinazione il tuo iPhone; in Edit Scheme → Run →
   Arguments aggiungi `-Trifoglio3D` (apre il campus 3D al posto dell'app). Con anche
   `-Trifoglio3DBench` il banco parte da solo appena il campus è disegnato.
2. Altrimenti tocca **Misura** nella barra in alto del campus. La camera si muove da sola per
   circa un minuto; non toccare lo schermo.
3. Alla fine compare la scheda con i risultati; il pulsante di condivisione manda il JSON
   (incollalo nel thread e lo analizzo). Tieni premuto **Misura** per rifarlo.
4. Lo stesso JSON finisce in `Documents/trifoglio3d-bench.json` dell'app e nella console tra
   `TRIFOGLIO3D_BENCH_BEGIN` e `TRIFOGLIO3D_BENCH_END`. Dal Mac:

       xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
         --domain-identifier segrini.samuele.PoliVerse \
         --source Documents/trifoglio3d-bench.json --destination bench.json

Cosa misura (`PoliVerse/Features/Map/Campus3D/Trifoglio3DBench.swift`):

| Misura | Come la legge |
|---|---|
| Apertura: campus nella scena e primo frame, in ms | orologio dall'inizio del caricamento |
| Memoria dell'app | `phys_footprint` (`task_info`), quella che iOS conta per il limite |
| Memoria GPU | `MTLDevice.currentAllocatedSize` |
| CPU | tempo CPU del processo (`CLOCK_PROCESS_CPUTIME_ID`) diviso il tempo trascorso |
| Frame al secondo, durata dei frame, scatti in ms/s | `SceneEvents.Update` di RealityKit, frame per frame |
| Campus fermo 10 s, volo all'aula T.1.2, ancora fermo alla fine | le misure sopra, in quelle finestre |
| Ogni edificio letto a freddo | orologio attorno a `loadBuilding` |
| Il vecchio caricamento, tutto subito | i 38 modelli letti e tenuti insieme: tempo, memoria, GPU |
| Batteria e temperatura | `UIDevice.batteryLevel` e `thermalState` all'inizio e alla fine |

La batteria cambia di pochi punti in un minuto: per il consumo vero serve Instruments →
Power Profiler, oppure ripetere il banco più volte di fila.

## Gli strumenti

- **`misura.py <cartella>`** legge i `.usdz` che l'app carica e stampa le metriche
  (`--json`, `--md` per salvarle). Le fermate usano la stessa inquadratura di
  `Trifoglio3DScene.frame` e il frustum culling per riquadri, come RealityKit.
- **`ottimizza.py <file.usdz> …`** alleggerisce i modelli senza cambiare l'aspetto (sotto).
  `esporta3d.py` lo chiama da solo su ogni `.usdz` che scrive.
- **`lontano.py <campus.usdz>`** scrive `campus_lontano.usdz`, gli involucri semplificati per la
  vista campus (sezione 6). Serve `pip install fast-simplification`.
- **`PoliVerseTests/Trifoglio3DLoadTests.swift`**: tempo, CPU e memoria di ogni passo del
  caricamento, letto da RealityKit sul dispositivo.
- **`PoliVerseUITests/Trifoglio3DPerformanceTests.swift`**: l'app aperta con `-Trifoglio3D`:
  tempo al campus, CPU e memoria a campus fermo, scatti del volo all'aula.
- **Signpost** `trifoglio3d.campus`, `trifoglio3d.after-first-frame`, `trifoglio3d.building`
  nei Points of Interest: in Instruments (Time Profiler, Power Profiler) si vede dove va il tempo.

I test XCTest sono spenti di default. Per accenderli: nello schema **PoliVerseUI** (Debug,
perché il prototipo esiste solo in Debug) Test → Arguments → Environment
`TRIFOGLIO3D_BENCH=1`, oppure

    TEST_RUNNER_TRIFOGLIO3D_BENCH=1 xcodebuild test -scheme PoliVerseUI \
      -destination 'platform=iOS,name=<il tuo iPhone>' \
      -only-testing:PoliVerseTests/Trifoglio3DLoadTests \
      -only-testing:PoliVerseUITests/Trifoglio3DPerformanceTests

Poi "Set Baseline" nel report di Xcode, per dispositivo.

## Il giro del 19/10/2026

Misurato sui modelli della PR #26 (campus con tutti i gusci fino a 5b619e3).

### 1. Misura di partenza

| Metrica | Prima | Dopo | |
|---|---|---|---|
| Primo frame: file / MB / collisioni | 38 / 74,2 MB / 603 mesh | 1 / 34,8 MB / 0 | −53 % byte |
| Memoria GPU stimata a regime | 268 MB | 148 MB | −45 % |
| Bundle / download | 74,2 / 18,7 MB | 54,0 / 16,6 MB | −27 % / −11 % |
| Vertici totali | 5,65 M | 4,02 M | −29 % |
| Triangoli disegnati alle fermate, mediana / max | 779 k / 1,74 M | 318 k / 1,28 M | −59 % / −26 % |
| Draw call alle fermate, mediana | 118 | 129 | +9 % |
| Fermata campus: triangoli / draw call | 2,04 M / 781 | 2,04 M / 1032 | draw call +32 % |

Cosa diceva la misura di partenza:

- `RealityView` non disegna nulla finché la closure `make` non finisce, e la closure leggeva
  **tutti** i 38 file e generava le forme di collisione esatte di 603 mesh di aule prima del
  primo frame. Il campus aspettava edifici che nessuno aveva ancora chiesto.
- `campus.usdz` aveva **2,07 vertici per triangolo** (gli edifici 0,6): vertici doppi su ogni
  faccia piana, 46 MB di posizioni su 54.
- Chiome, prati, strade e città erano poche mesh grandi come tutta la zona: il frustum culling
  non scartava mai nulla, e vicino a un edificio si disegnavano ancora ~1,5 M triangoli.
- Con un'aula accesa l'etichetta cambiava posizione a ogni frame anche a camera ferma, e
  SwiftUI ridisegnava l'overlay 60–120 volte al secondo.

### 2. Idee, in ordine di guadagno stimato

| # | Idea | Stato |
|---|---|---|
| 1 | Primo frame con il solo campus; Giuriati e tocchi dopo | fatto (`Trifoglio3DScene.load`) |
| 2 | Piani di un edificio letti quando la camera ci va, durante il volo | fatto (`loadBuilding`) |
| 3 | Al più 4 edifici in memoria, il meno recente lasciato | fatto (`keptBuildings`) |
| 4 | Saldare i vertici doppi sulle facce piane | fatto (`ottimizza.py`, `salda`) |
| 5 | Tessere per il culling, come le tile di una mappa | fatto (`ottimizza.py`, `tessere`) |
| 6 | Etichetta aggiornata solo se si sposta; `unlight` senza visitare tutte le entità | fatto |
| 7 | Campus in due strati (terreno+edifici, poi alberi e città) | provato e scartato: −13 % byte al primo frame per un file e 2 MB in più |
| 8 | Chiome meno dense: 553 k triangoli, il 27 % del campus | da fare nel thread dell'arredo (PR #25), che possiede gli alberi |
| 9 | LOD degli involucri: 1,24 M triangoli, inutili da lontano | fatto (`lontano.py`, sezione 6), da misurare sul telefono |
| 10 | Ombra del sole limitata alla zona inquadrata (oggi 700 m: ogni triangolo disegnato due volte) | da provare sul telefono con `testStillCampus` |
| 11 | Meno materiali (517 nel campus): colori quasi uguali uniti | da provare |

### 3. Le scelte, con i numeri

- **Saldatura:** un vertice si unisce a un altro solo se ha la stessa posizione, la stessa uv e
  tocca solo facce con la stessa normale; i triangoli senza area si tolgono. Verificato su
  tutti i 38 file: lo scarto massimo delle normali ricavate per ogni angolo di ogni triangolo è
  0,07° (vertici spostati di meno di 0,1 mm).
- **Tessere:** un pezzo connesso (una chioma, un marciapiede) resta intero e va nella tessera
  del suo centro, così nessun vertice condiviso si stacca. Il lato è di almeno 60 m e cresce
  finché ogni tessera tiene in media 3000 triangoli. Gli altri valori provati:

  | Lato min / triangoli per tessera | Triangoli alle fermate, mediana | Draw call campus |
  |---|---|---|
  | nessuna tessera | 779 k | 781 |
  | 60 m / 3000 (scelto) | 321 k | 1032 |
  | 60 m / 6000 | 385 k | 913 |
  | 80 m / 10000 | 424 k | 854 |
  | 100 m / 20000 | 481 k | 815 |
  | 100 m fisso, ogni mesh | 251 k | 2037 |

### 4. Prima misura sul telefono (iPhone 12 Pro, iOS 27.2, Debug, 19/10/2026)

`Trifoglio3DLoadTests`, 5 giri ciascuno, con il campus.usdz vecchio (49 MB, non ottimizzato):

| Test | Tempo | Picco di memoria |
|---|---|---|
| Campus prima del primo frame (nuovo) | 1,53 s ±9 % | 324 MB |
| Solo campus.usdz | 1,29 s | 338 MB |
| Tutto subito (vecchio) | 5,72 s | 436 MB |
| Un edificio (MIA0201), con le forme di tocco di tutte le aule | 1,03 s (CPU 0,57 s) | 149 MB |
| Dieci edifici di fila | 6,1 s | 156 MB, piatta |

Il campus compare 3,7 volte prima. Un edificio era sopra il traguardo di 300 ms; il sospetto
(CPU 0,57 s su 1,03 s) è l'attesa delle forme di tocco esatte di ogni aula di ogni piano, generate
una dopo l'altra. Ora si generano solo per il piano su cui si entra (`tappableRooms(on:)`),
durante il volo: la prossima misura dice quanto vale.

### 5. Il banco nell'app (iPhone 12 Pro, 1c2c688, 19/10/2026)

Due giri da 6 minuti: con i modelli della PR #26 così come sono e con gli stessi passati da
`ottimizza.py` (solo sul Mac, mai committati). Il telefono parte freddo e finisce "serious".

| Misura | Modelli attuali | Ottimizzati |
|---|---|---|
| Primo frame | 1461 ms | 1624 ms |
| Memoria al primo frame | 274 MB | 285 MB |
| Campus fermo: fps / mediana frame / CPU | 39 / 33,1 ms / 38 % | 38 / 33,3 ms / 39 % |
| Campus fermo: memoria / GPU | 504 / 288 MB | 512 / 287 MB |
| Volo all'aula: fps / scatti | 33 / 432 ms/s | 35 / 88 ms/s |
| Tutto subito, con la scena a schermo | 144 s, 913 MB | 141 s, 951 MB |
| Un edificio letto con la scena a schermo, il più lento | 9,7 s | 12,3 s |

Cosa dicono:

- **I modelli ottimizzati non cambiano nulla di misurabile sul telefono.** Le differenze stanno
  nel rumore del calore. Meno byte e meno triangoli contati nel cloud non sono diventati né
  secondi né megabyte: RealityKit tiene la sua copia della geometria comunque.
- **Il campus fermo sta a 30 Hz**, mediana 33,3 ms, qualunque pezzo si spenga (ombre, alberi,
  città, arredi, terreno). Lo stesso pezzo spento passa da 30 a 60 Hz da un giro all'altro
  (senza ombre: 40 poi 60 fps). La GPU sta a cavallo dei 16,7 ms: quando ne sfora uno, iOS
  passa a un frame ogni due. Per uscirne serve un margine, non un pezzo solo, e ogni variante
  va misurata più volte: ora il banco fa 3 giri alternati da 4 s.
- **Le ombre** valgono 33 MB di GPU in tutti e due i giri.
- **Gli involucri in trasparenza** costano: sull'edificio 37 fps contro 57 con gli altri opachi.
  Ora restano opachi e sparisce solo chi copre la vista (95f6e48).
- **Un edificio** si legge in 1 s nei test, ma in 7–12 s con la scena a schermo: la lettura
  aspetta la GPU.
- La CPU resta al 38 % anche a 60 fps: non è il lavoro per frame dell'app.

### 6. Il campus a 30 Hz: sono i materiali degli edifici (dbf7c43, 3 giri per variante)

| Variante | fps nei 3 giri | Frame mediano |
|---|---|---|
| tutto acceso | 40 / 39 / 40 | 17 / 17 / 33 ms |
| senza ombre, alberi, città, arredi o terreno | 32–40 | salta tra 17 e 33 ms |
| senza edifici | 51 / 43 / 54 | 16,7 ms |
| scena vuota | 60 / 60 / 60 | 16,7 ms |
| involucri dettagliati invece dei semplificati | 40 / 40 / 40 | come sopra |

- RealityKit da solo sta a 60 Hz; gli edifici sono l'unico pezzo che fa scivolare a 30.
- Gli involucri semplificati, con il 60 % di triangoli in meno ma ancora una mesh per
  materiale, non cambiano nulla: non contano i triangoli. Contano le 540 mesh e i 404
  materiali degli involucri, ognuno una draw call e un cambio di stato.
- Le ombre valgono 33 MB di GPU e 25 MB di memoria in tutti e tre i giri.

### 7. Involucri da lontano: una mesh e un materiale per edificio (idea 9 + 11)

`lontano.py` scrive `campus_lontano.usdz`: per ogni edificio una sola mesh, senza i pezzi più
piccoli di 2 m (cornici, davanzali, ringhiere), colorata da una tavolozza
condivisa, una texture di 2,5 kB con un quadretto per colore: 36 mesh e 1 materiale invece di
540 mesh e 404 materiali. `esporta3d.py` lo produce insieme a `campus.usdz` e lo salda con
`ottimizza.py`; `Trifoglio3DScene` lo mostra dalla vista campus e torna agli involucri veri
quando la camera va su un edificio. Se il file non c'è, tutto resta com'era.

| Pezzi tolti sotto | Triangoli | Aspetto da 400 m |
|---|---|---|
| 2 m, senza semplificare (scelto) | 862 k, 29 MB | uguale |
| 2 m e semplificazione al 15 % | 500 k, 21 MB | tetti deformati, triangoli rossi attorno al camino del Trifoglio (visto anche sul telefono) |
| 4 m e semplificazione al 15 % | 253 k | muri bucati |
| solo semplificazione | 641 k | si ferma ai bordi aperti |

Provato e scartato: masse estruse dall'impronta (96 k triangoli), troppo lontane dall'aspetto.
