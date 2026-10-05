"""Edificio 1, il Rettorato (MIA0101): l'esterno ridisegnato dal satellite e dalle foto.

Moretti e Brusconi, dal 1927. Le misure vengono da tre fonti:
- le piante del Politecnico (piante/MIA0101-geometria.json): il contorno di ogni corpo, le
  finestre dei lati verso il giardino e i cortili, le scale esterne;
- l'ortofoto (Google, zoom 21, 5 cm per pixel): i tetti. A coppi a padiglione sopra l'Aula
  Magna e sopra lo scalone, terrazze piane dietro la balaustra sulle teste del fronte, la
  torretta tonda a sud dell'Aula Magna, e il corpo verso il giardino con il tetto ad anello
  intorno al lucernario a dieci campi;
- le foto della facciata su Piazza Leonardo da Vinci (Wikimedia Commons): nove campate fra
  dieci lesene d'ordine gigante, bugnato al terra con tre portoni ad arco, piano nobile con
  le finestre ad arco sui balconi a balaustri, fregio con la scritta, cornicione su mensole,
  balaustra con le sfere, frontoni ricurvi con lo stemma sulle campate 2 e 8, obelischi.

Quote dalla foto frontale (35,6 px per metro, 44,5 m fra le lesene esterne): gradini fino a
0,6 m, zoccolo di granito fino a 1,45, piano nobile a 6,0, capitelli a 12,4-13,1, fregio fino
a 14,7, cornicione fino a 15,6, balaustra fino a 17,6, obelischi alti fino a 22.

guscio(b, E) e quote(b, E) sono chiamati da esporta3d.py (E è quel modulo).
"""
import math
import numpy as np
import trimesh
from shapely.geometry import Polygon, Point, LineString, box
from shapely.ops import unary_union

# ---------------------------------------------------------------- misure

Z_PIANI = {"MIA0101000": 0.6, "MIA0101001": 6.0, "MIA0101002": 11.0}
GRADINI = 0.6          # il terra sopra la piazza: quattro gradini
ZOCCOLO = 1.45         # lo zoccolo di granito
NOBILE = 6.0           # il piano nobile (fascia dei balconi)
CAPITELLO = (12.4, 13.1)
FREGIO = 14.7
CORNICE = 15.6         # cima del cornicione del fronte
BALAUSTRA = 17.6
GRONDA = 15.0          # la gronda dello scalone e del corpo sul giardino
ANNESSI = 10.6         # i due corpi bassi a nord e a sud del fronte

# I corpi, dal contorno delle piante (metri, frame del campus: x est, y sud).
FRONTE = unary_union([box(-66.4, 187.8, -51.5, 232.9), box(-51.5, 187.8, -50.0, 194.1),
                      box(-51.5, 226.5, -50.0, 232.9)])
ANNESSO_N = box(-62.0, 183.3, -54.5, 187.8)
ANNESSO_S = box(-62.0, 232.9, -54.4, 237.4)
SCALONE = box(-51.5, 198.9, -37.8, 221.7)
GIARDINO = unary_union([box(-37.8, 194.4, -2.2, 226.0), box(-27.4, 192.1, -9.7, 194.4),
                        box(-27.4, 226.0, -9.6, 228.3), box(-2.2, 208.5, -1.1, 211.8)])

# Le dieci lesene della facciata (y nel frame del campus). Le campate sono quelle della
# pianta: al piano nobile ogni campata ha la sua porta sul balcone (y 191,1, 196,2, 201,2,
# 205,8, 210,4, 214,9, 219,5, 224,5, 229,6), al terra le finestre e i tre portoni; le lesene
# stanno a metà fra due porte, quelle d'angolo a 80 cm dallo spigolo.
LESENE = [188.6, 193.67, 198.72, 203.5, 208.1, 212.65, 217.2, 222.0, 227.05, 232.1]
CAMPATE = ["finestra", "nicchia", "finestra", "portone", "portone", "portone", "finestra", "nicchia", "finestra"]
PADIGLIONI = (1, 7)    # le campate con il frontone e lo stemma, sporgenti di 45 cm
X_FRONTE = -66.4
Y0, Y1 = 187.8, 232.9

# Colori dalle foto: pietra grigio-beige, granito grigio, ferro scuro, vetri quasi neri.
PIETRA = "#D8D2C5"
PIETRA_CHIARA = "#E4DFD4"
PIETRA_OMBRA = "#BDB6A8"
GRANITO = "#8F908B"
INTONACO = "#E2DBCB"          # il corpo sul giardino e lo scalone, intonaco chiaro
FERRO = "#2D3135"
VETRO = "#3E4A55"
TELAIO = "#ECEBE6"
BRONZO = "#4B4A3F"
PIOMBO = "#8E9592"            # la cupoletta della torretta
LUCERNARIO = "#93A9B8"
SOTTOGRONDA = "#CFC7B6"
BANDIERE = {"europa": ["#1F3E93"], "italia": ["#1E8C45", "#F4F4F0", "#CE2B37"], "milano": ["#F4F4F0"]}


# ---------------------------------------------------------------- texture

