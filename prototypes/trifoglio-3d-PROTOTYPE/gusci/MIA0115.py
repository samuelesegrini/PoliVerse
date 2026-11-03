"""PROTOTIPO — l'Edificio 3A (MIA0115), la nuova Palazzina Lerici (2022) fra il 3, il 5 e via
Celoria, senza aule.

Fonti, oltre alle piante del Politecnico (seminterrato, terra, primo): la sagoma di OSM, su cui
sta il seminterrato; le foto dell'inaugurazione (alumni.polimi.it, ottobre 2022) e del cantiere
finito (Urbanfile, luglio 2022). Come nelle foto:

- il primo è una scatola che sporge sul terra verso via Celoria e verso est: i lati lunghi
  tutti vetrati a montanti neri, quello su via Celoria un giardino verticale incorniciato di
  nero con le finestre a nastro e le mensole bianche, sotto l'intradosso bianco con la fascia
  nera; sul tetto una ringhiera nera leggera e i pannelli fotovoltaici;
- il terra vetrato a telai neri sotto la scatola, intonaco color sabbia con la fascia scura
  sul lato del 3 e verso nord; davanti, la piazzetta sopra il seminterrato con gli oblò;
- i tre livelli di tetto verde a scalini verso nord, con i nove alberi, le ringhiere nere e la
  scala che sale dal giardino sul tetto del terra;
- il lato est del seminterrato è una vetrata scura lungo il vicolo verso il 5, con il parapetto
  in vetro sopra;
- su via Celoria la vecchia cancellata coi pilastri in pietra, la scala d'ingresso fra i
  pilastri e il cancello scorrevole grigio.
Piani da 3,6 m, il seminterrato che esce di un metro.
"""
import sys
import math
import pathlib
import numpy as np
import trimesh
from shapely.geometry import box, Point

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0115"
H = 3.6
Z_T = 1.0
Z_1 = Z_T + H
QUOTE = {"MIA011500S": -2.6, "MIA0115000": Z_T, "MIA0115001": Z_1}
TETTO = Z_1 + H

SABBIA = "#D3C9B7"          # l'intonaco colorato
SCURO = "#2E3134"           # telai, fasce, ringhiere
VETRO = "#6E8AA5"
INTRADOSSO = "#EEEDE8"
PIETRA = "#CDBFA3"          # i pilastri della cancellata
LASTRE = "#C4C2BC"          # la piazzetta
VERDI = ("#3E5A2C", "#4A6833", "#355026", "#58763B", "#6B8A4A", "#44612F")
Y_CELORIA = 326.2           # il filo della cancellata


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def albero(k, x, y, z, r=2.0, h=6.5):
    """Un albero piantato su un tetto verde a quota z."""
    k.S.solid(K.TRONCO, trimesh.creation.cylinder(radius=0.13, height=h * 0.55, sections=6)
              .apply_translation([x, y, z + h * 0.27]))
    k.S.solid(K.CHIOMA, trimesh.creation.icosphere(subdivisions=1, radius=r)
              .apply_translation([x, y, z + h * 0.55 + r * 0.7]))
    k.top = max(k.top, z + h * 0.55 + r * 1.7)


def ringhiera(k, e, z, h=1.1, t0=0.0, t1=None, passo=1.5, vetro=False):
    """Un parapetto nero su un lato: corrente, montanti e (vetro=True) le lastre in mezzo."""
    t1 = e[4] if t1 is None else t1
    if t1 - t0 < 0.3:
        return
    P = k.pannello
    P(SCURO, e, K.rett(t0, t1, z + h - 0.05, z + h), -0.05, 0.03)
    n = max(1, round((t1 - t0) / passo))
    for i in range(n + 1):
        t = t0 + (t1 - t0) * i / n
        P(SCURO, e, K.rett(max(t0, t - 0.03), min(t1, t + 0.03), z, z + h), -0.05, 0.03)
    if vetro:
        P("#9FB1BC", e, K.rett(t0, t1, z + 0.05, z + h - 0.05), -0.02, 0.0)
    else:
        P(SCURO, e, K.rett(t0, t1, z + 0.1, z + 0.14), -0.04, 0.02)


