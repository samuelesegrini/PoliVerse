"""PROTOTIPO — l'Edificio 26 (MIA1401), via Golgi 20: le aule L26 e, nel seminterrato, la mensa
Golgi.

Fonti, oltre alle piante del Politecnico (seminterrato, terra rialzato, primo):
- la sagoma di OSM (w26013442, 9 m, due piani);
- l'ortofoto (Esri World Imagery, spostata di circa 8 m verso est e 5 m verso nord rispetto a
  OSM): il tetto piano tutto coperto di file di pannelli fotovoltaici in senso est-ovest,
  diviso da una linea a un terzo da nord, dove il primo piano comincia (come nelle piante, che
  disegnano il primo solo sulla parte sud); al centro del tetto del primo il blocco degli
  impianti con il suo parapetto;
- le piante: il terra ha finestre su tutto il perimetro e le porte verso via Golgi a ovest e
  verso il parcheggio a nord; le scale di sicurezza esterne del primo scendono a sud.

Le facciate, dai panorami Mapillary di via Golgi (febbraio 2025, da x 491 e x 503 lungo la
strada, y 426-520): un edificio basso e scuro degli anni Settanta, tutto in vetro bronzato tra
montanti bruni a passo fitto, con una fascia di pannelli bruni sotto la gronda e sul filo del
solaio; gli spigoli sono pilastri di mattone bruno a dentelli (lo spigolo nord-ovest porta il
totem del Politecnico); lo zoccolo del terra rialzato è di mattone; davanti al fronte su via
Golgi salgono due camini d'acciaio della mensa, più alti del tetto. Da via Golgi la gronda
corre quasi alla stessa quota per tutto il fronte: la parte nord, che le piante disegnano con il
solo terra (le sale grandi), qui è un piano unico alto, mezzo metro sotto il tetto del primo:
la linea dell'ortofoto.
"""
import sys
import pathlib
import trimesh
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA1401"
QUOTE = {"MIA140100S": -3.0, "MIA1401000": 1.2, "MIA1401001": 5.4}
TETTO_0, TETTO_1 = 5.4, 9.4
TETTO_N = 8.9              # la parte nord: un piano solo, alto quasi come i due a sud

BRUNO = "#3E271F"          # i pannelli e i montanti
MATTONE = "#5E3C30"
VETRO = "#272625"          # il vetro bronzato, quasi nero
ZOCCOLO = "#5E3B2E"
ACCIAIO = "#BFC3C6"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO_1


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def _pilastri(k, poly, z0, z1):
    """I pilastri di mattone sugli spigoli, a dentelli: lo spigolo è tolto a gradini."""
    from shapely.geometry import Point
    fuori = poly.buffer(0.2, join_style=2)
    pts = list(poly.exterior.coords)[:-1]
    for i, p in enumerate(pts):
        a, c = pts[i - 1], pts[(i + 1) % len(pts)]
        if (p[0] - a[0]) * (c[1] - p[1]) - (p[1] - a[1]) * (c[0] - p[0]) == 0:
            continue
        q = fuori.intersection(box(p[0] - 1.3, p[1] - 1.3, p[0] + 1.3, p[1] + 1.3))
        # il vertice esterno: il punto di `fuori` più lontano dal centro dell'edificio
        cx, cy = poly.centroid.x, poly.centroid.y
        sx, sy = (1 if p[0] > cx else -1), (1 if p[1] > cy else -1)
        if not poly.buffer(0.05).contains(Point(p[0] - sx * 0.3, p[1] - sy * 0.3)):
            continue                                       # uno spigolo rientrante: niente pilastro
        ox, oy = p[0] + sx * 0.2, p[1] + sy * 0.2
        for w, d in ((0.6, 0.2), (0.4, 0.4), (0.2, 0.6)):
            q = q.difference(box(min(ox, ox - sx * w), min(oy, oy - sy * d), max(ox, ox - sx * w), max(oy, oy - sy * d)))
            q = q.difference(box(min(ox, ox - sx * d), min(oy, oy - sy * w), max(ox, ox - sx * d), max(oy, oy - sy * w)))
        for r in k.pezzi(q, 0.2):
            k.S.solid(MATTONE, trimesh.creation.extrude_polygon(r, z1 - z0 + 0.3).apply_translation([0, 0, z0]))


