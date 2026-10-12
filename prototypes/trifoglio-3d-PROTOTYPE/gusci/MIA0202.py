"""PROTOTIPO — l'Edificio 12 "Cesare Chiodi" (MIA0202), via Bonardi: la torre di sette piani fra
il Trifoglio e il 14, senza aule.

Fonti, oltre alle piante del Politecnico (seminterrato e soppalco, rialzato, dal primo al
sesto):
- la sagoma di OSM, su cui stanno il seminterrato e il rialzato;
- le piante: i piani dal primo al quinto sono disegnati con un'origine loro, e stanno sul
  rialzato spostandoli finché la scala coincide (gli `spostamenti` in `leonardo.json`); sono un
  po' più stretti del rialzato, che sporge a est, e sporgono loro sul rialzato a ovest. Il
  sesto è un attico sul lato ovest. Le finestre delle piante vanno a coppie (0,8 m, 30 cm fra
  le due, 45 cm fra una coppia e l'altra); vicino agli spigoli ce ne sono di più piccole;
- l'ortofoto (Esri World Imagery): il tetto piano grigio della torre con qualche impianto, la
  lunga ombra verso nord, la striscia più bassa del rialzato a est;
- le foto di Urbanfile: lo spigolo in alto (settembre 2019), la facciata intera da via
  Bonardi col cantiere del campus (dicembre 2020), il totem "12 Cesare Chiodi" (marzo 2021),
  lo zoccolo e la rampa al seminterrato (settembre 2019). Dicono:
  - il klinker è bruno scuro a toni misti, rossiccio al sole, posato a cestello irregolare
    (gruppi di mattoni orizzontali e verticali), con la copertina in metallo scuro sottile;
  - ogni finestra ha un telaio bianco a cassetta che sporge dal muro, col davanzale più
    spesso; fra le due finestre di una coppia sale una lesena bianca, dal piede della torre
    fino alla copertina; fra una coppia e l'altra c'è solo mattone;
  - le finestre piccole vicino agli spigoli sono orizzontali, a due ante, più alte delle
    altre;
  - dove la torre sporge sul rialzato il terra è arretrato e vetrato, coi pilastri in
    mattone agli spigoli e l'intradosso bianco.

Piani da 3,3 m e il rialzato a un metro da terra.
"""
import sys
import pathlib
import numpy as np
import trimesh
from shapely.geometry import Point

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0202"
H = 3.3
R = 1.0
SU = [f"MIA020200{i}" for i in range(1, 7)]
QUOTE = {"MIA020200S": -3.0, "MIA0202S0S": -1.4, "MIA020200R": R, **{c: round(R + (i + 1) * H, 2) for i, c in enumerate(SU)}}
TETTO = round(QUOTE["MIA0202005"] + H, 2)
PARAPETTO = 0.9

KLINKER = "ed12_klinker"
BIANCO = "#ECEBE6"           # i telai a cassetta e le lesene
COPERTINA = "#3A3532"        # la copertina in metallo scuro
INTRADOSSO = "#E9E8E3"
VETRO = "#4A5866"
TELAIO = "#F0F0EC"


# ---------------------------------------------------------------- il klinker a cestello

