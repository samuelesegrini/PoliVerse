"""PROTOTIPO — l'Edificio 32.1 (MIA0601), via Colombo 40: la palazzina del complesso 32 sul filo
di via Colombo, con due aule.

Fonti, oltre alle piante del Politecnico (seminterrato, terra, dal primo al terzo, sottotetto):
- le panoramiche di Mapillary su via Colombo (novembre 2024 e giugno 2025, per esempio
  1238320334310203 sotto la facciata e 1319190056167457 da sud, oltre il muro di cinta): una
  palazzina degli anni Trenta color crema. Il piano terra è rivestito di lastre di pietra chiara
  a corsi orizzontali, con le finestre grandi e le inferriate grigie e, sotto, le bocche di
  lupo del seminterrato; sopra, tre piani a intonaco con le finestre incorniciate di pietra,
  una fascia marcapiano sopra il terra e il cornicione in cima. Sul tetto piano della parte
  sud spunta il torrino della scala;
  A sud della palazzina il complesso è chiuso su via Colombo da un muro di cinta di circa 3 m;
- la sagoma di OSM (w248727391): una L, il corpo lungo da nord a sud e l'ala corta a est in fondo;
- l'ortofoto (Esri World Imagery; qui combacia con OSM): il tetto a padiglione in coppi sul corpo
  nord, attaccato alla palazzina accanto (il muro nord è cieco), e la parte sud col tetto piano
  grigio e gli impianti;
- le piante: quattro piani pieni sulla L, il sottotetto sotto le falde a nord, la scala che sale
  fino al tetto nell'angolo sud-est del corpo lungo; le finestre di ogni piano.
"""
import sys
import pathlib
import numpy as np
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0601"
H = 3.6
RIALZO = 1.2                                  # il terra rialzato sopra il marciapiede
H_TERRA = 4.4                                 # il terra, con le finestre alte quasi 3 m
PIANI = [f"MIA060100{i}" for i in range(4)]
QUOTE = {"MIA060100S": RIALZO - 3.4, "MIA0601000": RIALZO,
         **{c: round(RIALZO + H_TERRA + (i - 1) * H, 2) for i, c in enumerate(PIANI) if i},
         "MIA0601004": round(RIALZO + H_TERRA + 3 * H, 2)}
GRONDA = QUOTE["MIA0601004"]
FALDE = box(-98.5, 850.0, -84.0, 869.5)       # il corpo nord col tetto in coppi
ALA = box(-84.2, 868.5, -70.0, 885.0)          # l'ala est, un piano più bassa, con la loggia in cima
LOGGIA = 2.2                                  # quanto il terzo piano dell'ala arretra dal fronte sud
TORRINO = box(-89.6, 875.0, -84.4, 881.0)     # il torrino vetrato sul tetto (ortofoto)

INTONACO = "#EEE0C4"
PIETRA = "#DDD2BC"
GIUNTI = "#C4B79C"
CORNICE = "#F3EBDA"
TELAIO = "#ECEAE3"
INFERRIATA = "#8D918D"
MURO_COLOMBO = (-98.6, 883.6, 926.0)         # x del filo, y da nord a sud
LARGA, LARGA_TERRA = 1.3, 2.1                 # le finestre più larghe, sopra e al terra
VETRO = "#74828D"                             # i vetri chiari, con le tende bianche dietro
NORD = 851.5                                  # sotto questa y il lato è contro la palazzina accanto


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return GRONDA


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def cieco(e):
    """Il muro nord, contro la palazzina accanto: niente finestre."""
    return K.verso(e) == "N" and K.mid(e)[1] < NORD


def finestre(k, csip, e, st, larga):
    """Le finestre della pianta su questo lato, strette a una larghezza massima e centrate:
    nelle foto sono più strette dei vani che le piante disegnano."""
    out = []
    for t0, t1 in k.finestre_pianta(csip, e, st.reach, st.minima):
        if t1 - t0 > larga:
            tm = (t0 + t1) / 2
            t0, t1 = tm - larga / 2, tm + larga / 2
        out.append((t0, t1))
    return out


def per_lato(k, st, csip, larga):
    def f(e, m):
        if cieco(e):
            return st.con(finestre=None, marcapiano=None)
        iv = finestre(k, csip, e, st, larga)
        return st.con(finestre=iv) if iv else st
    return f


