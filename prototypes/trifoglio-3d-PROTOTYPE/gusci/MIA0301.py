"""PROTOTIPO — l'Edificio 20 (MIA0301), via Ponzio 34/5: la stecca del DEIB lungo via Bassini,
con l'aula 20.S.1 nel seminterrato.

Fonti, oltre alle piante del Politecnico (seminterrato, terra, primo, secondo, terzo):
- la sagoma e l'altezza di OSM (w643507930, 18 m, quattro piani, tetto piano);
- le piante: la stecca lunga 93 m e larga 17, uffici sui due lati del corridoio con le
  finestre fitte, e la torre delle scale a pianta quadrata girata di 45° sul lato nord;
- l'ortofoto (Esri World Imagery, spostata di circa 8 m verso est e 5 m verso nord): il tetto
  bianco con due lunghe file di pannelli fotovoltaici, la testata est più bassa e scura con
  gli impianti, la torre delle scale col tetto a piramide.

- le foto di via Ponzio e via Bassini (Urbanfile, gennaio 2020 e giugno 2025, col numero 20
  all'ingresso), confrontate col render dagli stessi punti di vista: la pelle di pannelli
  bianchi, a ogni campata (2,8 m) una finestra a due ante sopra un pannello grigio scuro e una
  lama frangisole sulle mensole; il terra con le stesse campate chiuse da vetri e pannelli
  scuri quasi fino al soffitto; l'ingresso sotto una pensilina scura a scatola; il cornicione
  di lamiera che sporge tutto intorno al posto del parapetto; la testata ovest cieca, grigia,
  ora contro l'edificio nuovo del DEIB, e davanti alle prime campate la scala di sicurezza in
  acciaio zincato che nel 2025 ha preso il posto di quella vecchia sulla testata;
- l'ortofoto più recente (Esri, z19): le due fasce di pannelli fotovoltaici, la nord più corta.

Piani da 4,5 m.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0301"
H = 4.5
QUOTE = {"MIA030100S": -4.0, "MIA0301000": 0.0, "MIA0301001": 4.5, "MIA0301002": 9.0, "MIA0301003": 13.5}
TETTO = 18.0
EST = 377.0                    # da qui la testata est, coi tetti scuri degli impianti

INTONACO = "#E5E6E4"       # i pannelli bianchi
TERRA = "#B4B8BC"
SOTTO = "#7E8389"          # il pannello sotto le finestre
TELAIO = "#4E545A"
VETRO_TERRA = "#4A525B"    # i vetri e i pannelli scuri del terra
TESTATA = "#9AA0A6"        # la testata ovest, cieca
PENSILINA = "#3F444A"
LAMIERA = "#B9BDC1"        # il cornicione
ACCIAIO = "#A9AFB4"        # la scala di sicurezza zincata
INGRESSO = (356.0, 364.0)  # la pensilina dell'ingresso, a x
SCALA = (305.6, 152.9, 313.6, 157.4)   # la scala di sicurezza esterna (x0, y0, x1, y1)


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def _scala(k, x0, y0, x1, y1, z1, colore=ACCIAIO):
    """La scala di sicurezza in acciaio zincato davanti alla testata ovest (giugno 2025):
    una torre di montanti e traversi, i pianerottoli a ogni piano e a mezza altezza, le
    rampe in diagonale e i parapetti."""
    E, S = k.E, k.S
    xs = [x0 + (x1 - x0) * i / 4 for i in range(5)]
    for x in xs:
        for y in (y0, y1):
            E.trave(S, colore, (x, y, 0.0), (x, y, z1 + 1.1), 0.1)
    xm = (x0 + x1) / 2
    z = 0.0
    livelli = []
    while z < z1 - 0.1:
        livelli += [z, z + H / 2]
        z += H
    livelli.append(z1)
    for j, z in enumerate(livelli):
        if z > 0.1:
            # il pianerottolo, alternato ai due capi; quello dei piani anche davanti alle porte
            if j % 2 == 0:
                E.prisma(S, colore, [(x0, y0), (x1, y0), (x1, y0 + 1.4), (x0, y0 + 1.4)], z - 0.08, z)
            else:
                E.prisma(S, colore, [(x0, y1 - 1.4), (x1, y1 - 1.4), (x1, y1), (x0, y1)], z - 0.08, z)
        for y in (y0, y1):
            E.trave(S, colore, (x0, y, z + 1.1), (x1, y, z + 1.1), 0.05)
            E.trave(S, colore, (x0, y, z + 0.55), (x1, y, z + 0.55), 0.04)
        for x in (x0, x1):
            E.trave(S, colore, (x, y0, z + 1.1), (x, y1, z + 1.1), 0.05)
        if j + 1 < len(livelli):
            za, zb = z, livelli[j + 1]
            ya, yb = (y0 + 1.4, y1 - 1.4) if j % 2 == 0 else (y1 - 1.4, y0 + 1.4)
            for xa, xb in ((x0 + 0.1, xm - 0.1), (xm + 0.1, x1 - 0.1)):
                # due rampe affiancate, una che sale e una che scende
                p0, p1 = ((xa + xb) / 2, ya, za), ((xa + xb) / 2, yb, zb)
                E.trave(S, colore, p0, p1, 0.18)
                for dx in (xa, xb):
                    E.trave(S, colore, (dx, ya, za + 1.0), (dx, yb, zb + 1.0), 0.04)
    # le crociere sui lati corti
    for x in (x0, x1):
        for z, zz in zip(livelli, livelli[1:]):
            E.trave(S, colore, (x, y0, z), (x, y1, zz), 0.05)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    # sopra: a ogni campata una finestra a due ante sopra un pannello grigio, tra le lesene
    # bianche dei pannelli di facciata, con la lama frangisole sulle mensole
    st = K.Stile(muro=INTONACO, finestre=("passo", 2.8, 1.75), davanzale=1.25, architrave=3.35, telaio=TELAIO, sguincio=0.15,
                 montante=0.9, sottofinestra=SOTTO, frangisole=(0.7, "#C8CBCE"), marcapiano=(0.05, 0.02, "#C9CCCF"))
    # il terra: le stesse campate chiuse da pannelli e vetri scuri, quasi fino al soffitto
    terra = st.con(davanzale=0.05, architrave=3.7, vetro=VETRO_TERRA, telaio=TERRA, sottofinestra=None, frangisole=None,
                   marcapiano=None, montante=0.95)
    corto = st.con(finestre="pianta", ripiego=None)
    cieco = st.con(muro=TESTATA, finestre=None, sottofinestra=None, frangisole=None)
    vetro = K.Stile(muro=INTONACO, finestre="vetrata", telaio=TELAIO, vetro=K.VETRO_CHIARO, passo_montanti=1.2, architrave=99)

    def stile(terreno):
        def f(e, m):
            n, L = e[3], e[4]
            if L < 2.5:
                return cieco
            if n[0] < -0.7:
                return cieco                     # la testata ovest, cieca, ora contro l'edificio nuovo
            if abs(n[1]) > 0.7 and L > 10:
                return terra if terreno else st
            return corto.con(muro=INTONACO) if not terreno else terra.con(finestre="pianta")
        return f

    for csip in ("MIA0301000", "MIA0301001", "MIA0301002", "MIA0301003"):
        tutto = k.contorno(csip, chiudi=0.4)
        corpo = k.squadra(tutto.intersection(box(0, 134.6, 1000, 200)), passo=0.5)
        torre = max(k.pezzi(tutto.difference(box(0, 134.8, 1000, 200)).buffer(-0.6, join_style=2).buffer(0.6, join_style=2)), key=lambda g: g.area)
        z0 = QUOTE[csip]
        k.piano(corpo, z0, z0 + H, stile(csip.endswith("000")), csip=csip)
        # la torre delle scale: i lati liberi vetrati, a tutta altezza
        k.piano(torre.simplify(0.3), z0, z0 + H, vetro)
    # l'ingresso col numero 20: la porta vetrata sotto la pensilina scura a scatola
    sud = max((e for e in k.E.edges(k.E.ring_ccw(corpo)) if e[3][1] > 0.7), key=lambda e: e[4])
    ta, tb = sorted((sud[0][0] - x) for x in INGRESSO)
    k.pannello(VETRO_TERRA, sud, K.rett(ta, tb, 0.0, 3.7), 0.0, 0.08)
    k.porta(sud, ta + 1.2, tb - 1.2, 0.0, h=2.7, telaio=TERRA)
    k.pannello(PENSILINA, sud, K.rett(ta - 0.4, tb + 0.4, 3.75, 4.4), 0.0, 3.2)
    for t in (ta - 0.4, tb + 0.1):
        k.pannello(PENSILINA, sud, K.rett(t, t + 0.3, 0.0, 3.75), 2.9, 3.2)
    # il tetto: il cornicione di lamiera che sporge tutto intorno, poi la copertura bianca
    # coi pannelli fotovoltaici; la testata est più scura, con gli impianti
    k.E.prisma(k.S, LAMIERA, k.E.ring_ccw(corpo.buffer(0.7, join_style=2)), TETTO, TETTO + 0.4)
    k.tetto_piano(corpo, TETTO + 0.4, parapetto=0.0, colore="#E8E8E4")
    ovest = corpo.intersection(box(0, 0, EST, 200))
    x0, y0, x1, y1 = ovest.bounds
    # le due fasce di pannelli dell'ortofoto: la nord più corta, la sud lunga fin quasi agli impianti
    k.fotovoltaico(box(315.0, y0 + 0.9, 346.0, y0 + 5.2), TETTO + 0.48, passo=1.4)
    k.fotovoltaico(box(307.0, y1 - 11.0, 368.0, y1 - 6.4), TETTO + 0.48, passo=1.4)
    est = corpo.intersection(box(EST, 0, 1000, 200))
    k.tetto_piano(est, TETTO + 0.4, parapetto=0.0, colore="#6F7276")
    ex0, ey0, ex1, ey1 = est.bounds
    for i, (x, y) in enumerate(((ex0 + 4, ey0 + 4), (ex0 + 9, ey0 + 5), (ex0 + 14, ey1 - 5), (ex0 + 6, ey1 - 4))):
        k.impianto(x, y, 3.0, 2.0, TETTO + 0.48, h=1.4 + 0.3 * (i % 2))
    k.falde(torre.simplify(0.3), TETTO, pendenza=0.5, sporto=0.2, colore="#B8BDC2", gronda="#D9DBDC")
    # la scala di sicurezza davanti alle prime campate da ovest
    _scala(k, *SCALA, TETTO)
    return k.fine()
