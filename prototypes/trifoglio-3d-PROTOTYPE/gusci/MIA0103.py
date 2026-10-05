"""PROTOTIPO — l'Edificio 3 "Gino Cassinis" (MIA0103), l'esterno rifatto da zero.

Fonti, oltre ai contorni di leonardo.json e alle piante:
- l'ortofoto (Esri World Imagery, z19): le falde in coppi delle ali nord e sud e dei padiglioni,
  il tetto piano scuro del fronte ovest, il prato del cortile con l'ippocastano, il tetto
  bianco del corpo est coperto di pannelli in due campi, i tetti scuri con gli impianti alle
  sue testate;
- le foto di Wikimedia Commons: dal piazzale del Rettorato (il padiglione nord-ovest con le
  paraste, gli archi del terra bugnato, i balaustrini sotto le finestre del primo, la
  balaustra con le sfere e i due obelischi sull'avancorpo d'ingresso nord; il fronte ovest più
  basso e liscio), dal portico verso l'ingresso nord, e dal cortile (la loggia del corpo est:
  archi a terra, finestre ad arco con balaustrini al primo, il secondo piano vetrato bianco;
  le scale di sicurezza bianche agli angoli; le ali in intonaco grigio-beige con il terra
  bugnato, le finestre del seminterrato a filo del prato; il cubo di vetro sul tetto).

Il seminterrato è a quota del giardino; il terra sta 3,6 m sopra, il primo a 9 m, il secondo
(solo il corpo est, la sopraelevazione vetrata) a 14,4 m. Il cortile è un prato rialzato a
2,8 m, poco sotto il terra, come nelle foto. Coordinate Z-up del frame del campus: x est, y sud.
"""
import math
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union

Z_S, Z_T, Z_1, Z_2 = 0.0, 3.6, 9.0, 14.4
QUOTE = {"MIA010300S": Z_S, "MIA0103000": Z_T, "MIA0103001": Z_1, "MIA0103002": Z_2}
ZOCCOLO = 1.3          # lo zoccolo in granito, con le bocche del seminterrato
FASCIA = 8.7           # la fascia marcapiano fra terra e primo
FREGIO = 13.4          # sotto il cornicione
GRONDA = 14.4          # il cornicione delle ali, dei padiglioni e del fronte
EST_TOP = 18.0         # il tetto del corpo est, sopra il secondo vetrato
PRATO = 2.8            # il cortile, rialzato

STUCCO = "#D5CAB0"     # l'intonaco grigio-beige delle ali (foto del cortile)
OCRA = "#D9C49A"       # i padiglioni e gli avancorpi, più caldi (foto dal piazzale)
FRONTE = "#DCD6C8"     # il fronte ovest, più chiaro e liscio
STUCCO_CHIARO = "#E9E3D3"   # cornici, paraste, balaustre
BUGNATO = "#CFC3A6"
PIETRA = "#9C9890"     # lo zoccolo in granito
EST_INTONACO = "#E7E3D8"    # il corpo est, più chiaro
VETRO_SCURO = "#3D4752"     # le finestre, scure di giorno
TELAIO = "#F2F0EA"
COPPI = "coppi"
TETTO_PIANO = "#77797A"     # il tetto piano del fronte ovest, scuro nell'ortofoto
TETTO_EST = "#E4E4DF"       # il bordo chiaro del tetto del corpo est
PANNELLI = "#2E3A55"
GRIGIO_IMPIANTI = "#B9BDC2"
VETRO_SOPRA = "#9DB3C6"     # il secondo piano vetrato e il cubo di vetro
BIANCO = "#F4F5F3"
PRATO_C = "#7FA35E"
LASTRE = "#C9C5BB"
FERRO = "#2F3236"
TRONCO = "#6E5844"
CHIOMA = "#8DA868"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    """Sotto il tetto dell'ultimo piano (il secondo vetrato del corpo est)."""
    return EST_TOP - 0.6


# ------------------------------------------------------------------ coppi