def rivestimento(k, corpo, z0, z1, st, csip, passo=0.6):
    """I giunti orizzontali delle lastre di pietra del piano terra, lato per lato, interrotti
    dalle finestre."""
    for e in k.E.edges(k.E.ring_ccw(corpo)):
        a, c, u, n, L, _ = e
        if cieco(e):
            continue
        buchi = finestre(k, csip, e, st, LARGA_TERRA)
        P = lambda t, zz: (a[0] + u[0] * t + n[0] * 0.07, a[1] + u[1] * t + n[1] * 0.07, zz)
        z = z0 + passo
        while z < z1 - 0.1:
            tratti, t = [], 0.0
            if st.davanzale - 0.05 < z < st.architrave + 0.05:
                for t0, t1 in buchi:
                    tratti.append((t, t0 - 0.05))
                    t = t1 + 0.05
            tratti.append((t, L))
            for t0, t1 in tratti:
                if t1 - t0 > 0.1:
                    k.E.trave(k.S, GIUNTI, P(t0, z), P(t1, z), 0.03)
            z += passo


def inferriate(k, corpo, csip, z0, st):
    """Le inferriate davanti alle finestre del terra: barre verticali e due traversi."""
    for e in k.E.edges(k.E.ring_ccw(corpo)):
        a, c, u, n, L, _ = e
        if cieco(e):
            continue
        zf0, zf1 = z0 + st.davanzale, z0 + st.architrave
        for t0, t1 in finestre(k, csip, e, st, LARGA_TERRA):
            P = lambda t, z: (a[0] + u[0] * t + n[0] * 0.04, a[1] + u[1] * t + n[1] * 0.04, z)
            k_ = max(3, round((t1 - t0) / 0.22))
            for i in range(1, k_):
                t = t0 + (t1 - t0) * i / k_
                k.E.trave(k.S, INFERRIATA, P(t, zf0), P(t, zf1), 0.03)
            for z in (zf0 + 0.35, (zf0 + zf1) / 2, zf1 - 0.35):
                k.E.trave(k.S, INFERRIATA, P(t0, z), P(t1, z), 0.035)


def bocche_di_lupo(k, corpo, csip, st):
    """Le finestrelle del seminterrato nello zoccolo, sotto le finestre del terra."""
    for e in k.E.edges(k.E.ring_ccw(corpo)):
        a, c, u, n, L, _ = e
        if cieco(e):
            continue
        for t0, t1 in finestre(k, csip, e, st, LARGA_TERRA):
            tm, w = (t0 + t1) / 2, min(1.2, t1 - t0)
            k.pannello("#3A3D40", e, K.rett(tm - w / 2, tm + w / 2, 0.12, 0.58), -0.02, 0.0)
            k.pannello(INFERRIATA, e, K.rett(tm - w / 2 - 0.05, tm + w / 2 + 0.05, 0.08, 0.62).difference(
                K.rett(tm - w / 2, tm + w / 2, 0.12, 0.58)), 0.0, 0.04)


def cornicione(k, poly, z0, z1, sporto):
    anello = poly.buffer(sporto, join_style=2).difference(poly.buffer(-0.05, join_style=2))
    for r in k.pezzi(anello, 0.05):
        k.E.prisma(k.S, CORNICE, k.E.ring_ccw(r), z0, z1)


