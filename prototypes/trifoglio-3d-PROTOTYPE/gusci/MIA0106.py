"""PROTOTIPO — l'Edificio 6 "Giulio Natta" (MIA0106), l'esterno rifatto da zero.

Fonti, oltre ai contorni di leonardo.json e alle piante del Politecnico:
- l'ortofoto (Google, zoom 21, 5 cm per pixel): il corpo storico in coppi intorno ai due
  pozzi di luce, con le falde a padiglione e i compluvi; la spina fra i pozzi, più bassa, col
  suo tettuccio e il vano dell'ascensore; l'ottagono a ovest col tetto a padiglione; il blocco
  sud; la torre a nord col tetto piano grigio, tre macchine in fila e un volume tecnico; la
  striscia bassa dei laboratori lungo il lato est. L'ortofoto non è zenitale: il tetto della
  torre appare spostato di circa 4,4 m verso nord, e lo si riporta sulla pianta;
- la foto "Ciminiera neve" (Wikimedia Commons): la torre dietro la ciminiera dell'Edificio 4,
  intonaco chiaro, finestre singole in griglia con le tende da sole, la striscia vetrata
  della scala all'angolo sud del lato ovest, la lastra del cornicione e i camini delle cappe
  in fila sul tetto;
- la foto dell'Aula Natta (Alumni Polimi): file ripide di banchi in legno rossiccio, muri
  bianchi, finestre alte con le tende blu.

Le quote vengono dalle scale delle piante. Le scale esterne del rialzato hanno 8-10 alzate:
il rialzato del corpo storico sta 1,5 m sopra il giardino. Nella torre la scala dal piano
000 al rialzato ha 17 alzate (circa 3 m) e quelle dei piani alti 22-27: il piano 000 esiste
solo nella torre, 1,5 m sotto il giardino, sul cortile di servizio ribassato a nord. Il
seminterrato sta sotto il 000. Il corpo storico ha tre piani sopra lo zoccolo (rialzato,
primo, secondo: le piante del secondo coprono tutto il corpo), la torre sette.
Coordinate Z-up del frame del campus: x est, y sud.
"""
import math
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union

CSIE = "MIA0106"

Z_S, Z_0, Z_R, Z_1, Z_2 = -4.6, -1.5, 1.5, 6.3, 10.9
TORRE_PIANO = 3.7
QUOTE = {"MIA010600S": Z_S, "MIA0106000": Z_0, "MIA010600R": Z_R, "MIA0106001": Z_1, "MIA0106002": Z_2,
         **{f"MIA010600{k}": round(Z_2 + TORRE_PIANO * (k - 2), 2) for k in range(3, 7)}}
TORRE_TOP = round(Z_2 + TORRE_PIANO * 5, 2)      # il solaio del tetto della torre, 29,4 m
FASCIA_1, FASCIA_2 = 5.9, 10.4   # le fasce marcapiano sotto il primo e sotto il secondo
FREGIO = 13.9
GRONDA = 14.8          # il cornicione del corpo storico
SPINA_GRONDA = 10.6    # la spina fra i pozzi, più bassa (ortofoto)
POZZI_TOP = 6.0        # i corpi a un piano dentro i pozzi, con la terrazza

STUCCO = "#D3CBB8"         # l'intonaco grigio-beige del corpo storico
BUGNATO = "#C6BDA8"
STUCCO_CHIARO = "#E8E3D6"  # cornici, fasce, cornicione
PIETRA = "#9D9990"         # lo zoccolo
TORRE = "#E4DDCB"          # l'intonaco chiaro della torre (foto)
TORRE_BORDO = "#EFEBE1"
VETRO_SCURO = "#3B4652"
TELAIO = "#F2F0EA"
TENDA = "#B8AE98"          # le tende da sole della torre
TETTO_PIANO = "#8D9091"    # il tetto della torre, grigio nell'ortofoto
TERRAZZA = "#9A9C98"
IMPIANTI = "#C3C7CB"
FERRO = "#2F3236"
LASTRE = "#B9B5AC"
VETRO_SCALA = "#7F95A8"
COPPI = "coppi"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    """Sotto il tetto dell'ultimo piano (il sesto, nella torre)."""
    return TORRE_TOP - 0.4