def _coppi_texture():
    """Coppi rossi in file, 0,5 m per ripetizione lungo la gronda e lungo la falda: il canale
    tondo di ogni coppo, la sovrapposizione ogni 40 cm, toni un po' diversi."""
    from PIL import Image
    rng = np.random.default_rng(3)
    size = 256
    y, x = np.mgrid[0:size, 0:size]
    col = 4                                  # 4 coppi per 0,5 m: 12,5 cm l'uno
    w = size // col
    fx = (x % w) / w
    ridge = np.sin(fx * math.pi)             # il dorso tondo
    fy = (y % (size // 1)) / size
    lap = (fy * 1.25) % 1.0                  # le sovrapposizioni
    shade = 0.82 + 0.18 * ridge - 0.12 * (lap > 0.9)
    tone = rng.normal(0, 0.05, (col * 2, 2))[(y // (size // 2)) % 2 * 0 + (x // w) % (col * 2), (y // (size // 2)) % 2]
    base = np.array([0.70, 0.38, 0.25])
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


def falde(E, S, x0, y0, x1, y1, z, pendenza=0.5, sporto=0.6, colmo=None):
    """Un tetto a padiglione in coppi su un rettangolo allineato agli assi: le falde lunghe
    fino al colmo, le testate a triangolo; sotto, il soffitto della gronda."""
    x0, y0, x1, y1 = x0 - sporto, y0 - sporto, x1 + sporto, y1 + sporto
    w, d = x1 - x0, y1 - y0
    h = min(w, d) / 2 * pendenza if colmo is None else colmo
    if w >= d:
        r0, r1 = (x0 + d / 2, (y0 + y1) / 2), (x1 - d / 2, (y0 + y1) / 2)
    else:
        r0, r1 = ((x0 + x1) / 2, y0 + w / 2), ((x0 + x1) / 2, y1 - w / 2)
    c = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    top = lambda p: (p[0], p[1], z + h)
    # per ogni lato del rettangolo: i due angoli e la parte di colmo che gli sta sopra
    for i in range(4):
        a, b = c[i], c[(i + 1) % 4]
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        near = sorted([r0, r1], key=lambda r: math.dist(r, a))
        ra, rb = near[0], near[1]
        if math.dist(ra, rb) < 1e-6 or abs((b[0] - a[0]) * (rb[1] - ra[1]) - (b[1] - a[1]) * (rb[0] - ra[0])) > 1e-6:
            pts = [(*a, z), (*b, z), top(min([r0, r1], key=lambda r: math.dist(r, mid)))]
        else:
            pts = [(*a, z), (*b, z), top(rb), top(ra)]
        L = math.dist(a, b)
        u = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
        n = (u[1], -u[0])
        if (mid[0] - (x0 + x1) / 2) * n[0] + (mid[1] - (y0 + y1) / 2) * n[1] < 0:
            n = (-n[0], -n[1])
        uv = lambda p: ((p[0] - a[0]) * u[0] + (p[1] - a[1]) * u[1],
                        math.hypot(*(np.array(p[:2]) - np.array(a) - np.dot(np.array(p[:2]) - np.array(a), u) * np.array(u))) + (p[2] - z) * 0.4)
        want = (n[0], n[1], 1.0)
        if len(pts) == 4:
            S.quad(COPPI, pts, want, [uv(p) for p in pts])
        else:
            S.tri(COPPI, pts, want, [uv(p) for p in pts])
    S.quad(STUCCO_CHIARO, [(*p, z - 0.01) for p in c], (0, 0, -1))
    return z + h


# ------------------------------------------------------------------ facciate

def arco(t0, t1, z0, zs, seg=6):
    """Una finestra ad arco a tutto sesto: rettangolo fino all'imposta e mezzo cerchio."""
    r = (t1 - t0) / 2
    c = t0 + r
    return Polygon([(t0, z0), (t1, z0)] + [(c + r * math.cos(math.pi * k / seg), zs + r * math.sin(math.pi * k / seg))
                                          for k in range(seg + 1)])


def rett(t0, t1, z0, z1):
    return Polygon([(t0, z0), (t1, z0), (t1, z1), (t0, z1)])


def finestra(E, S, e, shape, telaio=0.16, sporge=0.12, divisioni=True, vetro=VETRO_SCURO):
    """Il vetro scuro appena dentro il filo, la cornice chiara intorno, il montante e il
    traverso bianchi."""
    E.panel(S, vetro, e, shape, 0.0, 0.02)
    E.panel(S, STUCCO_CHIARO, e, shape.buffer(telaio, join_style=2).difference(shape), 0.0, sporge)
    if divisioni:
        t0, z0, t1, z1 = shape.bounds
        tm = (t0 + t1) / 2
        bars = [rett(tm - 0.03, tm + 0.03, z0, z1)]
        zt = z0 + (z1 - z0) * 0.62
        bars.append(rett(t0, t1, zt - 0.03, zt + 0.03))
        E.panel(S, TELAIO, e, unary_union(bars).intersection(shape), 0.0, 0.05)


def campate(L, passo, bordo=1.0):
    """Le posizioni (centri lungo il lato) delle finestre: il numero intero di campate che ci
    sta, centrato."""
    n = max(0, int((L - 2 * bordo) / passo) + 1)
    if n == 0:
        return []
    usato = (n - 1) * passo
    return [L / 2 - usato / 2 + i * passo for i in range(n)]


def libero(e, altre, dentro=0.6):
    """Il tratto [t0, t1] del lato che non tocca un'altra parte (le facce in vista)."""
    a, c, u, n, L, _ = e
    seg = LineString([(a[0] + n[0] * 0.3, a[1] + n[1] * 0.3), (c[0] + n[0] * 0.3, c[1] + n[1] * 0.3)])
    coperto = seg.intersection(unary_union([p.buffer(0.05) for p in altre])) if altre else None
    tratti = [(0.0, L)]
    if coperto is not None and not coperto.is_empty:
        cut = []
        for g in getattr(coperto, "geoms", [coperto]):
            if g.length < 0.2:
                continue
            ts = sorted(float(np.dot(np.array(q) - np.array(a), np.array(u))) for q in g.coords)
            cut.append((ts[0], ts[-1]))
        for c0, c1 in cut:
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
    return [(t0, t1) for t0, t1 in tratti if t1 - t0 > 1.2]


def scurisci(hex_, k=0.95):
    h = hex_.lstrip("#")
    return "#" + "".join(f"{int(int(h[i:i + 2], 16) * k):02X}" for i in (0, 2, 4))


def palazzo(E, S, pts, altre, cortile, passo, primo="archi", ordine=False, base=0.0, cornicione=0.6, tinta=STUCCO):
    """Le facciate di un'ala storica: zoccolo in pietra con le finestre del seminterrato,
    terra bugnato con le finestre ad arco, la fascia marcapiano, il primo liscio con archi o
    finestre rette (e lunetta cieca), il fregio. Sul cortile lo zoccolo parte dal prato."""
    for e in E.edges(pts):
        a, c, u, n, L, _ = e
        mid = Point((a[0] + c[0]) / 2 + n[0] * 0.5, (a[1] + c[1]) / 2 + n[1] * 0.5)
        sul_cortile = cortile is not None and cortile.buffer(0.3).contains(mid)
        z_basso = PRATO if sul_cortile else base
        for t0, t1 in libero(e, altre):
            Lt = t1 - t0
            pos = [t0 + p for p in campate(Lt, passo)]
            # zoccolo, sporge 8 cm, con le bocche del seminterrato
            z_zoc = max(ZOCCOLO, z_basso + 0.4)
            zoc = rett(t0, t1, z_basso, z_zoc)
            fin_s = [] if sul_cortile else [rett(p - 0.5, p + 0.5, 1.0, 2.3) for p in pos]
            if sul_cortile:     # sul cortile le bocche del seminterrato stanno a filo del prato
                fin_s = [rett(p - 0.5, p + 0.5, z_zoc, z_zoc + 0.5) for p in pos]
            E.panel(S, PIETRA, e, zoc.difference(unary_union(fin_s)) if fin_s else zoc, 0.0, 0.1)
            for f in fin_s:
                E.panel(S, "#2A2E33", e, f, 0.0, 0.02)
                for k in range(1, 5):
                    tt = f.bounds[0] + (f.bounds[2] - f.bounds[0]) * k / 5
                    E.panel(S, FERRO, e, rett(tt - 0.02, tt + 0.02, f.bounds[1], f.bounds[3]), 0.0, 0.06)
            # terra bugnato: corsi da 55 cm con il giunto, interrotti dagli archi
            w_t = min(1.5, passo * 0.42)
            archi = [arco(p - w_t / 2, p + w_t / 2, Z_T + 0.6, Z_T + 3.3) for p in pos]
            fori = unary_union([g.buffer(0.22, join_style=2) for g in archi]) if archi else Polygon()
            fori = unary_union([fori] + [f.buffer(0.12, join_style=2) for f in fin_s])
            z = z_zoc
            while z < FASCIA - 0.1:
                z1 = min(FASCIA, z + 0.49)
                E.panel(S, scurisci(tinta), e, rett(t0, t1, z, z1).difference(fori), 0.0, 0.06)
                z += 0.55
            for g in archi:
                finestra(E, S, e, g)
                cx = (g.bounds[0] + g.bounds[2]) / 2
                E.panel(S, STUCCO_CHIARO, e, Polygon([(cx - 0.18, g.bounds[3] - 0.05), (cx + 0.18, g.bounds[3] - 0.05),
                                                       (cx + 0.24, g.bounds[3] + 0.4), (cx - 0.24, g.bounds[3] + 0.4)]), 0.0, 0.16)
            # fascia marcapiano
            E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, FASCIA, FASCIA + 0.4), 0.0, 0.22)
            # primo piano
            w_p = min(1.45, passo * 0.4)
            for p in pos:
                if primo == "archi":
                    g = arco(p - w_p / 2, p + w_p / 2, Z_1 + 0.9, Z_1 + 3.3)
                    finestra(E, S, e, g)
                    cx = p
                    E.panel(S, STUCCO_CHIARO, e, Polygon([(cx - 0.16, g.bounds[3] - 0.05), (cx + 0.16, g.bounds[3] - 0.05),
                                                           (cx + 0.22, g.bounds[3] + 0.35), (cx - 0.22, g.bounds[3] + 0.35)]), 0.0, 0.16)
                else:
                    g = rett(p - w_p / 2, p + w_p / 2, Z_1 + 0.9, Z_1 + 3.0)
                    finestra(E, S, e, g)
                    lun = arco(p - w_p / 2, p + w_p / 2, Z_1 + 3.25, Z_1 + 3.25).difference(rett(p - 2, p + 2, 0, Z_1 + 3.26))
                    E.panel(S, BUGNATO, e, lun, 0.0, 0.03)
                # il davanzale
                E.panel(S, STUCCO_CHIARO, e, rett(p - w_p / 2 - 0.2, p + w_p / 2 + 0.2, Z_1 + 0.75, Z_1 + 0.9), 0.0, 0.18)
                if ordine:      # i balaustrini sotto le finestre dei padiglioni
                    balaustrini(E, S, e, p - w_p / 2 - 0.1, p + w_p / 2 + 0.1, Z_1 + 0.1, Z_1 + 0.75, 0.0, 0.12)
            if ordine:          # le paraste, a coppie agli spigoli, una fra le finestre
                tp = [t0 + 0.45, t1 - 0.45] + [(p0 + p1) / 2 for p0, p1 in zip(pos, pos[1:])]
                for t in tp:
                    E.panel(S, scurisci(tinta), e, rett(t - 0.35, t + 0.35, ZOCCOLO, FASCIA), 0.0, 0.16)
                    E.panel(S, STUCCO_CHIARO, e, rett(t - 0.3, t + 0.3, FASCIA + 0.4, FREGIO - 0.3), 0.0, 0.14)
                    E.panel(S, STUCCO_CHIARO, e, rett(t - 0.42, t + 0.42, FREGIO - 0.45, FREGIO - 0.05), 0.0, 0.22)   # il capitello
            # fregio
            E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, FREGIO, FREGIO + 0.12), 0.0, 0.1)
        if ordine:
            for t0, t1 in libero(e, altre):
                for k in range(int((t1 - t0) / 0.9)):
                    t = t0 + 0.45 + k * 0.9
                    E.panel(S, STUCCO_CHIARO, e, rett(t - 0.12, t + 0.12, GRONDA - 0.75, GRONDA - 0.25), 0.0, cornicione)


