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

- le aule hanno le file di banchi disegnate (`linee.arredi`): ogni fila diventa banco e
  seduta, su un gradino che sale di 17 cm da quello davanti. Le file si contano dalla
  cattedra (il lato con più spazio libero) e nelle aule a ventaglio ogni settore ha la sua
  direzione; le aule senza file restano piane;
- le scale (`linee.scale`) sono rampe gradino per gradino, che salgono dal lato della porta;
- gli ascensori sono vani pieni, le porte hanno l'anta aperta come nella pianta, i parapetti
  (`linee.ringhiere`) un corrimano;
- nei muri tagliati sono aperti i varchi delle porte, e dove la pianta disegna le finestre il
  muro diventa davanzale fino a 0,9 m con il vetro sopra.

Banchi, scale, ante e corrimano stanno in `<csip>_Arredi`, fuori da `_Locali`, così il tocco
seleziona sempre l'aula intera. Le piante dei piani
seguono le quote del guscio: seminterrato a 0, terra a 3,5 m, primo a 7,5 m. Gli altri edifici
restano estrusioni.

## Cosa manca

- Solo il Trifoglio ha il guscio: per gli altri edifici le forme di `build-mappa.py` (falde,
  volte, sheds, vetrate) non sono ancora portate nell'esportatore.
- Le file di banchi sono continue: la pianta non disegna le singole sedute.
- Le scale salgono di 17 cm a pedata dal pavimento del piano, senza pianerottoli: la pianta
  non dice a che quota sta ogni rampa.
