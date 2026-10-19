# Banco di prova del 3D — PROTOTYPE

**Domanda:** il campus 3D può aprirsi e muoversi come Apple Mappe, subito e senza scaldare
il telefono? Qui ci sono gli obiettivi, le metriche, gli strumenti per misurarle e il giro
misura → idee → modifica → rimisura fatto il 19/10/2026.

## Obiettivi e metriche

| Obiettivo | Metrica | Traguardo | Dove si misura |
|---|---|---|---|
| Latenza: il campus compare subito | tempo dal lancio al campus disegnato (`trifoglio3d.campus`) | < 1 s su iPhone 15 | `Trifoglio3DPerformanceTests.testTimeToCampus`, `Trifoglio3DLoadTests.testBeforeFirstFrame` |
| | byte, file e forme di collisione letti prima del primo frame | ≤ 1 file, ≤ 40 MB, 0 collisioni | `misura.py`, riga "Primo frame" |
| Latenza: entrare in un edificio non aspetta | tempo per leggere i piani di un edificio con le collisioni delle aule | < 300 ms, meno del volo di 1,3 s che lo nasconde | `Trifoglio3DLoadTests.testOneBuilding` |
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

Cosa misura (`PoliVerse/Features/Map/Campus3D/Trifoglio3DBench.swift`):

| Misura | Come la legge |
|---|---|
| Apertura: campus nella scena e primo frame, in ms | orologio dall'inizio del caricamento |
| Memoria dell'app | `phys_footprint` (`task_info`), quella che iOS conta per il limite |
| Memoria GPU | `MTLDevice.currentAllocatedSize` |
| CPU | tempo CPU del processo (`CLOCK_PROCESS_CPUTIME_ID`) diviso il tempo trascorso |
| Frame al secondo, durata dei frame, scatti in ms/s | `SceneEvents.Update` di RealityKit, frame per frame |
| Campus fermo 10 s, volo all'aula T.1.2, ancora fermo alla fine | le misure sopra, in quelle finestre |
| Ogni edificio letto a freddo, con le collisioni delle aule | orologio attorno a `loadBuilding` |
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
| 9 | LOD degli involucri: 1,24 M triangoli, inutili da lontano | da provare: una variante semplificata scambiata per distanza |
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

### 4. Da rimisurare sul telefono

I numeri sopra sono del cloud. Il prossimo giro parte dai test XCTest su un iPhone: tempo al
campus, memoria fisica, CPU a campus fermo, scatti del volo. Le idee 8–11 si scelgono su quei
numeri.
