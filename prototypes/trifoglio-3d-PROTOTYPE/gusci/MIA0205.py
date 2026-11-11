"""PROTOTIPO — l'Edificio 14 "Nave" (MIA0205), via Bonardi: la stecca delle aule da disegno
costruita fra il 1955 e il 1963, a L intorno alla piazza sopra il 16C, rifatta nel 2021.

Fonti, oltre alle piante del Politecnico (seminterrato, dal terra all'ottavo):
- la sagoma delle piante, tenuta com'è: la prua stretta e smussata in fondo all'ala ovest
  (da cui il nome) e lo spigolo tagliato in testa all'ala nord, che l'ortofoto conferma;
- le foto della piazza dopo il restauro (Urbanfile, giugno 2021) e quelle di Teamwork: la
  pelle di piastrelle grigio chiaro a punta di diamante, la griglia di cemento con un pilastro
  ogni campata e una fascia a ogni piano, due finestre per campata con il telaio grigio scuro,
  le tapparelle e una presa d'aria sotto ognuna, sfalsate da un piano all'altro; il terra è un
  portico su pilastri rastremati di cemento grezzo con la trave alta e la vetrata arretrata;
  in cima la ringhiera e il locale degli impianti schermato di lamiera;
- l'ortofoto (Esri World Imagery): i tetti piani, i canali e gli impianti lungo l'ala nord, il
  locale lungo sull'ala ovest (sul tetto l'ortofoto è spostata di qualche metro: l'edificio è
  alto e la foto non è a piombo).

Piani da 3,8 m.
"""
import sys
import math
import pathlib
import random
from shapely.geometry import box, Polygon

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K
from _kit import rett

CSIE = "MIA0205"
H = 3.8
PIANI = [f"MIA020500{i}" for i in range(8)]
QUOTE = {"MIA020500S": -3.6, **{c: round(i * H, 2) for i, c in enumerate(PIANI)}, "MIA0205008": round(8 * H, 2)}
TETTO = round(8 * H, 2)

PIASTRELLE = "kit_punta_diamante"
CLS = "#D6D5D0"            # la griglia di cemento, appena più chiara delle piastrelle
GREZZO = "#9C9890"         # i pilastri del portico
TELAIO = "#4A4E52"
TAPPARELLE = ("#4C5054", "#4C5054", "#E2DFD7", "#8E9296")
LAMIERA = "#9EA2A5"
CAMPATA = 6.6              # il passo dei pilastri
PORTICO = 2.8              # quanto è arretrata la vetrata del terra


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def campate(L):
    n = max(1, round(L / CAMPATA))
    return [L * j / n for j in range(n + 1)]


def colonne(L, rng):
    """Le file di finestre di un lato: due per campata, in colonna dal primo al settimo."""
    out = []
    ts = campate(L)
    for t0, t1 in zip(ts, ts[1:]):
        a, b = t0 + 0.35, t1 - 0.35
        n = 2 if b - a > 4.6 else 1
        for h in range(n):
            w = rng.choice((1.7, 1.8, 1.9)) if b - a > 2.4 else (b - a) - 0.6
            m0, m1 = a + (b - a) * h / n + w / 2 + 0.3, a + (b - a) * (h + 1) / n - w / 2 - 0.3
            out.append((rng.uniform(m0, max(m0, m1)), w))
    return out


def facciata(k, e, z0, z1, rng, st, file_):
    """Un piano su un lato: le piastrelle, le finestre con la presa d'aria sotto (in colonna ma
    sfalsate in altezza), i pilastri e la fascia di cemento."""
    L = e[4]
    P = k.pannello
    if L < 4.0:
        k.muro(e, z0, z1, PIASTRELLE)
        P(CLS, e, rett(0.0, L, z0 - 0.16, z0 + 0.16), 0.0, 0.06)
        return
    ts = campate(L)
    buchi, fori, prese = [], [], []
    for tc, w in file_:
        tc += rng.uniform(-0.2, 0.2)
        zs = z0 + rng.uniform(0.85, 1.4)
        ze = zs + rng.choice((1.6, 1.7, 1.8))
        buchi.append((tc - w / 2, tc + w / 2, zs, ze))
        fori.append((tc - w / 2, tc + w / 2, zs, ze))
        vc = tc + rng.uniform(-0.15, 0.15)
        prese.append((vc - 0.4, vc + 0.4, zs - 0.6, zs - 0.28))
    k.muro(e, z0, z1, PIASTRELLE, buchi + prese)
    for t0, t1, zs, ze in fori:
        k.foro(e, t0, t1, zs, ze, st)
        u = rng.random()
        if u < 0.75:                                      # la tapparella giù per un pezzo
            zt = ze - (ze - zs) * rng.choice((0.3, 0.6, 1.0))
            P(rng.choice(TAPPARELLE), e, rett(t0 + 0.06, t1 - 0.06, zt, ze - 0.06), -st.sguincio + 0.06, -st.sguincio + 0.09)
    for t0, t1, zs, ze in prese:
        P("#3A3E42", e, rett(t0, t1, zs, ze), -0.12, -0.1)
        P("#DADAD6", e, rett(t0, t1, zs, ze).difference(rett(t0 + 0.05, t1 - 0.05, zs + 0.05, ze - 0.05)), -0.12, -0.02)
    for t in ts:
        P(CLS, e, rett(max(0.0, t - 0.3), min(L, t + 0.3), z0, z1), 0.0, 0.1)
    P(CLS, e, rett(0.0, L, z0 - 0.16, z0 + 0.16), 0.0, 0.06)


