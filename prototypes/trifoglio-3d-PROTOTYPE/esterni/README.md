# Strade e verde della zona — esterni 3D

Il suolo intorno a tutti gli edifici modellati: il campus Leonardo, via Bassini e via Golgi
con il Giuriati, Città Studi (via Colombo, Golgi 20, Casa dello Studente). Prima il campus
aveva otto strade dritte bianche, un prato chiaro e gli alberi tutti uguali, e gli edifici di
Città Studi stavano nel vuoto, fuori dal terreno.

| File | Cosa contiene |
|---|---|
| `importa.py` | scarica da OpenStreetMap (copia di Overture Maps, come `giuriati/importa.py`) strade, tram, marciapiedi, attraversamenti, percorsi, verde, aiuole, siepi, acqua, alberi, filari, lampioni, panchine, semafori ed edifici della città, e scrive `zona.json` |
| `zona.json` | tutto questo nel frame del campus (metri, x verso est, y verso sud, origine 45.48, 9.22803); la zona è il riquadro degli edifici dei file in `design/mappa` più 80 m |
| `importa_arredo.py` | i dettagli dell'arredo che `zona.json` non tiene (tipo di lampione, schienale e materiale delle panchine, direzione), più cestini, rastrelliere, dissuasori, fontanelle, fermate e idranti; scrive `arredo.json` |
| `arredo.json` | questi dettagli, nello stesso frame |
| `arredo.py` | l'arredo dettagliato sopra il suolo: alberi, cordoli, formelle, panchine, lampioni, arredi, attrezzature dei campi e dei giochi, pergole (vedi sotto) |
| `esterni3d.py` | da `zona.json` al suolo in 3D: `terreno()` lo chiama `campus()` di `esporta3d.py`, da solo scrive `zona.usdz` o `zona.glb` per provarlo |

```
python3 -m pip install pyarrow shapely trimesh mapbox_earcut numpy usd-core
python3 importa.py zona.json --mappa ../../../design/mappa      # circa 2 minuti
python3 esterni3d.py zona.json /tmp/zona --glb                   # solo il suolo, 20 secondi
python3 importa_arredo.py arredo.json --zona zona.json       # 10 secondi
python3 arredo.py /tmp/zona --glb [--riquadro x0 y0 x1 y1]   # suolo e arredo, senza gli edifici
```

Poi si rigenerano `campus.usdz` (con l'elenco `--edifici` completo, vedi `../README.md`) e
`giuriati.usdz` con `--zona` (vedi `../giuriati/README.md`).

## Cosa c'è nel modello

Sotto `Campus` in `campus.usdz`:

- **Terreno**: il suolo; le **strade** in asfalto (texture `asfalto`), larghe secondo la
  classe di OSM (14 m le primarie, 9 le terziarie, 7 le residenziali, 4,5 i passi carrai) o
  la larghezza di OSM dove c'è; le **strisce pedonali** sugli attraversamenti di OSM (zebre
  da 50 cm ogni metro, lunghe 3 m) e la **mezzeria** tratteggiata sulle strade principali,
  lontano dagli incroci; i **binari del tram** (due rotaie ogni binario di OSM);
  i **marciapiedi** rialzati di 15 cm, dove OSM li disegna e lungo le strade che non li
  hanno a parte; gli **spartitraffico** verdi dove gli alberi stanno in mezzo alla strada;
  piazze, percorsi, i **vialetti** in ghiaia dentro i parchi, parcheggi, campi da gioco
  fuori dal Giuriati, piscine e laghetto.
- **Prati**: il verde per tipo (prati, parchi, giardini, aree cani, boschetti, arbusti) con
  la texture `erba`, le **aiuole** di OSM con i fiori, le **siepi** alte 1,2 m.
- **Alberi**: `Chiome` (latifoglie in tre verdi, conifere, palme) e `Tronchi`, gli stessi
  nomi che `Trifoglio3DView` spegne quando si entra in un piano. Dimensioni di OSM dove ci
  sono (diametro della chioma, altezza), se no un albero di città di 9-12 m, sempre lo
  stesso per la stessa posizione; i filari un albero ogni 8 m. Nessun albero dentro un
  edificio.
