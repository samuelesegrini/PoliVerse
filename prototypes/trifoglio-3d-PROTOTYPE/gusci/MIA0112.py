"""PROTOTIPO — l'Edificio 4A "Gaudenzio Fantoli" (MIA0112): la palazzina lunga di due piani fra
il 4 e l'8, con un'aula al primo, coperta da una grande volta.

Fonti, oltre alle piante del Politecnico (seminterrato, terra, primo):
- la sagoma di OSM e le piante, che combaciano;
- l'ortofoto (Esri World Imagery, z19): la volta ribassata lungo l'asse nord-sud va dalla
  testata su via Ponzio fino a circa y 136; è coperta di pannelli fotovoltaici scuri in sei
  campi, fra una fascia chiara di colmo, due fasce chiare sulle imposte e tre costoloni
  trasversali (alle due testate e a metà, y 116). La testata sud, più stretta (fino a x 77,6),
  ha una volta sua più piccola, chiara con due campi scuri; davanti, la pensilina;
- la foto Urbanfile della piazza della Nave (giugno 2021, "Campus Leonardo"): la testata nord
  con la lunetta della volta sopra il cornicione scuro, le finestre del primo in alto;
- le panoramiche Mapillary del cortile fra l'8 e il 6 (ottobre 2024): la testata sud in
  intonaco crema, il terra alto con la fascia marcapiano e le finestre ad arco, il primo con
  finestre rettangolari dai telai chiari, il cornicione sporgente, la lunetta crema della volta
  della testata, larga quanto la testata, la pensilina su pilastri sottili con la fascia scura.

Il terra alto 5,6 m (finestre e sopra le finestrelle ad arco), il primo 7 m con le finestre
alte; il cornicione a 12,6 m, dove imposta la volta, che sale di 3,6 m (la testata sud 2,4 m).
"""
import sys
import math
import pathlib
import numpy as np
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0112"
H0 = 5.6
TETTO = 12.6
QUOTE = {"MIA011200S": -3.4, "MIA0112000": 0.0, "MIA0112001": H0}

INTONACO = "#EAE3D0"
FASCE = "#D3C7AB"            # il marcapiano
CORNICIONE = "#B4AEA2"
TELAIO = "#EFEDE8"
PANNELLI = "#2F3A47"
CHIARO = "#E6E4DE"           # le fasce chiare della volta
LUNETTA = "#E8DFC9"

VOLTA_Y = (92.0, 136.0)      # dove sta la volta (il resto, a sud, ha il tetto piano)
COSTOLONI = (92.6, 116.3, 135.4)
FRECCIA = 3.6
VOLTA_SUD = (63.8, 77.6)     # la testata sud, più stretta, ha una volta sua
FRECCIA_SUD = 2.4
CAMPI_SUD = ((67.4, 71.1), (73.5, 75.2))
BORDO = 0.9                  # le fasce piane lungo le imposte


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def _arco(x0, x1, z, f):
    """z(x) di un arco ribassato (circolare) da x0 a x1 che sale di f."""
    xc, hw = (x0 + x1) / 2, (x1 - x0) / 2
    R = (hw * hw + f * f) / (2 * f)
    zc = z + f - R
    return lambda x: zc + math.sqrt(max(R * R - (x - xc) ** 2, 0.0)), xc, zc


def _volta(k, x0, x1, y0, y1, z, f, colore, da=None, a=None, alza=0.0, n=24):
    """La superficie della volta (asse lungo y) fra x da..a, sollevata di alza."""
    zx, xc, zc = _arco(x0, x1, z, f)
    da, a = x0 if da is None else da, x1 if a is None else a
    xs = np.linspace(da, a, max(2, int(n * (a - da) / (x1 - x0)) + 1))
    for xa, xb in zip(xs, xs[1:]):
        za, zb = zx(xa) + alza, zx(xb) + alza
        xm = (xa + xb) / 2
        q = [(xa, y0, za), (xb, y0, zb), (xb, y1, zb), (xa, y1, za)]
        k.S.quad(colore, q, (xm - xc, 0.0, zx(xm) - zc), [(p[0], p[1]) for p in q])