def balaustrini(E, S, e, t0, t1, z0, z1, d0, d1, passo=0.28):
    """Una balaustra in facciata: lo zoccolo, i balaustrini e il corrimano."""
    E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, z0, z0 + 0.1), d0, d1)
    E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, z1 - 0.1, z1), d0, d1 + 0.03)
    k = max(1, int((t1 - t0) / passo))
    for i in range(k):
        t = t0 + (t1 - t0) * (i + 0.5) / k
        E.panel(S, STUCCO_CHIARO, e, Polygon([(t - 0.05, z0 + 0.1), (t + 0.05, z0 + 0.1), (t + 0.08, (z0 + z1) / 2 - 0.05),
                                               (t + 0.04, z1 - 0.1), (t - 0.04, z1 - 0.1), (t - 0.08, (z0 + z1) / 2 - 0.05)]),
                d0 + 0.02, d1 - 0.02)


def cornicione(E, S, pts, z, sporto, h=0.6, colore=STUCCO_CHIARO):
    """Il cornicione: un gradino sotto e la lastra che sporge."""
    E.prisma(S, colore, E.ring_ccw(Polygon(pts).buffer(sporto * 0.4, join_style=2)), z - h, z - h * 0.45)
    E.prisma(S, colore, E.ring_ccw(Polygon(pts).buffer(sporto, join_style=2)), z - h * 0.45, z)


def balaustra(E, S, pts, z, h=1.1, passo_piede=3.8, sfere=True, salta=()):
    """La balaustra sopra il cornicione: plinto, balaustrini, cimasa; i piedistalli agli
    spigoli e ogni passo_piede, con la sfera di pietra sopra."""
    piedi = []
    for a, c, u, n, L, _ in E.edges(pts):
        k = max(1, round(L / passo_piede))
        for i in range(k + 1):
            piedi.append((a[0] + u[0] * L * i / k, a[1] + u[1] * L * i / k))
        steps = int(L / 0.3)
        for i in range(steps):
            t = (i + 0.5) * L / steps
            x, y = a[0] + u[0] * t, a[1] + u[1] * t
            S.solid(STUCCO_CHIARO, trimesh.creation.cylinder(radius=0.07, height=h - 0.3, sections=4).apply_translation([x, y, z + 0.15 + (h - 0.3) / 2]))
        for z0, z1, w in ((z, z + 0.15, 0.4), (z + h - 0.15, z + h, 0.45)):
            q = [(a[0] - n[0] * w / 2, a[1] - n[1] * w / 2), (c[0] - n[0] * w / 2, c[1] - n[1] * w / 2),
                 (c[0] + n[0] * w / 2, c[1] + n[1] * w / 2), (a[0] + n[0] * w / 2, a[1] + n[1] * w / 2)]
            S.solid(STUCCO_CHIARO, E.hexa([(*p, z0) for p in q], [(*p, z1) for p in q]))
    seen = []
    for p in piedi:
        if any(math.dist(p, q) < 0.5 for q in seen):
            continue
        seen.append(p)
        S.solid(STUCCO_CHIARO, E.box_z(p[0], p[1], 0.6, 0.6, z, z + h + 0.15))
        if sfere:
            S.solid(STUCCO_CHIARO, E.box_z(p[0], p[1], 0.4, 0.4, z + h + 0.15, z + h + 0.3))
            S.solid(STUCCO_CHIARO, trimesh.creation.icosphere(subdivisions=1, radius=0.3).apply_translation([p[0], p[1], z + h + 0.6]))