- **Arredi**: lampioni, semafori e panchine di OSM.
- **Quartiere**: gli edifici della città che non sono del Politecnico, volumi chiari con
  l'altezza di OSM (o 3,2 m a piano); fuori da `Edifici`, quindi non si toccano.

### L'arredo dettagliato (`arredo.py`)

`campus()` lo usa quando c'è `arredo.json`: `prima()` dà a `terreno()` gli alberi nuovi e gli
toglie lampioni e panchine semplici, `arreda()` aggiunge il resto. Tutto da OSM, niente
inventato di posizione:

- **Alberi**: tronco rastremato e leggermente storto, colletto, tre rami principali; chioma a
  lobi irregolari, a globo (platani, bagolari) o ovale e più alta (tigli, carpini), sempre la
  stessa per la stessa posizione; conifere a cinque palchi; palme di Milano (Trachycarpus)
  con dodici foglie a ventaglio e le foglie secche sotto. Stessi gruppi `Chiome`/`Tronchi`.
- **Marciapiedi**: il **cordolo** in granito verso la carreggiata, abbassato per 2 m intorno
  agli attraversamenti; le **formelle** in terra con il bordo in acciaio degli alberi sul
  marciapiede, girate come la strada.
- **Panchine** (351): legno su fianchi in ghisa con doghe, schienale inclinato e braccioli dove
  OSM li dà; blocchi in pietra o cemento senza schienale; metallo. Lunghe 60 cm a posto, girate
  come dice `direction` o, se manca, verso il percorso o la strada più vicina.
- **Lampioni** (425): a pastorale da 8 m che sporge sulla carreggiata (`bent_mast` e quelli
  senza tipo), a palo dritto da 7 m (`straight_mast`, `pole` vicino alla strada), lanterne in
  ghisa da 4,5 m lontano dalle strade, nei parchi. Quelli appesi ai cavi (`wire`) no.
- **Arredi**: cestini, rastrelliere ad archetto (uno ogni due posti, coperte dove OSM lo dice),
  dissuasori, le **vedovelle** (fontanelle in ghisa verde), pensiline e paline delle fermate,
  idranti.
- **Sport** (gruppo `Sport`): porte da calcio a misura del campo, canestri con tabellone e
  ferro, reti da tennis, padel con il vetro sul fondo e la rete sui lati (un'area di OSM con
  più campi si divide), pali da rugby, la struttura della calistenica; le righe dei campi
  fuori dal Giuriati. Nei parchi giochi altalene, scivoli con la torretta, dondoli, giochi a
  molla e sabbiere, quanti ce ne stanno. `giuriati/esterni3d.py` chiama `sport()` per i suoi
  campi, che le righe le hanno già.
- **Aree cani**: recinzione a rete alta 1,2 m.
- **Pergole**: sulla terrazza della Sala Lettura (corte di MIA0114 in `leonardo.json`), quattro
  pergole in acciaio con il rampicante sopra fioriere rialzate, alla quota del tetto del guscio.

Nell'isolato del Giuriati campi e pista restano in `giuriati.usdz`; qui sono solo tolti
dal verde.

## Limiti

- Le larghezze delle strade sono per classe: OSM non dà le corsie nei dati di Overture.
- Le strisce e la mezzeria sono ricostruite, non rilevate: una mezzeria può mancare o
  restare dove in realtà c'è una corsia del tram o un parcheggio.
- Nessuna ortofoto da questo ambiente (vedi `../giuriati/README.md`): quello che OSM non ha
  (fioriere, alberi giovani, aiuole piccole, altre pergole, giochi dei parchi uno per uno) non
  c'è, o è disposto, non rilevato: nei parchi giochi di OSM i giochi sono messi dove ci stanno.
- Le specie degli alberi in OSM sono quasi tutte assenti: la forma della chioma si sceglie
  dalle proporzioni e dalla posizione, non dalla specie.

Posizioni © OpenStreetMap contributors (ODbL).