def _lunetta(k, x0, x1, y, z, f, verso, colore, n=24):
    zx, _, _ = _arco(x0, x1, z, f)
    xs = np.linspace(x0, x1, n + 1)
    for xa, xb in zip(xs, xs[1:]):
        k.S.quad(colore, [(xa, y, z), (xb, y, z), (xb, y, zx(xb)), (xa, y, zx(xa))], (0.0, verso, 0.0))


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=INTONACO, davanzale=1.0, architrave=3.6, telaio=TELAIO, sguincio=0.18, reach=1.5,
                 cornice="#EAE2CE", ripiego=(3.4, 1.3, 8.0))
    corpo = k.squadra(k.contorno("MIA0112001", chiudi=0.6))
    x0, y0, x1, y1 = corpo.bounds
    zoccolo = st.con(muro="#CFC4AA", finestre=None)
    k.piano(corpo, -0.2, 0.5, zoccolo)
    # il terra, alto, con due ordini di finestre: quelle della pianta e sopra le finestrelle
    # ad arco (qui rettangolari)
    k.piano(corpo, 0.5, 3.6, st.con(davanzale=0.5, architrave=2.7), csip="MIA0112000", porte=True)
    k.piano(corpo, 3.6, H0, st.con(davanzale=0.5, architrave=1.5), csip="MIA0112000")
    k.piano(corpo, H0, TETTO, st.con(davanzale=3.0, architrave=5.0, marcapiano=(0.4, 0.18, FASCE)),
            csip="MIA0112001")
    # il cornicione sporgente, con l'ombra sotto
    for e in E.edges(E.ring_ccw(corpo)):
        k.pannello(CORNICIONE, e, K.rett(-0.45, e[4] + 0.45, TETTO - 0.45, TETTO), 0.0, 0.5)
        k.pannello("#8F8B82", e, K.rett(-0.45, e[4] + 0.45, TETTO - 0.55, TETTO - 0.45), 0.0, 0.42)

    # il tetto piano fra le volte (l'angolo smussato a sud-est), sotto le volte
    k.tetto_piano(corpo, TETTO, parapetto=0.0)

    # la volta più piccola della testata sud, chiara con due campi scuri
    sa, sb = VOLTA_SUD[0] + 0.4, VOLTA_SUD[1] - 0.4
    _volta(k, sa, sb, VOLTA_Y[1] + 1.2, y1 - 1.0, TETTO, FRECCIA_SUD, CHIARO)
    for da, a_ in CAMPI_SUD:
        _volta(k, sa, sb, VOLTA_Y[1] + 2.0, y1 - 2.6, TETTO, FRECCIA_SUD, PANNELLI, da, a_, alza=0.04)
    _lunetta(k, sa, sb, VOLTA_Y[1] + 1.2, TETTO, FRECCIA_SUD, -1.0, LUNETTA)
    _lunetta(k, sa, sb, y1 - 1.0, TETTO, FRECCIA_SUD, 1.0, LUNETTA)

    # la volta: pannelli scuri, colmo e imposte chiari, tre costoloni
    va, vb = x0 + 0.3, x1 - 0.3
    ya, yb = VOLTA_Y
    _volta(k, va, vb, ya, yb, TETTO, FRECCIA, PANNELLI)
    xc = (va + vb) / 2
    _volta(k, va, vb, ya, yb, TETTO, FRECCIA, CHIARO, xc - 0.75, xc + 0.75, alza=0.04)
    _volta(k, va, vb, ya, yb, TETTO, FRECCIA, CHIARO, va, va + BORDO, alza=0.04)
    _volta(k, va, vb, ya, yb, TETTO, FRECCIA, CHIARO, vb - BORDO, vb, alza=0.04)
    for yc in COSTOLONI:
        _volta(k, va, vb, max(ya, yc - 0.6), min(yb, yc + 0.6), TETTO, FRECCIA, CHIARO, alza=0.07)
    _lunetta(k, va, vb, ya, TETTO, FRECCIA, -1.0, LUNETTA)
    _lunetta(k, va, vb, yb, TETTO, FRECCIA, 1.0, LUNETTA)
    k.top = max(k.top, TETTO + FRECCIA + 0.1)

    # la pensilina delle biciclette davanti alla testata sud
    py0, py1, pz = y1, y1 + 3.4, 3.1
    k.S.solid("#E9E8E3", E.box_z(72.4, (py0 + py1) / 2, 17.2, py1 - py0, pz, pz + 0.12))
    k.S.solid("#4A4D51", E.box_z(72.4, py1 - 0.05, 17.2, 0.12, pz - 0.35, pz + 0.12))
    for x in np.linspace(64.3, 80.5, 6):
        k.S.solid("#D8D6CF", E.box_z(x, py1 - 0.3, 0.6, 0.6, 0.0, 0.6))
        k.S.solid("#7C7F82", E.box_z(x, py1 - 0.3, 0.14, 0.14, 0.6, pz))
    return k.fine()