def obelisco(E, S, x, y, z, h=4.2):
    S.solid(STUCCO_CHIARO, E.box_z(x, y, 0.9, 0.9, z, z + 0.8))
    S.solid(STUCCO_CHIARO, E.hexa([(x - 0.32, y - 0.32, z + 0.8), (x + 0.32, y - 0.32, z + 0.8), (x + 0.32, y + 0.32, z + 0.8), (x - 0.32, y + 0.32, z + 0.8)],
                                  [(x - 0.1, y - 0.1, z + h), (x + 0.1, y - 0.1, z + h), (x + 0.1, y + 0.1, z + h), (x - 0.1, y + 0.1, z + h)]))
    S.solid(STUCCO_CHIARO, E.hexa([(x - 0.1, y - 0.1, z + h), (x + 0.1, y - 0.1, z + h), (x + 0.1, y + 0.1, z + h), (x - 0.1, y + 0.1, z + h)],
                                  [(x, y, z + h + 0.35)] * 4))


# ------------------------------------------------------------------ corpo est

def loggia(E, S, x, y0, y1, passo=3.8):
    """La loggia del corpo est sul cortile (foto dal cortile): a terra gli archi su pilastri
    davanti al corridoio arretrato, al primo le finestre ad arco con i balaustrini e le paraste,
    poi il cornicione e il secondo piano vetrato."""
    prof = 3.2                 # il corridoio dietro gli archi (nella pianta, da -24,4 a -21,2)
    a, c = (x, y1), (x, y0)    # il lato guarda a ovest: da sud a nord
    e = (a, c, (0.0, -1.0), (-1.0, 0.0), y1 - y0, 0.0)
    L = y1 - y0
    pos = campate(L, passo, bordo=passo / 2)
    # il pavimento della loggia e la parete di fondo
    E.prisma(S, LASTRE, [(x, y0), (x + prof, y0), (x + prof, y1), (x, y1)], PRATO, Z_T)
    E.prisma(S, EST_INTONACO, [(x + prof, y0), (x + prof + 0.3, y0), (x + prof + 0.3, y1), (x + prof, y1)], Z_T, Z_1)
    for p in pos:              # le porte delle aule sul fondo
        f = rett(p - 0.6, p + 0.6, Z_T, Z_T + 2.4)
        e2 = ((x + prof, y1), (x + prof, y0), (0.0, -1.0), (-1.0, 0.0), L, 0.0)
        E.panel(S, "#B9B6AE", e2, f, 0.0, 0.03)
    # l'arcata: la parete forata dagli archi, spessa 0,6 m
    w_a = passo - 0.9
    vani = unary_union([arco(p - w_a / 2, p + w_a / 2, Z_T, Z_T + 3.2) for p in pos])
    E.panel(S, EST_INTONACO, e, rett(0, L, PRATO, Z_1).difference(vani), -0.6, 0.0)
    for p in pos:
        for t in (p - w_a / 2 - 0.45, p + w_a / 2 + 0.45):
            if 0.3 < t < L - 0.3:
                E.panel(S, STUCCO_CHIARO, e, rett(t - 0.3, t + 0.3, Z_T, Z_T + 3.0), 0.0, 0.12)      # i pilastri
        E.panel(S, STUCCO_CHIARO, e, arco(p - w_a / 2, p + w_a / 2, Z_T, Z_T + 3.2).buffer(0.25, join_style=2).difference(
            arco(p - w_a / 2, p + w_a / 2, Z_T, Z_T + 3.2)).difference(rett(-1, L + 1, PRATO - 1, Z_T + 3.2)), 0.0, 0.08)
    # il soffitto della loggia
    E.prisma(S, BIANCO, [(x - 0.6, y0), (x + prof, y0), (x + prof, y1), (x - 0.6, y1)], Z_1 - 0.6, Z_1)
    # il primo: parete piena con le finestre ad arco
    E.panel(S, STUCCO_CHIARO, e, rett(0, L, FASCIA, FASCIA + 0.4), 0.0, 0.2)
    w_p = 1.7
    fin = [arco(p - w_p / 2, p + w_p / 2, Z_1 + 0.9, Z_1 + 3.2) for p in pos]
    for p, g in zip(pos, fin):
        finestra(E, S, e, g, vetro="#566370")
        balaustrini(E, S, e, p - w_p / 2 - 0.15, p + w_p / 2 + 0.15, Z_1 + 0.1, Z_1 + 0.85, 0.0, 0.14)
    for p0, p1 in zip(pos, pos[1:]):
        t = (p0 + p1) / 2
        E.panel(S, STUCCO_CHIARO, e, rett(t - 0.3, t + 0.3, Z_1, Z_2 - 0.8), 0.0, 0.12)
    E.panel(S, STUCCO_CHIARO, e, rett(0, L, Z_2 - 0.6, Z_2), 0.0, 0.35)


def vetrato(E, S, pts, z0, z1, passo=1.5):
    """Il secondo piano del corpo est (la sopraelevazione): vetro a tutta altezza con i
    montanti bianchi, il parapetto e la veletta bianca in cima."""
    E.prisma(S, VETRO_SOPRA, pts, z0, z1)
    for a, c, u, n, L, _ in E.edges(pts):
        k = max(1, round(L / passo))
        for i in range(k + 1):
            x, y = a[0] + u[0] * L * i / k + n[0] * 0.05, a[1] + u[1] * L * i / k + n[1] * 0.05
            S.solid(BIANCO, E.box_z(x, y, 0.12, 0.12, z0, z1))
        for zz in (z0 + 1.0, z1 - 0.05):
            E.trave(S, BIANCO, (a[0] + n[0] * 0.06, a[1] + n[1] * 0.06, zz), (c[0] + n[0] * 0.06, c[1] + n[1] * 0.06, zz), 0.1)
    E.prisma(S, BIANCO, E.ring_ccw(Polygon(pts).buffer(0.15, join_style=2)), z1, z1 + 0.6)


