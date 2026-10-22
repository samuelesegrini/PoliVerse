"""PROTOTIPO — l'Edificio B2 (MIB0211), campus Bovisa di via Durando: il grande blocco quasi
quadrato (72 m per 70) delle aule, con la volta gialla sul lato nord e la facciata a nastri
gialli e vetro verso il prato ovale.

Fonti, oltre alle piante del Politecnico (seminterrato, terra, primo, secondo, terzo):
- la sagoma di OSM (w147256172), su cui il primo piano combacia a 2 cm; il terra e il terzo
  sono disegnati con un'altra origine e vanno spostati (`spostamenti` in bovisa.json);
- l'ortofoto di Google (z21, 2025): il tetto in tre campate est-ovest, quella sud larga quanto
  il terzo piano delle piante (le aule B2.3.x), i lucernari, le quattro torri scala che
  sporgono a nord e a sud;
- le foto di Urbanfile del febbraio 2026 ("cantiere campus Durando", foto 15 e 18): dal prato
  ovale, a ovest, la facciata è un curtain wall a montanti bianchi con fasce gialle ai solai e
  lo zoccolo giallo, la campata nord coperta da una volta ribassata col timpano giallo e tre
  finestre, il resto a tetto piano con la fascia alta di pannelli grigio chiaro; l'ingresso è
  un portico rientrato con i pilastri rossi, in cima a una gradinata larga. Dalla foto 18 (da
  sud-ovest, dietro il B1) la stessa facciata con la sigla B2;
- Mapillary (novembre 2018, 1497376033933110 e 1571403419715352, dall'angolo nord-ovest):
  il lato nord è un muro intonacato grigio, cieco.
Le altezze vengono dalla foto 15, con la gente sulla gradinata come metro: terra a +1,0
(sei gradini), piani da 3,8 m, tetto piano a 16,6 con 1 m di fascia sopra, volta da 13 a 19 m.
Il lato est non ha foto: è fatto come l'ovest, senza portico.
"""
import math
import sys
import pathlib
import numpy as np
from shapely.geometry import Polygon

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIB0211"
QUOTE = {"MIB021100S": -2.8, "MIB0211000": 1.0, "MIB0211001": 5.2, "MIB0211002": 9.0, "MIB0211003": 12.8}
SOLAI = (5.2, 9.0, 12.8)
TETTO = 16.6                 # sotto il tetto piano delle campate centrale e sud
CIMA = 17.6                  # la fascia di pannelli in cima
IMPOSTA, FRECCIA = 13.0, 5.8  # la volta della campata nord

# Il frame dell'edificio, dagli spigoli del primo piano: A a sud-ovest, t verso est lungo il
# lato sud, n verso nord.
A = np.array([1290.73, 284.09])
U = np.array([1357.48 - 1290.73, 258.34 - 284.09]); LU = float(np.linalg.norm(U)); U /= LU
N = np.array([1265.58 - 1290.73, 218.88 - 284.09]); LN = float(np.linalg.norm(N)); N /= LN
NORD = 44.0                  # dove comincia la campata nord, sotto la volta
PORTICO = (12.0, 30.0)       # l'ingresso sul lato ovest, lungo n
RIENTRO = 3.0

GIALLO = "#F2C200"
BIANCO = "#E6E8EA"
PANNELLI = "#C8CDD2"
INTONACO = "#9D9B96"
ROSSO = "#A8352B"
CEMENTO = "#B9B6B0"
ST = K.Stile(finestre="vetrata", telaio=BIANCO, vetro=K.VETRO, passo_montanti=1.5, architrave=99)


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def P(t, n):
    p = A + U * t + N * n
    return (float(p[0]), float(p[1]))


def rett_tn(t0, t1, n0, n1):
    return Polygon([P(t0, n0), P(t1, n0), P(t1, n1), P(t0, n1)])


def lato(e):
    """Il lato dell'edificio verso cui guarda e, nel frame dell'edificio: 'N', 'S', 'E', 'O'."""
    nx = float(np.dot(np.array(e[3]), U))
    ny = float(np.dot(np.array(e[3]), N))
    if abs(nx) > abs(ny):
        return "E" if nx > 0 else "O"
    return "N" if ny > 0 else "S"


def n_lungo(e, s):
    """La coordinata n del punto a distanza s lungo il lato e."""
    p = np.array(e[0]) + np.array(e[2]) * s
    return float(np.dot(p - A, N))