# ------------------------------------------------------------------ coppi

def _coppi_texture():
    """Coppi rossi in file, 0,5 m per ripetizione: il dorso tondo di ogni coppo, la
    sovrapposizione ogni 40 cm, toni un po' diversi (come l'Edificio 3)."""
    from PIL import Image
    rng = np.random.default_rng(6)
    size = 256
    y, x = np.mgrid[0:size, 0:size]
    col = 4
    w = size // col
    ridge = np.sin((x % w) / w * math.pi)
    lap = ((y / size) * 1.25) % 1.0
    shade = 0.82 + 0.18 * ridge - 0.12 * (lap > 0.9)
    tone = rng.normal(0, 0.05, (col * 2,))[(x // w) % (col * 2)]
    base = np.array([0.69, 0.40, 0.28])
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


def _semipiano(w, c, R=2000.0):
    """Il semipiano w·p <= c come poligono grande."""
    w = np.array(w, float)
    k = np.linalg.norm(w)
    w, c = w / k, c / k
    p0 = w * c
    t = np.array([-w[1], w[0]])
    return Polygon([tuple(p0 + t * R), tuple(p0 - t * R), tuple(p0 - t * R - w * R), tuple(p0 + t * R - w * R)])


def padiglione(E, S, poly, z, pendenza=0.55, sporto=0.6):
    """Un tetto a padiglione in coppi su un poligono convesso: ogni lato ha la sua falda,
    e in ogni punto vale la falda più bassa (le linee dove due falde si incontrano sono
    i displuvi e il colmo). Sotto, la lastra della gronda. Torna la quota del colmo."""
    P = poly.buffer(sporto, join_style=2)
    pts = E.ring_ccw(P)
    es = E.edges(pts)
    top = z
    for i, (a, c, u, n, L, _) in enumerate(es):
        reg = P
        di0 = float(np.dot(a, n))
        for j, (a2, c2, u2, n2, L2, _) in enumerate(es):
            if j == i or abs(float(np.dot(n, n2)) - 1) < 1e-9:
                continue
            # d_i(p) <= d_j(p), con d(p) = a·n - p·n la distanza dal lato verso l'interno
            reg = reg.intersection(_semipiano(np.array(n2) - np.array(n), float(np.dot(a2, n2)) - di0))
            if reg.is_empty:
                break
        for q in E.clean(reg):
            ring = list(q.exterior.coords)[:-1]
            if len(ring) < 3:
                continue
            d = lambda p: di0 - (p[0] * n[0] + p[1] * n[1])
            P3 = [(p[0], p[1], z + pendenza * d(p)) for p in ring]
            uv = [((p[0] - a[0]) * u[0] + (p[1] - a[1]) * u[1], d(p) * math.hypot(1, pendenza)) for p in ring]
            want = (n[0] * pendenza, n[1] * pendenza, 1.0)
            for k in range(1, len(ring) - 1):
                S.tri(COPPI, [P3[0], P3[k], P3[k + 1]], want, [uv[0], uv[k], uv[k + 1]])
            top = max(top, max(p[2] for p in P3))
    E.prisma(S, STUCCO_CHIARO, pts, z - 0.14, z - 0.01)
    return top


# ------------------------------------------------------------------ facciate

def arco(t0, t1, z0, zs, seg=8):
    """Un'apertura ad arco a tutto sesto: rettangolo fino all'imposta e mezzo cerchio."""
    r = (t1 - t0) / 2
    c = t0 + r
    return Polygon([(t0, z0), (t1, z0)] + [(c + r * math.cos(math.pi * k / seg), zs + r * math.sin(math.pi * k / seg))
                                          for k in range(seg + 1)])


def rett(t0, t1, z0, z1):
    return Polygon([(t0, z0), (t1, z0), (t1, z1), (t0, z1)])


def finestra(E, S, e, shape, cornice=0.15, sporge=0.1, vetro=VETRO_SCURO, colore=STUCCO_CHIARO):
    """Il vetro scuro appena dentro il filo, la cornice chiara, montante e traverso bianchi."""
    E.panel(S, vetro, e, shape, 0.0, 0.02)
    if cornice:
        E.panel(S, colore, e, shape.buffer(cornice, join_style=2).difference(shape), 0.0, sporge)
    t0, z0, t1, z1 = shape.bounds
    tm = (t0 + t1) / 2
    zt = z0 + (z1 - z0) * 0.62
    bars = unary_union([rett(tm - 0.03, tm + 0.03, z0, z1), rett(t0, t1, zt - 0.03, zt + 0.03)])
    E.panel(S, TELAIO, e, bars.intersection(shape), 0.0, 0.05)


def campate(L, passo, bordo=1.0):
    """I centri delle finestre lungo un lato: il numero intero di campate che ci sta, centrato."""
    n = max(0, int((L - 2 * bordo) / passo) + 1)
    usato = (n - 1) * passo
    return [L / 2 - usato / 2 + i * passo for i in range(n)]


def libero(e, altre):
    """I tratti [t0, t1] del lato che non toccano un'altra parte: le facce in vista."""
    a, c, u, n, L, _ = e
    seg = LineString([(a[0] + n[0] * 0.3, a[1] + n[1] * 0.3), (c[0] + n[0] * 0.3, c[1] + n[1] * 0.3)])
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
    return [(t0, t1) for t0, t1 in tratti if t1 - t0 > 1.2]


def cornicione(E, S, pts, z, sporto, h=0.8, colore=STUCCO_CHIARO):
    """Il cornicione: un gradino sotto e la lastra che sporge."""
    E.prisma(S, colore, E.ring_ccw(Polygon(pts).buffer(sporto * 0.4, join_style=2)), z - h, z - h * 0.45)
    E.prisma(S, colore, E.ring_ccw(Polygon(pts).buffer(sporto, join_style=2)), z - h * 0.45, z)


def storico(E, S, pts, altre, passo, piani=3, alte=False):
    """Le facciate del corpo storico, come le altre ali di Brusconi del campus: lo zoccolo in
    pietra con le bocche del seminterrato, il rialzato bugnato con le finestre ad arco, la
    fascia, il primo liscio ad archi, la seconda fascia, il secondo con finestre rette, il
    fregio. piani dice fin dove arriva il corpo (1: solo il rialzato, i corpi nei pozzi).
    alte: le finestre del primo più alte, per l'aula a gradoni dell'ottagono."""
    for e in E.edges(pts):
        for t0, t1 in libero(e, altre):
            pos = [t0 + p for p in campate(t1 - t0, passo)]
            # lo zoccolo, con le bocche di lupo del seminterrato
            bocche = [rett(p - 0.55, p + 0.55, 0.25, 1.05) for p in pos]
            E.panel(S, PIETRA, e, rett(t0, t1, 0.0, Z_R).difference(unary_union(bocche)), 0.0, 0.1)
            for f in bocche:
                E.panel(S, "#2A2E33", e, f, 0.0, 0.02)
                x0, z0, x1, z1 = f.bounds
                for k in range(1, 6):
                    tt = x0 + (x1 - x0) * k / 6
                    E.panel(S, FERRO, e, rett(tt - 0.02, tt + 0.02, z0, z1), 0.0, 0.07)
            # il rialzato bugnato, corsi da 50 cm, interrotti dagli archi
            archi = [arco(p - 0.7, p + 0.7, Z_R + 0.9, Z_R + 3.1) for p in pos]
            fori = unary_union([g.buffer(0.2, join_style=2) for g in archi])
            z = Z_R
            while z < FASCIA_1 - 0.05:
                E.panel(S, BUGNATO, e, rett(t0, t1, z, min(FASCIA_1, z + 0.45)).difference(fori), 0.0, 0.06)
                z += 0.5
            for g in archi:
                finestra(E, S, e, g)
                cx = (g.bounds[0] + g.bounds[2]) / 2
                E.panel(S, STUCCO_CHIARO, e, Polygon([(cx - 0.16, g.bounds[3] - 0.05), (cx + 0.16, g.bounds[3] - 0.05),
                                                       (cx + 0.22, g.bounds[3] + 0.35), (cx - 0.22, g.bounds[3] + 0.35)]), 0.0, 0.15)
            if piani == 1:
                E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, FASCIA_1, FASCIA_1 + 0.35), 0.0, 0.2)
                continue
            E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, FASCIA_1, FASCIA_1 + 0.4), 0.0, 0.22)
            # il primo: finestre ad arco con il davanzale
            for p in pos:
                g = arco(p - 0.7, p + 0.7, Z_1 + 0.75, Z_1 + (3.3 if alte else 2.6))
                finestra(E, S, e, g)
                E.panel(S, STUCCO_CHIARO, e, rett(p - 0.9, p + 0.9, Z_1 + 0.6, Z_1 + 0.75), 0.0, 0.18)
            if piani == 2:
                continue
            E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, FASCIA_2, FASCIA_2 + 0.3), 0.0, 0.18)
            # il secondo: finestre rette, più basse, con la cornice
            for p in pos:
                finestra(E, S, e, rett(p - 0.6, p + 0.6, Z_2 + 0.8, Z_2 + 2.5))
                E.panel(S, STUCCO_CHIARO, e, rett(p - 0.8, p + 0.8, Z_2 + 0.65, Z_2 + 0.8), 0.0, 0.16)
            E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, FREGIO, FREGIO + 0.15), 0.0, 0.1)
            # le mensole sotto il cornicione
            for k in range(int((t1 - t0) / 0.9)):
                t = t0 + 0.45 + k * 0.9
                E.panel(S, STUCCO_CHIARO, e, rett(t - 0.1, t + 0.1, GRONDA - 0.75, GRONDA - 0.35), 0.0, 0.45)


