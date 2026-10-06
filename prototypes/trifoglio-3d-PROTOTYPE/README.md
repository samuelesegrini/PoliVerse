# Trifoglio in 3D — PROTOTYPE

**Domanda:** si può andare dalla mappa del campus all'aula in 3D, con transizioni animate,
partendo dagli stessi dati delle illustrazioni della mappa?

Si apre in Xcode: `PoliVerse/Features/Map/Campus3D/Trifoglio3DView.swift`, preview
"Trifoglio 3D". Solo in Debug, non raggiungibile dall'app.

## Il percorso

1. **Campus:** tutti i volumi degli edifici, verde, strade, percorsi e alberi.
2. **Edificio:** gli altri edifici si fanno trasparenti, la camera vola sul Trifoglio.
3. **Piano:** l'involucro sparisce, i piani sopra salgono e svaniscono, quelli sotto restano
   in trasparenza.
4. **Aula:** l'aula si accende con il colore delle illustrazioni e un'etichetta la segue.
5. **Dentro:** "Entra nell'aula" porta la camera in piedi dietro l'ultima fila, rivolta
   alla cattedra; compaiono i muri a tutta altezza, il soffitto e le luci. "Esci dall'aula"
   torna alla vista dall'alto.

Dal campus si sceglie il Trifoglio, l'Edificio 11 o uno degli Edifici 1, 2, 3, 4 e 6.
"Portami all'aula T.1.2" fa tutto il percorso. Si può anche toccare l'edificio e le aule sul
modello, trascinare per ruotare e pizzicare per lo zoom.

## I modelli

`esporta3d.py` estrude i dati di `design/mappa/`, in questo stesso ramo:
i contorni di `leonardo.json` per i volumi e le piante CAD di `piante/<csie>-geometria.json`
per i piani. Scrive in `PoliVerse/Preview Content/Trifoglio3D/`:

| File | Cosa contiene |
|---|---|
| `campus.usdz` | terreno, alberi, volumi di tutti gli edifici sotto `Campus/Edifici/<csie>` |
| `MIA0203.usdz` | i piani del Trifoglio: `MIA0203/Piani/<csip>` con soletta, muri tagliati a 1,5 m, locali e arredi (`<csip>_Arredi`); ogni aula è un nodo chiamato con il suo `csiv` |
| `MIA0203.json` | piani, quote e aule (sigla, posti) per l'interfaccia |
| `MIA0201.usdz`, `MIA0201.json` | lo stesso per l'Edificio 11 |
| `MIA0101.usdz`, `MIA0101.json` | lo stesso per l'Edificio 1 (Rettorato) |
| `MIA0102.usdz`, `MIA0102.json` | lo stesso per l'Edificio 2 |
| `MIA0103.usdz`, `MIA0103.json` | lo stesso per l'Edificio 3 |
| `MIA0104.usdz`, `MIA0104.json` | lo stesso per l'Edificio 4 |
| `MIA0106.usdz`, `MIA0106.json` | lo stesso per l'Edificio 6 |
| `MIA0314.usdz`, `MIA0314.json` | lo stesso per l'Edificio 41 (campus Bassini, da `bassini.json`) |
| `MIA0403.usdz`, `MIA0403.json` | lo stesso per l'Edificio 25 (campus di via Golgi, da `bassini.json`) |
| `MIA1401.usdz`, `MIA1401.json` | lo stesso per l'Edificio 26 (da `citta-studi.json`) |
| `MIA0306.usdz`, `MIA0306.json` | lo stesso per l'Edificio 21 (da `bassini.json`) |
| `MIA0301.usdz`, `MIA0301.json` | lo stesso per l'Edificio 20 (da `bassini.json`) |
| `MIA0302.usdz`, `MIA0302.json` | lo stesso per l'Edificio 19 (da `bassini.json`) |
| `MIA0402.usdz`, `MIA0402.json` | lo stesso per l'Edificio 23 (da `bassini.json`) |
| `MIA0601.usdz`, `MIA0601.json` | lo stesso per l'Edificio 32.1 (da `citta-studi.json`) |
| `MIA0603.usdz`, `MIA0603.json` | lo stesso per l'Edificio 32.3 (da `citta-studi.json`) |
| `MIA0901.usdz`, `MIA0901.json` | lo stesso per l'Casa dello Studente (da `citta-studi.json`) |
| `MIA0202.usdz`, `MIA0202.json` | lo stesso per l'Edificio 12 (da `leonardo.json`) |
| `MIA0206.usdz`, `MIA0206.json` | lo stesso per l'Edificio 15 (da `leonardo.json`) |
| `MIA0207.usdz`, `MIA0207.json` | lo stesso per l'Edificio 18 (da `leonardo.json`) |
| `MIA0208.usdz`, `MIA0208.json` | lo stesso per l'Edificio 14A (da `leonardo.json`) |
| `MIA0209.usdz`, `MIA0209.json` | lo stesso per l'Edificio 14B (da `leonardo.json`) |
| `MIA0214.usdz`, `MIA0214.json` | lo stesso per l'Edificio 16A (da `leonardo.json`) |
| `MIA0113.usdz`, `MIA0113.json` | lo stesso per l'Edificio 9A (da `leonardo.json`) |
| `MIA0109.usdz`, `MIA0109.json` | lo stesso per l'Edificio CT1 (da `leonardo.json`) |
| `MIA0110.usdz`, `MIA0110.json` | lo stesso per l'Edificio 10 (da `leonardo.json`) |
| `giuriati.usdz` | gli esterni del Centro Sportivo Giuriati e del suo isolato, a est del campus; si genera con `giuriati/esterni3d.py` (vedi `giuriati/README.md`) |

