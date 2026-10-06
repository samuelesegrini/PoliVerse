"""PROTOTIPO — l'Edificio 21 (MIA0306), via Golgi 39: il Dipartimento di Chimica, Materiali e
Ingegneria Chimica e, nel seminterrato e al terra, le aule EG.

Fonti, oltre alle piante del Politecnico (seminterrato e sette piani, dal terra al sesto):
- la sagoma di OSM (w41277540): un corpo a L con la torre delle scale a sud e quella a est;
- l'ortofoto (Esri World Imagery, spostata di circa 8 m verso est e 5 m verso nord): la lunga
  ombra verso nord-ovest dice che è l'edificio più alto dell'isolato dopo il 22, e sui lati
  ovest e sud si leggono le alette verticali fitte fra una finestra e l'altra; sul tetto i
  locali degli impianti e le canne dei laboratori;
- le piante: le finestre su tutti i lati, a passo regolare, piano per piano; il ponte del
  primo piano verso l'Edificio 41 sta nel guscio del 41.

Nessuna foto delle facciate: il calcestruzzo grigio e le alette sono dedotti dall'ortofoto.
L'altezza di OSM (14,9 m) non regge sette piani: i piani sono da 3,6 m, come nei laboratori
del dopoguerra del campus.
"""
import sys
import pathlib
import trimesh
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0306"
H = 3.6
PIANI = [f"MIA030600{i}" for i in range(7)]
QUOTE = {"MIA030600S": -3.8, **{c: round(i * H, 2) for i, c in enumerate(PIANI)}}
TETTO = round(7 * H, 2)

CLS = "#BDB9B0"
ALETTE = "#CFCBC2"
TELAIO = "#3C4045"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=CLS, finestre=("passo", 1.8, 1.25), davanzale=0.9, architrave=2.9, telaio=TELAIO,
                 sguincio=0.12, lesene=(0.45, 0.16, ALETTE), marcapiano=(0.3, 0.05, "#A9A59D"))
    # i piani dal primo al sesto hanno lo stesso contorno nelle piante, a meno di pochi
    # centimetri: un corpo solo, squadrato; il terra ha il suo
    terra = k.squadra(k.contorno("MIA0306000", chiudi=1.5), passo=1.0)
    corpo = max(k.pezzi(k.squadra(k.contorno("MIA0306002", chiudi=1.5), passo=1.0)), key=lambda g: g.area)
    k.piano(terra, 0.0, H, st.con(davanzale=0.3, architrave=3.0), csip="MIA0306000", porte=True)
    k.tetto_piano(terra.difference(corpo.buffer(0.2, join_style=2)), H, parapetto=0.9, muro=CLS)
    for i in range(1, 7):
        k.piano(corpo, i * H, (i + 1) * H, st)
    k.tetto_piano(corpo, TETTO, parapetto=1.1, muro=CLS)
    # sul tetto: il locale degli impianti, le canne dei laboratori, una UTA
    q = max(k.pezzi(corpo.buffer(-3.0, join_style=2), 20), key=lambda g: g.area)
    x0, y0, x1, y1 = q.bounds
    loc = box(x0, y0, min(x1, x0 + 9), min(y1, y0 + 6))
    k.piano(loc, TETTO, TETTO + 3.0, K.Stile(muro=CLS, finestre=None))
    k.tetto_piano(loc, TETTO + 3.0, parapetto=0.3)
    for j in range(6):
        x = x0 + 11 + j * 2.4
        if x < x1 - 1:
            k.S.solid("#9A9EA2", trimesh.creation.cylinder(radius=0.25, height=2.4, sections=10).apply_translation([x, y0 + 1.5, TETTO + 1.2]))
    k.impianto((x0 + x1) / 2 + 3, (y0 + y1) / 2 + 4, 4.0, 2.4, TETTO + 0.1, h=1.8)
    return k.fine()