# ------------------------------------------------------------------ la torre

def torre(E, S, g, altre, scale):
    """La torre dei laboratori (foto "Ciminiera neve"): intonaco chiaro, una griglia di
    finestre singole con qualche tenda da sole, la striscia vetrata dove una scala tocca la
    facciata, la lastra del cornicione e il tetto piano. Parte dal cortile ribassato a nord
    (il piano 000)."""
    pts = E.ring_ccw(g)
    E.prisma(S, TORRE, pts, Z_0, TORRE_TOP + 0.9)
    livelli = [Z_0, Z_R] + [Z_1, Z_2] + [Z_2 + TORRE_PIANO * k for k in range(1, 5)]
    for e in E.edges(pts):
        a, c, u, n, L, _ = e
        strisce = []
        for sc_ in scale:          # le scale contro questo lato: vetrata a tutta altezza
            x0, y0, x1, y1 = sc_.bounds
            ts = sorted(float(np.dot(np.array(q) - np.array(a), np.array(u))) for q in sc_.exterior.coords)
            ds = [float(np.dot(np.array(q) - np.array(a), np.array(n))) for q in sc_.exterior.coords]
            if max(ds) > -0.8 and ts[0] < L and ts[-1] > 0:
                strisce.append((max(0.3, ts[0] + 0.3), min(L - 0.3, ts[-1] - 0.3)))
        for t0, t1 in libero(e, altre):
            pos = [t0 + p for p in campate(t1 - t0, 2.85, bordo=1.2)]
            pos = [p for p in pos if not any(s0 - 0.9 < p < s1 + 0.9 for s0, s1 in strisce)]
            for i, z in enumerate(livelli):
                for j, p in enumerate(pos):
                    f = rett(p - 0.75, p + 0.75, z + 0.95, z + 2.65)
                    finestra(E, S, e, f, cornice=0.08, sporge=0.06, colore=TORRE_BORDO)
                    E.panel(S, TORRE_BORDO, e, rett(p - 0.85, p + 0.85, z + 0.85, z + 0.95), 0.0, 0.12)
                    if (i * 3 + j * 7 + int(a[0])) % 5 < 2 and z > Z_R:      # le tende abbassate
                        E.panel(S, TENDA, e, rett(p - 0.8, p + 0.8, z + 1.7, z + 2.7), 0.25, 0.32)
        for s0, s1 in strisce:
            if s1 - s0 < 1:
                continue
            vetro = rett(s0, s1, Z_0 + 0.3, TORRE_TOP - 0.2)
            E.panel(S, VETRO_SCALA, e, vetro, 0.0, 0.03)
            k = max(1, round((s1 - s0) / 0.9))
            for i in range(k + 1):
                t = s0 + (s1 - s0) * i / k
                E.panel(S, TELAIO, e, rett(t - 0.04, t + 0.04, Z_0 + 0.3, TORRE_TOP - 0.2), 0.0, 0.07)
            zz = Z_0 + 0.3
            while zz < TORRE_TOP:
                E.panel(S, TELAIO, e, rett(s0, s1, zz - 0.04, zz + 0.04), 0.0, 0.07)
                zz += 0.9
    # la lastra del cornicione, il parapetto, il tetto
    E.prisma(S, TORRE_BORDO, E.ring_ccw(g.buffer(0.55, join_style=2)), TORRE_TOP + 0.5, TORRE_TOP + 0.9)
    E.prisma(S, TETTO_PIANO, E.ring_ccw(g.buffer(-0.3, join_style=2)), TORRE_TOP + 0.9, TORRE_TOP + 0.95)
    E.prisma(S, TORRE_BORDO, E.ring_ccw(g), TORRE_TOP + 0.9, TORRE_TOP + 1.4)
    E.prisma(S, TETTO_PIANO, E.ring_ccw(g.buffer(-0.25, join_style=2)), TORRE_TOP + 0.9, TORRE_TOP + 1.45)
    zt = TORRE_TOP + 1.0
    # tre macchine in fila e il volume tecnico (ortofoto, riportate sulla pianta)
    for x0, x1 in ((72.0, 79.0), (80.8, 87.6), (87.8, 93.2)):
        S.solid(IMPIANTI, E.box_z((x0 + x1) / 2, 177.3, x1 - x0, 2.6, zt, zt + 1.6))
        for k in range(int((x1 - x0) / 1.2)):
            S.solid("#7E848A", E.box_z(x0 + 0.6 + k * 1.2, 177.3, 0.8, 0.8, zt + 1.6, zt + 1.75))
    S.solid(IMPIANTI, E.box_z(85.0, 182.2, 3.2, 2.4, zt, zt + 2.4))
    # i camini delle cappe, in fila lungo il lato nord (foto)
    x0, y0, x1, y1 = g.bounds
    for k in range(13):
        x = x0 + 2.0 + k * (x1 - x0 - 4.0) / 12
        S.solid("#8A8F94", trimesh.creation.cylinder(radius=0.14, height=2.2, sections=10).apply_translation([x, y0 + 1.2, zt + 1.1]))
        S.solid("#6F7378", trimesh.creation.cylinder(radius=0.24, height=0.25, sections=10).apply_translation([x, y0 + 1.2, zt + 2.3]))
    return TORRE_TOP + 2.5