Il `csiv` è lo stesso codice di `Classroom.roomCode`, quindi dall'aula di una lezione si
trova il nodo da accendere senza tabelle in più.

Per rigenerarli, da questa cartella (circa 3 minuti):

```
python3 -m pip install shapely trimesh mapbox_earcut numpy usd-core
python3 esporta3d.py ../../design/mappa "../../PoliVerse/Preview Content/Trifoglio3D" --edifici=MIA0203,MIA0201,MIA0101,MIA0102,MIA0103,MIA0104,MIA0106,MIA0314,MIA0403,MIA1401,MIA0306,MIA0301,MIA0302,MIA0402,MIA0601,MIA0603,MIA0901,MIA0202,MIA0206,MIA0207,MIA0208,MIA0209,MIA0214,MIA0113,MIA0109,MIA0110
```

Metri, asse Y verso l'alto, X verso est, Z verso sud. Piani da 4 m.

`--edifici` va dato sempre con tutti gli edifici modellati: un guscio proprio entra anche in
`campus.usdz` solo se il suo edificio è nell'elenco, altrimenti lì resta l'estrusione.
Gli edifici dell'elenco che non sono in `leonardo.json` si cercano negli altri file del campus
in `design/mappa` (per ora `bassini.json`): in `campus.usdz` entra solo il loro esterno.

### Aggiungere un edificio

1. L'esterno va in `gusci/<csie>.py` (l'interfaccia è descritta in `esporta3d.py`, sopra
   `GUSCI`): `guscio()` serve sempre, il resto è facoltativo.
2. `python3 esporta3d.py ../../design/mappa <cartella> --edifici=<csie>` scrive
   `<csie>.usdz` e `<csie>.json`, da copiare in `PoliVerse/Preview Content/Trifoglio3D/`.
3. Il `<csie>` va aggiunto a `Trifoglio3DScene.buildings` e all'elenco `--edifici` qui sopra;
   poi si rigenera `campus.usdz` con tutti gli edifici, una volta sola, per non avere
   conflitti sul file binario.

## Il guscio del Trifoglio

Nel campus il Trifoglio non è un'estrusione piatta: `guscio()` lo costruisce come nelle foto
del restauro e della piazza (Coprat, TeamWork Italy, Urbanfile, Arketipo), ad altezze reali:

- il seminterrato è a quota piazza (nella pianta ha 21 porte verso l'esterno, il terra 5):
  uno zoccolo di 3,5 m in cemento grezzo con le sue finestre, porte vetrate dove la pianta
  ha le porte esterne e, dove sono vicine, portali larghi fra due pareti inclinate;
- terra e primo stanno nel volume di 9 m in mosaico a punta di diamante, con le finestre
  esagonali di Ponti su tre file e qualche fila di vetrocemento;
- le vetrate alte a griglia bianca sui vani scala della pianta che toccano il perimetro;
- la lastra bianca del tetto, che sporge di 1,8 m e sale verso le punte delle ali;
- i due ingressi del lato ovest, come nelle piante: al terra dal pianerottolo in cima a due
  rampe piene di cemento lungo il muro, con parapetto pieno e corrimano in metallo; al
  seminterrato, a quota piazza, dalla vetrata sotto il pianerottolo, che sta sui pilastri.

- quello che le piante disegnano fuori dal contorno: la torre scale vetrata a nord con il
  ponte verso il terra e il primo, le scale di sicurezza che scendono dalle punte del terra
  alla piazza, i balconi del primo sulle punte;
- le finestre dove le piante le disegnano (`linee.finestre`): rettangolari nello zoccolo,
  esagonali a metà di terra e primo, con qualche fila di vetrocemento nelle aule alte.

Il mosaico (tessere da 5 cm) e il cemento bocciardato sono texture generate dallo script,
colore e normali, ripetute in metri: il campus passa da 0,3 a 1,4 MB.

Gli interni seguono le linee della pianta, piano per piano:

- le aule hanno le file di banchi disegnate (`linee.arredi`): ogni fila diventa il parapetto
  bianco sul bordo del gradino, il piano del banco e le sedie una per una (50 cm l'una, come
  nelle foto delle aule rinnovate), su un gradino che sale di 17 cm da quello davanti;
  davanti alla prima fila stanno il leggio e, sulla parete di fondo, lo schermo scuro.
  Nei corridoi fra i settori la pianta disegna un rettangolo per fila: è il gradino
  intermedio, grigio scuro come nelle foto, a metà dell'alzata; il corrimano nero corre sul
  lato dei banchi, lontano dal muro (la riga in mezzo ai rettangoli è la freccia di
  percorrenza, non un corrimano). Le file si contano dalla
  cattedra (il lato con più spazio libero) e nelle aule a ventaglio ogni settore ha la sua
  direzione; le aule senza file restano piane;
- le scale (`linee.scale`) si leggono rampa per rampa (pedate parallele a 31 cm) e salgono
  davvero al piano di sopra: rampe in fila fanno una scala dritta con il pianerottolo in
  mezzo (lo scalone a sud del terra, due rampe parallele); due scale affiancate fanno una
  scala a U quando insieme salgono un piano con alzate di 15-24 cm (la scala nord, le due
  scale della torre vetrata, lo scalone del seminterrato), con la prima rampa che parte dal
  lato verso il corridoio e il pianerottolo a metà piano. Gradini pieni in pietra chiara e
  corrimano in metallo che seguono la pendenza, come nelle foto; il solaio del piano sopra
  è aperto dove le scale arrivano, e all'ultimo piano le rampe disegnate sono l'arrivo di
  quelle sotto;
- i corridoi, gli atri (quello coi pilastri del seminterrato, quello del primo) e il piano davanti alla prima fila delle aule hanno il pavimento delle
  foto (Aula Magna, aule restaurate): cubetti di pietra chiara a correre, file da 10 cm, una
  texture generata come il mosaico; è una pellicola fuori da `_Locali`, così il tocco e la
  luce restano sull'aula. La moquette blu di alcune foto del cantiere è di altri edifici del
  campus, non del Trifoglio;
- l'Aula Magna Giampiero Pesenti (2020) unisce due aule e l'atrio fra loro; le piante non la
  nominano, la riconosciamo al primo piano, dove T.2.1 e T.2.2 si guardano con i pilastri
  tondi davanti, come nelle foto: sul piano in mezzo poltrone bianche in file con il
  corridoio centrale, il palco a ovest con il leggio e il telo bianco, le pareti mobili fra
  le aule aperte; le gradonate restano ai lati;
- i pilastri sono gli anelli piccoli che la pianta disegna dentro un locale: quadrati come
  disegnati nell'atrio del seminterrato, tondi dove la pianta li disegna ottagoni (il fronte
  delle aule T.2.1 e T.2.2, che con l'atrio fra loro sono l'Aula Magna), bianchi come nelle
  foto e tagliati all'altezza dei muri;
- gli ascensori vengono dalle croci che la pianta disegna su ogni piano (`linee.ascensori`):
  pareti sottili, la porta sul lato del corridoio, la cabina in acciaio dentro; al terra e al
  primo il vano è tolto dai muri pieni che lo coprivano;
- le porte hanno l'anta aperta come nella pianta, i parapetti
  (`linee.ringhiere`) un corrimano;
- nei muri tagliati sono aperti i varchi delle porte, e dove la pianta disegna le finestre il
  muro diventa davanzale con il vetro sopra: al terra e al primo sono gli esagoni di Ponti
  del guscio, nelle stesse campate, e sotto il taglio dei muri si vede la loro metà bassa
  (davanzale a 1,2 m dal solaio, spigoli smussati, montanti grigi); nel seminterrato
  finestre rettangolari con il davanzale a 0,9 m.

Dentro le aule a gradoni (`<csiv>_Interno`, spento finché non si entra): una fodera di muro
a tutta altezza con i varchi delle porte e le finestre, il soffitto e le luci lineari accese.
Sotto il tetto il soffitto è piano a cassettoni in cemento, come nella foto dell'Aula Magna;
sotto un'altra aula è il retro delle sue gradonate, a gradini, mai a meno di 2,6 m dal
gradino sotto. Nel JSON ogni aula porta `interno.occhio` e `interno.guarda`.
L'Aula Magna ha un interno solo per le due aule (`Aula_Magna_Interno`, indicato da
`interno.nodo`): il soffitto a cassettoni in diagonale con le luci lineari che lo
attraversano e la parete di pannelli di cemento intorno al palco, come nelle foto; si entra
dal fondo del corridoio centrale fra le poltrone, verso il palco. Dentro la camera vede a
60° invece di 35°, come una persona in piedi nella sala. Dove la pianta
lascia lo stesso spazio davanti e dietro le file, le file salgono verso le punte delle ali:
così le aule sovrapposte salgono nello stesso verso (T.0.1 e T.0.2 sotto T.1.1, T.1.3 sotto
T.2.3), e le scale di sicurezza sulle punte escono in cima alle gradonate.

Banchi, scale, ante e corrimano stanno in `<csip>_Arredi`, fuori da `_Locali`, così il tocco
seleziona sempre l'aula intera. Le piante dei piani
seguono le quote del guscio: seminterrato a 0, terra a 3,5 m, primo a 7,5 m (prima il seminterrato delle piante stava mezzo metro sotto la piazza). Gli altri edifici
restano estrusioni.

## L'Edificio 11