def s_di(e, n):
    """La distanza lungo il lato e del punto con coordinata n."""
    a = np.array(e[0])
    return (n - float(np.dot(a - A, N))) / float(np.dot(np.array(e[2]), N))


def facciata(k, e, z_top, salta=None):
    """Il curtain wall: zoccolo giallo, il vetro piano per piano fra le fasce gialle dei solai,
    la fascia di pannelli in cima. salta: un intervallo (s0, s1) senza vetro al terra."""
    L = e[4]
    k.pannello(GIALLO, e, K.rett(0, L, 0.0, QUOTE["MIB0211000"]), -0.1, 0.04)
    livelli = [QUOTE["MIB0211000"]] + [z for z in SOLAI if z < z_top] + [min(z_top, TETTO)]
    for z0, z1 in zip(livelli, livelli[1:]):
        g0, g1 = z0 + (0.6 if z0 > 1.5 else 0.0), z1 - 0.4
        if g1 - g0 < 0.5:
            continue
        pezzi = [(0.0, L)]
        if salta and z0 < 2:
            pezzi = [(0.0, salta[0]), (salta[1], L)]
        for s0, s1 in pezzi:
            if s1 - s0 > 0.5:
                k.vetrata(e, g0, g1, ST, t0=s0, t1=s1)
    for z in SOLAI:
        if z < z_top - 0.5:
            k.pannello(GIALLO, e, K.rett(0, L, z - 0.4, z + 0.6), -0.1, 0.06)
    # le lesene grigio chiaro, larghe, agli spigoli e fra le campate
    if lato(e) == "O" and z_top >= TETTO:
        for n in (PORTICO[0] - 2.0, PORTICO[1] + 2.0):
            sn = s_di(e, n)
            k.pannello(PANNELLI, e, K.rett(sn - 1.0, sn + 1.0, 0.0, z_top), 0.0, 0.1)
    for sn in (0.0, L):
        k.pannello(PANNELLI, e, K.rett(max(0.0, sn - 1.2), min(L, sn + 1.2), 0.0, z_top), 0.0, 0.1)
    if z_top >= TETTO:
        k.pannello(PANNELLI, e, K.rett(0, L, TETTO - 0.4, CIMA), -0.1, 0.06)
        k.pannello(BIANCO, e, K.rett(0, L, CIMA - 0.06, CIMA), 0.0, 0.12)


def timpano(k, e):
    """La testata della volta: il timpano giallo con tre finestre e il bordo bianco."""
    s0, s1 = sorted((s_di(e, NORD), s_di(e, LN)))
    s0, s1 = max(0.0, s0), min(e[4], s1)
    pts = []
    for i in range(25):
        s = s0 + (s1 - s0) * i / 24
        f = (n_lungo(e, s) - NORD) / (LN - NORD)
        pts.append((s, IMPOSTA + FRECCIA * 4 * f * (1 - f)))
    forma = Polygon([(s0, IMPOSTA - 0.4)] + pts + [(s1, IMPOSTA - 0.4)]).buffer(0)
    finestre = []
    for fc in (0.3, 0.5, 0.7):
        sc = s0 + (s1 - s0) * fc
        finestre.append(K.rett(sc - 1.1, sc + 1.1, IMPOSTA + 1.0, IMPOSTA + 3.2))
    k.pannello(GIALLO, e, forma.difference(K.unary_union(finestre)), -0.2, 0.05)
    for w in finestre:
        t0, z0, t1, z1 = w.bounds
        k.foro(e, t0, t1, z0, z1, K.Stile(telaio=BIANCO, vetro=K.VETRO, sguincio=0.1))
    bordo = Polygon(pts + [(p[0], p[1] - 0.25) for p in reversed(pts)]).buffer(0)
    k.pannello(BIANCO, e, bordo, 0.05, 0.15)