def fotovoltaico(E, S, poly, z, margine=2.2, divisioni=(0.7,)):
    """I pannelli sul tetto del corpo est: un campo in due, divisi da un passaggio (ortofoto)."""
    campo = poly.buffer(-margine, join_style=2)
    if campo.is_empty:
        return
    x0, y0, x1, y1 = campo.bounds
    tagli = [y0] + [y0 + (y1 - y0) * f for f in divisioni] + [y1]
    for ya, yb in zip(tagli, tagli[1:]):
        pezzo = campo.intersection(box(x0, ya + 0.4, x1, yb - 0.4))
        for q in E.clean(pezzo):
            bx0, by0, bx1, by1 = q.bounds
            yy = by0
            while yy < by1 - 1.0:      # file di pannelli inclinati verso sud
                S.solid(PANNELLI, E.hexa([(bx0, yy, z + 0.3), (bx1, yy, z + 0.3), (bx1, yy + 1.0, z + 0.3), (bx0, yy + 1.0, z + 0.3)],
                                         [(bx0, yy, z + 0.75), (bx1, yy, z + 0.75), (bx1, yy + 1.0, z + 0.35), (bx0, yy + 1.0, z + 0.35)]))
                yy += 1.25


def scala_sicurezza(E, S, x0, x1, y_in, verso, z0, z1):
    """Le scale bianche in acciaio agli angoli del cortile: due rampe affiancate con il
    pianerottolo a metà, dal prato al primo, verso la loggia (est)."""
    alz = (z1 - z0) / 2
    n = max(2, round(alz / 0.17))
    run = x1 - x0 - 1.3
    for j, (ya, za) in enumerate(((y_in, z0), (y_in + verso * 1.3, z0 + alz))):
        yb = ya + verso * 1.2
        for i in range(n):
            f = i / n
            # la prima rampa sale verso ovest, la seconda torna verso est
            xs = (x1 - f * run, x1 - (f + 1 / n) * run) if j == 0 else (x0 + 1.3 + f * run, x0 + 1.3 + (f + 1 / n) * run)
            zz = za + alz * (i + 1) / n
            S.solid(BIANCO, E.hexa([(xs[0], min(ya, yb), zz - 0.05), (xs[1], min(ya, yb), zz - 0.05), (xs[1], max(ya, yb), zz - 0.05), (xs[0], max(ya, yb), zz - 0.05)],
                                   [(xs[0], min(ya, yb), zz), (xs[1], min(ya, yb), zz), (xs[1], max(ya, yb), zz), (xs[0], max(ya, yb), zz)]))
        for yr in (ya, yb):
            if j == 0:
                E.trave(S, BIANCO, (x1, yr, za + 1.0), (x1 - run, yr, za + alz + 1.0), 0.06)
            else:
                E.trave(S, BIANCO, (x0 + 1.3, yr, za + 1.0), (x1, yr, za + alz + 1.0), 0.06)
    ym0, ym1 = sorted((y_in, y_in + verso * 2.5))
    S.solid(BIANCO, E.box_z(x0 + 0.65, (ym0 + ym1) / 2, 1.3, ym1 - ym0, z0 + alz - 0.1, z0 + alz))      # pianerottolo
    S.solid(BIANCO, E.box_z(x1 + 0.6, (ym0 + ym1) / 2, 1.2, ym1 - ym0, z1 - 0.1, z1))                   # arrivo al primo
    for x, y in ((x0 + 0.1, ym0), (x0 + 0.1, ym1), (x1 + 1.1, ym0), (x1 + 1.1, ym1)):
        E.trave(S, BIANCO, (x, y, z0), (x, y, z1 if x > x1 else z0 + alz), 0.1)
    for y in (ym0, ym1):
        E.trave(S, BIANCO, (x0, y, z0 + alz + 1.0), (x0 + 1.3, y, z0 + alz + 1.0), 0.05)


# ------------------------------------------------------------------ guscio

