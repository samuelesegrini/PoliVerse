"""PROTOTIPO — l'Edificio 2A (MIA0114), la Sala Lettura: sta nel seminterrato sotto la terrazza
fra il 2 e il 4, senza aule.

Fonti, oltre alle piante del Politecnico (due interrati, seminterrato, terra): la sagoma di OSM;
la pianta del terra, che è la terrazza stessa (un locale grande quanto il tetto della Sala
Lettura, il passaggio fra il 2 e il 4, le scale in fondo e lungo il lato est, il chiosco a
nord); la `corte` della mappa (percorsi, pergole, tavoli); una foto della terrazza dall'alto
(Wikimedia Commons, "Solarium.jpg", gennaio 2013). Come nella foto:

- la terrazza pavimentata in lastre chiare, il vialetto scuro in mezzo e quelli ai lati;
- le quattro pergole in acciaio scuro, due per due, con le lamelle sopra; tavoli e panchine;
- i lampioni a globo bianco e la ringhiera nera lungo i bordi;
- a nord il chiosco basso col tetto in lamiera verde; a sud la pensilina bianca su pilastri
  sottili che attraversa la terrazza dal 2 al 4, poi le scale che scendono al giardino.
Il seminterrato esce dal suolo fino alla terrazza, con le finestre a nastro della Sala Lettura.
"""
import sys
import json
import pathlib
import trimesh
from shapely.geometry import box, Polygon, LineString
from shapely.ops import unary_union

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0114"
Z_T = 1.0                   # la terrazza, alla quota del terra delle piante
QUOTE = {"MIA011402I": -9.0, "MIA011401I": -6.0, "MIA011400S": -3.0, "MIA0114000": Z_T}
TETTO = Z_T + 3.4           # la pensilina

LASTRE = "#C7C6C0"
VIALETTO = "#7F807D"
ACCIAIO = "#3A3E42"
LAMELLE = "#6A6660"
BIANCO = "#ECEBE6"
LAMIERA = "#5E786A"
MURO = "#C9C4B8"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def corte():
    d = json.loads((pathlib.Path(__file__).resolve().parents[3] / "design/mappa/leonardo.json").read_text())
    return next(e for e in d["edifici"] if e["csie"] == CSIE).get("corte", {})


def vano(k, csip, *nomi):
    vs = [v for v in k.geo[csip]["vani"] if v["csiv"].endswith(nomi)]
    return unary_union([Polygon(r).buffer(0) for v in vs for r in v["forma"]])


def pergola(k, x, y, w, d, z):
    """Una pergola: quattro pilastri, il telaio e le lamelle di traverso."""
    h = 3.0
    for px, py in ((x + 0.15, y + 0.15), (x + w - 0.15, y + 0.15), (x + 0.15, y + d - 0.15), (x + w - 0.15, y + d - 0.15)):
        k.E.prisma(k.S, ACCIAIO, k.E.ring_ccw(box(px - 0.07, py - 0.07, px + 0.07, py + 0.07)), z, z + h)
    for px in (x + 0.08, x + w - 0.08):
        k.E.prisma(k.S, ACCIAIO, k.E.ring_ccw(box(px - 0.08, y, px + 0.08, y + d)), z + h - 0.25, z + h)
    for py in (y + 0.08, y + d - 0.08):
        k.E.prisma(k.S, ACCIAIO, k.E.ring_ccw(box(x, py - 0.08, x + w, py + 0.08)), z + h - 0.25, z + h)
    n = 9
    for i in range(n):
        yy = y + 0.35 + i * (d - 0.7) / (n - 1)
        k.E.trave(k.S, LAMELLE, (x + 0.1, yy - 0.15, z + h + 0.05), (x + w - 0.1, yy + 0.15, z + h + 0.05), 0.14)


def tavolo(k, x, y, z):
    k.E.prisma(k.S, LAMELLE, k.E.ring_ccw(box(x - 0.9, y - 0.4, x + 0.9, y + 0.4)), z + 0.7, z + 0.76)
    for dy in (-0.7, 0.7):
        k.E.prisma(k.S, LAMELLE, k.E.ring_ccw(box(x - 0.9, y + dy - 0.15, x + 0.9, y + dy + 0.15)), z + 0.42, z + 0.46)
    for dx in (-0.7, 0.7):
        k.E.prisma(k.S, ACCIAIO, k.E.ring_ccw(box(x + dx - 0.04, y - 0.8, x + dx + 0.04, y + 0.8)), z, z + 0.7)


def panchina(k, x, y, z):
    k.E.prisma(k.S, LAMELLE, k.E.ring_ccw(box(x - 0.25, y - 0.9, x + 0.25, y + 0.9)), z + 0.4, z + 0.46)
    k.E.prisma(k.S, ACCIAIO, k.E.ring_ccw(box(x - 0.2, y - 0.8, x + 0.2, y + 0.8)), z, z + 0.4)


def lampione(k, x, y, z):
    k.S.solid(ACCIAIO, trimesh.creation.cylinder(radius=0.06, height=3.2, sections=8).apply_translation([x, y, z + 1.6]))
    k.S.solid("#F4F3EE", trimesh.creation.icosphere(subdivisions=2, radius=0.25).apply_translation([x, y, z + 3.4]))