def ringhiera(k, terrazza, ala, z, h=1.0, passo=1.4):
    """La ringhiera sul bordo esterno della terrazza (i lati che stanno sul filo dell'ala)."""
    bordo = terrazza.exterior.intersection(ala.exterior.buffer(0.05))
    for g in getattr(bordo, "geoms", [bordo]):
        if g.geom_type != "LineString":
            continue
        pts = [np.array(p) for p in g.coords]
        for a, c in zip(pts, pts[1:]):
            d = c - a
            L = float(np.linalg.norm(d))
            if L < 0.3:
                continue
            a2, c2 = a + d / L * 0.0, c
            n = np.array([d[1], -d[0]]) / L
            # dentro di 15 cm
            ctr = np.array(terrazza.centroid.coords[0])
            if np.dot(ctr - a, n) < 0:
                n = -n
            a2, c2 = a + n * 0.15, c + n * 0.15
            for zz in (z + h, z + 0.12):
                k.E.trave(k.S, TELAIO, (*a2, zz), (*c2, zz), 0.05)
            for i in range(int(L // 0.12) + 1):
                p = a2 + (c2 - a2) * min(1.0, i * 0.12 / L)
                k.E.trave(k.S, TELAIO, (*p, z + 0.12), (*p, z + h), 0.02 if i % int(passo / 0.12) else 0.06)
    k.top = max(k.top, z + h)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    sopra = K.Stile(muro=INTONACO, davanzale=0.9, architrave=2.75, telaio=TELAIO, vetro=VETRO, sguincio=0.2, reach=1.5,
                    cornice=CORNICE, ripiego=(3.0, 1.2, 16.0))
    # il terra si disegna dal marciapiede: lo zoccolo col seminterrato, poi le finestre grandi
    terra = sopra.con(muro=PIETRA, davanzale=RIALZO + 0.8, architrave=RIALZO + 3.7, telaio="#7F837F", cornice=None,
                      marcapiano=(1.4, 0.05, "#CFC4AC"))
    # i quattro piani hanno la stessa L, a meno delle scale e dei terrazzini: un corpo solo,
    # quello del secondo piano, squadrato
    corpo = max(k.pezzi(k.squadra(k.contorno("MIA0601002", chiudi=1.0), passo=0.5)), key=lambda g: g.area)
    z1 = QUOTE[PIANI[1]]
    k.piano(corpo, 0.0, z1, per_lato(k, terra, PIANI[0], LARGA_TERRA), csip=PIANI[0])
    rivestimento(k, corpo, 0.7, z1, terra, PIANI[0])
    inferriate(k, corpo, PIANI[0], 0.0, terra)
    bocche_di_lupo(k, corpo, PIANI[0], terra)
    ala = corpo.intersection(ALA)
    lungo = corpo.difference(ALA)
    for i, csip in enumerate(PIANI[1:], 1):
        st = sopra.con(marcapiano=(0.3, 0.12, CORNICE)) if i == 1 else sopra
        z0 = QUOTE[csip]
        k.piano(lungo if i == 3 else corpo, z0, z0 + H, per_lato(k, st, csip, LARGA), csip=csip)
    # l'ala est: il terzo piano arretra dal fronte sud e lascia una terrazza con la ringhiera;
    # sopra il secondo piano il cornicione, il terzo è una loggia vetrata
    z3 = QUOTE[PIANI[3]]
    ax0, ay0, ax1, ay1 = ala.bounds
    arretrata = ala.intersection(box(ax0 - 1, ay0 - 1, ax1 + 1, ay1 - LOGGIA))
    terrazza = ala.difference(arretrata)
    k.piano(arretrata, z3, z3 + H, sopra.con(finestre="nastro", davanzale=0.5, architrave=2.6,
                                              passo_montanti=1.0, cornice=None))
    cornicione(k, ala, z3 - 0.4, z3, 0.35)
    for q in k.pezzi(terrazza, 1.0):
        k.tetto_piano(q, z3, parapetto=0.0, colore="#B9B4AA")
    ringhiera(k, terrazza, ala, z3)
    cornicione(k, lungo, GRONDA - 0.45, GRONDA, 0.45)
    cornicione(k, arretrata, GRONDA - 0.3, GRONDA, 0.3)

    nord = lungo.intersection(FALDE)
    k.falde(nord.minimum_rotated_rectangle, GRONDA, pendenza=0.45, sporto=0.5, colore="kit_coppi", gronda=CORNICE)
    sud = lungo.difference(FALDE)
    for q in k.pezzi(sud, 10):
        k.tetto_piano(q, GRONDA, parapetto=0.8, muro=INTONACO, copertina=CORNICE)
    k.tetto_piano(arretrata, GRONDA, parapetto=0.5, muro=INTONACO, copertina=CORNICE)
    # il torrino della scala, con una fascia di finestre tutto intorno
    torrino = K.Stile(muro=INTONACO, finestre="nastro", davanzale=0.9, architrave=2.3,
                      telaio=TELAIO, vetro=K.VETRO, cornice=None, passo_montanti=0.9)
    k.piano(TORRINO, GRONDA, GRONDA + 2.9, torrino)
    k.tetto_piano(TORRINO, GRONDA + 2.9, parapetto=0.25, muro=INTONACO, copertina=CORNICE)
    x0, y0, x1, y1 = sud.bounds
    k.impianto(x0 + 4.5, y0 + 5, 3.0, 2.2, GRONDA + 0.1, h=1.5)
    k.impianto(-79.5, 875.5, 2.2, 1.8, GRONDA + 0.1, h=1.1)
    # il muro di cinta su via Colombo, dallo spigolo sud fino al cancello del cantiere
    m = box(MURO_COLOMBO[0], MURO_COLOMBO[1], MURO_COLOMBO[0] + 0.35, MURO_COLOMBO[2])
    k.E.prisma(k.S, "#B6B1A7", k.E.ring_ccw(m), 0.0, 3.0)
    k.E.prisma(k.S, "#C9C5BC", k.E.ring_ccw(m.buffer(0.05, join_style=2)), 3.0, 3.08)
    return k.fine()