# ------------------------------------------------------------------ guscio

def scalinate(E, S, b, corpo):
    """Le scale esterne del rialzato, dove la pianta le disegna fuori dal contorno: un
    blocco di gradini dal giardino al rialzato, che scende allontanandosi dal muro."""
    import json
    geo = json.loads((E.SRC / "piante" / f"{CSIE}-geometria.json").read_text())["piani"]
    lin = geo["MIA010600R"]["linee"].get("scale", [])
    fuori = [LineString([s_[:2], s_[2:4]]) for s_ in lin if not corpo.buffer(0.3).contains(Point(s_[:2]))
             and corpo.distance(Point(s_[:2])) < 4.0]
    if not fuori:
        return
    gruppi = unary_union([l.buffer(0.35) for l in fuori])
    for gr in E.clean(gruppi):
        if gr.area < 1.5:
            continue
        hull = gr.convex_hull.buffer(-0.3, join_style=2)
        if hull.is_empty:
            continue
        # verso: dal muro più vicino verso fuori
        p_muro = corpo.exterior.interpolate(corpo.exterior.project(hull.centroid))
        d = np.array(hull.centroid.coords[0]) - np.array(p_muro.coords[0])
        d = d / (np.linalg.norm(d) or 1)
        q = [float(np.dot(np.array(c), d)) for c in hull.exterior.coords]
        q0, q1 = min(q), max(q)
        n = 9
        for k in range(n):
            fetta = hull.intersection(_semipiano(d, q0 + (q1 - q0) * (k + 1) / n))
            for f in E.clean(fetta):
                E.prisma(S, LASTRE, E.ring_ccw(f), 0.0 if k == 0 else Z_R * (n - k) / n - Z_R / n, Z_R * (n - k) / n)


