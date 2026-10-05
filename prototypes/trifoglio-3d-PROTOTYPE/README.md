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
| `MIA0203.usdz` | i piani del Trifoglio: `MIA0203/Piani/<csip>` con soletta, muri tagliati a 1,5 m e locali; ogni aula è un nodo chiamato con il suo `csiv` |
| `MIA0203.json` | piani, quote e aule (sigla, posti) per l'interfaccia |

Il `csiv` è lo stesso codice di `Classroom.roomCode`, quindi dall'aula di una lezione si
trova il nodo da accendere senza tabelle in più.

Per rigenerarli, con il ramo della mappa estratto:

```
python3 -m pip install shapely trimesh mapbox_earcut numpy usd-core
python3 esporta3d.py <checkout>/design/mappa "../../PoliVerse/Preview Content/Trifoglio3D" --edifici=MIA0203
```

Metri, asse Y verso l'alto, X verso est, Z verso sud. Piani da 4 m, terra a quota zero.

## Cosa manca

- Volumi senza tetti né facciate: le forme di `build-mappa.py` (falde, volte, sheds) non sono
  ancora portate nell'esportatore.
- Porte e vani scala non tagliati nei muri.
- I tocchi usano forme di collisione convesse: in un'aula a L il tocco può prendere la vicina.