def _testo(E):
    """La scritta del fregio come texture: lettere incise, scure, su pietra."""
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
    W, H = 4096, 160
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    font = None
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf", "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf"):
        try:
            font = ImageFont.truetype(f, 92)
            break
        except OSError:
            pass
    font = font or ImageFont.load_default()
    # "1863" sopra la sesta lesena da nord... come nella foto: tre gruppi sopra le campate 4-6.
    for txt, cx in (("1 8 6 3", 0.215), ("P O L I T E C N I C O", 0.5), ("D I   M I L A N O", 0.785)):
        w = d.textlength(txt, font=font)
        d.text((cx * W - w / 2, 28), txt, fill=255, font=font)
    a = np.asarray(img.filter(ImageFilter.GaussianBlur(1.2)), float) / 255
    base = np.array([0.85, 0.82, 0.77])
    rgb = base[None, None] * (1 - 0.55 * a)[..., None]
    gy, gx = np.gradient(-a)
    nrm = np.dstack([-gx * 4, gy * 4, np.ones_like(a)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    to8 = lambda x: Image.fromarray(np.clip(x * 255, 0, 255).astype(np.uint8))
    return to8(rgb), to8(nrm * 0.5 + 0.5)


def _coppi(E):
    """I coppi: canali lungo la falda ogni 16 cm, file sovrapposte ogni 40 cm, toni del cotto."""
    from PIL import Image
    rng = np.random.default_rng(1)
    size = 512                         # un metro
    y, x = np.mgrid[0:size, 0:size]
    u, v = x / size, y / size
    ch = (u * 6.25) % 1.0               # 6 canali e un quarto per metro: 16 cm
    row = (v * 2.5) % 1.0               # file da 40 cm
    height = np.sin(ch * math.pi) ** 0.6 * (0.75 + 0.25 * row)
    tone = rng.normal(0, 0.06, (3, 7))[(v * 2.5).astype(int) % 3, (u * 6.25).astype(int) % 7]
    base = np.array([0.70, 0.40, 0.27])
    rgb = base[None, None] * (0.78 + 0.32 * height + tone)[..., None]
    rgb[row < 0.04] *= 0.7
    gy, gx = np.gradient(height)
    nrm = np.dstack([-gx * 20, gy * 20, np.ones_like(height)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    to8 = lambda a: Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return to8(rgb), to8(nrm * 0.5 + 0.5)


def _registra(E):
    """Le texture di questo edificio, nella cache di esporta3d: le usano sia il glb sia l'USDZ."""
    if "mia0101_scritta" not in E._TEXTURES:
        E._TEXTURES["mia0101_scritta"] = _testo(E)
        E._TEXTURES["coppi"] = _coppi(E)
    E.TEX["mia0101_scritta"] = 1.0
    E.TEX["coppi"] = 1.0


# ---------------------------------------------------------------- attrezzi

class Facciata:
    """Un lato del fronte, con le coordinate della foto: t lungo la facciata da nord, z in
    altezza, d verso l'esterno."""

    def __init__(self, E, S, a, c):
        self.E, self.S = E, S
        L = math.dist(a, c)
        u = ((c[0] - a[0]) / L, (c[1] - a[1]) / L)
        n = (u[1], -u[0])               # a→c in senso antiorario: fuori a destra
        self.e = (a, c, u, n, L, 0.0)
        self.fori = []                  # le aperture, che il bugnato deve lasciare libere
        self.off = 0.0                  # di quanto è avanti il piano del muro (i padiglioni)

    def piatto(self, key, shape, d0, d1):
        self.E.panel(self.S, key, self.e, shape, d0 + self.off, d1 + self.off)

    def rett(self, key, t0, t1, z0, z1, d0, d1):
        self.piatto(key, box(min(t0, t1), min(z0, z1), max(t0, t1), max(z0, z1)), d0, d1)

    def punto(self, t, d, z):
        a, _, u, n, _, _ = self.e
        return np.array([a[0] + u[0] * t + n[0] * d, a[1] + u[1] * t + n[1] * d, z])


def arco(t0, t1, z0, zi):
    """Un'apertura ad arco a tutto sesto: rettangolo fino all'imposta zi, poi mezzo cerchio."""
    r = (t1 - t0) / 2
    c = Point((t0 + t1) / 2, zi).buffer(r, 32)
    return unary_union([box(t0, z0, t1, zi), c.intersection(box(t0, zi, t1, zi + r))])


def balaustri(F, key, t0, t1, z0, z1, d, passo=0.22):
    """Una fila di balaustri a clessidra stilizzata (due tronchi di piramide) fra t0 e t1."""
    n = max(1, int((t1 - t0) / passo))
    for i in range(n):
        t = t0 + (i + 0.5) * (t1 - t0) / n
        mid = z0 + (z1 - z0) * 0.45
        shape = Polygon([(t - 0.07, z0), (t + 0.07, z0), (t + 0.035, mid), (t + 0.08, mid + 0.12),
                         (t + 0.05, z1), (t - 0.05, z1), (t - 0.08, mid + 0.12), (t - 0.035, mid)])
        F.piatto(key, shape, d - 0.06, d + 0.06)


def balcone(F, t0, t1, z, sporto=0.65):
    """Il balcone del piano nobile: lastra su due mensole, balaustri, corrimano di pietra."""
    F.rett(PIETRA_CHIARA, t0, t1, z - 0.25, z, 0, sporto)
    for tm in (t0 + 0.25, t1 - 0.25):
        F.rett(PIETRA, tm - 0.12, tm + 0.12, z - 0.75, z - 0.25, 0, sporto * 0.7)
    balaustri(F, PIETRA_CHIARA, t0 + 0.2, t1 - 0.2, z, z + 0.8, sporto - 0.12)
    F.rett(PIETRA_CHIARA, t0, t1, z + 0.8, z + 0.95, sporto - 0.25, sporto)
    for tm in (t0, t1 - 0.2):                 # i pilastrini alle estremità
        F.rett(PIETRA_CHIARA, tm, tm + 0.2, z, z + 0.8, sporto - 0.22, sporto)


def finestra_arco(F, t0, t1, z0, zi, telaio=TELAIO, cornice=True):
    """Finestra ad arco con la cornice modanata e la chiave, il vetro scuro e la griglia
    bianca dei serramenti come nelle foto (montanti e traversi, raggiera nella lunetta)."""
    s = arco(t0, t1, z0, zi)
    F.fori.append(s.buffer(0.3 if cornice else 0.06))
    F.piatto(VETRO, s, 0.0, 0.03)
    w, r = t1 - t0, (t1 - t0) / 2
    bars = []
    for k in (1, 2, 3):
        t = t0 + w * k / 4
        bars.append(box(t - 0.035, z0, t + 0.035, zi + r))
    for z in np.arange(z0 + 0.55, zi, 0.55):
        bars.append(box(t0, z - 0.03, t1, z + 0.03))
    bars.append(box(t0, zi - 0.05, t1, zi + 0.05))
    F.piatto(telaio, unary_union(bars).intersection(s), 0.0, 0.06)
    F.piatto(telaio, s.buffer(0.06).difference(s), 0.0, 0.06)
    if cornice:
        F.piatto(PIETRA_CHIARA, s.buffer(0.28).difference(s.buffer(0.06)).difference(box(t0 - 1, z0 - 1, t1 + 1, z0)), 0.0, 0.14)
        tc = (t0 + t1) / 2                     # la chiave dell'arco
        F.piatto(PIETRA_CHIARA, Polygon([(tc - 0.18, zi + r - 0.05), (tc + 0.18, zi + r - 0.05),
                                         (tc + 0.26, zi + r + 0.45), (tc - 0.26, zi + r + 0.45)]), 0.0, 0.2)


def finestra_rett(F, t0, t1, z0, z1, inferriata=False, timpano=False):
    """Finestra rettangolare: vetro, telaio, cornice; inferriata al terra, timpano piatto sopra."""
    F.rett(VETRO, t0, t1, z0, z1, 0.0, 0.03)
    F.fori.append(box(t0 - 0.3, z0 - 0.2, t1 + 0.3, z1 + (0.4 if timpano else 0.18)))
    if inferriata:
        for k in range(1, int((t1 - t0) / 0.14)):
            t = t0 + k * (t1 - t0) / int((t1 - t0) / 0.14)
            F.rett(FERRO, t - 0.015, t + 0.015, z0, z1, 0.0, 0.12)
        for z in np.linspace(z0 + 0.3, z1 - 0.3, 4):
            F.rett(FERRO, t0, t1, z - 0.02, z + 0.02, 0.0, 0.12)
    else:
        F.rett(TELAIO, (t0 + t1) / 2 - 0.035, (t0 + t1) / 2 + 0.035, z0, z1, 0.0, 0.06)
        F.rett(TELAIO, t0, t1, z0 + (z1 - z0) * 0.7 - 0.03, z0 + (z1 - z0) * 0.7 + 0.03, 0.0, 0.06)
    f = box(t0, z0, t1, z1)
    F.piatto(PIETRA_CHIARA, f.buffer(0.18, join_style=2).difference(f), 0.0, 0.12)
    F.rett(PIETRA_CHIARA, t0 - 0.3, t1 + 0.3, z0 - 0.2, z0, 0.0, 0.18)        # davanzale
    if timpano:
        F.rett(PIETRA_CHIARA, t0 - 0.35, t1 + 0.35, z1 + 0.18, z1 + 0.4, 0.0, 0.25)


def bugnato(F, t0, t1, z0, z1, alto=0.45, giunto=0.06, sporto=0.05, key=PIETRA):
    """Il bugnato liscio del terra: corsi orizzontali staccati da un giunto in ombra."""
    fori = unary_union(F.fori) if F.fori else Polygon()
    z = z0
    while z < z1 - 0.1:
        F.piatto(key, box(t0, z + giunto, t1, min(z1, z + alto)).difference(fori), 0.0, sporto)
        z += alto


def sfera(S, key, p, r):
    m = trimesh.creation.icosphere(subdivisions=2, radius=r)
    m.apply_translation(p)
    S.solid(key, m)


def obelisco(S, E, x, y, z0, h, lato):
    """Un obelisco di pietra su un dado, con la sfera in cima."""
    q = lambda s, z: [(x - s, y - s, z), (x + s, y - s, z), (x + s, y + s, z), (x - s, y + s, z)]
    S.solid(PIETRA_CHIARA, E.hexa(q(lato * 0.75, z0), q(lato * 0.75, z0 + 0.7)))
    S.solid(PIETRA_CHIARA, E.hexa(q(lato * 0.5, z0 + 0.7), q(lato * 0.12, z0 + h)))
    sfera(S, PIETRA_CHIARA, (x, y, z0 + h + 0.12), 0.14)


def falda(S, pts, uvs, want):
    """Una falda di coppi: triangoli con le uv in metri, u lungo la gronda, v lungo la falda."""
    for i in range(1, len(pts) - 1):
        S.tri("coppi", [pts[0], pts[i], pts[i + 1]], want, [uvs[0], uvs[i], uvs[i + 1]])


def padiglione(S, x0, y0, x1, y1, z, pend=0.5, sporto=0.6, sotto=SOTTOGRONDA):
    """Un tetto a padiglione su un rettangolo: due falde a trapezio, due a triangolo, il colmo
    lungo il lato lungo. Torna la quota del colmo."""
    x0, y0, x1, y1 = x0 - sporto, y0 - sporto, x1 + sporto, y1 + sporto
    W, D = x1 - x0, y1 - y0
    h = min(W, D) / 2 * pend
    zc = z + h
    if W >= D:
        r0, r1 = (x0 + D / 2, (y0 + y1) / 2, zc), (x1 - D / 2, (y0 + y1) / 2, zc)
    else:
        r0, r1 = ((x0 + x1) / 2, y0 + W / 2, zc), ((x0 + x1) / 2, y1 - W / 2, zc)
    A, B, C, D_ = (x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)
    s = math.hypot(min(W, D) / 2, h)          # lunghezza della falda
    lati = [(A, B, (0, -1)), (B, C, (1, 0)), (C, D_, (0, 1)), (D_, A, (-1, 0))]
    for p, q, nn in lati:
        # i punti del colmo che stanno su questa falda
        top = [r for r in (r0, r1) if abs((r[0] - p[0]) * nn[0] + (r[1] - p[1]) * nn[1] + min(W, D) / 2) < 1e-6]
        L = math.dist(p[:2], q[:2])
        ux, uy = (q[0] - p[0]) / L, (q[1] - p[1]) / L
        uv = lambda r: ((r[0] - p[0]) * ux + (r[1] - p[1]) * uy, s * (1 - (r[2] - z) / h) if h else 0)
        top = sorted(top, key=lambda r: (r[0] - p[0]) * ux + (r[1] - p[1]) * uy, reverse=True)
        pts = [p, q] + top
        want = np.array([nn[0] * h, nn[1] * h, min(W, D) / 2])
        falda(S, pts, [uv(r) for r in pts], want)
    S.quad(sotto, [A, B, C, D_], (0, 0, -1))
    return zc


# ---------------------------------------------------------------- il fronte

def fronte(E, S):
    """La facciata su Piazza Leonardo da Vinci, campata per campata come nella foto."""
    a, c = (X_FRONTE, Y0), (X_FRONTE, Y1)
    # Lungo x = -66,4 da nord a sud la normale esterna è -x: a→c va da sud a nord in un anello
    # antiorario (y verso sud), quindi si parte da sud e si conta t al contrario.
    F = Facciata(E, S, c, a)
    L = Y1 - Y0
    T = lambda y: Y1 - y                   # y del campus → t sulla faccia, che parte da sud
    pil = [T(y) for y in LESENE]
    # Gradinata e zoccolo di granito lungo tutto il fronte.
    for i in range(4):
        F.rett(GRANITO, T(LESENE[1] + 0.3), T(LESENE[8] - 0.3), 0, GRADINI - i * 0.15, 0, 0.45 * (4 - i) + 0.3)
    F.rett(GRANITO, -0.4, L + 0.4, 0, ZOCCOLO, 0, 0.12)
    # Le campate: muro, aperture, balconi.
    for i, kind in enumerate(CAMPATE):
        t0, t1 = sorted((pil[i], pil[i + 1]))
        sp = 0.45 if i in PADIGLIONI else 0.0
        tc = (t0 + t1) / 2
        F.fori = []
        if kind == "portone":
            s = arco(tc - 1.15, tc + 1.15, GRADINI, 4.05)
            F.fori.append(s.buffer(0.32))
        elif kind == "nicchia":
            s = arco(tc - 1.0, tc + 1.0, ZOCCOLO + 0.3, 4.3)
            F.fori.append(s.buffer(0.25))
        F.off = sp
        if kind == "portone":
            F.piatto(FERRO, s, 0, 0.08)
            griglia = unary_union([box(tc + dt - 0.03, GRADINI, tc + dt + 0.03, 5.3) for dt in np.arange(-1.0, 1.05, 0.25)]
                                  + [box(tc - 1.2, z - 0.03, tc + 1.2, z + 0.03) for z in (1.6, 2.6, 3.6, 4.05)]).intersection(s)
            F.piatto("#4A5056", griglia, 0.08, 0.12)
            F.piatto(PIETRA_CHIARA, s.buffer(0.32).difference(s.buffer(0.02)).difference(box(t0, -1, t1, GRADINI + 0.0)), 0, 0.16)
        elif kind == "nicchia":
            F.piatto(PIETRA_OMBRA, s, -0.4, -0.38)
            F.piatto(PIETRA_CHIARA, s.buffer(0.25).difference(s), 0, 0.14)
            # la statua di bronzo sul piedistallo
            p = F.punto(tc, sp + 0.9, 0)
            S.solid(GRANITO, trimesh.creation.box((1.0, 1.0, 1.6)).apply_translation((p[0], p[1], GRADINI + 0.8)))
            S.solid(BRONZO, trimesh.creation.cylinder(0.28, 1.6, 12).apply_translation((p[0], p[1], GRADINI + 2.4)))
            S.solid(BRONZO, trimesh.creation.cylinder(0.2, 0.25, 10).apply_translation((p[0], p[1], GRADINI + 3.3)))
            sfera(S, BRONZO, (p[0], p[1], GRADINI + 3.6), 0.17)
        else:
            finestra_rett(F, tc - 0.75, tc + 0.75, 2.5, 5.0, inferriata=True)
        # piano nobile
        balcone(F, tc - 1.5, tc + 1.5, NOBILE + 0.05)
        if i in PADIGLIONI:
            finestra_rett(F, tc - 0.8, tc + 0.8, NOBILE + 0.3, 10.7, timpano=True)
            F.rett(PIETRA_CHIARA, tc - 1.1, tc + 1.1, 11.1, 12.1, 0, 0.08)     # la lapide
            # lo stemma nel fregio: un ovale in un cartiglio
            F.piatto(PIETRA_CHIARA, Point(tc, 13.9).buffer(0.9, 24).union(box(tc - 1.2, 13.0, tc + 1.2, 13.4)), 0, 0.3)
            F.piatto(PIETRA_OMBRA, Point(tc, 13.95).buffer(0.55, 24), 0.3, 0.35)
        else:
            finestra_arco(F, tc - 1.0, tc + 1.0, NOBILE + 0.3, 10.9)
        bugnato(F, t0, t1, ZOCCOLO, NOBILE - 0.3)
        F.rett(PIETRA_CHIARA, t0 - (0.7 if sp else 0), t1 + (0.7 if sp else 0), NOBILE - 0.3, NOBILE, 0, 0.25)   # la fascia
        F.off = 0.0
        if sp:      # il risalto del padiglione, con le sue aperture
            fori = unary_union(F.fori)
            F.piatto(PIETRA, box(t0 - 0.7, ZOCCOLO, t1 + 0.7, FREGIO).difference(fori), 0, sp)
            F.piatto(PIETRA_OMBRA, fori.intersection(box(t0 - 0.7, ZOCCOLO, t1 + 0.7, FREGIO)).buffer(-0.02), -0.01, 0.0)
        F.fori = []
    # Le lesene d'ordine gigante, con base e capitello, e il risalto dei padiglioni.
    for i, t in enumerate(pil):
        sp = 0.45 if (i in PADIGLIONI or i - 1 in PADIGLIONI) else 0.0
        w = 0.7
        F.rett(PIETRA, t - w, t + w, ZOCCOLO, CAPITELLO[0], sp, sp + 0.35)
        F.rett(PIETRA_CHIARA, t - w - 0.12, t + w + 0.12, ZOCCOLO, ZOCCOLO + 0.5, sp, sp + 0.47)
        F.rett(PIETRA_CHIARA, t - w - 0.15, t + w + 0.15, NOBILE - 0.3, NOBILE, sp, sp + 0.5)
        # il capitello: un tronco di piramide rovesciato con le volute (due dischi)
        F.piatto(PIETRA_CHIARA, Polygon([(t - w, CAPITELLO[0]), (t + w, CAPITELLO[0]), (t + w + 0.3, CAPITELLO[1]),
                                         (t - w - 0.3, CAPITELLO[1])]), sp, sp + 0.5)
        for dt in (-w - 0.05, w + 0.05):
            F.piatto(PIETRA_CHIARA, Point(t + dt, CAPITELLO[1] - 0.25).buffer(0.2, 12), sp + 0.3, sp + 0.55)
    # Fregio con la scritta, cornicione su mensole, balaustra con sfere e pilastrini.
    F.rett(PIETRA, 0, L, CAPITELLO[1], FREGIO, 0, 0.35)
    _scritta(S, F, T(LESENE[3]), T(LESENE[6]), 13.45, 14.3, 0.36)
    F.rett(PIETRA_CHIARA, -0.6, L + 0.6, FREGIO, FREGIO + 0.25, 0, 0.6)
    for t in np.arange(0.4, L, 0.9):                                  # le mensole
        F.piatto(PIETRA_CHIARA, Polygon([(t - 0.15, FREGIO + 0.25), (t + 0.15, FREGIO + 0.25), (t + 0.15, CORNICE - 0.2),
                                         (t - 0.15, CORNICE - 0.2)]), 0.6, 0.95)
    F.rett(PIETRA_CHIARA, -1.0, L + 1.0, CORNICE - 0.2, CORNICE, 0, 1.05)
    F.rett(PIETRA, 0, L, CORNICE, CORNICE + 0.4, -0.2, 0.15)          # lo zoccolo della balaustra
    for i in range(len(pil) - 1):
        t0, t1 = sorted((pil[i], pil[i + 1]))
        balaustri(F, PIETRA_CHIARA, t0 + 0.6, t1 - 0.6, CORNICE + 0.4, BALAUSTRA - 0.35, 0.0)
        F.rett(PIETRA_CHIARA, t0, t1, BALAUSTRA - 0.35, BALAUSTRA - 0.15, -0.15, 0.15)
    for i, t in enumerate(pil):
        F.rett(PIETRA_CHIARA, t - 0.6, t + 0.6, CORNICE + 0.4, BALAUSTRA, -0.2, 0.25)
        p = F.punto(t, 0.02, 0)
        if i in (1, 2, 7, 8):                     # obelischi alti sui padiglioni
            obelisco(S, E, p[0], p[1], BALAUSTRA, 4.3, 0.55)
        elif i in (0, 9):                         # più bassi sugli spigoli
            obelisco(S, E, p[0], p[1], BALAUSTRA, 2.1, 0.45)
        else:
            sfera(S, PIETRA_CHIARA, (p[0], p[1], BALAUSTRA + 0.35), 0.32)
    # I frontoni ricurvi sopra i padiglioni, con lo stemma sotto.
    for i in PADIGLIONI:
        t0, t1 = sorted((pil[i], pil[i + 1]))
        tc = (t0 + t1) / 2
        r = 4.6
        zc = CORNICE + 1.55 - r
        anello = Point(tc, zc).buffer(r, 64).difference(Point(tc, zc).buffer(r - 0.45, 64))
        anello = anello.intersection(box(t0 - 0.8, CORNICE, t1 + 0.8, CORNICE + 3))
        F.piatto(PIETRA_CHIARA, anello, 0.3, 1.1)
        F.piatto(PIETRA, Point(tc, zc).buffer(r - 0.45, 64).intersection(box(t0 - 0.8, CORNICE, t1 + 0.8, CORNICE + 3)), 0.3, 0.6)
    # Le bandiere sui balconi: Europa (campata 2), Italia (5), Milano (8).
    for i, nome in ((1, "europa"), (4, "italia"), (7, "milano")):
        t0, t1 = sorted((pil[i], pil[i + 1]))
        tc = (t0 + t1) / 2 + (0.9 if i != 4 else 0)
        p0 = F.punto(tc, 0.6, NOBILE + 1.0)
        p1 = F.punto(tc, 2.1, NOBILE + 3.6)
        S.solid(FERRO, trimesh.creation.cylinder(0.035, segment=[p0, p1], sections=6))
        cols = BANDIERE[nome]
        for j, col in enumerate(cols):
            q0 = p1 + (p0 - p1) * (j / len(cols)) * 0.0
            # il drappo pende dall'asta: un rettangolo verticale lungo l'asta, a strisce
            a_ = p1 - (p1 - p0) * (0.05 + 0.5 * j / len(cols))
            b_ = p1 - (p1 - p0) * (0.05 + 0.5 * (j + 1) / len(cols))
            S.solid(col, E.hexa([a_ + (0, 0.02, 0), b_ + (0, 0.02, 0), b_ + (0, 0.02, -1.6), a_ + (0, 0.02, -1.6)],
                                [a_ - (0, 0.02, 0), b_ - (0, 0.02, 0), b_ - (0, 0.02, -1.6), a_ - (0, 0.02, -1.6)]))
        if nome == "milano":       # la croce rossa sul bianco
            a_, b_ = p1 - (p1 - p0) * 0.05, p1 - (p1 - p0) * 0.55
            m_ = (a_ + b_) / 2
            S.solid("#C8102E", E.hexa([a_ + (0, 0.03, -0.65), b_ + (0, 0.03, -0.65), b_ + (0, 0.03, -0.95), a_ + (0, 0.03, -0.95)],
                                      [a_ - (0, 0.03, -0.65), b_ - (0, 0.03, -0.65), b_ - (0, 0.03, -0.95), a_ - (0, 0.03, -0.95)]))
            S.solid("#C8102E", E.hexa([m_ + (0.0, 0.03, 0) + (p1 - p0) * 0.04, m_ + (0, 0.03, 0) - (p1 - p0) * 0.04, m_ + (0, 0.03, -1.6) - (p1 - p0) * 0.04, m_ + (0, 0.03, -1.6) + (p1 - p0) * 0.04],
                                      [m_ - (0.0, 0.03, 0) + (p1 - p0) * 0.04, m_ - (0, 0.03, 0) - (p1 - p0) * 0.04, m_ - (0, 0.03, -1.6) - (p1 - p0) * 0.04, m_ - (0, 0.03, -1.6) + (p1 - p0) * 0.04]))


def _scritta(S, F, t0, t1, z0, z1, d):
    """La lastra con la scritta del fregio: uv da 0 a 1, la texture non si ripete."""
    t0, t1 = sorted((t0, t1))
    p = [F.punto(t0, d, z0), F.punto(t1, d, z0), F.punto(t1, d, z1), F.punto(t0, d, z1)]
    # t cresce verso nord, la scritta si legge da nord a sud: u = 1 a t0.
    uv = [(1, 0), (0, 0), (0, 1), (1, 1)]
    n = F.e[3]
    S.quad("mia0101_scritta", p, (n[0], n[1], 0), uv)


# ---------------------------------------------------------------- gli altri lati

def finestre_pianta(E, b, piano, anello, near=0.9):
    """Le finestre che la pianta disegna su un lato dell'anello: {indice del lato: [(t0, t1)]}."""
    f = E.plan_floor(b, piano)
    out = {}
    es = E.edges(anello)
    for s in f.get("linee", {}).get("finestre", []):
        p, q = s[:2], s[2:4]
        if math.dist(p, q) < 0.5:
            continue
        mid = Point((p[0] + q[0]) / 2, (p[1] + q[1]) / 2)
        best = None
        for i, (a, c, u, n, L, _) in enumerate(es):
            seg = LineString([a, c])
            if seg.distance(mid) > near:
                continue
            dv = ((q[0] - p[0]) / math.dist(p, q), (q[1] - p[1]) / math.dist(p, q))
            if abs(dv[0] * u[0] + dv[1] * u[1]) < 0.9:
                continue
            t0 = (p[0] - a[0]) * u[0] + (p[1] - a[1]) * u[1]
            t1 = (q[0] - a[0]) * u[0] + (q[1] - a[1]) * u[1]
            t0, t1 = max(0.3, min(t0, t1)), min(L - 0.3, max(t0, t1))
            if t1 - t0 > 0.5 and (best is None or seg.distance(mid) < best[0]):
                best = (seg.distance(mid), i, t0, t1)
        if best:
            out.setdefault(best[1], []).append((best[2], best[3]))
    # finestre vicine (i due battenti disegnati come due tratti) diventano una
    for i, spans in out.items():
        spans.sort()
        merged = [list(spans[0])]
        for t0, t1 in spans[1:]:
            if t0 - merged[-1][1] < 0.35:
                merged[-1][1] = max(merged[-1][1], t1)
            else:
                merged.append([t0, t1])
        out[i] = [(t0, t1) for t0, t1 in merged]
    return out


def lati(E, S, b, anello, corpo):
    """Le facciate verso i cortili e il giardino, con le finestre dove le disegna la pianta.

    corpo(i, e) dice di chi è il lato: "fronte" (pietra, ordine di lesene, archi al piano
    nobile), "giardino" e "scalone" (intonaco chiaro su un basamento di pietra bocciardata,
    archi al terra, finestre con timpano al primo, piccole al secondo), "annesso", o None.
    """
    es = E.edges(anello)
    per_piano = {p: finestre_pianta(E, b, p, anello) for p in Z_PIANI}
    for i, e in enumerate(es):
        a, c, u, n, L, _ = e
        kind = corpo(i, e)
        if kind is None:
            continue
        F = Facciata(E, S, a, c)
        if kind == "fronte":
            F.rett(GRANITO, 0, L, 0, ZOCCOLO, 0, 0.12)
            F.rett(PIETRA_CHIARA, 0, L, NOBILE - 0.3, NOBILE, 0, 0.25)
            F.rett(PIETRA, 0, L, CAPITELLO[1], FREGIO, 0, 0.35)
            F.rett(PIETRA_CHIARA, -0.6, L + 0.6, FREGIO, FREGIO + 0.25, 0, 0.6)
            F.rett(PIETRA_CHIARA, -1.0, L + 1.0, CORNICE - 0.2, CORNICE, 0, 1.05)
            for t in np.arange(0.4, L, 0.9):
                F.rett(PIETRA_CHIARA, t - 0.15, t + 0.15, FREGIO + 0.25, CORNICE - 0.2, 0.6, 0.95)
            # le lesene agli spigoli e fra le finestre del piano nobile
            spans = per_piano["MIA0101001"].get(i, [])
            ts = sorted({0.7, L - 0.7} | {round((s0 + s1) / 2 + d, 2) for (s0, s1), d in
                                           ((s, dd) for s in spans for dd in (-1.9, 1.9)) if 1.2 < (s0 + s1) / 2 + d < L - 1.2})
            for t in ts:
                F.rett(PIETRA, t - 0.6, t + 0.6, ZOCCOLO, CAPITELLO[0], 0, 0.3)
                F.rett(PIETRA_CHIARA, t - 0.75, t + 0.75, CAPITELLO[0], CAPITELLO[1], 0, 0.42)
            for t0, t1 in per_piano["MIA0101000"].get(i, []):
                tc = (t0 + t1) / 2
                finestra_rett(F, tc - 0.7, tc + 0.7, 2.5, 4.9, inferriata=True)
            for t0, t1 in spans:
                tc = (t0 + t1) / 2
                balcone(F, tc - 1.4, tc + 1.4, NOBILE + 0.05)
                finestra_arco(F, tc - 0.95, tc + 0.95, 7.25, 10.9)
            # balaustra sul cornicione
            F.rett(PIETRA, 0, L, CORNICE, CORNICE + 0.4, -0.2, 0.15)
            balaustri(F, PIETRA_CHIARA, 0.5, L - 0.5, CORNICE + 0.4, BALAUSTRA - 0.35, 0.0)
            F.rett(PIETRA_CHIARA, 0, L, BALAUSTRA - 0.35, BALAUSTRA - 0.15, -0.15, 0.15)
            for t in np.linspace(0.3, L - 0.3, max(2, round(L / 4.8) + 1)):
                F.rett(PIETRA_CHIARA, t - 0.3, t + 0.3, CORNICE + 0.4, BALAUSTRA, -0.2, 0.2)
                p = F.punto(t, 0.0, 0)
                sfera(S, PIETRA_CHIARA, (p[0], p[1], BALAUSTRA + 0.3), 0.28)
            bugnato(F, 0, L, ZOCCOLO, NOBILE - 0.3)
        elif kind in ("giardino", "scalone"):
            F.rett("cemento", 0, L, 0, ZOCCOLO, 0, 0.1)
            F.rett(PIETRA_CHIARA, 0, L, NOBILE - 0.3, NOBILE, 0, 0.18)
            F.rett(PIETRA_CHIARA, 0, L, Z_PIANI["MIA0101002"] - 0.2, Z_PIANI["MIA0101002"], 0, 0.12)
            F.rett(PIETRA_CHIARA, -0.6, L + 0.6, GRONDA - 0.6, GRONDA, 0, 0.45)
            for t0, t1 in per_piano["MIA0101000"].get(i, []):
                tc, w = (t0 + t1) / 2, min(1.8, max(1.2, t1 - t0))
                finestra_arco(F, tc - w / 2, tc + w / 2, 2.0, 4.2)
            for t0, t1 in per_piano["MIA0101001"].get(i, []):
                tc, w = (t0 + t1) / 2, min(1.8, max(1.1, t1 - t0))
                finestra_arco(F, tc - w / 2, tc + w / 2, 7.0, 9.6)
                F.rett(PIETRA_CHIARA, tc - w / 2 - 0.3, tc + w / 2 + 0.3, 6.8, 7.0, 0, 0.15)
            if kind == "giardino":
                # il secondo piano sta nell'attico sopra la fascia: finestrelle quadrate
                F.rett(PIETRA_CHIARA, 0, L, 11.2, 11.6, 0, 0.2)
                for t0, t1 in per_piano["MIA0101002"].get(i, []):
                    tc = (t0 + t1) / 2
                    finestra_rett(F, tc - 0.5, tc + 0.5, 12.4, 13.6)
            if abs(a[0] - c[0]) < 0.05 and a[0] > -1.5:       # l'avancorpo sul giardino: il portone
                s_ = arco(L / 2 - 1.1, L / 2 + 1.1, GRADINI, 3.4)
                F.fori.append(s_.buffer(0.3))
                F.piatto(FERRO, s_, 0, 0.06)
                F.piatto(PIETRA_CHIARA, s_.buffer(0.3).difference(s_).difference(box(-1, -1, L + 1, GRADINI)), 0, 0.15)
                balcone(F, L / 2 - 1.4, L / 2 + 1.4, NOBILE + 0.05)
            F.rett("#5E6368", -0.6, L + 0.6, GRONDA - 0.05, GRONDA + 0.2, 0.45, 0.7)     # il canale
            bugnato(F, 0, L, ZOCCOLO, NOBILE - 0.3, alto=0.5, key=INTONACO)
        elif kind == "annesso":
            F.rett(GRANITO, 0, L, 0, ZOCCOLO, 0, 0.12)
            F.rett(PIETRA_CHIARA, 0, L, NOBILE - 0.3, NOBILE, 0, 0.25)
            F.rett(PIETRA_CHIARA, -0.4, L + 0.4, ANNESSI - 0.4, ANNESSI, 0, 0.5)
            F.rett(PIETRA, 0, L, ANNESSI, ANNESSI + 0.3, -0.2, 0.1)
            balaustri(F, PIETRA_CHIARA, 0.4, L - 0.4, ANNESSI + 0.3, ANNESSI + 1.0, 0.0)
            F.rett(PIETRA_CHIARA, 0, L, ANNESSI + 1.0, ANNESSI + 1.15, -0.15, 0.12)
            if L > 4:
                finestra_arco(F, L / 2 - 0.8, L / 2 + 0.8, 7.0, 9.4)
                finestra_rett(F, L / 2 - 0.6, L / 2 + 0.6, 2.5, 4.6, inferriata=True)
            bugnato(F, 0, L, ZOCCOLO, NOBILE - 0.3)


# ---------------------------------------------------------------- tetti

def tetti(E, S):
    """I tetti come nell'ortofoto."""
    # Il fronte: terrazza piana dietro la balaustra, coppi a padiglione sopra l'Aula Magna.
    E.prisma(S, "#D9D7D2", E.ring_ccw(FRONTE.buffer(-0.2, join_style=2)), CORNICE - 0.1, CORNICE + 0.05)
    padiglione(S, -64.0, 198.3, -54.3, 221.3, CORNICE + 0.05, pend=0.3, sporto=0.0)
    # La torretta tonda a sud dell'Aula Magna, sopra la scala a chiocciola della pianta.
    cx, cy, r = -55.6, 220.4, 1.9
    S.solid(PIETRA, trimesh.creation.cylinder(r, BALAUSTRA + 0.6 - CORNICE, 32).apply_translation((cx, cy, (CORNICE + BALAUSTRA + 0.6) / 2)))
    S.solid(PIETRA_CHIARA, trimesh.creation.cylinder(r + 0.25, 0.3, 32).apply_translation((cx, cy, BALAUSTRA + 0.75)))
    for k in range(8):
        ang = k * math.pi / 4
        S.solid(VETRO, trimesh.creation.box((0.5, 0.06, 1.1)).apply_transform(
            trimesh.transformations.rotation_matrix(ang + math.pi / 2, (0, 0, 1))).apply_translation(
            (cx + math.cos(ang) * (r + 0.01), cy + math.sin(ang) * (r + 0.01), CORNICE + 1.4)))
    cup = trimesh.creation.icosphere(subdivisions=3, radius=r + 0.1)
    cup.vertices[:, 2] = np.maximum(cup.vertices[:, 2], 0) * 0.65
    S.solid(PIOMBO, cup.apply_translation((cx, cy, BALAUSTRA + 0.9)))
    sfera(S, PIOMBO, (cx, cy, BALAUSTRA + 0.9 + (r + 0.1) * 0.65 + 0.2), 0.18)
    # Gli annessi: piani, dietro la loro balaustra.
    for g in (ANNESSO_N, ANNESSO_S):
        E.prisma(S, "#D9D7D2", E.ring_ccw(g.buffer(-0.15, join_style=2)), ANNESSI - 0.1, ANNESSI + 0.05)
    # Lo scalone: padiglione sopra lo scalone d'onore, piano intorno.
    E.prisma(S, "#C9C6BF", E.ring_ccw(SCALONE), GRONDA - 0.3, GRONDA)
    padiglione(S, -51.0, 202.2, -40.6, 217.4, GRONDA, pend=0.5, sporto=0.2)
    # Il corpo sul giardino: un anello di falde intorno al lucernario, i due avancorpi.
    xo0, yo0, xo1, yo1 = -37.8, 194.4, -2.2, 226.0
    xi0, yi0, xi1, yi1 = -31.6, 204.0, -14.8, 216.3
    padiglione(S, xo0, yo0, xo1, yi0, GRONDA, sporto=0.7)
    padiglione(S, xo0, yi1, xo1, yo1, GRONDA, sporto=0.7)
    padiglione(S, xo0, yo0, xi0, yo1, GRONDA, sporto=0.7)
    padiglione(S, xi1, yo0, xo1, yo1, GRONDA, sporto=0.7)
    padiglione(S, -27.4, 192.1, -9.7, 192.1 + (yi0 - yo0), GRONDA, sporto=0.7)
    padiglione(S, -27.4, 228.3 - (yo1 - yi1), -9.6, 228.3, GRONDA, sporto=0.7)
    # il lucernario: vetro su un telaio bianco, due file di cinque campi
    E.prisma(S, SOTTOGRONDA, [(xi0, yi0), (xi1, yi0), (xi1, yi1), (xi0, yi1)], GRONDA - 0.4, GRONDA + 0.2)
    E.prisma(S, LUCERNARIO, [(xi0 + 0.3, yi0 + 0.3), (xi1 - 0.3, yi0 + 0.3), (xi1 - 0.3, yi1 - 0.3), (xi0 + 0.3, yi1 - 0.3)], GRONDA + 0.2, GRONDA + 0.65)
    for k in range(6):
        x = xi0 + 0.3 + (xi1 - xi0 - 0.6) * k / 5
        E.trave(S, TELAIO, (x, yi0 + 0.3, GRONDA + 0.7), (x, yi1 - 0.3, GRONDA + 0.7), 0.18)
    for y in (yi0 + 0.3, (yi0 + yi1) / 2, yi1 - 0.3):
        E.trave(S, TELAIO, (xi0 + 0.3, y, GRONDA + 0.7), (xi1 - 0.3, y, GRONDA + 0.7), 0.25)
    # L'orologio sul lato del giardino (la foto del Politecnico dal giardino): un'edicola sul
    # filo della facciata, sopra l'avancorpo centrale, con il quadrante, le lesene, il
    # frontone ricurvo e la banderuola di ferro; dietro, la terrazza bianca dell'ortofoto.
    E.prisma(S, "#E6E4DE", [(-10.0, 207.4), (-2.2, 207.4), (-2.2, 211.6), (-10.0, 211.6)], GRONDA - 0.2, GRONDA + 0.6)
    y0, y1, x0, x1 = 208.0, 212.2, -4.4, -1.1
    E.prisma(S, INTONACO, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], GRONDA - 0.5, GRONDA + 3.6)
    F = Facciata(E, S, (x1, y1), (x1, y0))
    W = y1 - y0
    for t in (0.25, W - 0.25):
        F.rett(PIETRA_CHIARA, t - 0.25, t + 0.25, GRONDA - 0.5, GRONDA + 3.2, 0, 0.18)
    F.piatto("#F4F2EC", Point(W / 2, GRONDA + 1.6).buffer(1.0, 32), 0.0, 0.08)
    F.piatto(FERRO, Point(W / 2, GRONDA + 1.6).buffer(1.0, 32).difference(Point(W / 2, GRONDA + 1.6).buffer(0.9, 32)), 0.0, 0.1)
    for k in range(12):                                   # le ore
        ang = k * math.pi / 6
        F.piatto(FERRO, Point(W / 2 + math.cos(ang) * 0.78, GRONDA + 1.6 + math.sin(ang) * 0.78).buffer(0.05, 6), 0.08, 0.1)
    F.rett(FERRO, W / 2 - 0.03, W / 2 + 0.03, GRONDA + 1.6, GRONDA + 2.3, 0.08, 0.11)
    F.rett(FERRO, W / 2 - 0.5, W / 2, GRONDA + 1.57, GRONDA + 1.63, 0.08, 0.11)
    F.rett(PIETRA_CHIARA, -0.3, W + 0.3, GRONDA + 3.2, GRONDA + 3.6, 0, 0.35)
    cen = Point(W / 2, GRONDA + 3.6 - 2.4)
    sopra = box(-0.3, GRONDA + 3.6, W + 0.3, GRONDA + 6)
    F.piatto(PIETRA_CHIARA, cen.buffer(3.3, 48).difference(cen.buffer(2.95, 48)).intersection(sopra), 0, 0.35)
    F.piatto(INTONACO, cen.buffer(2.95, 48).intersection(sopra), -3.0, 0.1)
    p = F.punto(W / 2, 0.15, 0)
    S.solid(FERRO, trimesh.creation.cylinder(0.04, segment=[(p[0], p[1], GRONDA + 4.3), (p[0], p[1], GRONDA + 6.2)], sections=6))
    sfera(S, FERRO, (p[0], p[1], GRONDA + 4.9), 0.22)
    S.solid(FERRO, trimesh.creation.box((0.04, 0.9, 0.3)).apply_translation((p[0], p[1] + 0.3, GRONDA + 5.7)))


# ---------------------------------------------------------------- l'edificio

def guscio(b, E):
    """({colore: mesh}, quota del tetto) dell'Edificio 1."""
    _registra(E)
    S = E.Solidi()
    tutto = unary_union([FRONTE, ANNESSO_N, ANNESSO_S, SCALONE, GIARDINO])
    # I volumi pieni.
    E.prisma(S, PIETRA, E.ring_ccw(FRONTE), 0, CORNICE - 0.1)
    for g in (ANNESSO_N, ANNESSO_S):
        E.prisma(S, PIETRA, E.ring_ccw(g), 0, ANNESSI)
    E.prisma(S, INTONACO, E.ring_ccw(SCALONE.difference(FRONTE.buffer(0.01))), 0, GRONDA - 0.3)
    E.prisma(S, INTONACO, E.ring_ccw(GIARDINO), 0, GRONDA)
    fronte(E, S)
    anello = E.ring_ccw(tutto)

    def corpo(i, e):
        a, c, u, n, L, _ = e
        mid = Point((a[0] + c[0]) / 2 + n[0] * -0.1, (a[1] + c[1]) / 2 + n[1] * -0.1)
        if abs(a[0] - X_FRONTE) < 0.05 and abs(c[0] - X_FRONTE) < 0.05:
            return None                              # la facciata principale, fatta a mano
        if ANNESSO_N.contains(mid) or ANNESSO_S.contains(mid):
            return "annesso"
        if FRONTE.contains(mid):
            return "fronte"
        if GIARDINO.contains(mid):
            return "giardino"
        if SCALONE.contains(mid):
            return "scalone"
        return None
    lati(E, S, b, anello, corpo)
    # La scala esterna verso il giardino, dove la pianta del terra la disegna (073).
    for k in range(4):
        E.prisma(S, GRANITO, [(-1.1, 207.4 - 0.4 * (4 - k)), (0.4 + 0.35 * (4 - k), 207.4 - 0.4 * (4 - k)),
                                (0.4 + 0.35 * (4 - k), 212.9 + 0.4 * (4 - k)), (-1.1, 212.9 + 0.4 * (4 - k))], 0, GRADINI - k * 0.15)
    tetti(E, S)
    return S.meshes(), BALAUSTRA + 4.3


def quote(b, E):
    """Le quote dei piani dalla foto: il terra sopra i quattro gradini, il piano nobile alla
    fascia dei balconi, il secondo sopra le finestre ad arco."""
    return {c: Z_PIANI.get(c, 0.0) for c in b.get("livelli", [])}


# ---------------------------------------------------------------- l'Aula Magna

# L'Aula Magna è il locale 023 del primo piano (la pianta la chiama così): 26 m per 11 dietro
# le cinque porte-finestre centrali del fronte, con l'abside a nord. Al secondo piano sopra di
# lei la pianta non ha locali, quindi è alta due piani. Foto dell'interno non ne abbiamo
# trovate: platea, palco nell'abside, boiserie e soffitto a cassettoni sono una stima, non
# un rilievo.
AULA_MAGNA = "MIA0101001023"
SOFFITTO = 14.2               # sotto il tetto a padiglione dell'ortofoto
LEGNO, LEGNO_SCURO = "#7A5536", "#4E3626"
VELLUTO = "#8C2A2E"           # le poltroncine
STUCCO = "#ECE6D8"
PORTE_FINESTRE = [201.24, 205.79, 210.36, 214.92, 219.49]   # le porte sul balcone, dalla pianta


def _box(x0, y0, x1, y1, z0, z1):
    return trimesh.creation.box(bounds=[(min(x0, x1), min(y0, y1), z0), (max(x0, x1), max(y0, y1), z1)])


def _sala(E, poly):
    """L'asse della sala, il palco nell'abside e la platea."""
    x0, y0, x1, y1 = poly.bounds
    xc = (x0 + x1) / 2
    return x0, y0, x1, y1, xc


def arredi(b, E, csip, z, piano):
    """La platea dell'Aula Magna: poltroncine rosse in file verso l'abside, il corridoio in
    mezzo e due ai lati; il palco di legno nell'abside, il tavolo della presidenza e il leggio."""
    out = {LEGNO: [], LEGNO_SCURO: [], VELLUTO: []}
    v = next((v for v in piano.get("vani", []) if v["csiv"] == AULA_MAGNA), None)
    if v is None:
        return out
    poly = E.shape_of(v)
    x0, y0, x1, y1, xc = _sala(E, poly)
    palco = poly.intersection(box(x0, y0, x1, 200.2))
    for q in E.clean(palco.buffer(-0.1)):
        out[LEGNO].append(trimesh.creation.extrude_polygon(q, 0.45).apply_translation((0, 0, z)))
    zp = z + 0.45
    out[LEGNO_SCURO].append(_box(xc - 3.2, 198.0, xc + 3.2, 198.9, zp + 0.7, zp + 0.78))       # il tavolo
    out[LEGNO_SCURO].append(_box(xc - 3.2, 198.85, xc + 3.2, 198.9, zp, zp + 0.7))             # il pannello davanti
    for k in range(7):
        x = xc - 2.7 + k * 0.9
        out[VELLUTO].append(_box(x - 0.25, 197.2, x + 0.25, 197.7, zp + 0.42, zp + 0.5))
        out[VELLUTO].append(_box(x - 0.25, 196.95, x + 0.25, 197.05, zp + 0.5, zp + 1.15))
        out[LEGNO_SCURO].append(_box(x - 0.22, 197.25, x + 0.22, 197.65, zp, zp + 0.42))
    out[LEGNO_SCURO].append(_box(x1 - 2.2, 199.5, x1 - 1.6, 200.0, zp, zp + 1.15))              # il leggio
    out[LEGNO_SCURO].append(_box(x1 - 2.3, 199.4, x1 - 1.5, 200.1, zp + 1.1, zp + 1.2))
    # la platea: file a 1 m, dalla prima a 1,8 m dal palco fino a 1 m dal fondo
    lato, mezzo, passo = 0.9, 1.4, 0.6
    for y in np.arange(202.0, y1 - 1.0, 1.0):
        for a_, c_ in ((x0 + lato, xc - mezzo / 2), (xc + mezzo / 2, x1 - lato)):
            n = int((c_ - a_) / passo)
            for k in range(n):
                x = a_ + (k + 0.5) * (c_ - a_) / n
                if not poly.buffer(-0.3).contains(Point(x, y)):
                    continue
                out[LEGNO_SCURO].append(_box(x - 0.24, y - 0.22, x + 0.24, y + 0.22, z, z + 0.4))
                out[VELLUTO].append(_box(x - 0.26, y - 0.24, x + 0.26, y + 0.24, z + 0.4, z + 0.48))
                out[VELLUTO].append(_box(x - 0.26, y + 0.24, x + 0.26, y + 0.34, z + 0.48, z + 1.0))
    return out


def interno(b, E, csiv, poly, z, porte):
    """Dentro l'Aula Magna: muri a tutta altezza con la boiserie, le cinque porte-finestre ad
    arco sul balcone come in facciata, la cornice e il soffitto a cassettoni, tre lampadari
    sull'asse. Torna ({colore: [mesh]}, occhio, guarda) come interno() di esporta3d."""
    if csiv != AULA_MAGNA:
        return None
    out = {STUCCO: [], LEGNO: [], E.VETRO: [], TELAIO: [], E.LUCE: [], E.METALLO: []}
    x0, y0, x1, y1, xc = _sala(E, poly)
    top = SOFFITTO
    # Il muro ovest, verso la piazza, con le porte-finestre: una lastra (t, z) dentro il muro.
    xw = x0
    dritto = [q[1] for q in poly.exterior.coords if q[0] < x0 + 0.5]       # il tratto dritto del muro, lesene comprese
    ya, yb = min(dritto) - 0.3, max(dritto) + 0.3
    e = ((xw + 0.12, yb), (xw + 0.12, ya), (0.0, -1.0), (-1.0, 0.0), yb - ya, 0.0)
    T = lambda y: yb - y
    aperture_ = unary_union([arco(T(y) - 1.0, T(y) + 1.0, z, 10.9) for y in PORTE_FINESTRE])
    muro = box(0, z, yb - ya, top).difference(aperture_)
    S = E.Solidi()
    E.panel(S, STUCCO, e, muro.intersection(box(0, z + 2.2, yb - ya, top)), -0.08, 0.0)
    E.panel(S, LEGNO, e, muro.intersection(box(0, z, yb - ya, z + 2.2)), -0.12, 0.0)
    for y in PORTE_FINESTRE:
        s_ = arco(T(y) - 1.0, T(y) + 1.0, z, 10.9)
        E.panel(S, E.VETRO, e, s_, 0.08, 0.1)
        bars = [box(T(y) - 0.04, z, T(y) + 0.04, 11.9), box(T(y) - 1.0, 10.86, T(y) + 1.0, 10.94)]
        bars += [box(T(y) - 1.0, zz - 0.03, T(y) + 1.0, zz + 0.03) for zz in np.arange(z + 1.1, 10.9, 1.1)]
        E.panel(S, TELAIO, e, unary_union(bars).intersection(s_), 0.0, 0.08)
        E.panel(S, TELAIO, e, s_.buffer(0.18).difference(s_), -0.14, 0.12)
    for key, m in S.meshes().items():
        m = m.copy()
        m.apply_transform(np.linalg.inv(E.YUP))       # Solidi gira già in Y su: si torna in Z su
        out.setdefault(key, []).append(m)
    # Gli altri muri: la fodera di esporta3d, alta fino al soffitto, con i varchi delle porte.
    resto = box(x0 - 1, y0 - 1, x1 + 1, y1 + 1).difference(box(x0 - 1, ya + 0.4, x0 + 0.12, yb - 0.4))
    E.fodera(poly, z, top, porte, Polygon(), out, muro=STUCCO, maschera=resto)
    # dietro la fodera un secondo strato nello spessore del muro: chiude le fessure che la
    # fodera lascia negli spigoli dell'abside (clean() scarta i pezzi più piccoli)
    dietro = poly.buffer(0.2, join_style=2).difference(poly).intersection(resto)
    for alto, g_ in ((True, dietro), (False, dietro.difference(porte.buffer(0.15)))):
        for q in getattr(g_, "geoms", [g_]):
            if q.geom_type == "Polygon" and q.area > 0.001:
                z0_, z1_ = (z + 2.3, top) if alto else (z, z + 2.3)
                out[STUCCO].append(trimesh.creation.extrude_polygon(q, z1_ - z0_).apply_translation((0, 0, z0_)))
    anello = poly.difference(poly.buffer(-0.1, join_style=2))
    for q in E.clean(anello.intersection(resto).difference(porte.buffer(0.1))):
        out[LEGNO].append(trimesh.creation.extrude_polygon(q.buffer(0.02), 2.2).apply_translation((0, 0, z)))
    # La cornice sotto il soffitto e il soffitto a cassettoni.
    for q in E.clean(poly.difference(poly.buffer(-0.35, join_style=2))):
        out[STUCCO].append(trimesh.creation.extrude_polygon(q, 0.45).apply_translation((0, 0, top - 0.85)))
    for q in E.clean(poly):
        out[STUCCO].append(trimesh.creation.extrude_polygon(q, 0.25).apply_translation((0, 0, top - 0.05)))
    ribs = [LineString([(x, y0 - 1), (x, y1 + 1)]).buffer(0.12) for x in np.arange(x0 + 1.35, x1 - 0.5, 1.35)]
    ribs += [LineString([(x0 - 1, y), (x1 + 1, y)]).buffer(0.12) for y in np.arange(y0 + 2.0, y1 - 0.5, 1.35)]
    for q in E.clean(unary_union(ribs).intersection(poly.buffer(-0.35))):
        out[STUCCO].append(trimesh.creation.extrude_polygon(q, 0.35).apply_translation((0, 0, top - 0.4)))
    # Tre lampadari: un anello di metallo con le luci, appeso all'asse.
    for y in (206.0, 211.5, 217.0):
        out[E.METALLO].append(trimesh.creation.cylinder(0.02, segment=[(xc, y, top - 0.4), (xc, y, 11.3)], sections=6))
        ring_ = trimesh.creation.annulus(r_min=0.8, r_max=0.9, height=0.08, sections=32)
        out[E.METALLO].append(ring_.apply_translation((xc, y, 11.2)))
        for k in range(12):
            a = k * math.pi / 6
            out[E.LUCE].append(trimesh.creation.icosphere(1, 0.09).apply_translation((xc + math.cos(a) * 0.85, y + math.sin(a) * 0.85, 11.33)))
    occhio = [round(xc, 2), round(z + 1.65, 2), round(y1 - 1.0, 2)]
    guarda = [round(xc, 2), round(z + 0.45 + 1.2, 2), round(198.4, 2)]
    return out, occhio, guarda
