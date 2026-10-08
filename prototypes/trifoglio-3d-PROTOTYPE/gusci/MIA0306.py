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

- le foto di via Golgi e via Corfù (Urbanfile, gennaio 2020): il calcestruzzo grigio con le
  alette verticali, le finestre e i pannelli scuri sotto che fanno strisce verticali continue,
  e su via Golgi la scala esterna aperta a rampe sfalsate, in calcestruzzo.

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
SCALA = box(474.6, 105.7, 481.4, 117.3)    # la scala esterna su via Golgi (i pianerottoli dei piani pari)

CLS = "#AEADA8"
ALETTE = "#C2C1BC"
SCURO = "#3B4246"          # i pannelli sotto le finestre
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
                 sguincio=0.12, lesene=(0.45, 0.16, ALETTE), sottofinestra=SCURO)
    # i piani dal primo al sesto hanno lo stesso contorno nelle piante, a meno di pochi
    # centimetri: un corpo solo, squadrato; il terra ha il suo
    terra = k.squadra(k.contorno("MIA0306000", chiudi=1.5), passo=1.0)
    corpo = max(k.pezzi(k.squadra(k.contorno("MIA0306002", chiudi=1.5), passo=1.0)), key=lambda g: g.area)
    corpo = max(k.pezzi(corpo.difference(SCALA.buffer(0.3, join_style=2))), key=lambda g: g.area)
    k.piano(terra, 0.0, H, st.con(davanzale=0.3, architrave=3.0), csip="MIA0306000", porte=True)
    k.tetto_piano(terra.difference(corpo.buffer(0.2, join_style=2)), H, parapetto=0.9, muro=CLS)
    for i in range(1, 7):
        k.piano(corpo, i * H, (i + 1) * H, st)
    k.tetto_piano(corpo, TETTO, parapetto=1.1, muro=CLS)
    scala(k)
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


def scala(k):
    """La scala esterna aperta su via Golgi: due rampe per piano che si alternano fra il lato
    verso il muro e quello verso la strada, coi pianerottoli alle due testate e i parapetti
    pieni in calcestruzzo che fanno lo zig-zag delle foto."""
    E, S = k.E, k.S
    x0, y0, x1, y1 = SCALA.bounds
    xm = (x0 + x1) / 2
    ya, yb = y0 + 1.8, y1 - 1.8                  # le rampe stanno fra i due pianerottoli
    for j in range(2 * 7):
        z0, z1 = j * H / 2, (j + 1) * H / 2
        fuori = j % 2 == 1
        xa, xb = (xm + 0.05, x1) if fuori else (x0, xm - 0.05)
        ys, ye = (ya, yb) if fuori else (yb, ya)
        # la rampa: una soletta inclinata di 25 cm
        bot = [(xa, ys, z0 - 0.25), (xb, ys, z0 - 0.25), (xb, ye, z1 - 0.25), (xa, ye, z1 - 0.25)]
        top = [(x, y, z + 0.25) for x, y, z in bot]
        S.solid(CLS, E.hexa(bot, top))
        # il parapetto pieno sul lato libero della rampa
        xp = (x1 - 0.18, x1) if fuori else (xm - 0.05, xm + 0.13)
        bot = [(xp[0], ys, z0), (xp[1], ys, z0), (xp[1], ye, z1), (xp[0], ye, z1)]
        top = [(x, y, z + 1.1) for x, y, z in bot]
        S.solid(CLS if fuori else ALETTE, E.hexa(bot, top))
        # il pianerottolo d'arrivo, con il parapetto in testata
        yl = (yb, y1) if fuori else (y0, ya)
        S.solid(CLS, E.box_z(xm, sum(yl) / 2, x1 - x0, yl[1] - yl[0], z1 - 0.25, z1))
        yt = yl[1] - 0.18 if fuori else yl[0]
        S.solid(CLS, E.box_z(xm, yt + 0.09, x1 - x0, 0.18, z1, z1 + 1.1))
        S.solid(CLS, E.box_z(x1 - 0.09, sum(yl) / 2, 0.18, yl[1] - yl[0], z1, z1 + 1.1))
    k.top = max(k.top, 7 * H + 1.1)
