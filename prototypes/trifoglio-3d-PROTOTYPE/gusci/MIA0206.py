"""PROTOTIPO — l'Edificio 15 (MIA0206), via Bonardi: i laboratori a E fra il 16C e la ferrovia,
senza aule.

Fonti, oltre alle piante del Politecnico (seminterrato, terra, primo, secondo):
- la sagoma di OSM: la E aperta verso est;
- le piante: il terra copre tutta la E, il primo la C senza il braccio di mezzo, il secondo
  solo la manica sud. Il primo sta sulla sagoma; il terra e il seminterrato erano disegnati
  27 m più a est e stanno sul primo con gli `spostamenti` in `leonardo.json` (le scale
  coincidono);
- l'ortofoto (Esri World Imagery): il tetto chiaro in ghiaia della manica nord con un
  lucernario, il braccio di mezzo più basso e scuro, la manica sud col tetto scuro e un volume
  tecnico a ovest;
- le foto: Urbanfile, "Il nuovo Campus Leonardo del Politecnico", giugno 2021 (il fronte ovest
  dalla piazza sopra il 16C e il totem "15"), e i panorami Mapillary dell'autunno 2024 dal
  cortile e dal vialetto lungo la ferrovia. Rivestimento bianco liscio, finestre a nastro con
  telai grigio scuro e frangisole a lamelle grigie davanti a gran parte delle campate, al terra
  uno zoccolo di granito grigio sotto il nastro, sui tetti la ringhiera in tubolare; nel
  cortile la pensilina su pilastri bianchi con le travi scure fino all'ingresso vetrato; in
  fondo alla manica sud, verso la ferrovia, la scala di sicurezza in acciaio e vetro (il
  dente del terra a est).
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0206"
H = 4.0
PIANI = ["MIA0206000", "MIA0206001", "MIA0206002"]
QUOTE = {"MIA020600S": -3.8, **{c: i * H for i, c in enumerate(PIANI)}}
TETTO = 3 * H

BIANCO = "#EFEEE9"        # il rivestimento
GRANITO = "#85817B"       # lo zoccolo del terra
TELAIO = "#3B4147"
LAMELLE = "#8D949A"       # i frangisole
LAMELLE_FONDO = "#6B7279"
GHIAIA = "#CDBFAE"
FERRO = "#5E6368"         # ringhiere, scala, travi
DAVANZALE, ARCHITRAVE = 1.0, 2.9


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def frangisole(k, e, z0, z1, passo=1.5):
    """Le lamelle grigie davanti alle campate del nastro: tre campate su cinque, a gruppi come
    nelle foto, con un vetro libero in mezzo."""
    L = e[4]
    n = max(1, round((L - 0.5) / passo))
    w = (L - 0.5) / n
    for i in range(n):
        if i % 5 in (1, 3):
            continue
        t0, t1 = 0.25 + i * w + 0.04, 0.25 + (i + 1) * w - 0.04
        k.pannello(LAMELLE_FONDO, e, K.rett(t0, t1, z0, z1), -0.07, -0.06)
        z = z0 + 0.06
        while z < z1 - 0.05:
            k.pannello(LAMELLE, e, K.rett(t0, t1, z, z + 0.07), -0.06, 0.02)
            z += 0.16


def ringhiera(k, poly, z, h=1.1, dentro=0.15):
    """La ringhiera in tubolare sul bordo di un tetto: montanti, corrimano e un traverso."""
    for q in k.pezzi(poly):
        for e in k.E.edges(k.E.ring_ccw(q)):
            L = e[4]
            d0, d1 = -dentro - 0.05, -dentro
            for zr in (z + h - 0.05, z + h * 0.5):
                k.pannello(FERRO, e, K.rett(0.0, L, zr, zr + 0.05), d0, d1)
            m = max(1, round(L / 1.8))
            for i in range(m + 1):
                t = min(max(L * i / m, 0.03), L - 0.03)
                k.pannello(FERRO, e, K.rett(t - 0.03, t + 0.03, z, z + h), d0, d1)
    k.top = max(k.top, z + h)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=BIANCO, finestre="nastro", davanzale=DAVANZALE, architrave=ARCHITRAVE,
                 telaio=TELAIO, passo_montanti=1.5)

    def cieco(e, z0):
        # i lati corti e le testate verso la ferrovia sopra il terra sono ciechi
        return e[4] <= 3.0 or (z0 > 0 and e[4] < 9.0 and e[3][0] > 0.9)

    def stile_di(z0):
        return lambda e, c: st.con(finestre=None) if cieco(e, z0) else st

    corpi = [max(k.pezzi(k.squadra(k.contorno(c, chiudi=0.8))), key=lambda g: g.area) for c in PIANI]
    # il dente del terra a est della manica sud è la base della scala: la scala la fa sotto
    corpi[0] = corpi[0].difference(box(135.9, 50.0, 140.0, 61.0))
    for i, (c, g) in enumerate(zip(PIANI, corpi)):
        z0 = i * H
        k.piano(g, z0, z0 + H, stile_di(z0), csip=c, porte=i == 0)
        for e in E.edges(E.ring_ccw(g)):
            if cieco(e, z0):
                continue
            frangisole(k, e, z0 + DAVANZALE, z0 + ARCHITRAVE)
            if i == 0:
                k.pannello(GRANITO, e, K.rett(0.0, e[4], -0.3, DAVANZALE - 0.05), 0.0, 0.05)
        sopra = corpi[i + 1].buffer(0.2, join_style=2) if i + 1 < len(corpi) else None
        resto = g.difference(sopra) if sopra is not None else g
        for q in k.pezzi(resto, 6.0):
            k.tetto_piano(q, z0 + H, parapetto=0.35, muro=BIANCO, copertina="#9DA2A6",
                          colore=GHIAIA if q.centroid.y < 38 else K.GUAINA)
        for q in k.pezzi(resto, 30.0):
            ringhiera(k, q, z0 + H + 0.35)

    # il lucernario della manica nord e il volume tecnico della manica sud, con la sua ringhiera
    k.piano(box(108.0, 31.0, 111.5, 35.0), 2 * H, 2 * H + 0.8, K.Stile(muro="#E3E3DF", finestre=None))
    sud = corpi[2].bounds
    k.impianto(sud[0] + 5.0, sud[1] + 5.0, 6.0, 4.0, TETTO + 0.1, h=1.8, colore="#B9B6AF")

    # la scala di sicurezza in testa alla manica sud: torre dell'ascensore vetrata, rampe e
    # pianerottoli in acciaio con i parapetti di vetro
    x0, x1, y0, y1 = 136.0, 139.4, 52.2, 60.2
    asc = box(x0, y1 - 2.6, x1, y1)
    E.prisma(k.S, "#4C5258", E.ring_ccw(asc.buffer(-0.25, join_style=2)), 0.0, TETTO + 1.2)
    vetro = K.Stile(finestre="vetrata", telaio=FERRO, vetro=K.VETRO_CHIARO, passo_montanti=1.1)
    for e in E.edges(E.ring_ccw(asc)):
        k.vetrata(e, 0.0, TETTO + 1.2, vetro, traversi=(H, 2 * H, TETTO))
    k.tetto_piano(asc, TETTO + 1.2, parapetto=0.1, colore=FERRO, copertina=FERRO)
    for x in (x0 + 0.1, x1 - 0.1):
        for y in (y0 + 0.1, y1 - 2.7):
            k.S.solid(FERRO, E.box_z(x, y, 0.2, 0.2, 0.0, TETTO + 1.1))
    for z in (H, 2 * H, TETTO):
        pian = box(x0, y1 - 5.0, x1, y1 - 2.6)
        E.prisma(k.S, FERRO, E.ring_ccw(pian), z - 0.25, z)
        for e in E.edges(E.ring_ccw(pian)):
            if e[3][0] > 0.9 or e[3][1] < -0.9:
                k.pannello(K.VETRO_CHIARO, e, K.rett(0.0, e[4], z, z + 1.1), -0.03, 0.0)
                k.pannello(FERRO, e, K.rett(0.0, e[4], z + 1.05, z + 1.12), -0.06, 0.02)
    # le rampe: due per piano, a forbice lungo il lato verso la ferrovia
    import trimesh
    for z in (0.0, H, 2 * H):
        for (xa, xb) in ((x1 - 1.6, x1), (x0, x0 + 1.6)):
            ya, yb = (y0, y1 - 5.0) if xa > x0 else (y1 - 5.0, y0)
            za, zb = (z, z + H / 2) if xa > x0 else (z + H / 2, z + H)
            if xa == x0:
                E.prisma(k.S, FERRO, E.ring_ccw(box(x0, y0, x1, y0 + 1.2)), z + H / 2 - 0.2, z + H / 2)
            v = [(xa, ya, za), (xb, ya, za), (xb, yb, zb), (xa, yb, zb)]
            top = [(p[0], p[1], p[2]) for p in v]
            bot = [(p[0], p[1], p[2] - 0.2) for p in v]
            k.S.solid(FERRO, E.hexa(bot, top))
            vx = xb if xa > x0 else xa
            gl = [(vx, ya, za), (vx, yb, zb), (vx, yb, zb + 1.1), (vx, ya, za + 1.1)]
            k.S.solid(K.VETRO_CHIARO, trimesh.Trimesh(vertices=gl + [(vx + 0.02, p[1], p[2]) for p in gl],
                                                      faces=[[0, 1, 2], [0, 2, 3], [4, 6, 5], [4, 7, 6]]))

    # la pensilina del cortile: pilastri bianchi, travi scure, lastre chiare
    y0, y1 = 42.6, 45.6
    for x in (118.5, 122.5, 126.5):
        for y in (y0 + 0.15, y1 - 0.15):
            k.S.solid("#F1F0EC", E.box_z(x, y, 0.2, 0.2, 0.0, 3.0))
    k.S.solid("#4A3A30", E.box_z(121.6, y0 + 0.1, 10.8, 0.25, 3.0, 3.35))
    k.S.solid("#4A3A30", E.box_z(121.6, y1 - 0.1, 10.8, 0.25, 3.0, 3.35))
    k.S.solid("#E4E8DC", E.box_z(121.6, (y0 + y1) / 2, 10.8, y1 - y0 + 0.3, 3.35, 3.42))
    # la veranda vetrata del terra in testa alla manica nord, verso la ferrovia
    ver = box(135.6, 24.4, 137.0, 31.0)
    E.prisma(k.S, "#3A3F44", E.ring_ccw(ver), 0.0, 1.3)
    for e in E.edges(E.ring_ccw(ver)):
        if e[3][0] > -0.9:
            k.vetrata(e, 1.3, 3.2, K.Stile(finestre="vetrata", telaio="#33373B", vetro="#A3B2B9",
                                            passo_montanti=1.6))
    E.prisma(k.S, "#33373B", E.ring_ccw(ver.buffer(0.15, join_style=2)), 3.2, 3.5)
    return k.fine()
