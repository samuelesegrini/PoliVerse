"""PROTOTIPO — l'Edificio 9A (MIA0113), Poli.Radio: la palazzina stretta di due piani a est del 9,
senza aule.

Fonti, oltre alle piante del Politecnico (terra e primo): la sagoma di OSM; il terra era
disegnato 3 m più a ovest del primo e ci sta sopra con lo `spostamento` in `leonardo.json`;
l'ortofoto (falde rosse); e le panoramiche di Mapillary del 2024-25 su via Bonardi, dove il lato
est è il muro di cinta stesso, raddrizzate sul piano della facciata (le prese da tre punti
combaciano solo con la facciata a 2,8 m dalla camera, e da lì vengono le misure):
- il corpo a due piani è lungo 12,9 m dalla testa nord; nei 2,5 m a sud c'è un corpo a un piano
  con la terrazza, la ringhiera e un'unità esterna, contro il pilastro d'angolo della cancellata;
- verso strada il terra è cieco: intonaco grigio su uno zoccolo di ghiaietto alto 0,9 m;
- quattro campate fra cinque lesene di pietra chiara larghe 0,6 m; al primo un nastro di
  finestre per campata (vetro sopra, pannello scuro sotto), da 3,6 a 5,05 m, su una fascia di
  pietra a 3,3-3,6 m; la cornice di pietra fino alla gronda a 5,9 m; il tetto in coppi a
  padiglione, basso.
Gli altri lati non si vedono dalla strada: hanno le finestre delle piante e gli stessi materiali.
"""
import sys
import pathlib
import numpy as np
from shapely.geometry import Polygon

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K
from _kit import rett

CSIE = "MIA0113"
P1 = 3.0                       # il pavimento del primo
GRONDA = 5.9
QUOTE = {"MIA0113000": 0.0, "MIA0113001": P1}
TETTO = GRONDA
LUNGO = 12.9                   # il corpo a due piani, dalla testa nord
H_TERRAZZA = 3.4

INTONACO = "#ABA79F"
PIETRA = "#CEC5B2"
ZOCCOLO = "#8C877D"
TELAIO = "#3B3F44"
PANNELLO = "#4A4E53"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def _parti(corpo):
    """Il rettangolo diviso lungo l'asse lungo: il corpo alto a nord, la terrazza a sud."""
    pts = [np.array(p) for p in list(corpo.exterior.coords)[:4]]
    lati = sorted(range(4), key=lambda i: -np.linalg.norm(pts[(i + 1) % 4] - pts[i]))
    i = lati[0]
    a, c = pts[i], pts[(i + 1) % 4]
    u = (c - a) / np.linalg.norm(c - a)
    if u[1] < 0:                                   # u verso sud (y cresce verso sud)
        u = -u
    larg = min(np.linalg.norm(pts[(i + 1) % 4] - pts[(i + 2) % 4]), np.linalg.norm(c - a))
    w = np.array([-u[1], u[0]])
    ctr = np.mean(pts, axis=0)
    ys = [float(np.dot(p - ctr, u)) for p in pts]
    s0, s1 = min(ys), max(ys)
    xs = [float(np.dot(p - ctr, w)) for p in pts]
    w0, w1 = min(xs), max(xs)

    def blocco(t0, t1):
        return Polygon([tuple(ctr + u * t + w * x) for t, x in ((t0, w0), (t1, w0), (t1, w1), (t0, w1))])
    sm = min(s0 + LUNGO, s1 - 1.0)
    return blocco(s0, sm), blocco(sm, s1)


def _est(e):
    return e[3][0] > 0.7