def portico(k, e, s0, s1):
    """L'ingresso ovest: le porte vetrate, il portico sui pilastri rossi, la gradinata."""
    z = QUOTE["MIB0211000"]
    k.vetrata(e, z, z + 3.2, ST.con(passo_montanti=1.2), t0=s0, t1=s1)
    for s in np.linspace(s0, s1, 6):
        k.pannello(ROSSO, e, K.rett(s - 0.3, s + 0.3, z, SOLAI[0] - 0.4), RIENTRO - 0.3, RIENTRO + 0.3)
    k.pannello(ROSSO, e, K.rett(s0 - 0.3, s1 + 0.3, SOLAI[0] - 0.7, SOLAI[0] - 0.4), 0.0, RIENTRO + 0.3)
    # il pavimento del portico e i sei gradini fino al prato
    k.pannello(CEMENTO, e, K.rett(s0, s1, 0.0, z), 0.0, RIENTRO)
    # sopra il portico il primo piano è chiuso da pannelli gialli, come nella foto 15
    k.pannello(GIALLO, e, K.rett(s0, s1, SOLAI[0] - 0.4, SOLAI[1] - 0.4), -0.1, 0.07)
    for i in range(6):
        h = z * (i + 1) / 7
        k.pannello(CEMENTO, e, K.rett(s0 - 0.5, s1 + 0.5, 0.0, h), RIENTRO, RIENTRO + 0.32 * (6 - i))


def guscio(b, E):
    k = K.Kit(E, CSIE)
    z0 = QUOTE["MIB0211000"]
    sud = rett_tn(0, LU, 0, NORD)
    nord = rett_tn(0, LU, NORD, LN)

    # i nuclei pieni: le campate sud e centrale fino al tetto piano, la nord fino all'imposta
    k.piano(sud, 0.0, TETTO, lambda e, c: None)
    k.piano(nord, 0.0, IMPOSTA, lambda e, c: None)

    for e in E.edges(E.ring_ccw(sud)):
        v = lato(e)
        if v == "N":
            # sopra la volta resta scoperto il muro grigio della campata centrale
            k.pannello(INTONACO, e, K.rett(0, e[4], IMPOSTA - 0.5, CIMA), -0.4, 0.04)
        elif v == "O":
            s0, s1 = sorted((s_di(e, PORTICO[0]), s_di(e, PORTICO[1])))
            facciata(k, e, TETTO, salta=(s0, s1))
            portico(k, e, s0, s1)
        else:
            facciata(k, e, TETTO)
    for e in E.edges(E.ring_ccw(nord)):
        v = lato(e)
        if v in ("O", "E"):
            facciata(k, e, IMPOSTA)
            timpano(k, e)
        elif v == "N":
            # il lato nord: intonaco grigio, cieco, con lo zoccolo
            k.muro(e, 0.0, IMPOSTA, INTONACO)
            k.pannello("#7E7C78", e, K.rett(0, e[4], 0.0, 0.6), 0.0, 0.08)
            k.pannello(BIANCO, e, K.rett(0, e[4], IMPOSTA - 0.15, IMPOSTA + 0.1), 0.0, 0.2)

    # la volta ribassata della campata nord
    k.volta(nord, IMPOSTA, FRECCIA)

    # le quattro torri scala che sporgono a nord e a sud, intonacate, fino al secondo piano
    for t0, t1 in ((17.0, 27.8), (43.7, 54.6)):
        for n0, n1 in ((-3.1, 0.0), (LN, LN + 3.0)):
            torre = rett_tn(t0, t1, n0, n1)
            k.piano(torre, 0.0, SOLAI[2] + 0.4, lambda e, c: None)
            for e in E.edges(E.ring_ccw(torre)):
                k.muro(e, 0.0, SOLAI[2] + 0.4, INTONACO, d=0.04)
                if abs(float(np.dot(np.array(e[3]), N))) > 0.9:
                    # la fessura vetrata della scala, su tutta l'altezza
                    m = e[4] / 2
                    k.vetrata(e, z0 + 0.5, SOLAI[2] - 0.2, ST, t0=m - 0.8, t1=m + 0.8)
            k.tetto_piano(torre, SOLAI[2] + 0.4, parapetto=0.5)

    # il tetto piano, i due lucernari lunghi della campata centrale, i torrini e gli impianti
    k.tetto_piano(sud, TETTO, parapetto=CIMA - TETTO, colore=K.GUAINA, muro=PANNELLI)
    for tc in (30.0, 38.0):
        c = P(tc, 34.0)
        k.impianto(c[0], c[1], 7.0, 2.4, TETTO, h=0.9, colore="#B4C2C9",
                   angolo=math.degrees(math.atan2(U[1], U[0])))
    for tc, nc in ((12.0, 14.0), (32.0, 8.0), (52.0, 16.0), (60.0, 30.0)):
        c = P(tc, nc)
        k.impianto(c[0], c[1], 2.6, 2.6, TETTO, h=0.5, colore="#C9C2A0",
                   angolo=math.degrees(math.atan2(U[1], U[0])))
    k.top = max(k.top, CIMA, IMPOSTA + FRECCIA)
    return k.fine()