def pilastro(k, e, t, z1):
    """Un pilastro del portico, rastremato verso il basso, sul filo della facciata."""
    a, _, u, n, _, _ = e
    def giro(w, d, z):
        c = (a[0] + u[0] * t - n[0] * (d / 2), a[1] + u[1] * t - n[1] * (d / 2))
        return [(c[0] + su * u[0] * w / 2 + sn * n[0] * d / 2, c[1] + su * u[1] * w / 2 + sn * n[1] * d / 2, z)
                for su, sn in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    k.S.solid(GREZZO, k.E.hexa(giro(0.8, 0.9, 0.0), giro(1.0, 1.2, z1 - 0.9)))
    k.S.solid(GREZZO, k.E.hexa(giro(1.0, 1.2, z1 - 0.9), giro(1.5, 1.2, z1)))


def ringhiera(k, poly, z, h=1.1):
    for e in k.E.edges(k.E.ring_ccw(poly)):
        L = e[4]
        k.pannello("#7D8286", e, rett(0.0, L, z + h - 0.05, z + h), -0.25, -0.2)
        for i in range(int(L / 1.4) + 1):
            t = min(L - 0.03, max(0.03, i * 1.4))
            k.pannello("#7D8286", e, rett(t - 0.03, t + 0.03, z, z + h), -0.25, -0.2)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    rng = random.Random(14)
    st = K.Stile(muro=PIASTRELLE, telaio=TELAIO, sguincio=0.16, montante=1.0)
    # la sagoma vera, senza raddrizzarla: la prua e gli spigoli tagliati sono la Nave
    corpo = max(k.pezzi(k.contorno("MIA0205004", chiudi=1.2).simplify(0.35)), key=lambda g: g.area)
    terra = k.contorno("MIA0205000", chiudi=1.2).simplify(0.35)

    # il terra: il portico sui pilastri e la vetrata arretrata
    dentro = max(k.pezzi(corpo.buffer(-PORTICO, join_style=2)), key=lambda g: g.area)
    k.piano(dentro, 0.0, H - 0.9, K.Stile(muro="#D9D8D3", finestre="vetrata", telaio="#B8BBBD", vetro="#6F7E8A",
                                          passo_montanti=1.6, architrave=2.6))
    for q in k.pezzi(corpo.difference(dentro)):
        k.E.prisma(k.S, "#B9B6AE", k.E.ring_ccw(q), -0.02, 0.02)
    for e in E.edges(E.ring_ccw(corpo)):
        k.pannello(CLS, e, rett(0.0, e[4], H - 0.9, H), -PORTICO, 0.12)    # la trave alta
        if e[4] >= 4.0:
            for t in campate(e[4]):
                pilastro(k, e, min(e[4] - 0.75, max(0.75, t)), H - 0.9)
    # i corpi bassi sul lato ovest (ingressi e scale fuori sagoma)
    bassi = terra.difference(corpo.buffer(0.3, join_style=2))
    for q in k.pezzi(bassi, 4.0):
        k.piano(q, 0.0, H - 0.6, K.Stile(muro=PIASTRELLE, finestre=("passo", 2.4, 1.4), davanzale=1.0,
                                         architrave=2.5, telaio=TELAIO))
        k.tetto_piano(q, H - 0.6, parapetto=0.3, muro=CLS)

    # dal primo al settimo: la griglia di cemento con le piastrelle
    lati = E.edges(E.ring_ccw(corpo))
    file_ = [colonne(e[4], rng) for e in lati]
    for i in range(1, 8):
        z0 = i * H
        for c in k.pezzi(corpo.buffer(-K.SPESSORE + 0.02, join_style=2), 0.5):
            E.prisma(k.S, "#55595F", E.ring_ccw(c), z0, z0 + H)
        for e, f in zip(lati, file_):
            facciata(k, e, z0, z0 + H, rng, st, f)
    k.top = TETTO
    k.tetto_piano(corpo, TETTO, parapetto=0.5, muro=CLS)
    ringhiera(k, corpo.buffer(-0.35, join_style=2), TETTO + 0.5, 0.6)

    # l'ottavo: il locale degli impianti sull'ala ovest, schermato di lamiera
    loc = max(k.pezzi(k.contorno("MIA0205008", chiudi=1.0).simplify(0.4)), key=lambda g: g.area)
    k.piano(loc, TETTO, TETTO + 3.4, K.Stile(muro="kit_lamiera", finestre=None))
    k.tetto_piano(loc, TETTO + 3.4, parapetto=0.2, muro=LAMIERA)

    # l'ala nord: i canali lungo il colmo e gli impianti (dall'ortofoto, tolto lo spostamento)
    z = TETTO + 0.08
    for x0, x1, y, w in ((72, 124, -0.5, 1.4), (80, 118, 2.5, 1.0)):
        k.S.solid("#D4D5D3", E.box_z((x0 + x1) / 2, y, x1 - x0, w, z, z + 0.9))
    for j, x in enumerate(range(76, 122, 7)):
        k.impianto(x, 4.8 if j % 2 else -3.4, 4.2, 2.6, z, h=1.5 + 0.3 * (j % 3))
    for x in range(88, 110, 4):
        k.impianto(x, -4.2, 2.6, 1.6, z, h=1.1, colore="#5E6368")
    return k.fine()