def giardino_verticale(k, e, z0, z1):
    """Il lato su via Celoria: pannelli di verde a tessere di più toni, la cornice nera,
    due file di finestre a nastro con la mensola bianca sopra."""
    L = e[4]
    rng = np.random.default_rng(3)
    finestre = [(0.9, 3.4, z0 + 1.0, z0 + 1.55), (5.0, 7.6, z0 + 1.0, z0 + 1.55),
                (2.6, 5.0, z0 + 2.25, z0 + 2.8), (7.2, 9.8, z0 + 2.25, z0 + 2.8)]
    finestre = [(a, min(b, L - 0.5), c, d) for a, b, c, d in finestre if a < L - 1.2]
    passo = 0.35
    nt, nz = int(L / passo) + 1, int((z1 - z0) / passo) + 1
    buchi = [K.rett(a - 0.05, b + 0.05, c - 0.05, d + 0.05) for a, b, c, d in finestre]
    for i in range(nt):
        for j in range(nz):
            t, z = i * passo, z0 + j * passo
            q = K.rett(t, min(L, t + passo), z, min(z1, z + passo))
            for b in buchi:
                q = q.difference(b)
            if q.area > 0.01:
                k.pannello(VERDI[int(rng.integers(len(VERDI)))], e, q, 0.0, 0.16 + 0.1 * rng.random())
    k.muro(e, z0, z1, "#2F3A2A", [(a, b, c, d) for a, b, c, d in finestre], d=0.0)
    for a, b, c, d in finestre:
        k.pannello(VETRO, e, K.rett(a, b, c, d), -0.12, -0.08)
        k.pannello("#F1F0EC", e, K.rett(a - 0.3, b + 0.3, d + 0.05, d + 0.22), 0.0, 0.45)
    cornice = K.rett(-0.15, L + 0.15, z0 - 0.5, z1 + 0.1).difference(K.rett(0.1, L - 0.1, z0, z1))
    k.pannello(SCURO, e, cornice, 0.0, 0.3)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    sotto = max(k.pezzi(k.squadra(k.contorno("MIA011500S", chiudi=0.6))), key=lambda g: g.area)
    terra = max(k.pezzi(k.squadra(k.contorno("MIA0115000", chiudi=0.6))), key=lambda g: g.area)
    primo = max(k.pezzi(k.squadra(k.contorno("MIA0115001", chiudi=0.6))), key=lambda g: g.area)
    x0, y0, x1, y1 = sotto.bounds
    px0, py0, px1, py1 = primo.bounds
    tx0, ty0, tx1, ty1 = terra.bounds

    # il seminterrato: vetrata scura verso il vicolo a est, zoccolo intonacato altrove
    zoccolo = K.Stile(muro=SABBIA, finestre=None)
    vicolo = K.Stile(muro=SCURO, finestre="vetrata", telaio=SCURO, vetro="#2C343C", passo_montanti=1.3,
                     architrave=9.0)
    k.piano(sotto, -0.3, Z_T, lambda e, c: vicolo if K.verso(e) == "E" else zoccolo)

    # i tetti del seminterrato: a nord il giardino, a sud la piazzetta sotto la scatola
    scoperto = sotto.difference(terra.buffer(0.15, join_style=2))
    piazzetta = scoperto.intersection(box(x0 - 1, ty1 - 0.5, x1 + 1, y1 + 1))
    giardino = scoperto.difference(piazzetta)
    k.tetto_piano(giardino, Z_T, parapetto=0.0, colore=K.PRATO)
    for p in k.pezzi(piazzetta):
        E.prisma(k.S, LASTRE, E.ring_ccw(p), Z_T, Z_T + 0.06)
    for i, y in enumerate((ty1 + 1.6, ty1 + 3.2, ty1 + 4.8)):   # gli oblò sul seminterrato
        x = tx1 - 1.2 - 0.4 * i
        k.S.solid("#2C3A44", trimesh.creation.cylinder(radius=0.45, height=0.04, sections=20)
                  .apply_translation([x, y, Z_T + 0.08]))
        k.S.solid(SCURO, trimesh.creation.annulus(r_min=0.45, r_max=0.58, height=0.03, sections=20)
                  .apply_translation([x, y, Z_T + 0.08]))
    for e in E.edges(E.ring_ccw(sotto)):          # parapetti in vetro sul vicolo e verso nord
        if K.verso(e) in ("E", "N"):
            ringhiera(k, e, Z_T, vetro=True)
    for x, y in ((-1.6, 273.0), (4.4, 273.5), (1.2, 278.0), (6.6, 279.5)):
        albero(k, x, y, Z_T, r=1.8, h=6.0)

    # il terra: vetrato sotto la scatola e verso est, intonaco con la fascia scura altrove
    vetrato = K.Stile(muro=SCURO, finestre="vetrata", telaio=SCURO, vetro=VETRO, passo_montanti=1.25,
                      architrave=H - 0.7)
    pieno = K.Stile(muro=SABBIA, davanzale=0.9, architrave=2.7, telaio=SCURO, sguincio=0.12, reach=1.5)

    def st_terra(e, c):
        if K.verso(e) == "S" or (K.verso(e) == "E" and c[1] > py0 - 0.5):
            return vetrato
        return pieno
    k.piano(terra, Z_T, Z_1, st_terra, csip="MIA0115000", porte=True)
    for e in E.edges(E.ring_ccw(terra)):
        if st_terra(e, K.mid(e)) is pieno:
            k.pannello(SCURO, e, K.rett(0.0, e[4], Z_1 - 0.9, Z_1 - 0.35), 0.0, 0.04)
    tetto_t = terra.difference(primo.buffer(0.15, join_style=2))
    k.tetto_piano(tetto_t, Z_1, parapetto=0.0, colore=K.PRATO)
    for e in E.edges(E.ring_ccw(terra)):
        if K.verso(e) in ("N", "E", "O"):
            ringhiera(k, e, Z_1)
    for x, y in ((-1.2, 292.0), (2.4, 295.5), (5.0, 288.0)):
        albero(k, x, y, Z_1, r=1.7, h=5.5)

    # la scala dal giardino sul tetto del terra, nella rientranza a nord-ovest del terra
    n = 20
    for i in range(n):
        ya = ty0 + 0.2 + i * (4.4 / n)
        E.prisma(k.S, "#BDBBB5", E.ring_ccw(box(0.4, ya, 2.0, ya + 4.4 / n + 0.02)),
                 Z_T, Z_T + (i + 1) * (Z_1 - Z_T) / n)

    # il primo: la scatola che sporge, vetrata sui lati lunghi, il giardino su via Celoria
    vetri = K.Stile(muro=SCURO, finestre="vetrata", telaio=SCURO, vetro=VETRO, passo_montanti=1.25,
                    architrave=H - 0.7)
    intonaco = K.Stile(muro=SABBIA, davanzale=0.9, architrave=2.7, telaio=SCURO, sguincio=0.12, reach=1.5)

    def st_primo(e, c):
        v = K.verso(e)
        return None if v == "S" else vetri if v in ("E", "O") else intonaco
    k.piano(primo, Z_1, TETTO, st_primo, csip="MIA0115001")
    for e in E.edges(E.ring_ccw(primo)):
        if K.verso(e) == "S":
            giardino_verticale(k, e, Z_1, TETTO)
        k.pannello(SCURO, e, K.rett(-0.05, e[4] + 0.05, Z_1 - 0.5, Z_1 + 0.05), 0.0, 0.1)   # la fascia nera
        ringhiera(k, e, TETTO, h=1.2, passo=2.5)
    for p in k.pezzi(primo.difference(terra)):     # l'intradosso bianco della parte a sbalzo
        E.prisma(k.S, INTRADOSSO, E.ring_ccw(p), Z_1 - 0.5, Z_1)
    k.tetto_piano(primo, TETTO, parapetto=0.0, colore="#CFCCC4")
    k.tetto_piano(primo.intersection(box(px0, py0, px1, py0 + 6.0)).buffer(-0.4, join_style=2), TETTO + 0.05,
                  parapetto=0.0, colore=K.PRATO)
    for x, y in ((0.0, py0 + 3.0), (5.5, py0 + 3.2)):
        albero(k, x, y, TETTO, r=1.5, h=5.0)
    k.fotovoltaico(primo.intersection(box(px0, py0 + 7.0, px1, py1)).buffer(-0.8, join_style=2), TETTO + 0.4)

    # via Celoria: la cancellata coi pilastri in pietra, la scala, il cancello scorrevole
    yc = Y_CELORIA
    for x in (x0 - 0.6, x0 + 3.2, -1.9, 3.3):
        E.prisma(k.S, PIETRA, E.ring_ccw(box(x - 0.35, yc - 0.35, x + 0.35, yc + 0.35)), 0.0, 2.6)
        E.prisma(k.S, PIETRA, E.ring_ccw(box(x - 0.45, yc - 0.45, x + 0.45, yc + 0.45)), 2.6, 2.85)
    E.prisma(k.S, PIETRA, E.ring_ccw(box(x0 - 0.6, yc - 0.2, -1.9, yc + 0.2)), 0.0, 0.7)
    for i in range(int((-1.9 - x0 + 0.6) / 0.25)):
        xb = x0 - 0.6 + 0.4 + i * 0.25
        if xb < -2.2 and abs(xb - (x0 + 3.2)) > 0.45:
            E.prisma(k.S, "#8F7F68", E.ring_ccw(box(xb - 0.05, yc - 0.06, xb + 0.05, yc + 0.06)), 0.7, 1.9)
    E.prisma(k.S, "#8F7F68", E.ring_ccw(box(x0 - 0.6, yc - 0.08, -1.9, yc + 0.08)), 1.9, 2.0)
    E.prisma(k.S, "#C9C8C3", E.ring_ccw(box(3.65, yc - 0.1, x1 + 1.2, yc + 0.1)), 0.0, 2.1)
    passi = 6
    for i in range(passi):                        # dalla strada alla piazzetta
        ya = yc + 0.3 - (i + 1) * 0.36
        E.prisma(k.S, "#BDBBB5", E.ring_ccw(box(-1.5, ya, 2.9, ya + 0.38)), 0.0, (i + 1) * Z_T / passi)
    k.top = max(k.top, TETTO + 1.2)
    return k.fine()
