"""PROTOTIPO — l'Edificio 4 "Giulio De Marchi" (MIA0104), l'esterno rifatto da zero.

Fonti, oltre ai contorni di leonardo.json e alle piante:
- l'ortofoto (Google, z20-21, 5-10 cm per pixel): l'ala lunga su via Bonardi con il tetto a
  padiglione in coppi e la fascia di lucernari sulla falda nord, i due padiglioni che
  sporgono sulla strada con il colmo perpendicolare, il corpo grigio a tetto piano
  sull'angolo ovest con la torre delle scale, i due blocchi degli impianti a tetto piano ai
  lati del corpo basso centrale, il chiostro a quattro ali in coppi con le finestre a
  tetto, il prato del cortile con la ciminiera, l'aula a sud con la testata smussata;
- le foto del restauro (B&B Progetti, 2020-2023) e la foto "Ciminiera neve" (Wikimedia
  Commons): la ciminiera in mattoni con le costole e i ricorsi in cemento grigio, il
  serbatoio tondo a due anelli chiari a metà altezza e il fusto liscio in mattoni sopra; le
  facciate del cortile in intonaco chiaro con le finestre ad arco e la cornice sotto la
  gronda; il salone a doppia altezza dell'ala nord con le finestre ad arco.

Le misure che le foto non danno sono dedotte: la ciminiera alta 48 m (lo spostamento della
cima nell'ortofoto, 10,6 m, con l'inclinazione della ripresa misurata sulle gronde del
cortile, ~0,2 m per metro), il terra rialzato di 1,2 m, il primo a 7 m, il sottotetto a 12 m,
la gronda a 13,2 m. Coordinate Z-up del frame del campus: x est, y sud.
"""
import math
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union

CSIE = "MIA0104"

Z_S, Z_T, Z_1, Z_2 = -3.4, 1.2, 7.0, 12.0
QUOTE = {"MIA010400S": Z_S, "MIA0104000": Z_T, "MIA0104001": Z_1, "MIA0104002": Z_2}
ZOCCOLO = Z_T + 0.3    # lo zoccolo in pietra, con le bocche del seminterrato
FASCIA = Z_1 - 0.35    # la fascia marcapiano
GRONDA = 13.2          # la cornice sotto le falde
PENDENZA = 0.5         # le falde in coppi, ~27°
GRIGIO_TOP = 15.6      # il tetto piano del corpo grigio sull'angolo ovest
TORRE_TOP = 16.6       # la torre delle scale
IMPIANTI_TOP = 12.4    # i due blocchi degli impianti
CENTRO_TOP = 7.6       # il corpo basso fra l'ala nord e il chiostro
PRATO = 0.9            # il cortile, un gradino sotto il terra

# I corpi, dal contorno delle piante (frame del campus) e dall'ortofoto.
GRIGIO = box(-7.2, 92.3, 13.0, 101.3)
TORRE = box(7.2, 101.3, 11.0, 107.0)
PAD_O = box(13.0, 92.2, 23.3, 100.0)
PAD_E = box(41.8, 92.1, 52.1, 100.0)
STRADA = box(11.0, 95.8, 59.7, 107.4).difference(GRIGIO)
IMP_O = box(10.4, 107.0, 23.3, 117.3)
IMP_E = box(42.0, 107.4, 54.0, 117.3)
CENTRO = box(23.3, 107.4, 42.0, 117.3)
CORTILE = box(23.7, 132.1, 39.6, 148.5)       # il vuoto del primo piano
ALA_N = box(23.7, 117.3, 39.6, 132.1)
ALA_S = box(23.7, 148.5, 39.6, 162.2)
ALA_O = box(9.8, 117.3, 23.7, 162.2)
ALA_E = box(39.6, 117.3, 55.3, 162.2)
AULA = Polygon([(23.3, 161.6), (23.3, 171.2), (26.0, 173.7), (39.8, 173.6), (42.5, 170.9), (42.5, 161.6)])
CIMINIERA = (31.92, 140.18)                   # il centro dell'ottagono nella pianta del terra

STUCCO = "#D9CBAE"         # l'intonaco chiaro del chiostro (foto del cortile)
STUCCO_STRADA = "#D6C29C"  # l'ala su via Bonardi, un po' più calda
CHIARO = "#ECE6D8"         # cornici, archivolti, fasce
BUGNATO = "#CDBE9E"
PIETRA = "#9D9A92"         # lo zoccolo
GRIGIO_C = "#A9ACAD"       # il corpo grigio sull'angolo
GRIGIO_SCURO = "#7E8285"
VETRO = "#3C4651"
TELAIO = "#F1EFE9"
FERRO = "#2E3134"
COPPI = "coppi"
LUCERNARIO = "#8FA6B8"     # la fascia vetrata sulla falda nord dell'ala lunga
FINESTRA_TETTO = "#3A4048"
TETTO_PIANO = "#8E9192"
TETTO_CHIARO = "#D9DAD6"   # il tetto chiaro del corpo basso
IMPIANTI = "#B7BCC1"
VENTOLE = "#3B3F44"
PRATO_C = "#7FA35E"
LASTRE = "#C9C5BB"
MATTONE = "#9A5638"        # la ciminiera
CEMENTO = "#8B8E8F"        # le costole e i ricorsi della ciminiera
SERBATOIO = "#DCD5C6"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    """Sotto le falde, sopra il sottotetto."""
    return GRONDA + 1.4