Gli edifici esportati che nella mappa hanno un `profilo` (o `parti` con un profilo ciascuna)
prendono l'esterno da lì, fascia per fascia come lo disegna `build-mappa.py`, in metri veri
(18 unità della mappa = un piano da 4 m): `vetro` (bordo del solaio, vetro arretrato,
montanti ogni 5 m, neri e vetro fumé dove c'è il `telaio`), `portico` (vetro arretrato di
`arretrato` m, parapetti arancio, condotti sotto il soffitto), `pieno` e `fessura`, `sporto`,
`sagoma: propria` (il piano sul suo contorno, sul tetto di quello sotto). Per l'Edificio 11:
la parte di Viganò con l'esoscheletro in acciaio nero (pilastri a croce staccati dalla
facciata, coronamento con le V, travi sul tetto) e la A rossa e nera davanti all'ingresso di
via Ampère; la parte di Ponti in ceramica con il primo piano in mattone che sporge.

Poi, dalle foto (MiBACT 2020 per l'Atlante dell'architettura contemporanea, Urbanfile
2021-22 sul restauro):

- l'esoscheletro come è: i pilastri a croce salgono 6 m sopra il tetto e finiscono in punta;
  in cima a ognuno una trave lungo la facciata, larga 4 m, su due puntoni, da cui pendono i
  due tiranti che reggono i piani; dalla cima una trave obliqua torna sul tetto;
- sotto il portico i tre grossi condotti argentati, i montanti delle vetrate fitti (1,25 m);
- la parte di Ponti com'è dopo il restauro: piastrelle chiare da 20 x 10 cm lisce, a punta di
  diamante o rigate (una texture generata), e il volume in alto che sporge con le facce che
  si aprono salendo, con l'intradosso bianco sopra la fascia vetrata;
- nelle aule: piani grigi su gambe nere, sedie nere con qualcuna rossa o verde, soffitto
  bianco con le travi nere a vista e pilastri neri.

Le quote dei piani vengono dalle fasce della parte con l'ingresso: il terra a 1,1 m sopra la
fessura del seminterrato, che sta sotto terra.

Dentro, le stesse regole del Trifoglio, più due:

- dove la pianta non disegna locali per più dello spessore di un muro il solaio è aperto,
  con un parapetto: al terra è il pozzo sul seminterrato sotto la A;
- le file a 60 cm sono i due bordi dei tavoli, non gradoni: le aule dell'Edificio 11 sono
  piane, con tavoli e sedie dietro. Anche lì si entra, dal fondo verso il lato da cui
  partono le file.

### Il patio

Il cortile interno di Viganò è il locale S068a del seminterrato, sotto il vuoto di 490 m²
del piano terra: alto due piani, dal seminterrato al soffitto sotto il primo. Si sceglie
come un'aula ("Patio") e si entra ("Entra nel patio"). Dalle foto del MiBACT (2020) e di
Urbanfile (2018):

- i pilastri cruciformi neri sulle file a 8,5 m; la pianta ne disegna il piede (un quadrato
  di 2 m, nella linea delle scale) solo lungo i bordi, e le file in mezzo si ricavano dal
  passo; sui pilastri del vuoto i grappoli di quattro faretti, a due altezze;
- il soffitto nero con le travi sulle file dei pilastri, il ballatoio del terra tutto
  intorno al vuoto col parapetto nero, vetrate nere sui due livelli;
- i tavolini come li disegna la pianta (60 × 106 cm), con sedie rosse, arancio e verdi;
- la scala elicoidale in cemento con la lamiera arancio fuori: sale in senso antiorario per
  300° e arriva sul lato del vuoto più vicino, con un pianerottolo fino al ballatoio.

Nella vista per piani i pilastri e la scala sono tagliati all'altezza dei muri; il resto è
nascosto finché non si entra.

## L'Edificio 2

Il guscio dell'Edificio 2 (Bruno Finzi) sta in un modulo suo, `gusci/MIA0102.py`, che
l'esportatore carica come gli altri gusci propri (`guscio(b, E)` per l'esterno, `quote(b, E)`
per i piani, `piante(b, geo, aule, E)` per i banchi). È rifatto dalla foto aerea (Esri World Imagery)
e dalle foto della piazza; le fasce della mappa dicono solo quale parte ha quali finestre,
rivestimento, cornicione e copertura. Le altezze sono vere: zoccolo di pietra fino a 1,6 m
con le finestrelle del seminterrato (che sta sotto la piazza, a -2,2 m), terra bugnato
alto 5,6 m, piano nobile 5,4 m, secondo piano solo nell'ala est e nelle torri.

- I due padiglioni sulla piazza: lesene dell'ordine gigante a ogni campata, base e
  capitello; finestre ad arco con la chiave al terra, porte finestre ad arco con il
  balconcino al primo; cornicione su mensole, balaustra con le sfere sui pilastrini e gli
  obelischi sugli spigoli verso la piazza; il portone ad arco sul lato corto con il balcone
  grande sopra, su tre mensole.