def guscio(b, E):
    """L'esterno dell'Edificio 6: {chiave: mesh} e la quota più alta."""
    _registra(E)
    S = E.Solidi()
    parti = {p["nome"]: Polygon(p["pianta"]).buffer(0) for p in b["parti"]}
    passo = {p["nome"]: next((f.get("campata") for f in p["profilo"] if f.get("campata")), 3.8) for p in b["parti"]}
    tg = parti["torre"]
    storiche = ["nord", "est", "ovest", "sud", "abside", "blocco-sud"]
    corpi = {k: parti[k] for k in storiche}
    # l'ala nord abbraccia la torre: a ovest della torre arriva fino al suo filo nord, sotto la
    # torre parte dal suo filo sud (ortofoto). Due rettangoli, ognuno col suo padiglione.
    x0n, y0n, x1n, y1n = parti["nord"].bounds
    del corpi["nord"]
    corpi["nord-ovest"] = box(x0n, y0n, tg.bounds[0], y1n)
    corpi["nord-est"] = box(tg.bounds[0], tg.bounds[3], x1n, y1n)
    storiche = ["nord-ovest", "nord-est"] + storiche[1:]
    corpi["spina"] = parti["spina"]
    corpi["pozzo-nord"], corpi["pozzo-sud"] = parti["pozzo-nord"], parti["pozzo-sud"]
    # la striscia bassa dei laboratori lungo il lato est (ortofoto, porte delle piante a x 91)
    annesso = box(86.0, 189.0, 90.6, 236.8)
    tutti = {**corpi, "torre": tg, "annesso": annesso}
    # le masse piene
    for nome in storiche:
        E.prisma(S, STUCCO, E.ring_ccw(corpi[nome]), 0.0, GRONDA)
    E.prisma(S, STUCCO, E.ring_ccw(corpi["spina"]), 0.0, SPINA_GRONDA)
    for nome in ("pozzo-nord", "pozzo-sud"):
        E.prisma(S, STUCCO, E.ring_ccw(corpi[nome]), 0.0, POZZI_TOP)
    # le facciate
    for nome in storiche:
        altre = [g for k, g in tutti.items() if k != nome and not k.startswith("pozzo")]
        storico(E, S, E.ring_ccw(corpi[nome]), altre, passo.get(nome, 3.8), alte=(nome == "abside"))
    storico(E, S, E.ring_ccw(corpi["spina"]), [g for k, g in tutti.items() if k != "spina"], 3.8, piani=2)
    for nome in ("pozzo-nord", "pozzo-sud"):
        storico(E, S, E.ring_ccw(corpi[nome]), [g for k, g in tutti.items() if k != nome], 3.8, piani=1)
    # cornicioni e tetti a padiglione: ogni ala con le sue falde, i compluvi dove si incontrano
    top = GRONDA
    for nome in storiche:
        cornicione(E, S, E.ring_ccw(corpi[nome]), GRONDA, 0.6)
    for nome in ("nord-ovest", "nord-est", "est", "ovest", "sud", "blocco-sud"):
        top = max(top, padiglione(E, S, corpi[nome], GRONDA, 0.55, 0.5))
    top = max(top, padiglione(E, S, corpi["abside"], GRONDA, 0.6, 0.5))
    cornicione(E, S, E.ring_ccw(corpi["spina"]), SPINA_GRONDA, 0.4, h=0.6)
    padiglione(E, S, parti["spina"].intersection(box(66.0, 204.0, 77.0, 210.5)), SPINA_GRONDA, 0.5, 0.3)
    # il vano dell'ascensore bianco sulla spina (ortofoto)
    S.solid(TORRE_BORDO, E.box_z(72.6, 210.3, 2.2, 2.2, SPINA_GRONDA, SPINA_GRONDA + 3.0))
    # le terrazze dei corpi nei pozzi: parapetto, pavimento grigio, qualche fioriera
    for nome in ("pozzo-nord", "pozzo-sud"):
        g = corpi[nome]
        E.prisma(S, STUCCO_CHIARO, E.ring_ccw(g), POZZI_TOP, POZZI_TOP + 0.9)
        E.prisma(S, TERRAZZA, E.ring_ccw(g.buffer(-0.3, join_style=2)), POZZI_TOP, POZZI_TOP + 0.95)
        x0, y0, x1, y1 = g.bounds
        for k in range(3):
            S.solid("#7E9A62", trimesh.creation.icosphere(subdivisions=1, radius=0.7).apply_translation(
                [x0 + 1.5 + k * (x1 - x0 - 3) / 2, y0 + 1.2, POZZI_TOP + 1.4]))
    # la torre
    scale_torre = []
    import json
    geo = json.loads((E.SRC / "piante" / f"{CSIE}-geometria.json").read_text())["piani"]
    for v in geo["MIA0106004"]["vani"]:
        if v["tipo"] == "scale":
            scale_torre.append(E.shape_of(v))
    top = max(top, torre(E, S, tg, [g for k, g in tutti.items() if k != "torre"], scale_torre))
    # il cortile ribassato a nord della torre, al piano 000: muro di sostegno e ringhiera
    x0, y0, x1, y1 = tg.bounds
    cortile = box(x0, y0 - 6.0, x1, y0)
    E.prisma(S, LASTRE, E.ring_ccw(cortile), Z_0 - 0.1, Z_0)
    for a_, c_ in (((x0, y0 - 6.0), (x1, y0 - 6.0)), ((x0, y0 - 6.0), (x0, y0)), ((x1, y0 - 6.0), (x1, y0))):
        seg = LineString([a_, c_]).buffer(0.15, cap_style=2)
        E.prisma(S, PIETRA, E.ring_ccw(seg), Z_0, 0.1)
        E.trave(S, FERRO, (*a_, 1.1), (*c_, 1.1), 0.05)
    # la rampa per i furgoni, contro il lato ovest del cortile
    for k in range(10):
        S.solid(LASTRE, E.box_z(x0 + 1.6, y0 - 6.0 + 0.3 + k * 0.6, 3.0, 0.6, Z_0 - 0.05, Z_0 * (k + 1) / 10))
    # la striscia dei laboratori a est: un piano, tetto piano scuro con i condotti
    E.prisma(S, "#CFC9BA", E.ring_ccw(annesso), 0.0, 4.0)
    E.prisma(S, "#6E7275", E.ring_ccw(annesso.buffer(0.15, join_style=2)), 4.0, 4.25)
    ae = [e for e in E.edges(E.ring_ccw(annesso)) if e[3][0] > 0.9][0]
    for t in np.arange(1.6, ae[4] - 1.0, 3.9):
        E.panel(S, "#56606B", ae, rett(t - 0.55, t + 0.55, 0.0, 2.4), 0.0, 0.03)        # le porte dei laboratori
        E.panel(S, VETRO_SCURO, ae, rett(t + 1.0, t + 2.4, 1.2, 2.6), 0.0, 0.02)
    for y in np.arange(192.0, 236.0, 6.5):
        S.solid("#9AA2AC", trimesh.creation.cylinder(radius=0.25, height=2.5, sections=10).apply_translation([88.8, y, 5.4]))
    # le scale esterne del rialzato
    corpo = unary_union([g.buffer(0.01) for k, g in corpi.items()] + [tg]).buffer(-0.01)
    scalinate(E, S, b, max(E.clean(corpo), key=lambda q: q.area))
    return S.meshes(), round(top, 2)


