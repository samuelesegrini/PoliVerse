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

"Portami all'aula T.1.2" fa tutto il percorso. Si può anche toccare l'edificio e le aule sul
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

Il `csiv` è lo stesso codice di `Classroom.roomCode`, quindi dall'aula di una lezione si
trova il nodo da accendere senza tabelle in più.

Per rigenerarli, con il ramo della mappa estratto:

```
python3 -m pip install shapely trimesh mapbox_earcut numpy usd-core
python3 esporta3d.py <checkout>/design/mappa "../../PoliVerse/Preview Content/Trifoglio3D" --edifici=MIA0203
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

## Cosa manca

- Solo il Trifoglio ha il guscio: per gli altri edifici le forme di `build-mappa.py` (falde,
  volte, sheds, vetrate) non sono ancora portate nell'esportatore.
- Le file di banchi sono continue: la pianta non disegna le singole sedute.
- I bagni restano vuoti: le piante del Trifoglio non disegnano i sanitari (`linee.sanitari`
  è vuota).
- La scritta "AULA MAGNA" e il logo sulla parete di cemento non ci sono. Le alzate dei gradoni
  sono stimate (17 cm a fila): in qualche aula sovrapposta il soffitto a gradini resta basso
  dietro, e la verifica dell'altezza lo alza a 2,6 m.
- Le alzate delle scale sono ricavate dal numero di pedate disegnate e dall'altezza del
  piano; le piante non le quotano. Le scale della torre vengono ripide (20 cm) perché la
  pianta disegna 9 pedate per rampa.