def guscio(b, E):
    """L'esterno dell'Edificio 3: {chiave: mesh} e la quota più alta."""
    _registra(E)
    S = E.Solidi()
    parti = {p["nome"]: Polygon(p["pianta"]).buffer(0) for p in b["parti"]}
    cortile = Polygon(b["cortili"][0]).buffer(0) if b.get("cortili") else None
    passo = {p["nome"]: next((f.get("campata") for f in p["profilo"] if f.get("campata")), 4.2) for p in b["parti"]}
    # il corpo est guarda il cortile più a est di quanto dica la sua pianta: la loggia sta sul
    # filo del cortile
    x_l = cortile.bounds[2] if cortile else -24.4
    y_l0, y_l1 = 266.6, 303.1
    if cortile:
        ys = [q[1] for q in cortile.exterior.coords if abs(q[0] - x_l) < 0.3]
        y_l0, y_l1 = min(ys), max(ys)
    est = parti["est"].difference(box(-200, y_l0, x_l, y_l1))
    storiche = ["ala-nord", "ala-sud", "aula-nord", "aula-sud", "pad-nord", "pad-sud", "fronte"]
    tutte = {**{k: parti[k] for k in storiche}, "est": est, "torre-nord": parti["torre-nord"], "torre-sud": parti["torre-sud"]}
    # le masse: muri pieni fino al cornicione
    tinta = {n: OCRA if n.startswith("pad") else FRONTE if n == "fronte" else STUCCO for n in storiche}
    for nome in storiche:
        E.prisma(S, tinta[nome], E.ring_ccw(parti[nome]), 0.0, GRONDA)
    for nome in ("torre-nord", "torre-sud"):
        E.prisma(S, EST_INTONACO, E.ring_ccw(parti[nome]), 0.0, EST_TOP)
    # il corpo est è pieno tranne il corridoio della loggia, aperto sul cortile sotto il primo
    corridoio = box(x_l - 0.1, y_l0, x_l + 3.2, y_l1)
    E.prisma(S, EST_INTONACO, E.ring_ccw(est), 0.0, PRATO)
    for q in E.clean(est.difference(corridoio)):
        E.prisma(S, EST_INTONACO, E.ring_ccw(q), PRATO, Z_1 - 0.6)
    E.prisma(S, EST_INTONACO, E.ring_ccw(est), Z_1 - 0.6, Z_2)
    # le facciate delle ali storiche
    for nome in storiche:
        altre = [g for k, g in tutte.items() if k != nome]
        prof = next(p for p in b["parti"] if p["nome"] == nome)["profilo"]
        primo = next((f.get("finestre") for f in prof if f.get("piano") == "MIA0103001"), "archi")
        ordine = nome.startswith("pad")
        palazzo(E, S, E.ring_ccw(parti[nome]), altre, cortile, passo[nome],
                primo="rette" if primo == "rette" else "archi", ordine=ordine, tinta=tinta[nome])
    # le facciate del corpo est verso fuori: zoccolo, terra bugnato, primo con finestre rette
    altre_est = [g for k, g in tutte.items() if k != "est"]
    # la loggia sul cortile copre il lato ovest fra y_l0 e y_l1
    lato_loggia = box(x_l - 0.5, y_l0 - 0.1, x_l + 0.5, y_l1 + 0.1)
    palazzo(E, S, E.ring_ccw(est), altre_est + [lato_loggia], None, 4.2, primo="rette", tinta=EST_INTONACO)
    for nome in ("torre-nord", "torre-sud"):
        altre = [g for k, g in tutte.items() if k != nome]
        palazzo(E, S, E.ring_ccw(parti[nome]), altre, cortile, 3.0, primo="rette", tinta=EST_INTONACO)
    loggia(E, S, x_l, y_l0, y_l1)
    # il secondo piano vetrato e il tetto del corpo est
    sopra = est.union(parti["torre-nord"]).union(parti["torre-sud"]).buffer(0.01).buffer(-0.01)
    cornicione(E, S, E.ring_ccw(est), Z_2, 0.4, h=0.5)
    vetrato(E, S, E.ring_ccw(est.buffer(-0.2, join_style=2)), Z_2, EST_TOP - 0.6)
    E.prisma(S, TETTO_EST, E.ring_ccw(est.buffer(0.15, join_style=2)), EST_TOP - 0.6, EST_TOP - 0.3)
    # i pannelli sul corpo principale; alle testate a ovest i tetti scuri con gli impianti
    principale = est.intersection(box(-22.5, 240, 0, 330))
    fotovoltaico(E, S, principale, EST_TOP - 0.3)
    for nome in ("torre-nord", "torre-sud"):
        g = parti[nome]
        E.prisma(S, TETTO_PIANO, E.ring_ccw(g.buffer(-0.15, join_style=2)), EST_TOP, EST_TOP + 0.1)
        x0, y0, x1, y1 = g.bounds
        S.solid(GRIGIO_IMPIANTI, E.box_z((x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) * 0.6, (y1 - y0) * 0.4, EST_TOP, EST_TOP + 1.6))
    for y in (250.0, 320.0):          # gli impianti sulle testate del corpo est (ortofoto)
        S.solid(GRIGIO_IMPIANTI, E.box_z(-24.5, y, 2.5, 4.0, EST_TOP - 0.3, EST_TOP + 1.4))
    # il cubo di vetro sul tetto, sopra la torre sud (foto dal cortile)
    tx0, ty0, tx1, ty1 = parti["torre-sud"].bounds
    cubo = [(tx0 + 0.6, ty0 + 3.0), (tx1 - 0.3, ty0 + 3.0), (tx1 - 0.3, ty0 + 7.5), (tx0 + 0.6, ty0 + 7.5)]
    vetrato(E, S, cubo, EST_TOP, EST_TOP + 3.4, passo=1.2)
    # cornicioni, tetti a padiglione, balaustre, obelischi
    top = EST_TOP + 3.4
    for nome in ("ala-nord", "ala-sud", "aula-nord", "aula-sud"):
        g = parti[nome]
        cornicione(E, S, E.ring_ccw(g), GRONDA, 0.6, h=1.0)
        x0, y0, x1, y1 = g.bounds
        top = max(top, falde(E, S, x0, y0, x1, y1, GRONDA, pendenza=0.55, sporto=0.4))
    for nome in ("pad-nord", "pad-sud"):
        g = parti[nome]
        pts = E.ring_ccw(g)
        cornicione(E, S, pts, GRONDA, 0.9, h=1.0)
        E.prisma(S, OCRA, E.ring_ccw(g.buffer(-0.1, join_style=2)), GRONDA, GRONDA + 0.8)      # l'attico
        balaustra(E, S, E.ring_ccw(g.buffer(-0.35, join_style=2)), GRONDA + 0.8)
        x0, y0, x1, y1 = g.bounds
        falde(E, S, x0 + 1.1, y0 + 1.1, x1 - 1.1, y1 - 1.1, GRONDA + 0.8, pendenza=0.45, sporto=0.0)
    # il fronte ovest: tetto piano scuro dietro il parapetto, gli impianti della mappa
    g = parti["fronte"]
    cornicione(E, S, E.ring_ccw(g), GRONDA, 0.6, h=0.9)
    E.prisma(S, STUCCO, E.ring_ccw(g), GRONDA, GRONDA + 0.6)
    E.prisma(S, TETTO_PIANO, E.ring_ccw(g.buffer(-0.35, join_style=2)), GRONDA + 0.3, GRONDA + 0.62)
    for f in next(p for p in b["parti"] if p["nome"] == "fronte")["profilo"]:
        for x, y, w, d, hh in f.get("impianti", []):
            S.solid(GRIGIO_IMPIANTI, E.box_z(x + w / 2, y + d / 2, w, d, GRONDA + 0.62, GRONDA + 0.62 + hh * 0.4))
    # gli avancorpi d'ingresso a nord e a sud, sul fianco dei padiglioni (pianta del terra):
    # il portale ad arco, il balcone sopra, i due obelischi sulla balaustra
    for nome, verso in (("ala-nord", -1), ("ala-sud", 1)):
        g = parti[nome]
        y_f = g.bounds[1] if verso < 0 else g.bounds[3]
        xa, xb = -63.6, -58.2
        corpo = box(xa, min(y_f, y_f + verso * 1.4), xb, max(y_f, y_f + verso * 1.4))
        pts = E.ring_ccw(corpo)
        E.prisma(S, OCRA, pts, 0.0, GRONDA)
        fronte_e = [e for e in E.edges(pts) if abs(e[3][1] - verso) < 0.1][0]
        L = fronte_e[4]
        E.panel(S, PIETRA, fronte_e, rett(0, L, 0, ZOCCOLO), 0.0, 0.1)
        z = ZOCCOLO
        portale = arco(L / 2 - 1.5, L / 2 + 1.5, 0.0 if verso < 0 else Z_T, Z_T + 3.2 if verso < 0 else Z_T + 3.6)
        while z < FASCIA - 0.1:
            E.panel(S, scurisci(OCRA), fronte_e, rett(0, L, z, min(FASCIA, z + 0.49)).difference(portale.buffer(0.3)), 0.0, 0.08)
            z += 0.55
        E.panel(S, "#2B2A28", fronte_e, portale, 0.0, 0.02)
        E.panel(S, STUCCO_CHIARO, fronte_e, portale.buffer(0.3).difference(portale).difference(rett(-1, L + 1, -1, 0.0 if verso < 0 else Z_T)), 0.0, 0.16)
        E.panel(S, STUCCO_CHIARO, fronte_e, rett(0, L, FASCIA, FASCIA + 0.4), 0.0, 0.22)
        f1 = arco(L / 2 - 0.9, L / 2 + 0.9, Z_1 + 0.6, Z_1 + 3.2)
        finestra(E, S, fronte_e, f1)
        # il balcone con la balaustra
        E.panel(S, STUCCO_CHIARO, fronte_e, rett(L / 2 - 1.8, L / 2 + 1.8, Z_1 + 0.3, Z_1 + 0.6), 0.0, 1.0)
        balaustrini(E, S, fronte_e, L / 2 - 1.8, L / 2 + 1.8, Z_1 + 0.6, Z_1 + 1.6, 0.85, 1.0)
        for t in (0.4, L - 0.4):
            E.panel(S, STUCCO_CHIARO, fronte_e, rett(t - 0.35, t + 0.35, FASCIA + 0.4, FREGIO), 0.0, 0.18)
        cornicione(E, S, pts, GRONDA, 0.9, h=1.0)
        E.prisma(S, OCRA, pts, GRONDA, GRONDA + 0.8)
        balaustra(E, S, E.ring_ccw(corpo.buffer(-0.3, join_style=2)), GRONDA + 0.8)
        cx = (xa + xb) / 2
        for x in (xa + 0.6, xb - 0.6):
            obelisco(E, S, x, y_f + verso * 0.9, GRONDA + 0.8)
        if verso > 0:     # a sud la scalinata sale dal giardino al terra
            y_p = y_f + 1.4 + 1.5                 # il pianerottolo davanti al portale
            S.solid(LASTRE, E.box_z(cx, y_f + 1.4 + 0.75, 5.2, 1.5, 0.0, Z_T))
            for i in range(20):
                d = (20 - i) * 0.3
                S.solid(LASTRE, E.box_z(cx, y_p + d / 2, 5.2, d, 0.0, Z_T * (i + 1) / 21))
    # la bocca di lupo lungo il fronte ovest, con la ringhiera
    for y0, y1 in ((255.0, 300.0),):
        xw = parti["fronte"].bounds[0] - 1.4
        E.prisma(S, "#55585B", [(xw, y0), (parti["fronte"].bounds[0], y0), (parti["fronte"].bounds[0], y1), (xw, y1)], -0.02, 0.02)
        E.trave(S, FERRO, (xw, y0, 1.0), (xw, y1, 1.0), 0.05)
        for k in range(int((y1 - y0) / 1.5) + 1):
            E.trave(S, FERRO, (xw, y0 + k * 1.5, 0.0), (xw, y0 + k * 1.5, 1.0), 0.04)
    # il cortile: il prato rialzato, il bordo in lastre, l'ippocastano, le scale bianche
    if cortile:
        E.prisma(S, LASTRE, E.ring_ccw(cortile), 0.0, PRATO - 0.04)
        for q in E.clean(cortile.buffer(-1.6, join_style=2)):
            E.prisma(S, PRATO_C, E.ring_ccw(q), PRATO - 0.04, PRATO)
        tx, ty = -42.0, 279.0
        S.solid(TRONCO, trimesh.creation.cylinder(radius=0.3, height=5.0, sections=8).apply_translation([tx, ty, PRATO + 2.5]))
        S.solid(CHIOMA, trimesh.creation.icosphere(subdivisions=2, radius=4.6).apply_translation([tx, ty, PRATO + 8.0]))
        scala_sicurezza(E, S, -30.0, -26.4, 275.0, 1, PRATO, Z_1)
        scala_sicurezza(E, S, -30.0, -26.4, 296.0, -1, PRATO, Z_1)
    # il ponte coperto verso est, al terra (OpenStreetMap, pianta del terra)
    px0, px1, py0, py1 = parti["est"].bounds[2], 12.5, 265.9, 270.0
    E.prisma(S, PIETRA, [(px0, py0), (px1, py0), (px1, py1), (px0, py1)], Z_T - 0.5, Z_T)
    E.prisma(S, VETRO_SOPRA, [(px0, py0 + 0.1), (px1, py0 + 0.1), (px1, py1 - 0.1), (px0, py1 - 0.1)], Z_T, Z_T + 3.0)
    E.prisma(S, BIANCO, [(px0, py0 - 0.2), (px1, py0 - 0.2), (px1, py1 + 0.2), (px0, py1 + 0.2)], Z_T + 3.0, Z_T + 3.4)
    for x in np.arange(px0 + 3, px1, 5.0):
        for y in (py0 + 0.3, py1 - 0.3):
            E.trave(S, PIETRA, (x, y, 0.0), (x, y, Z_T - 0.5), 0.4)
    return S.meshes(), round(top, 2)