# ------------------------------------------------------------------ coppi

def _coppi_texture():
    """Coppi rossi in file, 0,5 m per ripetizione: il dorso tondo di ogni coppo, la
    sovrapposizione ogni 40 cm, toni un po' diversi."""
    from PIL import Image
    rng = np.random.default_rng(4)
    size = 256
    y, x = np.mgrid[0:size, 0:size]
    col = 4
    w = size // col
    ridge = np.sin((x % w) / w * math.pi)
    lap = (y / size * 1.25) % 1.0
    shade = 0.82 + 0.18 * ridge - 0.12 * (lap > 0.9)
    tone = rng.normal(0, 0.05, (col * 2,))[(x // w) % (col * 2)]
    base = np.array([0.72, 0.40, 0.27])
    rgb = base[None, None] * (shade + tone)[..., None]
    height = ridge * 0.8 + (1 - lap) * 0.2
    gy, gx = np.gradient(height)
    nrm = np.dstack([-gx * 4, gy * 4, np.ones_like(height)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    to8 = lambda a: Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return to8(rgb), to8(nrm * 0.5 + 0.5)


def _registra(E):
    if COPPI not in E.TEX:
        E.TEX[COPPI] = 0.5
        E._TEXTURES[COPPI] = _coppi_texture()


# ------------------------------------------------------------------ tetti

def _lati_interni(pts):
    """Per ogni lato di un poligono convesso antiorario: (punto, normale verso l'interno)."""
    out = []
    for a, c in zip(pts, pts[1:] + pts[:1]):
        L = math.dist(a, c)
        if L < 1e-6:
            continue
        out.append((np.array(a, float), np.array([-(c[1] - a[1]) / L, (c[0] - a[0]) / L]), a, c))
    return out


def falde(E, S, poly, z, pendenza=PENDENZA, sporto=0.6, finestre=None, vetrata=None):
    """Un tetto a padiglione in coppi su un poligono convesso (rettangoli, testate smussate):
    ogni falda è la parte del poligono più vicina al suo lato e sale verso l'interno con la
    stessa pendenza, come il tetto vero. Sotto, il soffitto della gronda. `finestre`: il
    passo delle finestre a tetto lungo le falde lunghe; `vetrata`: (lato, t0, t1, profondità)
    una fascia di vetro sulla falda di quel lato (0 = il primo da ovest a nord...).
    Restituisce la quota del colmo."""
    g = poly.buffer(sporto, join_style=2)
    pts = E.ring_ccw(g)
    lati = _lati_interni(pts)
    top = z
    for i, (p0, n, a, c) in enumerate(lati):
        # la regione del lato i: dentro il poligono, più vicina a i che a ogni altro lato
        reg = g
        for j, (q0, m, _, _) in enumerate(lati):
            if j == i:
                continue
            # d_i(x) <= d_j(x)  ⇔  (n - m)·x <= n·p0 - m·q0
            k = n - m
            rhs = float(np.dot(n, p0) - np.dot(m, q0))
            if np.linalg.norm(k) < 1e-9:
                continue
            reg = reg.intersection(_semipiano(k, rhs))
            if reg.is_empty:
                break
        if reg.is_empty or reg.area < 1e-4:
            continue
        L = math.dist(a, c)
        u = np.array([(c[0] - a[0]) / L, (c[1] - a[1]) / L])
        want = (-n[0], -n[1], 1.0)
        for q in E.clean(reg):
            ring_ = list(q.exterior.coords)[:-1]
            p3 = [(x, y, z + pendenza * float(np.dot(n, np.array([x, y]) - p0))) for x, y in ring_]
            top = max(top, max(p[2] for p in p3))
            tri = trimesh.creation.triangulate_polygon(q) if len(ring_) > 4 else None
            uv = lambda p: (float(np.dot(np.array(p[:2]) - p0, u)),
                            float(np.dot(np.array(p[:2]) - p0, n)) * math.sqrt(1 + pendenza ** 2))
            if tri is None:
                if len(p3) == 3:
                    S.tri(COPPI, p3, want, [uv(p) for p in p3])
                else:
                    S.quad(COPPI, p3, want, [uv(p) for p in p3])
            else:
                v2, f2 = tri
                for f_ in f2:
                    tp = [(float(v2[k][0]), float(v2[k][1]), z + pendenza * float(np.dot(n, v2[k] - p0))) for k in f_]
                    S.tri(COPPI, tp, want, [uv(p) for p in tp])
        # le finestre a tetto: sulla parte trapezia della falda, a 40% della salita
        corsa = max(float(np.dot(n, np.array(p) - p0)) for p in reg.exterior.coords)
        if finestre and L > 2 * corsa + 2.0:
            d = min(corsa * 0.45, 2.6)
            t = corsa + 1.0
            while t + 0.5 < L - corsa - 0.5:
                _finestra_tetto(S, p0, u, n, t, d, z, pendenza)
                t += finestre
        if vetrata and vetrata[0] == i:
            _, t0, t1, prof = vetrata
            d0, d1 = corsa - prof, corsa - 0.25
            q = [p0 + u * t0 + n * d0, p0 + u * t1 + n * d0, p0 + u * t1 + n * d1, p0 + u * t0 + n * d1]
            hz = lambda p, off: (p[0], p[1], z + pendenza * float(np.dot(n, p - p0)) + off)
            S.quad(LUCERNARIO, [hz(p, 0.08) for p in q], want)
            for k in range(int((t1 - t0) / 1.2) + 1):          # i montanti
                tt = t0 + k * (t1 - t0) / max(1, int((t1 - t0) / 1.2))
                E.trave(S, TELAIO, hz(p0 + u * tt + n * d0, 0.12), hz(p0 + u * tt + n * d1, 0.12), 0.06)
            for dd in (d0, (d0 + d1) / 2, d1):
                E.trave(S, TELAIO, hz(p0 + u * t0 + n * dd, 0.12), hz(p0 + u * t1 + n * dd, 0.12), 0.06)
    S.quad(CHIARO, [(*p, z - 0.01) for p in pts[:4]], (0, 0, -1)) if len(pts) == 4 else \
        E.prisma(S, CHIARO, pts, z - 0.06, z - 0.01)
    return top


def _semipiano(k, rhs, R=2000.0):
    """Il semipiano k·x <= rhs come un grande poligono."""
    k = np.asarray(k, float)
    kn = np.linalg.norm(k)
    k, rhs = k / kn, rhs / kn
    o = k * rhs                       # un punto sulla retta
    t = np.array([-k[1], k[0]])
    pts = [o + t * R, o - t * R, o - t * R - k * R, o + t * R - k * R]
    return Polygon([tuple(p) for p in pts])


def _finestra_tetto(S, p0, u, n, t, d, z, pendenza, w=0.8, h=1.1):
    """Una finestra a tetto: il vetro scuro appena sopra i coppi, con il telaio chiaro."""
    hz = lambda tt, dd, off: tuple(p0 + u * tt + n * dd) + (z + pendenza * dd + off,)
    want = (-n[0], -n[1], 1.0)
    S.quad(TELAIO, [hz(t - w / 2 - 0.06, d - 0.06, 0.07), hz(t + w / 2 + 0.06, d - 0.06, 0.07),
                    hz(t + w / 2 + 0.06, d + h + 0.06, 0.07), hz(t - w / 2 - 0.06, d + h + 0.06, 0.07)], want)
    S.quad(FINESTRA_TETTO, [hz(t - w / 2, d, 0.09), hz(t + w / 2, d, 0.09), hz(t + w / 2, d + h, 0.09), hz(t - w / 2, d + h, 0.09)], want)


# ------------------------------------------------------------------ facciate

def arco(t0, t1, z0, zi, seg=8):
    """Un'apertura ad arco a tutto sesto: il rettangolo fino all'imposta e il mezzo cerchio."""
    r = (t1 - t0) / 2
    c = t0 + r
    return Polygon([(t0, z0), (t1, z0)] + [(c + r * math.cos(math.pi * k / seg), zi + r * math.sin(math.pi * k / seg))
                                          for k in range(seg + 1)])


def rett(t0, t1, z0, z1):
    return Polygon([(t0, z0), (t1, z0), (t1, z1), (t0, z1)])


def finestra(E, S, e, shape, ad_arco):
    """Il vetro scuro appena dentro il filo, la cornice chiara, montante e traverso; sopra
    gli archi l'archivolto in pietra con la chiave."""
    E.panel(S, VETRO, e, shape, 0.0, 0.02)
    E.panel(S, CHIARO, e, shape.buffer(0.14, join_style=2).difference(shape), 0.0, 0.1)
    t0, z0, t1, z1 = shape.bounds
    tm = (t0 + t1) / 2
    bars = [rett(tm - 0.03, tm + 0.03, z0, z1)]
    zt = z0 + (z1 - z0) * (0.66 if ad_arco else 0.62)
    bars.append(rett(t0, t1, zt - 0.03, zt + 0.03))
    E.panel(S, TELAIO, e, unary_union(bars).intersection(shape), 0.0, 0.05)
    if ad_arco:
        r = (t1 - t0) / 2
        zi = z1 - r
        ghiera = arco(t0 - 0.3, t1 + 0.3, zi, zi).difference(arco(t0, t1, zi - 1, zi)).difference(rett(t0 - 1, t1 + 1, zi - 2, zi))
        E.panel(S, CHIARO, e, ghiera, 0.0, 0.12)
        E.panel(S, CHIARO, e, Polygon([(tm - 0.17, z1 - 0.05), (tm + 0.17, z1 - 0.05), (tm + 0.23, z1 + 0.38),
                                         (tm - 0.23, z1 + 0.38)]), 0.0, 0.17)
    # il davanzale
    E.panel(S, CHIARO, e, rett(t0 - 0.18, t1 + 0.18, z0 - 0.14, z0), 0.0, 0.16)


def campate(L, passo, bordo=1.0):
    n = max(0, int((L - 2 * bordo) / passo) + 1)
    if n == 0:
        return []
    usato = (n - 1) * passo
    return [L / 2 - usato / 2 + i * passo for i in range(n)]


def libero(e, altre, dentro=0.3):
    """I tratti [t0, t1] del lato che non toccano un'altra parte: le facce in vista."""
    a, c, u, n, L, _ = e
    seg = LineString([(a[0] + n[0] * dentro, a[1] + n[1] * dentro), (c[0] + n[0] * dentro, c[1] + n[1] * dentro)])
    coperto = seg.intersection(unary_union([p.buffer(0.05) for p in altre])) if altre else None
    tratti = [(0.0, L)]
    if coperto is not None and not coperto.is_empty:
        for g in getattr(coperto, "geoms", [coperto]):
            if g.length < 0.2:
                continue
            ts = sorted(float(np.dot(np.array(q) - np.array(a), np.array(u))) for q in g.coords)
            c0, c1 = ts[0], ts[-1]
            nuovi = []
            for t0, t1 in tratti:
                if c1 <= t0 or c0 >= t1:
                    nuovi.append((t0, t1))
                    continue
                if c0 > t0:
                    nuovi.append((t0, c0))
                if c1 < t1:
                    nuovi.append((c1, t1))
            tratti = nuovi
    return [(t0, t1) for t0, t1 in tratti if t1 - t0 > 0.8]


_FINESTRE = {}


def _aperture(E, b, csip, pts, e_idx, t0, t1, passo):
    """Le finestre di un tratto di facciata: quelle della pianta del piano, se ce ne sono,
    altrimenti a campate regolari. [(centro, larghezza)]."""
    chiave = (csip, tuple(map(tuple, pts)))
    if chiave not in _FINESTRE:
        _FINESTRE[chiave] = E.plan_windows(b, csip, pts, reach=1.0)
    win = _FINESTRE[chiave].get(e_idx, [])
    out = [((w0 + w1) / 2, min(1.7, max(0.9, w1 - w0))) for w0, w1 in win if w0 >= t0 + 0.3 and w1 <= t1 - 0.3]
    if out:
        return out
    return [(t0 + p, 1.4) for p in campate(t1 - t0, passo, 1.2)]


def palazzo(E, S, b, pts, altre, tinta, cima, archi_primo=False, passo=3.8, angoli=False, sul_cortile=None):
    """Le facciate di un corpo storico: lo zoccolo in pietra con le bocche del seminterrato,
    il terra a bugne piatte con le finestre ad arco, la fascia marcapiano, il primo liscio
    (finestre rette, o ad arco sul cortile e nel salone dell'ala nord), la cornice."""
    for i, e in enumerate(E.edges(pts)):
        a, c, u, n, L, _ = e
        mid = Point((a[0] + c[0]) / 2 + n[0] * 0.8, (a[1] + c[1]) / 2 + n[1] * 0.8)
        cortile = sul_cortile is not None and sul_cortile.contains(mid)
        z_basso = PRATO if cortile else 0.0
        for t0, t1 in libero(e, altre):
            terra = _aperture(E, b, "MIA0104000", pts, i, t0, t1, passo)
            primo = _aperture(E, b, "MIA0104001", pts, i, t0, t1, passo) if cima > Z_1 + 2 else []
            # lo zoccolo, con le bocche del seminterrato sotto le finestre del terra
            bocche = [] if cortile else [rett(p - min(w, 1.2) / 2, p + min(w, 1.2) / 2, 0.25, ZOCCOLO - 0.25) for p, w in terra]
            zoc = rett(t0, t1, z_basso, ZOCCOLO)
            E.panel(S, PIETRA, e, zoc.difference(unary_union(bocche)) if bocche else zoc, 0.0, 0.1)
            for f in bocche:
                E.panel(S, "#2A2E33", e, f, 0.0, 0.03)
                for k in range(1, 5):
                    tt = f.bounds[0] + (f.bounds[2] - f.bounds[0]) * k / 5
                    E.panel(S, FERRO, e, rett(tt - 0.02, tt + 0.02, f.bounds[1], f.bounds[3]), 0.0, 0.07)
            # il terra: finestre ad arco fino a 1 m sotto la fascia, bugne piatte da 50 cm
            fin_t = [arco(p - w / 2, p + w / 2, Z_T + 0.9, FASCIA - 1.0 - w / 2) for p, w in terra]
            fori = unary_union([g.buffer(0.3, join_style=2) for g in fin_t]) if fin_t else Polygon()
            z = ZOCCOLO
            while z < FASCIA - 0.1:
                z1 = min(FASCIA, z + 0.46)
                E.panel(S, BUGNATO if tinta == STUCCO else _scurisci(tinta), e, rett(t0, t1, z, z1).difference(fori), 0.0, 0.05)
                z += 0.5
            for g in fin_t:
                finestra(E, S, e, g, True)
            if cima <= Z_1 + 1:
                continue
            E.panel(S, CHIARO, e, rett(t0, t1, FASCIA, FASCIA + 0.35), 0.0, 0.2)
            # il primo
            for p, w in primo:
                if archi_primo or cortile:
                    g = arco(p - w / 2, p + w / 2, Z_1 + 0.95, cima - 2.0 - w / 2)
                    finestra(E, S, e, g, True)
                else:
                    g = rett(p - w / 2, p + w / 2, Z_1 + 0.95, min(cima - 2.0, Z_1 + 3.6))
                    finestra(E, S, e, g, False)
                    E.panel(S, CHIARO, e, rett(p - w / 2 - 0.25, p + w / 2 + 0.25, g.bounds[3] + 0.14, g.bounds[3] + 0.32), 0.0, 0.2)
            if angoli:                    # i cantonali a bugne alterne sugli spigoli
                for t in (t0, t1):
                    if t not in (0.0, L):
                        continue
                    z = ZOCCOLO
                    k = 0
                    while z < cima - 1.0:
                        w_ = 0.9 if k % 2 == 0 else 0.55
                        tt0, tt1 = (t, t + w_) if t == 0.0 else (t - w_, t)
                        E.panel(S, CHIARO, e, rett(tt0, tt1, z, z + 0.42), 0.0, 0.08)
                        z += 0.5
                        k += 1
            # la fascia sotto la cornice e le mensole
            E.panel(S, CHIARO, e, rett(t0, t1, cima - 0.9, cima - 0.75), 0.0, 0.1)
            for k in range(int((t1 - t0) / 0.8)):
                t = t0 + 0.4 + k * 0.8
                E.panel(S, CHIARO, e, rett(t - 0.09, t + 0.09, cima - 0.6, cima - 0.32), 0.0, 0.32)


def _scurisci(hex_, k=0.94):
    h = hex_.lstrip("#")
    return "#" + "".join(f"{int(int(h[i:i + 2], 16) * k):02X}" for i in (0, 2, 4))


def cornice(E, S, poly, z, sporto=0.55):
    """La cornice sotto la gronda: un gradino e la lastra che sporge."""
    E.prisma(S, CHIARO, E.ring_ccw(poly.buffer(sporto * 0.45, join_style=2)), z - 0.32, z - 0.15)
    E.prisma(S, CHIARO, E.ring_ccw(poly.buffer(sporto, join_style=2)), z - 0.15, z)


def moderno(E, S, pts, altre, cima, piani):
    """Il corpo grigio: pannelli lisci, finestre a nastro per piano, il coronamento."""
    for e in E.edges(pts):
        for t0, t1 in libero(e, altre):
            E.panel(S, GRIGIO_SCURO, e, rett(t0, t1, 0.0, ZOCCOLO), 0.0, 0.06)
            for z0 in piani:
                for p in campate(t1 - t0, 1.9, 0.9):
                    g = rett(t0 + p - 0.75, t0 + p + 0.75, z0 + 0.9, z0 + 3.0)
                    E.panel(S, VETRO, e, g, 0.0, 0.02)
                    E.panel(S, "#C9CCCD", e, g.buffer(0.08, join_style=2).difference(g), 0.0, 0.06)
                E.panel(S, "#B8BBBC", e, rett(t0, t1, z0 + 0.6, z0 + 0.78), 0.0, 0.08)
            E.panel(S, "#C4C7C8", e, rett(t0, t1, cima - 0.5, cima + 0.6), 0.0, 0.1)


def tetto_piano(E, S, poly, z, colore=TETTO_PIANO, parapetto=0.6, bordo=CHIARO):
    """Il tetto piano dietro il parapetto."""
    E.prisma(S, bordo, E.ring_ccw(poly.buffer(0.1, join_style=2)), z - 0.2, z + parapetto)
    for q in E.clean(poly.buffer(-0.3, join_style=2)):
        E.prisma(S, colore, E.ring_ccw(q), z + parapetto - 0.4, z + parapetto - 0.32)


def impianti(E, S, z, macchine):
    """Le macchine sui tetti piani (ortofoto): casse grigie, e sopra i gruppi frigo le
    ventole scure in fila."""
    for x0, y0, w, d, h, ventole in macchine:
        S.solid(IMPIANTI, E.box_z(x0 + w / 2, y0 + d / 2, w, d, z, z + h))
        if ventole:
            for i in range(int(d / 1.25)):
                for j in range(int(w / 1.25)):
                    cx, cy = x0 + 0.62 + j * 1.25, y0 + 0.62 + i * 1.25
                    S.solid(VENTOLE, trimesh.creation.cylinder(radius=0.5, height=0.08, sections=12)
                            .apply_translation([cx, cy, z + h + 0.04]))


# ------------------------------------------------------------------ la ciminiera

def _anello(S, key, x, y, z0, z1, r0, r1, sezioni=24):
    """Un tronco di cono pieno."""
    m = trimesh.creation.cylinder(radius=1.0, height=1.0, sections=sezioni)
    v = m.vertices.copy()
    alto = v[:, 2] > 0
    r = np.where(alto, r1, r0)
    v[:, 0] *= r
    v[:, 1] *= r
    v[:, 2] = np.where(alto, z1, z0)
    v[:, 0] += x
    v[:, 1] += y
    S.solid(key, trimesh.Trimesh(v, m.faces, process=False))


def ciminiera(E, S, x, y, z0):
    """La ciminiera del cortile (foto del restauro e "Ciminiera neve"): lo zoccolo ottagonale
    chiaro della pianta, il fusto in mattoni rastremato con otto costole in cemento grigio e
    i ricorsi ogni 3,4 m, il serbatoio tondo a due anelli, il fusto liscio in mattoni fino a
    48 m con la corona in cima."""
    ott = Polygon([(x + 2.1 * math.cos(math.pi / 8 + k * math.pi / 4), y + 2.1 * math.sin(math.pi / 8 + k * math.pi / 4))
                   for k in range(8)])
    E.prisma(S, SERBATOIO, E.ring_ccw(ott), z0, z0 + 2.4)
    E.prisma(S, CEMENTO, E.ring_ccw(ott.buffer(0.12, join_style=2)), z0 + 2.4, z0 + 2.7)
    zb, zs = z0 + 2.7, 20.5
    r_b, r_s = 1.85, 1.6
    _anello(S, MATTONE, x, y, zb, zs, r_b, r_s, 16)
    rr = lambda z: r_b + (r_s - r_b) * (z - zb) / (zs - zb)
    for k in range(8):                                    # le costole
        th = math.pi / 8 + k * math.pi / 4
        p = lambda z, d=0.0: (x + (rr(z) + d) * math.cos(th), y + (rr(z) + d) * math.sin(th), z)
        E.trave(S, CEMENTO, p(zb, 0.05), p(zs, 0.05), 0.36)
    z = zb + 0.4
    while z < zs - 0.5:                                   # i ricorsi
        _anello(S, CEMENTO, x, y, z, z + 0.32, rr(z) + 0.1, rr(z + 0.32) + 0.1, 16)
        z += 3.4
    # il serbatoio: la coppa che si allarga, il primo anello, il secondo un po' più stretto
    _anello(S, SERBATOIO, x, y, zs, zs + 1.8, r_s + 0.1, 3.7, 32)
    _anello(S, SERBATOIO, x, y, zs + 1.8, zs + 3.2, 3.7, 3.7, 32)
    _anello(S, CHIARO, x, y, zs + 3.2, zs + 3.45, 3.85, 3.85, 32)
    _anello(S, SERBATOIO, x, y, zs + 3.45, zs + 5.6, 3.35, 3.35, 32)
    _anello(S, CHIARO, x, y, zs + 5.6, zs + 5.8, 3.45, 3.3, 32)
    # il fusto liscio e la corona
    zt = 48.0
    _anello(S, MATTONE, x, y, zs + 5.8, zt - 0.8, 1.45, 1.05, 16)
    _anello(S, _scurisci(MATTONE, 0.85), x, y, zt - 0.8, zt, 1.2, 1.2, 16)
    for k in range(10):                                   # il parafulmine ad anello
        th = k * math.pi / 5
        E.trave(S, FERRO, (x + 1.1 * math.cos(th), y + 1.1 * math.sin(th), zt),
                (x + 1.1 * math.cos(th), y + 1.1 * math.sin(th), zt + 0.9), 0.04)
    _anello(S, FERRO, x, y, zt + 0.85, zt + 0.92, 1.15, 1.15, 16)
    return zt + 0.92


# ------------------------------------------------------------------ guscio

def guscio(b, E):
    """L'esterno dell'Edificio 4: {chiave: mesh} e la quota più alta."""
    _registra(E)
    S = E.Solidi()
    storici = {"pad-o": PAD_O, "pad-e": PAD_E, "strada": STRADA, "ala-n": ALA_N, "ala-s": ALA_S,
               "ala-o": ALA_O, "ala-e": ALA_E, "aula": AULA}
    piatti = {"grigio": GRIGIO, "torre": TORRE, "imp-o": IMP_O, "imp-e": IMP_E, "centro": CENTRO}
    tutti = {**storici, **piatti}
    # le masse, piene fino alla gronda o al tetto piano
    tinta = {k: STUCCO_STRADA if k in ("pad-o", "pad-e", "strada") else STUCCO for k in storici}
    for k, g in storici.items():
        E.prisma(S, tinta[k], E.ring_ccw(g), 0.0, GRONDA - 0.3)
    E.prisma(S, GRIGIO_C, E.ring_ccw(GRIGIO), 0.0, GRIGIO_TOP)
    E.prisma(S, GRIGIO_C, E.ring_ccw(TORRE), 0.0, TORRE_TOP)
    for g in (IMP_O, IMP_E):
        E.prisma(S, STUCCO, E.ring_ccw(g), 0.0, IMPIANTI_TOP)
    E.prisma(S, STUCCO, E.ring_ccw(CENTRO), 0.0, CENTRO_TOP)
    # le facciate
    for k, g in storici.items():
        altre = [h for kk, h in tutti.items() if kk != k]
        palazzo(E, S, b, E.ring_ccw(g), altre, tinta[k], GRONDA, archi_primo=k in ("strada", "pad-o", "pad-e"),
                angoli=k in ("pad-o", "pad-e"), sul_cortile=CORTILE)
    for k, top in (("imp-o", IMPIANTI_TOP), ("imp-e", IMPIANTI_TOP), ("centro", CENTRO_TOP)):
        altre = [h for kk, h in tutti.items() if kk != k]
        palazzo(E, S, b, E.ring_ccw(tutti[k]), altre, STUCCO, top, passo=3.8)
    for k in ("grigio", "torre"):
        altre = [h for kk, h in tutti.items() if kk != k]
        moderno(E, S, E.ring_ccw(tutti[k]), altre, GRIGIO_TOP if k == "grigio" else TORRE_TOP,
                [Z_T, Z_1, Z_2] if k == "grigio" else [Z_T + 2.0, Z_1 + 2.0, Z_2])
    # cornici e tetti in coppi. Le ali del chiostro si incrociano agli angoli: ogni ala ha il
    # suo padiglione, e dove due si sovrappongono le falde fanno da sé i compluvi.
    for g in storici.values():
        cornice(E, S, g, GRONDA)
    top = GRONDA
    top = max(top, falde(E, S, box(9.8, 117.3, 55.3, 132.1), GRONDA, finestre=3.8))
    top = max(top, falde(E, S, box(9.8, 148.5, 55.3, 162.2), GRONDA, finestre=3.8))
    top = max(top, falde(E, S, ALA_O, GRONDA, finestre=3.8))
    top = max(top, falde(E, S, ALA_E, GRONDA, finestre=3.8))
    # l'aula a sud: la falda va fino all'ala sud, la testata smussata come nella pianta
    aula_tetto = Polygon([(23.3, 150.0), (42.5, 150.0), (42.5, 170.9), (39.8, 173.6), (26.0, 173.7), (23.3, 171.2)])
    top = max(top, falde(E, S, aula_tetto, GRONDA, finestre=None))
    # l'ala su via Bonardi: la fascia di lucernari sulla falda nord, dalla foto aerea
    strada_tetto = box(13.0, 95.8, 59.7, 107.4)
    lati = _lati_interni(E.ring_ccw(strada_tetto.buffer(0.6, join_style=2)))
    nord = min(range(len(lati)), key=lambda i: lati[i][1][1] * -1)     # la normale interna verso sud
    t_x = lambda x: x - (13.0 - 0.6) if lati[nord][2][0] < lati[nord][3][0] else (59.7 + 0.6) - x
    t0, t1 = sorted((t_x(16.5), t_x(52.5)))
    top = max(top, falde(E, S, strada_tetto, GRONDA, vetrata=(nord, t0, t1, 3.0)))
    # i padiglioni: falde basse fino alla falda nord dell'ala, che resta intera con i suoi
    # lucernari (ortofoto)
    for g in (box(13.0, 92.2, 23.3, 98.6), box(41.8, 92.1, 52.1, 98.6)):
        top = max(top, falde(E, S, g, GRONDA + 0.4, finestre=None))
        x0, y0, x1, y1 = g.bounds
        for dx in (-1.0, 1.0):                             # le due finestre a tetto verso la strada
            _finestra_tetto(S, np.array([x0 - 0.6, y0 - 0.6]), np.array([1.0, 0.0]), np.array([0.0, 1.0]),
                            (x1 - x0) / 2 + 0.6 + dx, 1.4, GRONDA + 0.4, PENDENZA)
    # i tetti piani
    tetto_piano(E, S, GRIGIO, GRIGIO_TOP, bordo="#C4C7C8")
    tetto_piano(E, S, TORRE, TORRE_TOP, bordo="#C4C7C8")
    S.solid(IMPIANTI, E.box_z(9.1, 104.0, 2.2, 2.2, TORRE_TOP + 0.3, TORRE_TOP + 1.8))
    impianti(E, S, GRIGIO_TOP + 0.3, [(2.5, 93.5, 3.2, 3.2, 1.2, True), (-5.5, 94.0, 6.0, 1.8, 0.9, False)])
    tetto_piano(E, S, IMP_O, IMPIANTI_TOP)
    impianti(E, S, IMPIANTI_TOP + 0.3, [(11.4, 107.8, 2.6, 8.6, 1.6, True), (14.6, 107.8, 6.5, 5.0, 2.0, False),
                                         (14.6, 113.6, 6.5, 2.6, 1.1, False)])
    tetto_piano(E, S, IMP_E, IMPIANTI_TOP)
    impianti(E, S, IMPIANTI_TOP + 0.3, [(43.0, 108.4, 4.4, 8.0, 1.4, False), (48.4, 108.4, 2.6, 8.0, 1.7, True),
                                         (51.2, 108.6, 2.2, 7.0, 0.9, False)])
    tetto_piano(E, S, CENTRO, CENTRO_TOP, colore=TETTO_CHIARO)
    S.solid(IMPIANTI, E.box_z(29.0, 110.7, 3.2, 1.4, CENTRO_TOP + 0.3, CENTRO_TOP + 1.3))   # l'uscita della scala
    # il cortile: il prato un gradino sotto il terra, il bordo in lastre, la ciminiera
    E.prisma(S, LASTRE, E.ring_ccw(CORTILE), 0.0, PRATO - 0.05)
    for q in E.clean(CORTILE.buffer(-1.4, join_style=2).difference(Point(CIMINIERA).buffer(3.2))):
        E.prisma(S, PRATO_C, E.ring_ccw(q), PRATO - 0.05, PRATO)
    top = max(top, ciminiera(E, S, *CIMINIERA, PRATO))
    # su via Bonardi: davanti all'ala lunga la bocca di lupo del seminterrato, chiusa dal
    # muretto con la cancellata e i pilastrini (le ombre in fila nell'ortofoto); l'ingresso al
    # centro con i gradini della pianta e il ponticello
    y_s, y_f = 92.3, 95.8
    for x0, x1 in ((23.3, 30.4), (34.4, 41.8)):
        E.prisma(S, "#4F5254", [(x0, y_s + 0.3), (x1, y_s + 0.3), (x1, y_f), (x0, y_f)], -1.5, -1.45)
        E.prisma(S, PIETRA, [(x0, y_s), (x1, y_s), (x1, y_s + 0.3), (x0, y_s + 0.3)], -1.5, 0.6)
        for k in range(int((x1 - x0) / 2.4) + 1):
            x = x0 + 0.2 + k * (x1 - x0 - 0.4) / max(1, int((x1 - x0) / 2.4))
            S.solid(PIETRA, E.box_z(x, y_s + 0.15, 0.45, 0.45, 0.6, 1.9))
        E.trave(S, FERRO, (x0, y_s + 0.15, 1.75), (x1, y_s + 0.15, 1.75), 0.05)
        E.trave(S, FERRO, (x0, y_s + 0.15, 0.75), (x1, y_s + 0.15, 0.75), 0.05)
        for k in range(int((x1 - x0) / 0.14)):
            x = x0 + 0.07 + k * 0.14
            E.trave(S, FERRO, (x, y_s + 0.15, 0.6), (x, y_s + 0.15, 1.85), 0.025)
    S.solid(LASTRE, E.box_z(32.4, (y_s + y_f) / 2, 4.0, y_f - y_s, 0.0, 0.25))
    for k in range(4):
        S.solid(LASTRE, E.box_z(32.4, y_f - 0.15 - k * 0.3, 3.5, 0.3 + k * 0.0, 0.25, 0.25 + Z_T * (4 - k) / 5))
    e_n = [e for e in E.edges(E.ring_ccw(STRADA)) if e[3][1] < -0.9][0]
    t_p = abs(32.4 - e_n[0][0])
    portale = arco(t_p - 1.3, t_p + 1.3, Z_T, Z_T + 2.9)
    E.panel(S, "#3A2E26", e_n, portale, 0.0, 0.04)
    E.panel(S, CHIARO, e_n, portale.buffer(0.35, join_style=2).difference(portale).difference(rett(-99, 99, -9, Z_T)), 0.0, 0.2)
    return S.meshes(), round(top, 2)


# ------------------------------------------------------------------ piante

AULA_401 = "MIA0104000026"


def piante(b, geo, aule, E):
    """L'aula 4.0.1 (310 posti) non ha le file nella pianta. La sala è un rettangolo che
    finisce a sud nella testata smussata, con le porte a nord sul corridoio: la cattedra sta
    nella testata, le file guardano a sud, ogni 92 cm, con il corridoio centrale e quelli ai
    lati. 310 posti a 55 cm l'uno sono 12 file da 26."""
    f = geo.get("MIA0104000")
    if not f:
        return geo
    v = next((v for v in f["vani"] if v["csiv"] == AULA_401), None)
    if v is None:
        return geo
    poly = E.shape_of(v)
    segs = f.setdefault("linee", {}).setdefault("arredi", [])
    x0, y0, x1, y1 = poly.bounds
    m = (x0 + x1) / 2
    for k in range(12):
        y = y1 - 4.2 - 0.92 * k                 # 4,2 m davanti alla prima fila per la cattedra
        for p0, p1 in ((x0 + 1.2, m - 0.7), (m + 0.7, x1 - 1.2)):
            segs.append([round(p0, 2), round(y, 2), round(p1, 2), round(y, 2)])
    return geo


def ritocca(sc, meta, E):
    """Dentro la 4.0.1 l'occhio va in fondo al corridoio centrale, non nell'angolo dove lo
    mette il primo gradino (che qui gira anche sui corridoi laterali), e guarda la cattedra
    nella testata."""
    for piano in meta.get("piani", []):
        for a in piano.get("aule", []):
            if a.get("csiv") == AULA_401 and a.get("interno"):
                cx = a["centro"][0]
                a["interno"]["occhio"] = [cx, a["interno"]["occhio"][1], 158.3]
                a["interno"]["guarda"] = [cx, round(Z_T + 1.6, 2), 171.0]