def scala(k, rett_, z0, z1, verso_y=1):
    """Una scala dritta lungo y che scende da z1 a z0 nel verso di verso_y."""
    x0, y0, x1, y1 = rett_
    n = max(2, round((z1 - z0) / 0.16))
    p = (y1 - y0) / n
    for i in range(n):
        ya = y0 + i * p if verso_y > 0 else y1 - (i + 1) * p
        k.E.prisma(k.S, "#BDBBB5", k.E.ring_ccw(box(x0, ya, x1, ya + p + 0.01)), z0, z1 - i * (z1 - z0) / n)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    c = corte()
    terrazza = k.squadra(k.contorno("MIA0114000", chiudi=0.6))
    scale_s = vano(k, "MIA0114000", "004b").envelope
    scale_e = vano(k, "MIA0114000", "005").envelope
    chiosco = k.squadra(vano(k, "MIA0114000", "001a", "001b", "001d", "001e").envelope)
    piano_t = terrazza.difference(scale_s.buffer(0.05, join_style=2)).difference(scale_e.buffer(0.05, join_style=2))
    piano_t = max(k.pezzi(piano_t), key=lambda g: g.area)

    # il seminterrato fuori terra, con le finestre a nastro della Sala Lettura
    zoccolo = K.Stile(muro=MURO, finestre="nastro", davanzale=0.2, architrave=0.85, telaio=ACCIAIO,
                      vetro="#3A4650", passo_montanti=1.4)
    k.piano(piano_t, 0.0, Z_T, lambda e, m: zoccolo if e[4] > 4 else K.Stile(muro=MURO, finestre=None))

    # la terrazza: lastre chiare, i vialetti scuri, la ringhiera nera
    for p in k.pezzi(piano_t):
        E.prisma(k.S, LASTRE, E.ring_ccw(p), Z_T - 0.1, Z_T + 0.04)
    viali = unary_union([LineString(v).buffer(1.1 if i < 2 else 0.6, cap_style=2, join_style=2)
                         for i, v in enumerate(c.get("percorsi", []))]).intersection(piano_t.buffer(-0.3))
    for p in k.pezzi(viali, 0.3):
        E.prisma(k.S, VIALETTO, E.ring_ccw(p), Z_T + 0.04, Z_T + 0.06)
    for e in E.edges(E.ring_ccw(piano_t)):
        if K.verso(e) in ("E", "O") and e[4] > 3:
            k.pannello(ACCIAIO, e, K.rett(0.0, e[4], Z_T + 1.05, Z_T + 1.1), -0.05, 0.0)
            n = int(e[4] / 0.15)
            for i in range(1, n):
                t = i * e[4] / n
                k.pannello(ACCIAIO, e, K.rett(t - 0.012, t + 0.012, Z_T, Z_T + 1.05), -0.04, -0.016)
            for i in range(int(e[4] / 8) + 1):
                t = min(e[4] - 0.5, 0.5 + i * 8)
                x, y = e[0][0] + e[2][0] * t - e[3][0] * 0.6, e[0][1] + e[2][1] * t - e[3][1] * 0.6
                lampione(k, x, y, Z_T)

    # le pergole, i tavoli, le panchine
    for x, y, w, d in c.get("pergole", []):
        pergola(k, x, y, w, d, Z_T)
    for x, y in ((-3.5, 116.5), (2.5, 116.5), (-3.5, 123.5), (2.5, 123.5), (-2.2, 128.9), (2.8, 128.8)):
        tavolo(k, x, y, Z_T)
    for x, y in ((-6.2, 120.6), (-6.2, 126.0), (6.2, 119.4), (6.3, 122.0), (6.4, 136.4), (-5.0, 139.1),
                 (-1.9, 155.4), (4.7, 154.9), (3.3, 163.5)):
        panchina(k, x, y, Z_T)

    # il chiosco a nord, col tetto in lamiera verde
    corpo = K.Stile(muro=MURO, davanzale=0.9, architrave=2.3, telaio=ACCIAIO, sguincio=0.1,
                    finestre=("passo", 1.8, 1.0))
    k.piano(chiosco, Z_T, Z_T + 2.8, corpo)
    k.falde(chiosco, Z_T + 2.8, pendenza=0.18, sporto=0.4, colore=LAMIERA, gronda=BIANCO, padiglione=False)

    # la pensilina bianca dal 2 al 4 sopra il passaggio, su pilastri sottili
    px0, py0, px1, py1 = vano(k, "MIA0114000", "003").bounds
    px0, px1 = max(px0, -10.3), min(px1, 11.6)
    E.prisma(k.S, BIANCO, E.ring_ccw(box(px0, py0 - 1.2, px1, py1 + 1.2)), TETTO - 0.35, TETTO)
    x = px0 + 1.5
    while x < px1 - 1.0:
        for y in (py0 - 0.9, py1 + 0.9):
            k.S.solid("#DADAD5", trimesh.creation.cylinder(radius=0.11, height=TETTO - 0.35 - Z_T, sections=10)
                      .apply_translation([x, y, (TETTO - 0.35 + Z_T) / 2]))
        x += 4.2

    # le scale: in fondo verso il giardino, lungo il lato est
    sx0, sy0, sx1, sy1 = scale_s.bounds
    scala(k, (sx0, sy0, sx1, sy1), 0.0, Z_T, verso_y=1)
    ex0, ey0, ex1, ey1 = scale_e.bounds
    scala(k, (ex0, ey0 + (ey1 - ey0) * 0.55, ex1, ey1), 0.0, Z_T, verso_y=1)
    E.prisma(k.S, LASTRE, E.ring_ccw(box(ex0, ey0, ex1, ey0 + (ey1 - ey0) * 0.55)), Z_T - 0.1, Z_T + 0.04)
    k.top = max(k.top, TETTO)
    return k.fine()