def _fronte(k, e):
    """Il fronte su via Bonardi del corpo alto: lesene, nastri, fasce di pietra."""
    P = k.pannello
    L = e[4]
    n = 4
    lw = 0.6
    cs = [lw / 2 + i * (L - lw) / n for i in range(n + 1)]
    z0, z1 = 3.6, 5.05
    buchi = [(cs[i] + lw / 2, cs[i + 1] - lw / 2, z0, z1) for i in range(n)]
    k.muro(e, 0.0, GRONDA, INTONACO, buchi)
    st = K.Stile(telaio=TELAIO, sguincio=0.12, montante=1.3, cornice=None)
    for t0, t1, _, _ in buchi:
        zm = z0 + 0.7
        P(PANNELLO, e, rett(t0, t1, z0, zm), -0.12, -0.09)                 # il pannello scuro sotto
        P("#7E93A4", e, rett(t0, t1, zm, z1), -0.14, -0.12)                # il vetro chiaro sopra
        tel = rett(t0, t1, z0, z1).difference(rett(t0 + 0.07, t1 - 0.07, z0 + 0.07, z1 - 0.07))
        P(TELAIO, e, tel, -0.12, -0.04)
        P(TELAIO, e, rett(t0, t1, zm - 0.03, zm + 0.03), -0.12, -0.05)
        tm = (t0 + t1) / 2
        P(TELAIO, e, rett(tm - 0.03, tm + 0.03, zm, z1), -0.12, -0.05)
    P(ZOCCOLO, e, rett(0.0, L, 0.0, 0.9), 0.0, 0.05)                         # lo zoccolo di ghiaietto
    P(PIETRA, e, rett(0.0, L, 3.3, 3.6), 0.0, 0.08)                          # la fascia sotto i nastri
    for c in cs:
        P(PIETRA, e, rett(c - lw / 2, c + lw / 2, 0.0, 5.25), 0.0, 0.12)    # le lesene
    P(PIETRA, e, rett(0.0, L, 5.25, GRONDA), 0.0, 0.14)                      # la cornice


def _ringhiera(k, poly, z, h=1.0):
    """La ringhiera della terrazza: i montanti radi e cinque correnti orizzontali, come in foto."""
    for e in k.E.edges(k.E.ring_ccw(poly)):
        L = e[4]
        for zz in np.linspace(z + 0.15, z + h, 5):
            k.pannello("#6F7479", e, rett(0.0, L, zz - 0.025, zz + 0.025), -0.15, -0.11)
        for i in range(int(L / 1.6) + 1):
            t = min(L - 0.03, max(0.03, i * 1.6))
            k.pannello("#6F7479", e, rett(t - 0.03, t + 0.03, z, z + h), -0.16, -0.1)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    corpo = k.contorno("MIA0113001", chiudi=0.4).minimum_rotated_rectangle
    alto, terrazza = _parti(corpo)
    st = K.Stile(muro=INTONACO, davanzale=0.9, architrave=2.6, telaio=TELAIO, sguincio=0.15, reach=1.5,
                 ripiego=(3.0, 1.1, 8.0), cornice=PIETRA)
    st1 = st.con(davanzale=0.6, architrave=2.05)

    def lato(st_):
        return lambda e, m: None if _est(e) else st_
    # il nucleo e i lati con le finestre delle piante; il fronte est a parte
    k.piano(alto, 0.0, P1, lato(st), csip="MIA0113000")
    k.piano(alto, P1, GRONDA, lato(st1), csip="MIA0113001")
    for e in E.edges(E.ring_ccw(alto)):
        if _est(e):
            _fronte(k, e)
            continue
        for t0, t1 in k.porte_esterne("MIA0113000", e):
            k.porta(e, t0, t1, 0.0, telaio=TELAIO)
        k.pannello(ZOCCOLO, e, rett(0, e[4], 0.0, 0.9), 0.0, 0.04)
        k.pannello(PIETRA, e, rett(0, e[4], P1 + 0.3, P1 + 0.6), 0.0, 0.1)
        k.pannello(PIETRA, e, rett(0, e[4], 5.25, GRONDA), 0.0, 0.14)
        for t in (0.3, e[4] - 0.3):
            k.pannello(PIETRA, e, rett(t - 0.3, t + 0.3, 0.9, 5.25), 0.0, 0.08)
    k.falde(alto, GRONDA, pendenza=0.35, sporto=0.35, colore="kit_coppi", gronda="#D9D2C2")

    # il corpo basso a sud con la terrazza
    k.piano(terrazza, 0.0, H_TERRAZZA, lambda e, m: K.Stile(muro=INTONACO, finestre=None) if _est(e) else st,
            csip="MIA0113000")
    for e in E.edges(E.ring_ccw(terrazza)):
        if e[3][1] < -0.7:
            continue                                          # il lato contro il corpo alto
        k.pannello(ZOCCOLO, e, rett(0, e[4], 0.0, 0.9), 0.0, 0.04)
        k.pannello(PIETRA, e, rett(0, e[4], H_TERRAZZA - 0.3, H_TERRAZZA), 0.0, 0.1)
    k.tetto_piano(terrazza, H_TERRAZZA, parapetto=0.0, colore="#9A9C9C")
    _ringhiera(k, terrazza.buffer(-0.12, join_style=2), H_TERRAZZA)
    c = terrazza.centroid
    k.impianto(c.x + 0.6, c.y, 0.9, 1.2, H_TERRAZZA + 0.08, h=1.1)
    return k.fine()
