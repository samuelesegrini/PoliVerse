"""PROTOTIPO — l'Edificio 14 "Nave" (MIA0205), via Bonardi: la stecca delle aule da disegno
costruita fra il 1955 e il 1963, a L intorno alla piazza sopra il 16C.

Fonti, oltre alle piante del Politecnico (seminterrato, dal terra all'ottavo):
- la sagoma di OSM e le piante: l'ala ovest stretta e lunga e l'ala nord su via Bonardi; il
  terzo piano c'è solo nell'ala ovest perché nell'ala nord le aule del secondo sono a doppia
  altezza; l'ottavo è il locale degli impianti sull'ala ovest;
- l'ortofoto (Esri World Imagery): i tetti piani, quello dell'ala nord pieno di impianti e
  canali, il locale lungo sull'ala ovest;
- il restauro delle facciate, appaltato insieme a quello dell'Edificio 12 (gare del
  Politecnico): la stessa pelle in klinker testa di moro con le finestre incorniciate di
  bianco del 12, che si vede nelle foto del campus. Non c'è una foto della Nave: il
  rivestimento è dedotto da quello del 12.

Piani da 3,8 m; le finestre sono quelle delle piante, piano per piano.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0205"
H = 3.8
PIANI = [f"MIA020500{i}" for i in range(8)]
QUOTE = {"MIA020500S": -3.6, **{c: round(i * H, 2) for i, c in enumerate(PIANI)}, "MIA0205008": round(8 * H, 2)}
TETTO = round(8 * H, 2)

KLINKER = "kit_klinker_scuro"
BIANCO = "#E6E5E0"
TELAIO = "#D9D9D5"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=KLINKER, davanzale=0.9, architrave=2.9, telaio=TELAIO, sguincio=0.15, reach=1.5,
                 ripiego=(3.0, 1.6, 10.0), cornice=BIANCO, lesene=(0.08, 0.16, BIANCO))
    corpo = max(k.pezzi(k.squadra(k.contorno("MIA0205004", chiudi=0.8), passo=0.5)), key=lambda g: g.area)
    terra = max(k.pezzi(k.squadra(k.contorno("MIA0205000", chiudi=0.8), passo=0.5)), key=lambda g: g.area)
    k.piano(terra, 0.0, H, st.con(davanzale=0.4, lesene=None), csip="MIA0205000", porte=True)
    k.tetto_piano(terra.difference(corpo.buffer(0.2, join_style=2)), H, parapetto=0.6, muro=KLINKER)
    for i, csip in enumerate(PIANI[1:], 1):
        # il terzo dell'ala nord è la doppia altezza del secondo: le finestre del secondo
        k.piano(corpo, i * H, (i + 1) * H, st, csip="MIA0205002" if csip == "MIA0205003" else csip)
    k.tetto_piano(corpo, TETTO, parapetto=1.0, muro=KLINKER)
    # l'ottavo: il locale lungo degli impianti sull'ala ovest
    loc = k.squadra(k.contorno("MIA0205008", chiudi=0.8)).minimum_rotated_rectangle
    k.piano(loc, TETTO, TETTO + 3.2, K.Stile(muro="#B9B7B1", finestre=("passo", 4.0, 1.2), davanzale=1.6,
                                                 architrave=2.6, telaio="#5A5F64"))
    k.tetto_piano(loc, TETTO + 3.2, parapetto=0.4)
    # gli impianti e i canali sul tetto dell'ala nord
    nord = corpo.intersection(box(70, -10, 140, 12))
    x0, y0, x1, y1 = nord.bounds
    for j, x in enumerate(range(int(x0) + 6, int(x1) - 4, 9)):
        k.impianto(x, (y0 + y1) / 2 + (1.5 if j % 2 else -1.5), 5.0, 3.0, TETTO + 0.1, h=1.6 + 0.4 * (j % 2))
    return k.fine()