# ------------------------------------------------------------------ piante

def piante(b, geo, aule, E):
    """Le aule del primo e del secondo non hanno le file disegnate (le piante del terra sì).
    Le foto (aula S.1.4 al primo) mostrano gradoni bassi di banchi in legno in file dritte,
    la lavagna davanti e le finestre sulla sinistra: le file si aggiungono qui, parallele
    alla cattedra, ogni 95 cm, con i corridoi ai lati e in mezzo se l'aula è larga. La
    cattedra sta a sud nel corpo est e a nord nell'ala ovest (finestre a sinistra), verso il
    cortile nelle due aule sopra quelle del terra."""
    for csip, f in geo.items():
        ai = aule.get(csip, {})
        segs = f.setdefault("linee", {}).setdefault("arredi", [])
        nuovi = []
        for v in f["vani"]:
            if v["csiv"] not in ai:
                continue
            poly = E.shape_of(v)
            if poly.is_empty or poly.area < 30:
                continue
            dentro = poly.buffer(-0.05)
            suoi = [s_ for s_ in segs if dentro.contains(Point(s_[:2]))]
            lunghi = sum(1 for s_ in suoi if math.dist(s_[:2], s_[2:4]) > 0.8)
            if lunghi >= 3 and lunghi > 0.1 * len(suoi):
                continue          # file già disegnate
            if len(suoi) > 50:    # la sala De Donato: la pianta disegna le poltrone una per una
                file_ = file_da_poltrone(E, poly, suoi)
                if file_:
                    tolti = {id(s_) for s_ in suoi}
                    segs[:] = [s_ for s_ in segs if id(s_) not in tolti]
                    nuovi.extend(file_)
                    continue
            x0, y0, x1, y1 = poly.bounds
            cx, cy = poly.centroid.x, poly.centroid.y
            if cx > -28:
                avanti = 1        # cattedra a sud
            elif cx < -55:
                avanti = -1       # cattedra a nord
            else:
                avanti = 1 if cy < 285 else -1     # verso il cortile
            interno = poly.buffer(-0.8, join_style=2)
            if interno.is_empty:
                continue
            ix0, iy0, ix1, iy1 = interno.bounds
            larga = ix1 - ix0 > 13
            y_front = iy1 - 2.6 if avanti > 0 else iy0 + 2.6
            y_back = iy0 if avanti > 0 else iy1
            n = int(abs(y_front - y_back) / 0.95)
            for k in range(n):
                y = y_front - avanti * 0.95 * k
                riga = LineString([(x0 - 1, y), (x1 + 1, y)]).intersection(interno)
                for g in getattr(riga, "geoms", [riga]):
                    if g.is_empty or g.length < 2:
                        continue
                    a, c = g.coords[0], g.coords[-1]
                    a, c = (min(a[0], c[0]), y), (max(a[0], c[0]), y)
                    pezzi = [(a[0] + 0.4, c[0] - 0.4)]
                    if larga:
                        m = (a[0] + c[0]) / 2
                        pezzi = [(a[0] + 0.4, m - 0.6), (m + 0.6, c[0] - 0.4)]
                    for p0, p1 in pezzi:
                        if p1 - p0 > 1.5:
                            nuovi.append([round(p0, 2), round(y, 2), round(p1, 2), round(y, 2)])
        segs.extend(nuovi)
    return geo


