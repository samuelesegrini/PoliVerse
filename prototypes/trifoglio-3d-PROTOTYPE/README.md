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

Dal campus si sceglie il Trifoglio, l'Edificio 11 o l'Edificio 8. "Portami all'aula T.1.2" fa tutto il
percorso. Si può anche toccare l'edificio e le aule sul
modello, trascinare per ruotare e pizzicare per lo zoom.

## I modelli

`esporta3d.py` estrude i dati di `design/mappa/` (ramo `feat/laughing-planck-ul1yj3`):
i contorni di `leonardo.json` per i volumi e le piante CAD di `piante/<csie>-geometria.json`
per i piani. Scrive in `PoliVerse/Preview Content/Trifoglio3D/`:

| File | Cosa contiene |
|---|---|
| `campus.usdz` | terreno, alberi, volumi di tutti gli edifici sotto `Campus/Edifici/<csie>` |
| `MIA0203.usdz` | i piani del Trifoglio: `MIA0203/Piani/<csip>` con soletta, muri tagliati a 1,5 m, locali e arredi (`<csip>_Arredi`); ogni aula è un nodo chiamato con il suo `csiv` |
| `MIA0203.json` | piani, quote e aule (sigla, posti) per l'interfaccia |
| `MIA0201.usdz`, `MIA0201.json` | lo stesso per l'Edificio 11 |
| `MIA0108.usdz`, `MIA0108.json` | lo stesso per l'Edificio 8 |

Il `csiv` è lo stesso codice di `Classroom.roomCode`, quindi dall'aula di una lezione si
trova il nodo da accendere senza tabelle in più.

Per rigenerarli, con il ramo della mappa estratto:

```
python3 -m pip install shapely trimesh mapbox_earcut numpy usd-core
python3 esporta3d.py <checkout>/design/mappa "../../PoliVerse/Preview Content/Trifoglio3D" --edifici=MIA0203,MIA0201,MIA0108
```

Metri, asse Y verso l'alto, X verso est, Z verso sud. Piani da 4 m.

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

## L'Edificio 8

L'esterno dell'Amerio (l'Istituto di Fisica, oggi il Dipartimento di Fisica) è rifatto da
zero in `gusci/MIA0108.py`, un guscio proprio come quelli degli altri edifici in `gusci/`
(`guscio`, `quote`, `tetto`, `piante`). Fonti: l'ortofoto (Google, zoom 21) per i tetti e i
corpi nel cortile, la foto della testata "FISICA SPERIMENTALE" (sito del Dipartimento) per
facciate e quote, le piante per finestre e porte:

- le ali in intonaco a graniglia grigio-beige, il terra a bugnato con le finestre ad arco
  ribassato dentro un arco a tutto sesto, la fascia, le finestre ad arco del primo sui
  davanzali a mensola, il cornicione con la gronda, i pluviali di rame; le porte ad arco
  dove la pianta del terra ha le porte esterne (anche negli smussi della testata);
- i tetti a padiglione in coppi come nell'ortofoto: un padiglione per ala (l'ala diagonale
  con gli smussi), dove si incrociano vince il più alto, così impluvi e displuvi vengono da
  sé; il corpo est piano fra due testate a padiglione, con un abbaino;
- nel cortile il corpo ottagonale basso (il locale 017 della pianta del secondo è il suo
  tetto piano bianco, con le macchine), la volta di vetro a rombi contro il suo lato nord-est,
  i corpi di un piano intorno e i pozzi di luce;
- a nord il secondo piano sotto la terrazza pavimentata, con le fioriere, il padiglione
  grigio e le pergole dell'ortofoto, e il torrino dell'ascensore.

Quote dalla foto (la testata è larga 12,9 m fra gli smussi) e dalle scale (32 alzate fra
terra e primo): seminterrato a -4,2, terra a 0,3, primo a 5,9, secondo a 10,4, gronda a 11,
terrazza a 14. Il primo, il secondo e il seminterrato sono importati fuori posto rispetto al
terra: `piante()` li riallinea (il primo è anche stirato di 2 cm per metro in x, misurato sui
muri e sull'ascensore del terra). L'aula 8.0.1 (260 posti) occupa tutta l'ala diagonale e
non ha file nelle piante: `piante()` le aggiunge parallele alla testata, ogni 95 cm, con la
cattedra verso l'ingresso interno a nord-est.

## Cosa manca

- Edificio 8: delle facciate c'è una foto sola, la testata dell'ala diagonale; le altre sono
  disegnate allo stesso modo. La cattedra dell'aula 8.0.1 a nord-est, l'altezza della volta
  di vetro e il secondo piano sotto la terrazza (sopra il cortiletto aperto del terra) sono
  dedotti dalle piante e dall'ortofoto, non rilevati.

- Solo il Trifoglio, l'Edificio 11 e l'Edificio 8 hanno l'esterno dettagliato; gli altri edifici restano
  estrusioni. Del profilo mancano ancora coppi, volte, denti, cornicioni, balaustre,
  finestre forate e lucernari.
- Le quote dell'Edificio 11 seguono una parte sola: la parte di Ponti ha fasce di altezze
  diverse, e lì piani e facciata non coincidono del tutto. Le aule ROGERS e IV e le aule A-F
  del primo non hanno file disegnate e restano vuote.
- Nel patio il bordo esterno (vetrate a 5 m dal vuoto) è un'approssimazione: la pianta lo
  apre su atri e corridoi. Mancano le pedane con i parapetti arancio intorno ai tavoli, il
  bar BCL, lo schermo e la trincea all'aperto lungo via Ampère (Urbanfile 2018).
- Le file di banchi sono continue: la pianta non disegna le singole sedute.
- I bagni restano vuoti: le piante del Trifoglio non disegnano i sanitari (`linee.sanitari`
  è vuota).
- La scritta "AULA MAGNA" e il logo sulla parete di cemento non ci sono. Le alzate dei gradoni
  sono stimate (17 cm a fila): in qualche aula sovrapposta il soffitto a gradini resta basso
  dietro, e la verifica dell'altezza lo alza a 2,6 m.
- Le alzate delle scale sono ricavate dal numero di pedate disegnate e dall'altezza del
  piano; le piante non le quotano. Le scale della torre vengono ripide (20 cm) perché la
  pianta disegna 9 pedate per rampa.