- Il fronte fra i padiglioni, le ali e le aule che sporgono nella corte: ocra, terra
  bugnato con gli archi, primo con finestre ad arco (la specchiatura sotto il davanzale) o
  rettangolari con la cimasa. Le finestre seguono quelle delle piante dove su una facciata
  sono in fila regolare (il fronte e l'ala est, ogni 2,8 m), altrimenti la campata della
  mappa; sono le stesse su tutti i piani, come in un palazzo. Verso la corte niente cornici
  intorno alle finestre né dentelli.
- I tetti: in coppi a padiglione su ali e aule, e padiglione e ala sotto un tetto solo come
  nella foto aerea, che parte dietro la balaustra; piano con gli impianti sul fronte e sulle
  torri. La foto aerea corregge la mappa sull'ala est: il tetto è piano, chiaro, con il
  camminamento lungo il parapetto e tre campi di pannelli fotovoltaici (`TETTI_PIANI`).
- Bugnato, coppi e fotovoltaico sono texture generate come il mosaico del Trifoglio.

Le piante dell'Edificio 2 non disegnano i banchi: `piante()` li ricava per ogni aula
(non per l'EDUCAFE) dalla forma, dalle porte e dai posti. Oltre 0,75 posti al m² l'aula è a
gradoni con file ogni 90 cm (2.0.1, 2.0.2, 2.1.1-2.1.5), altrimenti piana con tavoli da
50 cm ogni 1,25 m (2.2.1-2.2.5); le due aule a ventaglio hanno la cattedra sul lato
stretto, le altre sul lato corto lontano dalle porte; corridoi ai lati e in mezzo nelle
aule larghe più di 11 m. Così ogni aula ha file, cattedra e interno, e si entra.

## L'Edificio 3

L'esterno del Cassinis è rifatto da zero in `gusci/MIA0103.py`, un guscio proprio come
quelli degli altri edifici in `gusci/`: oltre a `guscio` e `quote` ha `tetto` (la quota sotto
il tetto dell'ultimo piano), `piante` (le file di banchi che le piante non disegnano) e
`ritocca` (i colori delle aule), tutti facoltativi in `esporta3d.py`. Le fonti sono l'ortofoto (Esri World Imagery) e le foto di Wikimedia
Commons dal piazzale del Rettorato, dal portico e dal cortile:

- le ali nord e sud e le due aule sul cortile in intonaco grigio-beige, con il tetto a
  padiglione in coppi (una texture generata, come il mosaico); zoccolo in granito con le
  bocche del seminterrato, terra bugnato con le finestre ad arco e la chiave, la fascia
  marcapiano, il primo liscio con gli archi, il fregio e il cornicione;
- i padiglioni d'angolo a ovest più caldi, con le paraste e i capitelli, i balaustrini sotto
  le finestre del primo, il cornicione a mensole, l'attico e la balaustra con le sfere; sul
  fianco nord e sud l'avancorpo d'ingresso con il portale ad arco, il balcone e i due
  obelischi (a sud la scalinata che sale dal giardino al terra);
- il fronte ovest più chiaro e liscio, con le finestre rette e la lunetta cieca al primo e
  il tetto piano scuro con gli impianti dell'ortofoto; la bocca di lupo con la ringhiera;
- il corpo est: sul cortile la loggia (archi a terra davanti al corridoio, finestre ad arco
  con i balaustrini al primo), sopra il secondo piano vetrato bianco della sopraelevazione,
  sul tetto i pannelli in due campi e i tetti scuri delle testate con gli impianti, il cubo
  di vetro sopra la torre sud; il ponte coperto verso est, al terra;
- il cortile è un prato rialzato a 2,8 m con il bordo in lastre, l'ippocastano e le due scale
  di sicurezza bianche agli angoli verso la loggia.

Quote: seminterrato a 0, terra a 3,6 m, primo a 9 m, secondo (solo il corpo est) a 14,4 m;
il cornicione a 14,4 m, il tetto del corpo est a 18 m.

Dentro: la sala De Donato ha le poltrone disegnate una per una, e le file si ricavano da
lì (le sedute a meno di 70 cm fanno una fila); le aule del primo e del secondo non hanno file
nelle piante, e `piante()` le aggiunge ogni 95 cm, con la cattedra a sud nel corpo est, a nord
nell'ala ovest e verso il cortile nelle due aule sopra le sale del terra. Colori dalle foto:
al terra poltrone rosse, banchi scuri e pareti nere nella De Donato; al primo e al secondo
banchi in legno e pareti bianche (aula S.1.4). Il cortile non è un pozzo: niente parapetto
intorno ai vuoti che stanno in un `cortili` della mappa.

## Edificio 1 (Rettorato, MIA0101)

L'esterno è in `gusci/MIA0101.py`: `esporta3d.py` carica `gusci/<csie>.py` quando l'edificio è in `--edifici` e ne usa `guscio()`, `quote()` e, se ci sono, `interno()` e `arredi()`. Facciata e tetti sono ridisegnati dall'ortofoto (zoom 21) e dalle foto; le campate seguono le porte dei balconi della pianta. L'interno dell'Aula Magna (MIA0101001023: palco, presidenza, ~228 poltrone, boiserie, lampadari) è dedotto, non rilevato.

## Edificio 4 (Giulio De Marchi, MIA0104)

L'esterno è in `gusci/MIA0104.py`, con l'interfaccia dei gusci propri (`guscio`, `quote`,
`tetto`, `piante`, `ritocca`). Dall'ortofoto (Google, z20-21): l'ala su
via Bonardi con il tetto in coppi e la fascia di lucernari sulla falda nord, i due
padiglioni sulla strada, il corpo grigio a tetto piano sull'angolo ovest con la torre delle
scale, i blocchi degli impianti, il chiostro a quattro ali con le finestre a tetto e l'aula
a sud con la testata smussata. Dalle foto del restauro (B&B Progetti) e da "Ciminiera neve"
(Wikimedia Commons): la ciminiera del cortile, in mattoni con le costole in cemento e il
serbatoio tondo, e le finestre ad arco del cortile. Le finestre seguono quelle delle piante.

Dedotti, non rilevati: la facciata su via Bonardi (nessuna foto trovata), le quote (terra
rialzato a 1,2 m, primo a 7, sottotetto a 12, gronda a 13,2) e l'altezza della ciminiera
(48 m, dallo spostamento della cima nell'ortofoto). L'aula 4.0.1 (310 posti) non ha le file
nella pianta: `piante()` ne mette 12 da 26 posti rivolte alla testata sud.

## Edificio 6 (Giulio Natta, MIA0106)

L'esterno è in `gusci/MIA0106.py` (stessa interfaccia degli altri gusci propri): il corpo
storico in coppi intorno ai due pozzi di luce, l'ottagono a ovest, il blocco sud, la spina
bassa e la torre dei laboratori. Tetti e masse vengono dall'ortofoto (zoom 21; il tetto della
torre vi appare spostato di 4,4 m verso nord ed è riportato sulla pianta), la torre dalla foto
"Ciminiera neve" di Wikimedia Commons (finestre in griglia con le tende, la striscia vetrata
della scala sul lato ovest, i camini delle cappe). Le facciate del corpo storico non hanno
foto: seguono le altre ali di Brusconi.

Le quote sono dedotte dalle scale delle piante: il rialzato a 1,5 m (le scale esterne hanno
8-10 alzate), il piano 000, che esiste solo nella torre, 1,5 m sotto il giardino sul cortile
ribassato a nord, il seminterrato sotto. L'aula 6.0.1 è l'Aula Natta, nell'ottagono del primo
piano: le file in tre settori a ventaglio sono aggiunte da `piante()` seguendo i due corridoi
a gradini della pianta, legno rossiccio e muri bianchi dalla foto. Nella foto le file salgono
più ripide dei 17 cm per fila dell'esportatore.

## Edificio 41 (DEIB e DCMIC, MIA0314)

È nel campus Bassini, oltre il Giuriati: la scheda è in `design/mappa/bassini.json` (contorno
di OSM, stesso frame di `leonardo.json`) e le piante sono quelle del Politecnico, seminterrato
compreso. Il seminterrato nel servizio è spostato: `spostamenti` lo riporta sulle tre scale che
ha in comune col piano terra, e così cade sullo scavo del 2021 nelle foto aeree.

L'esterno è in `gusci/MIA0314.py`, ridisegnato dalle foto di Urbanfile e del Politecnico (drone
e piazza): pettine di tre corpi neri a pannelli verso sud, due connettori vetrati verso Largo
Volontari del Sangue con il portale a tre fornici al piano terra, quinto piano chiuso, corona
più alta con le fasce degli impianti a lamelle e il fotovoltaico, il tunnel vetrato verso
l'Edificio 20A e il ponte del primo piano verso il 21. Piano terra a 4,8 m, gli altri a 4,4 m.
Il contorno di Edificio 41 in `giuriati.usdz` si salta perché c'è il guscio. Sono dedotti
l'annesso basso a est e la posizione della rampa del parcheggio.

## Gli edifici fatti col kit (`gusci/_kit.py`)

Gli edifici più semplici hanno un guscio corto che descrive l'esterno con gli attrezzi comuni
di `gusci/_kit.py`: il contorno di ogni piano dalle piante, per ogni lato il rivestimento e
le finestre (dove le piante le disegnano, o a passo regolare), i marcapiano, le porte esterne
della pianta, poi il tetto (piano col parapetto, a padiglione o a capanna in coppi, a botte),
gli impianti e il fotovoltaico. Le aule senza banchi nelle piante li ricevono come
nell'Edificio 2 (`completa_piante`). Gli edifici fuori da `leonardo.json` stanno in
`bassini.json` con la sagoma di OSM (da `giuriati/giuriati.json` o da Overture).

Le fonti di ognuno sono nel docstring del suo guscio; dove non c'è una foto, la facciata è
dedotta dalle piante e dalle descrizioni, e lo dice.

### Edificio 25 (Emilio Massa, MIA0403)

Il quadrato di via Secondo (1996-2000, supervisione artistica di Luigi Caccia Dominioni):
facciate in pannelli di fibrocemento a bugnato grigi (scheda di CSA Studio), le finestre
delle piante su tre piani da 4,5 m, il tetto a padiglione scuro con il lucernario tondo
sulla falda nord (ortofoto), il seminterrato sotto la strada con la scala esterna a ovest.
Il seminterrato nel servizio è spostato: `spostamenti` lo riporta sul terra.

### Edificio 26 (MIA1401)

Via Golgi 20, le aule L26 e la mensa nel seminterrato. È in `design/mappa/citta-studi.json`, il file nuovo per gli edifici di Città Studi fuori dai campus di piazza Leonardo, via Bonardi e via Bassini-Golgi 40 (sagome di OSM da Overture). Il terra rialzato su tutta la sagoma, il primo solo sulla parte sud come nelle piante e nell'ortofoto; i tetti piani coperti di file di fotovoltaico est-ovest, il blocco degli impianti al centro (ortofoto). Le piante nel servizio sono disegnate girate di mezzo giro: il terra è messo sulla sagoma con l'ingresso verso via Golgi. Le facciate non hanno foto: intonaco chiaro con le finestre delle piante.

### Edificio 21 (MIA0306)

Via Golgi 39, il Dipartimento di Chimica e le aule EG. Sette piani da 3,6 m (dal terra al sesto, più il seminterrato): il terra ha il suo contorno, i piani dal primo al sesto un corpo solo a L, squadrato dalle piante. Calcestruzzo grigio con le alette verticali fra le finestre, a passo regolare, e i locali degli impianti e le canne dei laboratori sul tetto: dedotti dall'ortofoto, senza foto delle facciate. L'altezza di OSM (14,9 m) è troppo bassa per sette piani.

### Edificio 20 (MIA0301)

Via Ponzio 34/5, la stecca del DEIB lungo via Bassini, con l'aula 20.S.1. Quattro piani da 4,5 m (18 m come in OSM), la torre delle scale vetrata girata di 45° sul lato nord col tetto a piramide, il tetto bianco con due file di fotovoltaico e la testata est scura con gli impianti (ortofoto). Facciate senza foto: intonaco chiaro con le finestre delle piante, e a passo regolare (`ripiego` del kit) sui lati lunghi dove le piante non le disegnano. Terra e seminterrato nel servizio sono spostati di 2 m e 1,5 m verso nord: `spostamenti`.

### Edificio 19 "Mario Silvestri" (`MIA0302`)

La stecca di via Ponzio 34/3: tre piani da 3,4 m con le finestre delle piante (dove le piante non ne disegnano su un tratto lungo, una fila a passo regolare), il tetto bianco a padiglione quasi piano dell'ortofoto. Il corpo basso a nord, che OSM mette nella stessa sagoma e le piante non disegnano, è un volume di due piani col tetto scuro. Le facciate sono dedotte: nessuna foto.

### Edificio 23 (`MIA0402`)

Il capannone a un piano fra il 22 e il 25, con le aule G.0.1 e G.0.2: le finestre della pianta in basso, una fila alta a passo regolare, le due botti ribassate chiare che l'ortofoto mostra affiancate, la testata ovest più bassa col tetto piano scuro. La pianta è più lunga della sagoma di OSM e sta con l'ortofoto, quindi il guscio segue la pianta. Facciate dedotte, nessuna foto.

### Edificio 32.1 (`MIA0601`)

La palazzina a L di via Colombo con le aule E.P.6 ed E.P.7: quattro piani da 3,6 m sulla L del secondo piano, squadrata, con le finestre delle piante; il tetto in coppi a padiglione sul corpo nord, appoggiato alla palazzina accanto (il muro nord è cieco), e il tetto piano grigio con gli impianti sulla parte sud, come nell'ortofoto. Facciate dedotte, nessuna foto.

### Edificio 32.3 (`MIA0603`)

Il padiglione a un piano di via Colombo con le aule E.P.1, E.P.2 ed E.P.3. Il seminterrato sta sulla L di OSM, il terra disegna un'altra forma, e una sola trasformazione non le mette d'accordo: il guscio prende l'unione della sagoma di OSM e del terra, un piano da 4,5 m col tetto piano scuro e i lucernari dell'ortofoto. Forma e facciate sono dedotte, nessuna foto.

### Casa dello Studente (`MIA0901`)

La residenza di viale Romagna con l'aula auditorium al terra: ogni piano col suo contorno, perché le maniche cambiano da un piano all'altro (il corpo di mezzo c'è solo dal secondo al quinto, il sesto è ridotto), e il tetto piano su ciò che il piano sopra non copre. Il terra da 3,8 m, i piani delle camere da 2,95 m per stare nei 20,5 m di OSM. Facciate dedotte, nessuna foto: intonaco caldo con le finestre delle piante.

### Edificio 12 (`MIA0202`)

La torre di via Bonardi, senza aule. Le piante dal primo al sesto erano disegnate con un'origine loro: ora stanno sul rialzato con gli `spostamenti` in `leonardo.json`, misurati facendo coincidere la scala. Rialzato a un metro, cinque piani da 3,3 m un po' più stretti del rialzato, l'attico sul lato ovest, i tetti piani con gli impianti. Facciate dedotte, nessuna foto.

### Edificio 15 (`MIA0206`)

I laboratori a E di via Bonardi, senza aule: il terra su tutta la E, il primo sulla C, il secondo sulla sola manica sud, ognuno col tetto piano su ciò che il piano sopra non copre (in ghiaia chiara sulla manica nord, come nell'ortofoto). Il terra e il seminterrato erano disegnati 27 m più a est: stanno sul primo con gli `spostamenti` in `leonardo.json`. Piani da 4 m, facciate dedotte, nessuna foto.

### Edificio 18 (`MIA0207`)

La palazzina quadrata a un piano fra gli alberi dietro al Trifoglio: il tetto a padiglione chiaro dell'ortofoto, finestre a passo regolare (le piante non ne disegnano). Facciate dedotte, nessuna foto.

### Edificio 14A (`MIA0208`)

Il corpo seminterrato davanti al 14: le piante hanno solo il seminterrato e il soppalco, quindi il tetto sta a 1,2 m sopra il cortile, col lungo lucernario dell'ortofoto, e la facciata sud vetrata scende nella trincea in ombra. Nessuna foto.

### Edificio 14B (`MIA0209`)

La palazzina a L di due piani all'angolo del 14, con l'angolo tagliato in diagonale delle piante, le finestre delle piante e il tetto piano scuro dell'ortofoto. Piani da 4 m, facciate dedotte, nessuna foto.

### Edificio 16A (`MIA0214`)

Il corpo sotto la piazza fra il Trifoglio e il 14: il seminterrato affiora sulle bocche di lupo con un nastro di finestre, sopra c'è la piazza pavimentata dell'ortofoto con le fioriere, gli alberi e il lucernario quadrato; i due ingressi a sud, dove il terra esce dal rettangolo, sono padiglioni vetrati bassi. Nessuna foto.

### Edificio 9A Poli.Radio (`MIA0113`)

La palazzina stretta di due piani a est del 9: il terra era disegnato 3 m più a ovest del primo e ci sta sopra con lo `spostamento` in `leonardo.json`; intonaco, finestre delle piante, cornicione e tetto in coppi come nel `profilo` e nell'ortofoto. Nessuna foto.

### Edificio CT1 Centralino (`MIA0109`)

La palazzina a un piano del Centralino, dal `profilo` dell'illustrazione: intonaco, finestre a campate di 3,6 m, cornicione, terrazza grigia. Nessuna foto.

### Edificio 10 Posta (`MIA0110`)

La palazzina a un piano della Posta, dal `profilo` dell'illustrazione: intonaco, finestre a campate di 3,6 m, cornicione, terrazza grigia. Nessuna foto.

## Cosa manca

- Edificio 3: le facciate verso l'esterno del corpo est e il lato sud delle ali non hanno
  foto; sono disegnate come quelle in vista. Le file del primo e del secondo sono stimate, e
  i colori dei banchi valgono per piano, non per aula.
- Solo il Trifoglio e gli Edifici 11, 1, 2, 3, 4, 6 e 41 hanno l'esterno dettagliato; gli altri
  edifici restano estrusioni. Del profilo mancano ancora coppi, volte, denti, cornicioni, balaustre,
  finestre forate e lucernari.
- Le quote dell'Edificio 11 seguono una parte sola: la parte di Ponti ha fasce di altezze
  diverse, e lì piani e facciata non coincidono del tutto. Le aule ROGERS e IV e le aule A-F
  del primo non hanno file disegnate e restano vuote.
- Nel patio il bordo esterno (vetrate a 5 m dal vuoto) è un'approssimazione: la pianta lo
  apre su atri e corridoi. Mancano le pedane con i parapetti arancio intorno ai tavoli, il
  bar BCL, lo schermo e la trincea all'aperto lungo via Ampère (Urbanfile 2018).
- Le file di banchi sono continue: la pianta non disegna le singole sedute.
- Edificio 2: i banchi sono dedotti, non disegnati (gradoni o tavoli, verso della cattedra),
  e nessuna foto degli interni li conferma. La forma dei tetti fra padiglioni, ali e aule è
  semplificata in rettangoli; le finestre delle facciate senza file regolari nelle piante
  seguono la campata della mappa. L'occhio dentro le aule a volte sta vicino a un muro.
- I bagni restano vuoti: le piante del Trifoglio non disegnano i sanitari (`linee.sanitari`
  è vuota).
- La scritta "AULA MAGNA" e il logo sulla parete di cemento non ci sono. Le alzate dei gradoni
  sono stimate (17 cm a fila): in qualche aula sovrapposta il soffitto a gradini resta basso
  dietro, e la verifica dell'altezza lo alza a 2,6 m.
- Le alzate delle scale sono ricavate dal numero di pedate disegnate e dall'altezza del
  piano; le piante non le quotano. Le scale della torre vengono ripide (20 cm) perché la
  pianta disegna 9 pedate per rampa.