ROSSO_POLTRONE, BANCO_SCURO = "#9B2C2C", "#3A3B3E"     # sala De Donato (foto)
LEGNO, LEGNO_SEDUTA = "#C58A4E", "#B9824C"             # aula S.1.4 (foto)
NERO_SALA, BIANCO_AULA = "#2E2F31", "#EEEDE8"


def ritocca(sc, meta, E):
    """I colori delle foto: al terra le poltrone rosse e i banchi scuri della sala De Donato,
    con le pareti nere della sala; al primo e al secondo i banchi e le sedute in legno e le
    pareti bianche dell'aula S.1.4."""
    for name, m in sc.s.geometry.items():
        colore = m.metadata.get("colore")
        if "_Arredi_" in name:
            terra = name.startswith("MIA0103000")
            nuovo = {E.SEAT: ROSSO_POLTRONE if terra else LEGNO_SEDUTA,
                     E.DESK: BANCO_SCURO if terra else LEGNO}.get(colore)
        elif "_Interno_" in name and colore == E.COL["muri"]:
            nuovo = NERO_SALA if name.startswith("MIA0103000010") else BIANCO_AULA
        else:
            nuovo = None
        if nuovo:
            E.colour(m, nuovo)


def file_da_poltrone(E, poly, segs):
    """Le file di una sala dalle poltrone disegnate una per una: i quadrati delle sedute,
    unite in file quelle a meno di 70 cm (le file distano di più); ogni fila diventa la
    linea del banco, 45 cm davanti alle sedute, verso il lato libero della sala."""
    from shapely.ops import polygonize
    sedute = [g for g in polygonize([LineString([s_[:2], s_[2:4]]) for s_ in segs]) if 0.12 < g.area < 0.45]
    if len(sedute) < 20:
        return None
    c = np.array([[g.centroid.x, g.centroid.y] for g in sedute])
    # componenti connesse a meno di 0,7 m
    gruppo = list(range(len(c)))
    def radice(i):
        while gruppo[i] != i:
            gruppo[i] = gruppo[gruppo[i]]
            i = gruppo[i]
        return i
    for i in range(len(c)):
        d = np.linalg.norm(c - c[i], axis=1)
        for j in np.nonzero((d < 0.7) & (d > 0))[0]:
            gruppo[radice(i)] = radice(int(j))
    file_ = {}
    for i in range(len(c)):
        file_.setdefault(radice(i), []).append(c[i])
    libero = poly.difference(unary_union(sedute).convex_hull.buffer(0.5))
    verso_libero = np.array(libero.centroid.coords[0]) - c.mean(axis=0) if not libero.is_empty else np.zeros(2)
    out = []
    for pts in file_.values():
        if len(pts) < 3:
            continue
        pts = np.array(pts)
        m = pts.mean(axis=0)
        u = np.linalg.svd(pts - m)[2][0]
        n = np.array([-u[1], u[0]])
        if np.dot(n, verso_libero) < 0:
            n = -n
        t = (pts - m) @ u
        a = m + u * (t.min() - 0.25) + n * 0.45
        b = m + u * (t.max() + 0.25) + n * 0.45
        out.append(([round(a[0], 2), round(a[1], 2), round(b[0], 2), round(b[1], 2)], u, len(pts)))
    if not out:
        return None
    # le file vanno tutte nello stesso verso: fuori quelle storte (poltrone lungo i muri)
    _, u0, _ = max(out, key=lambda o: o[2])
    out = [r for r, u, _ in out if abs(float(np.dot(u, u0))) > 0.95]
    return out if len(out) >= 3 else None