# ------------------------------------------------------------------ piante

# L'aula 6.0.1 (275 posti) è l'Aula Natta, nell'ottagono del primo piano: la pianta disegna i
# due corridoi a gradini, che convergono verso la cattedra a est. Le file si aggiungono qui,
# in tre settori (fra il muro e il primo corridoio, fra i due, fra il secondo e il muro),
# ognuno girato come il suo corridoio, ogni 80 cm come i gradini.
NATTA = "MIA0106001057"
LOMBARDI = "MIA0106001056"


def piante(b, geo, aule, E):
    f = geo["MIA0106001"]
    segs = f.setdefault("linee", {}).setdefault("arredi", [])
    poly = next(E.shape_of(v) for v in f["vani"] if v["csiv"] == NATTA)
    fuoco = np.array([65.1, 208.3])
    # i corridoi: da (53,9, 205,5) a (46,6, 203,7) e da (53,9, 211,0) a (46,7, 212,9)
    ang = math.atan2(205.49 - 203.70, 53.87 - 46.63)
    # gli angoli dei tre settori dal fuoco (0 = verso ovest, negativi verso nord)
    limiti = [(-1.2, -ang - 0.07), (-ang + 0.07, ang - 0.07), (ang + 0.07, 1.2)]
    interno = poly.buffer(-0.5, join_style=2)
    for (l0, l1), mid in zip(limiti, (-ang - 0.12, 0.0, ang + 0.12)):
        # nei settori laterali le file girano poco più dei corridoi: il muro è dritto
        r_dir = np.array([-math.cos(mid), math.sin(mid)])     # dal fuoco verso ovest
        t_dir = np.array([-r_dir[1], r_dir[0]])
        cuneo = Polygon([tuple(fuoco), tuple(fuoco + 40 * np.array([-math.cos(l0), math.sin(l0)])),
                         tuple(fuoco + 40 * np.array([-math.cos(l1), math.sin(l1)]))])
        zona = interno.intersection(cuneo)
        for k in range(13):
            d = 11.6 + 0.8 * k                  # la prima fila a 11,6 m dal fuoco: x ~53,5
            c = fuoco + r_dir * d
            riga = LineString([tuple(c - t_dir * 12), tuple(c + t_dir * 12)]).intersection(zona)
            for g in getattr(riga, "geoms", [riga]):
                if g.is_empty or g.length < 1.5:
                    continue
                a_, c_ = np.array(g.coords[0]), np.array(g.coords[-1])
                u = (c_ - a_) / np.linalg.norm(c_ - a_)
                a_, c_ = a_ + u * 0.3, c_ - u * 0.3
                segs.append([round(a_[0], 2), round(a_[1], 2), round(c_[0], 2), round(c_[1], 2)])
    # l'aula dipartimentale Lombardi (40 posti): tavoli in file, cattedra a nord, porte a ovest
    poly = next(E.shape_of(v) for v in f["vani"] if v["csiv"] == LOMBARDI)
    x0, y0, x1, y1 = poly.buffer(-0.6, join_style=2).bounds
    y = y0 + 2.4
    while y + 0.6 < y1:
        for yy in (y, y + 0.6):
            segs.append([round(x0 + 0.4, 2), round(yy, 2), round(x1 - 0.4, 2), round(yy, 2)])
        y += 1.25
    return geo


LEGNO, LEGNO_SEDUTA = "#8A4E2E", "#7A4428"      # il legno rossiccio dell'Aula Natta (foto)
BIANCO_AULA = "#EEEDE8"


def ritocca(sc, meta, E):
    """I colori delle foto: nell'Aula Natta i banchi e le sedute in legno rossiccio, pareti e
    soffitto bianchi."""
    for name, m in sc.s.geometry.items():
        colore = m.metadata.get("colore")
        nuovo = None
        if name.startswith("MIA0106001_Arredi_"):
            nuovo = {E.SEAT: LEGNO_SEDUTA, E.DESK: LEGNO}.get(colore)
        elif "_Interno_" in name and colore in (E.COL["muri"], E.CEMENTO_SOFF):
            nuovo = BIANCO_AULA       # muri e soffitto intonacati di bianco, come nella foto
        if nuovo:
            E.colour(m, nuovo)