def _fasce(k, poly, z0, z1, h=0.6, passo=1.25):
    """La fascia di pannelli bruni in alto su ogni lato, sopra il vetro, e i montanti bruni che
    sporgono dal vetro a passo fitto."""
    for q in k.pezzi(poly):
        for e in k.E.edges(k.E.ring_ccw(q)):
            k.pannello(BRUNO, e, K.rett(0, e[4], z1 - h, z1), 0.02, 0.1)
            n = int(e[4] / passo)
            for i in range(1, n):
                t = e[4] * i / n
                k.pannello(BRUNO, e, K.rett(t - 0.07, t + 0.07, z0, z1 - h), 0.0, 0.22)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=BRUNO, finestre="vetrata", telaio=BRUNO, vetro=VETRO, passo_montanti=1.25,
                 architrave=2.6)
    terra = k.squadra(k.contorno("MIA1401000", chiudi=0.8))
    primo = k.squadra(k.contorno("MIA1401001", chiudi=0.8))
    k.piano(terra, -0.2, 1.2, K.Stile(muro=ZOCCOLO, finestre=None))
    k.piano(terra, 1.2, TETTO_0, st, csip="MIA1401000", porte=True)
    k.piano(primo, TETTO_0, TETTO_1, st, csip="MIA1401001")
    basso = k.pezzi(terra.difference(primo), 20)
    for q in basso:
        k.piano(q, TETTO_0, TETTO_N, st)
        _fasce(k, q, TETTO_0, TETTO_N)
    _fasce(k, terra, 1.2, TETTO_0)
    _fasce(k, primo, TETTO_0, TETTO_1)
    _pilastri(k, terra, -0.2, TETTO_N)
    _pilastri(k, primo, TETTO_0 - 0.3, TETTO_1)
    # i due camini d'acciaio della mensa davanti al fronte su via Golgi
    for x, y in ((509.0, 482.0), (509.4, 485.6)):
        k.S.solid(ACCIAIO, trimesh.creation.cylinder(radius=0.3, height=11.6, sections=14).apply_translation([x, y, 5.8]))
        k.S.solid(ACCIAIO, trimesh.creation.cylinder(radius=0.4, height=0.3, sections=14).apply_translation([x, y, 11.5]))
    k.top = max(k.top, 11.7)
    # i tetti piani: la parte nord e il primo, coperti di fotovoltaico
    for q in basso:
        k.tetto_piano(q, TETTO_N, parapetto=0.6, muro=BRUNO)
    k.tetto_piano(primo, TETTO_1, parapetto=0.8, muro=BRUNO)
    for q in basso:
        k.fotovoltaico(q.buffer(-0.8, join_style=2), TETTO_N + 0.08)
    impianti = box(534.0, 471.0, 554.0, 482.0)
    for q in k.pezzi(primo.buffer(-0.9, join_style=2).difference(impianti.buffer(1.0, join_style=2)), 10):
        k.fotovoltaico(q, TETTO_1 + 0.08)
    # il blocco degli impianti al centro, col parapetto suo
    k.piano(impianti, TETTO_1, TETTO_1 + 2.4, K.Stile(muro="#CFCBC2", finestre=None))
    k.tetto_piano(impianti, TETTO_1 + 2.4, parapetto=0.4)
    for x, y in ((539.0, 476.0), (546.0, 475.0), (550.0, 478.5)):
        k.impianto(x, y, 2.2, 1.6, TETTO_1 + 2.5, h=1.0)
    return k.fine()