def _klinker():
    """Klinker bruno a toni misti, posato a cestello irregolare: celle da 25 cm con tre
    mattoni da 8 cm orizzontali o verticali, a caso; giunti scuri sottili. 2 x 2 m."""
    from PIL import Image
    rng = np.random.default_rng(12)
    size, celle = 512, 8                     # 8 celle per lato: 2 m
    y, x = np.mgrid[0:size, 0:size] / size * celle
    ci, cj = np.floor(x).astype(int), np.floor(y).astype(int)
    fx, fy = x - ci, y - cj
    verso = rng.random((celle, celle)) < 0.5
    v = verso[cj, ci]
    f = np.where(v, fx, fy)                  # i tre mattoni attraverso la cella
    k = np.floor(f * 3).clip(0, 2)
    toni = np.array([[0.38, 0.25, 0.21], [0.34, 0.23, 0.20], [0.30, 0.20, 0.18],
                     [0.26, 0.18, 0.16], [0.41, 0.28, 0.23], [0.32, 0.23, 0.21]])
    scelta = rng.integers(0, len(toni), (celle, celle, 3))
    rgb = toni[scelta[cj, ci, k.astype(int)]] * (0.95 + rng.normal(0, 0.02, (size, size)))[..., None]
    giunto = (np.minimum(f * 3 % 1, 1 - f * 3 % 1) < 0.07) | (np.minimum(fx, 1 - fx) < 0.012) | (np.minimum(fy, 1 - fy) < 0.012)
    rgb[giunto] = [0.24, 0.20, 0.18]
    h = np.where(giunto, 0.0, 1.0)
    gy, gx = np.gradient(h)
    nrm = np.dstack([-gx * 3, gy * 3, np.ones_like(h)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    to8 = lambda a: Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return to8(rgb), to8(nrm * 0.5 + 0.5)


def _registra(E):
    E.TEX.setdefault(KLINKER, 2.0)
    if KLINKER not in E._TEXTURES:
        E._TEXTURES[KLINKER] = _klinker()


# ---------------------------------------------------------------- le facciate

def coppie(iv):
    """Le finestre della pianta divise in quelle a coppie (larghe 0,8 m, con la lesena in
    mezzo) e le piccole orizzontali; per ogni coppia la t della lesena."""
    grandi = [w for w in iv if 0.75 <= w[1] - w[0] <= 1.05]
    piccole = [w for w in iv if w not in grandi]
    lesene = [round((a[1] + b[0]) / 2, 2) for a, b in zip(grandi, grandi[1:]) if b[0] - a[1] < 0.38]
    return grandi, piccole, lesene


def finestra(k, e, t0, t1, z0, z1, ante=1):
    """Una finestra col telaio bianco a cassetta che sporge 18 cm e il davanzale più
    spesso; il vetro arretrato nel telaio."""
    P = k.pannello
    P(VETRO, e, K.rett(t0, t1, z0, z1), -0.1, -0.07)
    for i in range(1, ante):
        t = t0 + (t1 - t0) * i / ante
        P(TELAIO, e, K.rett(t - 0.03, t + 0.03, z0, z1), -0.1, 0.0)
    if z1 - z0 > 1.3:                                        # il sopraluce
        P(TELAIO, e, K.rett(t0, t1, z1 - 0.42, z1 - 0.37), -0.1, 0.0)
    w = 0.08
    cassa = K.rett(t0 - w, t1 + w, z0 - 0.14, z1 + w).difference(K.rett(t0, t1, z0, z1))
    P(BIANCO, e, cassa, -0.1, 0.16)
    P(BIANCO, e, K.rett(t0 - w - 0.02, t1 + w + 0.02, z0 - 0.16, z0 - 0.06), 0.0, 0.22)


def facciata(k, e, z0, z1, csip, reach=1.4, spigoli=False):
    """Un piano su un lato: il muro in klinker coi buchi, le finestre grandi (0,75-2,6 m) e
    le piccole orizzontali (1,5-2,3 m); con spigoli, anche quelle d'angolo. Restituisce le t
    delle lesene."""
    iv = k.finestre_pianta(csip, e, reach, 0.5)
    grandi, piccole, lesene = coppie(iv)
    L = e[4]
    if spigoli and iv and L > 10:
        # la finestra orizzontale d'angolo, che gira lo spigolo: dove fra lo spigolo e la
        # prima finestra della pianta resta una fascia cieca di 1,5-2,2 m
        if 1.5 < iv[0][0] < 2.2:
            piccole.insert(0, (0.0, 1.25))
        if 1.5 < L - iv[-1][1] < 2.2:
            piccole.append((L - 1.25, L))
    buchi = [(a, b, z0 + 0.75, z0 + 2.6) for a, b in grandi] + [(a, b, z0 + 1.5, z0 + 2.3) for a, b in piccole]
    k.muro(e, z0, z1, KLINKER, buchi)
    for a, b in grandi:
        finestra(k, e, a, b, z0 + 0.75, z0 + 2.6)
    for a, b in piccole:
        finestra(k, e, a, b, z0 + 1.5, z0 + 2.3, ante=2 if b - a > 0.9 else 1)
    return lesene


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    _registra(E)
    rialzato = k.squadra(k.contorno("MIA020200R", chiudi=0.6))
    torre = k.squadra(k.contorno("MIA0202002", chiudi=0.6))
    attico = k.squadra(k.contorno("MIA0202006", chiudi=0.6))
    z1 = QUOTE["MIA0202001"]

    # lo zoccolo e il rialzato: dove il suo lato sta sotto la torre prende le finestre (e le
    # lesene) dei piani sopra, altrove le sue
    k.piano(rialzato, -0.3, R, K.Stile(muro=KLINKER, finestre=None))
    sotto = torre.exterior.buffer(0.8)
    lesene_basse = []
    for q in k.pezzi(rialzato):
        pts = E.ring_ccw(q)
        for c in k.pezzi(q.buffer(-K.SPESSORE + 0.02, join_style=2), 0.5):
            E.prisma(k.S, "#55595F", E.ring_ccw(c), R, z1)
        for e in E.edges(pts):
            allineato = sotto.contains(Point(K.mid(e)))
            ls = facciata(k, e, R, z1, "MIA0202002" if allineato else "MIA020200R")
            if allineato:
                lesene_basse.append((e, ls))
            for t0, t1 in k.porte_esterne("MIA020200R", e):
                k.porta(e, t0, t1, R, telaio=TELAIO)
    k.tetto_piano(rialzato.difference(torre.buffer(0.2, join_style=2)), z1, parapetto=0.8, muro=KLINKER, copertina=COPERTINA)
    for e, ls in lesene_basse:
        for t in ls:
            k.pannello(BIANCO, e, K.rett(t - 0.06, t + 0.06, -0.3, z1), 0.0, 0.2)

    # dove la torre sporge sul rialzato: il terra arretrato e vetrato, i pilastri in mattone
    # agli spigoli, l'intradosso bianco
    sbalzo = torre.difference(rialzato.buffer(0.3, join_style=2))
    for p in k.pezzi(sbalzo, 2.0):
        k.S.solid(INTRADOSSO, trimesh.creation.extrude_polygon(p, 0.12).apply_translation([0, 0, z1 - 0.12]))
    for x, y in list(torre.exterior.coords)[:-1]:
        if not rialzato.buffer(0.3).contains(Point(x, y)):
            c = torre.centroid
            dx, dy = np.sign(c.x - x) * 0.35, np.sign(c.y - y) * 0.35
            k.S.solid(KLINKER, E.box_z(x + dx, y + dy, 0.7, 0.7, 0.0, z1))

    # i cinque piani della torre, e le lesene su tutta l'altezza fino alla copertina
    lesene = {}
    for c in SU[:-1]:
        k._zpiano = QUOTE[c]
        for q in k.pezzi(torre):
            for cc in k.pezzi(q.buffer(-K.SPESSORE + 0.02, join_style=2), 0.5):
                E.prisma(k.S, "#55595F", E.ring_ccw(cc), QUOTE[c], QUOTE[c] + H)
            for e in E.edges(E.ring_ccw(q)):
                for t in facciata(k, e, QUOTE[c], QUOTE[c] + H, c, spigoli=True):
                    lesene.setdefault((tuple(e[0]), tuple(e[1])), (e, set()))[1].add(round(t, 1))
    k.tetto_piano(torre.difference(attico.buffer(0.2, join_style=2)), TETTO, parapetto=PARAPETTO,
                  muro=KLINKER, copertina=COPERTINA)
    for e, ts in lesene.values():
        for t in sorted(ts):
            k.pannello(BIANCO, e, K.rett(t - 0.06, t + 0.06, z1, TETTO + PARAPETTO + 0.06), 0.0, 0.2)

    # l'attico, arretrato: klinker con le finestre a passo, senza lesene
    k.piano(attico, TETTO, TETTO + 3.0, K.Stile(muro=KLINKER, finestre=("passo", 2.4, 1.2), davanzale=1.0,
                                                architrave=2.3, telaio=TELAIO, cornice=BIANCO), csip="MIA0202006")
    k.tetto_piano(attico, TETTO + 3.0, parapetto=0.5, muro=KLINKER, copertina=COPERTINA)
    x0, y0, x1, y1 = torre.bounds
    k.impianto(x1 - 4.0, y0 + 4.0, 3.0, 2.0, TETTO + 0.1, h=1.5)
    k.impianto(x1 - 4.0, y1 - 5.0, 2.4, 2.0, TETTO + 0.1, h=1.2)
    return k.fine()
