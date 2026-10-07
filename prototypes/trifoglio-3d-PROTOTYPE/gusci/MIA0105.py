"""PROTOTIPO — l'Edificio 5 "Arturo Danusso" (MIA0105), l'esterno rifatto da zero.

Fonti, oltre ai contorni di leonardo.json e alle piante (piante/MIA0105-geometria.json):
- l'ortofoto (Google, zoom 21, 5 cm per pixel): il tetto ad anello in coppi intorno al
  cortile, con i compluvi verdi in rame agli angoli e i lucernari a filo di falda; il
  padiglione nord a padiglione, con gli spigoli smussati; il terzo piano a T con il tetto
  piano grigio, il gruppo frigo a otto ventole e l'unità rossa; il tetto a padiglione
  dell'aula sud su via Celoria con la vetrata a nastro nella falda sud; i due corpi bassi a
  tetto piano ai lati del cortile di servizio; il capannone in lamiera grecata a est, con il
  colmo nord-sud, la testata nord a padiglione e quella sud a capanna; il raccordo basso con
  gli impianti; la sala studio a tetto piano bianco;
- le foto delle aule nel sito degli spazi del Politecnico (aule 5.0.1, 5.02, 5.03, 5.1.1,
  Beltrami, Castigliano): pareti bianche, finestre ad arco, travi nere e pilastri foderati in
  legno, banchi scuri e sedute rosse nelle aule del padiglione, sedute in faggio nella 5.02,
  grigie nella 5.03, tavoli scuri e sedie in faggio nelle aule piane;
- le foto di Urbanfile da via Celoria (2022) e gli altri edifici del 1927 sullo stesso lotto
  (Edificio 3): intonaco grigio-beige, zoccolo in pietra, terra bugnato con le finestre ad
  arco, fascia marcapiano, primo liscio con gli archi, secondo con le finestre rette,
  cornicione e coppi.

- le foto di Urbanfile del cantiere della palazzina Lerici (gennaio, marzo e luglio 2022,
  "adiacente all'edificio 5"): l'aula sud su via Celoria è un solo piano alto in finta pietra
  grigio-beige a bugne lisce, con lo zoccolo in granito e le grate del seminterrato, i
  finestroni ad arco con l'archivolto e le inferriate a disegno, il cornicione con la gronda;
  la facciata ovest, lungo il passaggio fra l'Edificio 5 e la Lerici, ha il terra a bugne
  grezze grigie con le finestre rette sotto una piattabanda a cunei con la chiave, gli archi
  al primo.

Le finestre del primo e del secondo stanno dove le disegnano le piante (linee.finestre); il
terra e il seminterrato le ripetono in colonna. Il terra a bugne grezze vale per tutte le
facciate esterne del corpo; verso il cortile resta bugnato liscio ad archi, come nel cortile
dell'Edificio 3 (foto di Wikimedia Commons). Il lato nord e quello est non hanno foto.

Quote come l'Edificio 3, con cui si collega con la passerella al terra: seminterrato a quota
del cortile (le porte esterne della pianta sono al seminterrato), terra a 3,6 m, primo a
8,8, secondo a 13,6, il terzo a T dentro il tetto a 18,2. Coordinate Z-up del frame del
campus: x est, y sud.
"""
import math
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString, Point, box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

CSIE = "MIA0105"

QUOTE = {"MIA010500S": 0.0, "MIA0105000": 3.6, "MIA0105001": 8.8, "MIA0105002": 13.6, "MIA0105003": 18.2}
ZOCCOLO = 1.3          # lo zoccolo in pietra
FASCIA = 8.4           # la fascia marcapiano fra terra e primo
GRONDA = 18.0          # il cornicione del corpo intorno al cortile
GRONDA_PAD = 14.8      # il padiglione nord (5.0.1 e 5.1.1), più basso
GRONDA_SUD = 10.0      # l'aula sud su via Celoria
BASSI = 8.4            # i due corpi bassi del cortile di servizio
TERZO = (18.0, 21.6)   # il terzo piano a T, dentro il tetto
PENDENZA = 0.5         # le falde in coppi, circa 27°

STUCCO = "#D6CBB2"     # l'intonaco grigio-beige (Edificio 3, via Celoria)
BUGNATO = "#CDBF9F"
STUCCO_CHIARO = "#E8E2D2"   # cornici, fasce, davanzali
RUSTICO = "#B4AE9E"    # il terra verso l'esterno: bugne grezze grigie (foto del passaggio della Lerici)
PIETRA_CELORIA = "#CBC4B1"  # l'aula su via Celoria: finta pietra a bugne lisce, grigio-beige
GIUNTO = "#8F8A7E"          # i giunti fra le bugne
PIETRA = "#9E9A91"     # lo zoccolo
GRIGIO = "#C9CBCB"     # il terzo piano, intonaco grigio
INTONACO = "#E2DED5"   # capannone, raccordo, sala studio
VETRO = "#3D4752"
TELAIO = "#F2F0EA"
FERRO = "#2F3236"
TETTO_PIANO = "#8E908F"     # i tetti piani grigi dell'ortofoto
TETTO_BEIGE = "#B9AF9C"     # il raccordo
LAMIERA = "#C4C7C6"         # il capannone
MEMBRANA = "#EDEDE9"        # la sala studio
VETRATA = "#93B7BF"         # la vetrata nella falda dell'aula sud
IMPIANTI = "#B7BBBF"
VENTOLA = "#3C3F43"
ROSSO_UNITA = "#9A4B3C"
LASTRE = "#C9C5BB"
TRONCO, CHIOMA = "#6E5844", "#7FA060"
COPPI = "coppi5"            # chiave propria: gli altri edifici usano "coppi" a un'altra scala


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    """Sotto il tetto piano del terzo a T."""
    return TERZO[1] - 0.4


# ------------------------------------------------------------------ texture

def _coppi_texture():
    """Coppi in file: 6 canali per metro, corsi da 40 cm, toni del cotto un po' diversi."""
    from PIL import Image
    rng = np.random.default_rng(5)
    size = 512                               # un metro
    y, x = np.mgrid[0:size, 0:size]
    u, v = x / size, y / size
    ch = (u * 6) % 1.0
    row = (v * 2.5) % 1.0
    height = np.sin(ch * math.pi) ** 0.6 * (0.75 + 0.25 * row)
    tone = rng.normal(0, 0.06, (3, 6))[(v * 2.5).astype(int) % 3, (u * 6).astype(int) % 6]
    base = np.array([0.71, 0.42, 0.30])
    rgb = base[None, None] * (0.8 + 0.3 * height + tone)[..., None]
    rgb[row < 0.04] *= 0.72
    gy, gx = np.gradient(height)
    nrm = np.dstack([-gx * 20, gy * 20, np.ones_like(height)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    to8 = lambda a: Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return to8(rgb), to8(nrm * 0.5 + 0.5)


def _registra(E):
    if COPPI not in E.TEX:
        E.TEX[COPPI] = 1.0
        E._TEXTURES[COPPI] = _coppi_texture()


# ------------------------------------------------------------------ attrezzi

def _croce(a, b):
    """Il prodotto vettoriale in 2D (numpy 2 non lo fa più su vettori di due componenti)."""
    return a[0] * b[1] - a[1] * b[0]


def rett(t0, t1, z0, z1):
    return box(t0, z0, t1, z1)


def arco(t0, t1, z0, z1, seg=8):
    """Una finestra ad arco a tutto sesto: z1 è la chiave."""
    r = (t1 - t0) / 2
    zs = max(z0 + 0.1, z1 - r)
    pts = [(t0, z0), (t1, z0), (t1, zs)]
    for i in range(1, seg):
        a = math.pi * i / seg
        pts.append(((t0 + t1) / 2 + r * math.cos(a), zs + r * math.sin(a)))
    pts.append((t0, zs))
    return Polygon(pts)


def finestra(E, S, e, shape, telaio=0.15, sporge=0.12, vetro=VETRO):
    """Il vetro scuro, la cornice chiara intorno, montante e traverso bianchi."""
    E.panel(S, vetro, e, shape, 0.0, 0.02)
    E.panel(S, STUCCO_CHIARO, e, shape.buffer(telaio, join_style=2).difference(shape), 0.0, sporge)
    t0, z0, t1, z1 = shape.bounds
    tm = (t0 + t1) / 2
    zt = z0 + (z1 - z0) * 0.62
    bars = unary_union([rett(tm - 0.03, tm + 0.03, z0, z1), rett(t0, t1, zt - 0.03, zt + 0.03)])
    E.panel(S, TELAIO, e, bars.intersection(shape), 0.0, 0.05)


def anelli(g):
    """Gli anelli di un poligono con il fuori a destra di ogni lato (come vuole E.edges):
    il contorno in senso antiorario, i cortili in senso orario."""
    out = []
    for p in (g.geoms if hasattr(g, "geoms") else [g]):
        p = orient(p, 1.0)
        out.append(list(p.exterior.coords)[:-1])
        out += [list(r.coords)[:-1] for r in p.interiors]
    return out


def tratti_liberi(e, masse, z_top, sé):
    """I tratti [t0, t1] del lato che restano in vista fino a z_top: quelli davanti a cui non
    c'è un'altra massa alta almeno quanto z_top."""
    a, c, u, n, L, _ = e
    alte = [g for k, (g, z) in masse.items() if k != sé and z >= z_top - 0.05]
    if not alte:
        return [(0.0, L)]
    davanti = unary_union([g.buffer(0.05) for g in alte])
    out, t0, step = [], None, 0.2
    ts = np.arange(0.0, L + 1e-6, step)
    for t in ts:
        p = Point(a[0] + u[0] * t + n[0] * 0.3, a[1] + u[1] * t + n[1] * 0.3)
        libero = not davanti.contains(p)
        if libero and t0 is None:
            t0 = t
        if not libero and t0 is not None:
            out.append((t0, t))
            t0 = None
    if t0 is not None:
        out.append((t0, L))
    return [(max(0.0, x0), min(L, x1)) for x0, x1 in out if x1 - x0 > 0.8]


def campate(t0, t1, passo, bordo=1.0):
    """I centri delle finestre a passo costante, centrati nel tratto."""
    L = t1 - t0
    n = max(0, int((L - 2 * bordo) / passo) + 1)
    usato = (n - 1) * passo
    return [t0 + L / 2 - usato / 2 + i * passo for i in range(n)]


def centri_da_pianta(b, E, csip, pts, e_index, t0, t1):
    """I centri delle finestre di un piano disegnate sul lato, nel tratto."""
    ws = E.plan_windows(b, csip, pts).get(e_index, [])
    return [((a + c) / 2, c - a) for a, c in ws if t0 + 0.5 < (a + c) / 2 < t1 - 0.5]


# ------------------------------------------------------------------ tetti

def _semipiano(w, c, B):
    """{p: w·p <= c} dentro il riquadro B."""
    w = np.array(w, float)
    k = np.linalg.norm(w)
    if k < 1e-9:
        return B if c >= 0 else Polygon()
    wh = w / k
    p0 = wh * c / k
    d = np.array([-wh[1], wh[0]])
    M = 1e4
    q = [p0 + d * M, p0 - d * M, p0 - d * M - wh * M, p0 + d * M - wh * M]
    return Polygon([tuple(x) for x in q]).intersection(B)


def falde(E, S, poly, z, pend=PENDENZA, sporto=0.6, key=COPPI, timpani=(), vetri=(), taglio=None,
          colmo=None, muro=STUCCO, sotto=STUCCO_CHIARO):
    """Un tetto a falde di pendenza costante su un poligono qualsiasi (anche con cortili):
    ogni falda è la parte di tetto più vicina al suo lato, come in un tetto vero, con le
    displuviate agli angoli sporgenti e i compluvi agli angoli rientranti. I lati verso le
    direzioni in `timpani` restano a capanna, con il muro triangolare. `vetri` diventano
    vetrate nella falda, `taglio` si toglie (un corpo più alto che esce dal tetto), `colmo`
    taglia il tetto in piano a quell'altezza. Ritorna la quota più alta."""
    P = orient(poly.buffer(sporto, join_style=2, mitre_limit=4.0).buffer(0), 1.0)
    if P.geom_type != "Polygon":
        P = max(P.geoms, key=lambda g: g.area)
    x0, y0, x1, y1 = P.bounds
    B = box(x0 - 50, y0 - 50, x1 + 50, y1 + 50)
    lati = []
    for r in [list(P.exterior.coords)[:-1]] + [list(i.coords)[:-1] for i in P.interiors]:
        r = [p for i, p in enumerate(r) if math.dist(p, r[i - 1]) > 0.05]
        m = len(r)
        dirs = []
        for i in range(m):
            a, c = np.array(r[i]), np.array(r[(i + 1) % m])
            dirs.append((c - a) / np.linalg.norm(c - a))
        for i in range(m):
            a, c = np.array(r[i]), np.array(r[(i + 1) % m])
            u = dirs[i]
            n = np.array([-u[1], u[0]])                    # verso dentro
            gable = any(np.dot(-n, np.array(t)) > 0.9 for t in timpani)
            conv0 = _croce(dirs[i - 1], u) > 1e-6
            conv1 = _croce(u, dirs[(i + 1) % m]) > 1e-6
            lati.append(dict(a=a, c=c, u=u, n=n, L=float(np.linalg.norm(c - a)), gable=gable,
                             conv0=conv0, conv1=conv1, prev=None, next=None))
        k0 = len(lati) - m
        for i in range(m):
            lati[k0 + i]["prev"] = lati[k0 + (i - 1) % m]
            lati[k0 + i]["next"] = lati[k0 + (i + 1) % m]
    BIG = 500.0
    for l in lati:
        lo = 0.0 if l["conv0"] and not l["prev"]["gable"] else -BIG
        hi = l["L"] if l["conv1"] and not l["next"]["gable"] else l["L"] + BIG
        a, u, n = l["a"], l["u"], l["n"]
        l["D"] = lambda p, a=a, n=n: float(np.dot(np.array(p[:2]) - a, n))
        l["T"] = lambda p, a=a, u=u: float(np.dot(np.array(p[:2]) - a, u))
        l["strip"] = (_semipiano(-u, -(np.dot(a, u) + lo), B).intersection(_semipiano(u, np.dot(a, u) + hi, B))
                      .intersection(_semipiano(-n, -np.dot(a, n), B)))
    attivi = [l for l in lati if not l["gable"]]
    vetri_u = unary_union(list(vetri)) if vetri else Polygon()
    top = z
    for i, l in enumerate(attivi):
        R = P.intersection(l["strip"])
        for j, f in enumerate(attivi):
            if f is l or R.is_empty:
                continue
            w = l["n"] - f["n"]
            c = np.dot(l["n"], l["a"]) - np.dot(f["n"], f["a"])
            if np.linalg.norm(w) < 1e-9:
                vince = c > 1e-6 or (abs(c) <= 1e-6 and j > i)
                allowed = B if vince else Polygon()
            else:
                allowed = _semipiano(w, c, B)
            R = R.intersection(unary_union([allowed, B.difference(f["strip"])]))
        if colmo is not None:
            R = R.intersection(_semipiano(l["n"], np.dot(l["n"], l["a"]) + colmo / pend, B))
        if taglio is not None:
            R = R.difference(taglio)
        R = R.buffer(0)
        pezzi = [(R, key)] if vetri_u.is_empty else [(R.difference(vetri_u), key), (R.intersection(vetri_u), VETRATA)]
        for parte, chiave in pezzi:
            for q in E.clean(parte):
                vs, fs = trimesh.creation.triangulate_polygon(q)
                k = math.sqrt(1 + pend * pend)
                for f3 in fs:
                    pts = [(vs[t][0], vs[t][1], z + pend * max(0.0, l["D"](vs[t]))) for t in f3]
                    uvs = [(l["T"](p), l["D"](p) * k) for p in pts]
                    S.tri(chiave, pts, (0, 0, 1), uvs if chiave == key else None)
                    top = max(top, *(p[2] for p in pts))
    if colmo is not None:
        piano = P.buffer(-colmo / pend, join_style=2)
        if taglio is not None:
            piano = piano.difference(taglio)
        for q in E.clean(piano):
            E.prisma(S, key if key != COPPI else TETTO_PIANO, E.ring_ccw(q), z + colmo - 0.05, z + colmo)
    # il sottogronda
    for q in E.clean(P.difference(poly.buffer(0.02))):
        vs, fs = trimesh.creation.triangulate_polygon(q)
        for f3 in fs:
            S.tri(sotto, [(vs[t][0], vs[t][1], z - 0.02) for t in f3], (0, 0, -1))
    # i timpani: il muro sotto la falda dei lati a capanna
    for g in (l for l in lati if l["gable"]):
        L = g["L"]
        prof = []
        for t in np.linspace(0, L, 41):
            p = g["a"] + g["u"] * t + g["n"] * 0.01
            h = min((f["D"](p) for f in attivi if f["strip"].buffer(0.02).contains(Point(p))), default=0.0)
            prof.append((t, z + pend * max(0.0, h)))
        sh = Polygon([(0, z - 0.5)] + prof + [(L, z - 0.5)]).buffer(0)
        e = (tuple(g["a"]), tuple(g["c"]), tuple(g["u"]), tuple(-g["n"]), L, 0.0)
        E.panel(S, muro, e, sh, -0.6, 0.0)
    return top


def lucernari():
    """(x, y, verso della falda in salita, filo del muro sotto la gronda) dei lucernari
    dell'ortofoto."""
    out = []
    for y in np.arange(262.0, 297.0, 3.2):
        out += [(14.0, float(y), (1, 0), 11.8), (53.6, float(y), (-1, 0), 55.4)]
    for x in (14.6, 18.0, 49.0, 52.4):
        out.append((x, 258.2, (0, 1), 256.3))
    for x in np.arange(26.0, 46.0, 3.0):
        out.append((float(x), 296.2, (0, -1), 298.0))
    for y in (272.0, 277.5, 283.0):                     # sul cortile
        out += [(24.0, y, (-1, 0), 22.1), (43.6, y, (1, 0), 45.6)]
    for x in (28.0, 33.0, 38.0):
        out.append((x, 289.5, (0, 1), 287.5))
    return out


def lucernario(E, S, x, y, n, filo, z_gronda, sporto=0.6, pend=PENDENZA):
    """Un lucernario da 70 x 110 cm sulla falda: telaio grigio e vetro scuro, a filo."""
    n = np.array(n, float)
    u = np.array([-n[1], n[0]])
    # la distanza dal bordo della gronda, in salita lungo n
    d = abs((x if n[1] == 0 else y) - filo) + sporto
    def p(du, dd, h):
        q = np.array([x, y]) + u * du + n * dd
        return (q[0], q[1], z_gronda + pend * (d + dd) + h)
    for key, w, l, h in (("#7E848A", 0.4, 0.62, 0.06), (VETRO, 0.33, 0.54, 0.09)):
        giu = [p(-w, -l, -0.05), p(w, -l, -0.05), p(w, l, -0.05), p(-w, l, -0.05)]
        S.solid(key, E.hexa(giu, [(q[0], q[1], q[2] + 0.05 + h) for q in giu]))


# ------------------------------------------------------------------ facciate

def palazzo(E, S, b, g, masse, nome, z_top, piani, passo=4.2, colore=STUCCO, cornice=0.6, terra_fuori="arco"):
    """Le facciate storiche di una massa: zoccolo in pietra con le finestre del seminterrato,
    terra bugnato con le finestre ad arco, la fascia marcapiano, poi un registro per piano
    sopra la fascia; il fregio e il cornicione. `piani` è la lista dei registri sopra la
    fascia: (csip della pianta per le finestre o None, z del davanzale, z della chiave,
    'arco' o 'retta'). `terra_fuori` è il terra delle facciate esterne: 'arco' come nei
    cortili, o 'retta' (bugne grezze e finestre rette con la piattabanda, come la facciata
    ovest nelle foto del passaggio fra l'Edificio 5 e la palazzina Lerici)."""
    for pts in anelli(g):
        fuori = Polygon(pts).exterior.is_ccw
        for ie, e in enumerate(E.edges(pts)):
            for t0, t1 in tratti_liberi(e, masse, z_top - 1.0, nome):
                _palazzo_tratto(E, S, b, pts, ie, e, t0, t1, z_top, piani, passo, colore, cornice,
                                terra_fuori if fuori else "arco")
            # il muro sopra le masse più basse (i corpi addossati): liscio, con il cornicione
            for t0, t1 in tratti_liberi(e, masse, z_top, nome):
                E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, z_top - 0.55, z_top), 0.0, cornice)
                E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, z_top - 0.85, z_top - 0.55), 0.0, cornice * 0.5)


def _palazzo_tratto(E, S, b, pts, ie, e, t0, t1, z_top, piani, passo, colore, cornice, terra="arco"):
    # le finestre: dalla pianta del primo registro, o a passo costante
    centri = []
    for csip, *_ in piani:
        if csip:
            centri = centri_da_pianta(b, E, csip, pts, ie, t0, t1)
            if centri:
                break
    if not centri:
        centri = [(t, 1.3) for t in campate(t0, t1, passo)]
    w_t = lambda w: max(1.0, min(1.5, w))
    # zoccolo con le finestre del seminterrato
    fin_s = [rett(t - 0.55, t + 0.55, 0.7, 2.4) for t, _ in centri]
    zoc = rett(t0, t1, 0.0, ZOCCOLO).difference(unary_union([f.buffer(0.1, join_style=2) for f in fin_s]))
    E.panel(S, PIETRA, e, zoc, 0.0, 0.1)
    for f in fin_s:
        E.panel(S, "#2A2E33", e, f, 0.0, 0.02)
        E.panel(S, STUCCO_CHIARO, e, f.buffer(0.1, join_style=2).difference(f), 0.0, 0.1)
        fx0, fz0, fx1, fz1 = f.bounds
        for k in range(1, 5):
            tt = fx0 + (fx1 - fx0) * k / 5
            E.panel(S, FERRO, e, rett(tt - 0.02, tt + 0.02, fz0, fz1), 0.0, 0.06)
    zt = QUOTE["MIA0105000"]
    if terra == "retta":
        # terra a bugne grezze: finestre rette con la piattabanda a cunei e la chiave
        archi = [rett(t - w_t(w) / 2, t + w_t(w) / 2, zt + 0.8, zt + 3.3) for t, w in centri]
        piatte = [Polygon([(a.bounds[0] - 0.1, a.bounds[3]), (a.bounds[2] + 0.1, a.bounds[3]),
                           (a.bounds[2] + 0.45, a.bounds[3] + 0.75), (a.bounds[0] - 0.45, a.bounds[3] + 0.75)])
                  for a in archi]
        fori = unary_union([a.buffer(0.12, join_style=2) for a in archi] + piatte +
                           [f.buffer(0.1, join_style=2) for f in fin_s])
        z, k = ZOCCOLO, 0
        while z < FASCIA - 0.1:
            corso = rett(t0, t1, z, min(FASCIA, z + 0.52)).difference(fori)
            E.panel(S, RUSTICO, e, corso, 0.0, 0.08 + 0.03 * (k % 2))
            z += 0.6
            k += 1
        for a, pb in zip(archi, piatte):
            finestra(E, S, e, a, telaio=0.12, sporge=0.1)
            E.panel(S, "#C2BCAC", e, pb, 0.0, 0.16)
            cx, top = (a.bounds[0] + a.bounds[2]) / 2, a.bounds[3]
            E.panel(S, STUCCO_CHIARO, e, Polygon([(cx - 0.2, top), (cx + 0.2, top),
                                                  (cx + 0.3, top + 0.8), (cx - 0.3, top + 0.8)]), 0.0, 0.22)
            E.panel(S, STUCCO_CHIARO, e, rett(a.bounds[0] - 0.2, a.bounds[2] + 0.2, a.bounds[1] - 0.15, a.bounds[1]), 0.0, 0.18)
    else:
        # terra bugnato, corsi da 55 cm interrotti dagli archi
        archi = [arco(t - w_t(w) / 2, t + w_t(w) / 2, zt + 0.8, zt + 4.0) for t, w in centri]
        fori = unary_union([a.buffer(0.2, join_style=2) for a in archi] + [f.buffer(0.1, join_style=2) for f in fin_s])
        z = ZOCCOLO
        while z < FASCIA - 0.1:
            E.panel(S, BUGNATO, e, rett(t0, t1, z, min(FASCIA, z + 0.49)).difference(fori), 0.0, 0.06)
            z += 0.55
        for a in archi:
            finestra(E, S, e, a)
            cx, top = (a.bounds[0] + a.bounds[2]) / 2, a.bounds[3]
            E.panel(S, STUCCO_CHIARO, e, Polygon([(cx - 0.18, top - 0.05), (cx + 0.18, top - 0.05),
                                                  (cx + 0.24, top + 0.4), (cx - 0.24, top + 0.4)]), 0.0, 0.16)
    E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, FASCIA, FASCIA + 0.4), 0.0, 0.22)
    # i registri sopra la fascia
    for k, (csip, z0, z1, forma) in enumerate(piani):
        cc = centri_da_pianta(b, E, csip, pts, ie, t0, t1) if csip else []
        if not cc:
            cc = centri
        for t, w in cc:
            ww = max(1.0, min(1.45, w))
            g = arco(t - ww / 2, t + ww / 2, z0, z1) if forma == "arco" else rett(t - ww / 2, t + ww / 2, z0, z1)
            finestra(E, S, e, g)
            E.panel(S, STUCCO_CHIARO, e, rett(t - ww / 2 - 0.2, t + ww / 2 + 0.2, z0 - 0.15, z0), 0.0, 0.18)
            if forma == "arco":
                E.panel(S, STUCCO_CHIARO, e, Polygon([(t - 0.16, z1 - 0.05), (t + 0.16, z1 - 0.05),
                                                      (t + 0.22, z1 + 0.35), (t - 0.22, z1 + 0.35)]), 0.0, 0.16)
        if k + 1 < len(piani):      # la fascetta fra due piani
            zf = piani[k + 1][1] - 0.75
            E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, zf, zf + 0.22), 0.0, 0.08)
    # fregio, cornicione a due gradini con le mensole
    E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, z_top - 1.25, z_top - 1.1), 0.0, 0.1)
    E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, z_top - 0.85, z_top - 0.55), 0.0, cornice * 0.5)
    E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, z_top - 0.55, z_top), 0.0, cornice)
    for k in range(int((t1 - t0) / 0.9)):
        t = t0 + 0.45 + k * 0.9
        E.panel(S, STUCCO_CHIARO, e, rett(t - 0.1, t + 0.1, z_top - 1.05, z_top - 0.55), 0.0, cornice * 0.8)


def aula_celoria(E, S, b, g, masse, nome, z_top, passo=4.0):
    """L'aula sud su via Celoria, come nelle foto di Urbanfile (2022) dalla via e dal cantiere
    della palazzina Lerici: un solo piano alto in finta pietra grigio-beige a bugne lisce,
    zoccolo in granito con le grate del seminterrato, finestroni ad arco con l'archivolto e
    le inferriate a disegno, la fascia dei davanzali, il cornicione con la gronda."""
    for pts in anelli(g):
        for e in E.edges(pts):
            for t0, t1 in tratti_liberi(e, masse, z_top - 1.0, nome):
                centri = campate(t0, t1, passo, bordo=1.6)
                fin_s = [rett(t - 0.6, t + 0.6, 0.35, 1.0) for t in centri]
                E.panel(S, PIETRA, e, rett(t0, t1, 0.0, ZOCCOLO).difference(unary_union(fin_s)), 0.0, 0.14)
                for f in fin_s:
                    E.panel(S, "#2A2E33", e, f, 0.0, 0.04)
                    for k in range(1, 6):
                        tt = f.bounds[0] + 1.2 * k / 6
                        E.panel(S, FERRO, e, rett(tt - 0.02, tt + 0.02, 0.35, 1.0), 0.0, 0.1)
                archi = [arco(t - 0.95, t + 0.95, 3.6, 8.2, seg=10) for t in centri]
                volti = [a.buffer(0.32, join_style=1).difference(a).difference(rett(-99, 999, -9, 5.8)) for a in archi]
                fori = unary_union([a.buffer(0.05) for a in archi] + volti)
                # il muro a bugne lisce: corsi da 60 cm, giunti scuri (la massa sotto)
                z = ZOCCOLO
                while z < z_top - 1.3:
                    E.panel(S, PIETRA_CELORIA, e, rett(t0, t1, z + 0.03, min(z_top - 1.3, z + 0.6) - 0.03).difference(fori), 0.0, 0.07)
                    z += 0.6
                E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, 3.3, 3.6), 0.0, 0.16)      # i davanzali
                for t, a, v in zip(centri, archi, volti):
                    E.panel(S, "#3A4049", e, a, 0.0, 0.02)
                    E.panel(S, STUCCO_CHIARO, e, v, 0.0, 0.12)
                    E.panel(S, STUCCO_CHIARO, e, Polygon([(t - 0.2, 8.1), (t + 0.2, 8.1), (t + 0.28, 8.75), (t - 0.28, 8.75)]), 0.0, 0.18)
                    # l'inferriata: bacchette ogni 18 cm, due traversi, la lunetta a raggi
                    x0, _, x1, _ = a.bounds
                    barre = [rett(x - 0.015, x + 0.015, 3.6, 8.2) for x in np.arange(x0 + 0.18, x1 - 0.1, 0.18)]
                    barre += [rett(x0, x1, zz - 0.025, zz + 0.025) for zz in (4.4, 6.2, 7.25)]
                    for i in range(1, 6):
                        ang = math.pi * i / 6
                        barre.append(LineString([(t, 7.25), (t + 0.95 * math.cos(ang), 7.25 + 0.95 * math.sin(ang))]).buffer(0.02))
                    E.panel(S, FERRO, e, unary_union(barre).intersection(a), 0.0, 0.08)
                # fregio e cornicione con la gronda
                E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, z_top - 1.3, z_top - 1.1), 0.0, 0.12)
                E.panel(S, PIETRA_CELORIA, e, rett(t0, t1, z_top - 1.1, z_top - 0.6), 0.0, 0.05)
                E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, z_top - 0.6, z_top - 0.3), 0.0, 0.3)
                E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, z_top - 0.3, z_top), 0.0, 0.55)


def porte_esterne(E, S, b, masse):
    """Le porte che la pianta del seminterrato segna come esterne, sul lato più vicino:
    il portone carraio e la porta dei corpi bassi verso ovest, per esempio."""
    f = E.plan_floor(b, "MIA010500S")
    for p in f.get("porte", []):
        if not p.get("esterna"):
            continue
        a, c = np.array(p["cardine"]), np.array(p["chiusa"])
        m = (a + c) / 2
        w = float(np.linalg.norm(c - a))
        for nome, (g, _) in masse.items():
            for pts in anelli(g):
                for e in E.edges(pts):
                    a_, c_, u, n, L, _ = e
                    t = float(np.dot(m - np.array(a_), u))
                    d = float(np.dot(m - np.array(a_), n))
                    if 0.5 < t < L - 0.5 and abs(d) < 0.6:
                        h = 2.4 if w < 2.5 else 3.6
                        q = rett(t - w / 2, t + w / 2, 0.0, h)
                        E.panel(S, "#3B3A37", e, q, 0.0, 0.04)
                        E.panel(S, PIETRA, e, q.buffer(0.18, join_style=2).difference(q).difference(rett(-99, 999, -1, 0)), 0.0, 0.14)
                        for k in range(1, int(w / 0.5)):
                            tt = t - w / 2 + k * w / int(w / 0.5)
                            E.panel(S, FERRO, e, rett(tt - 0.015, tt + 0.015, 0.1, h - 0.1), 0.0, 0.06)


def moderno(E, S, g, masse, nome, z_top, file_, colore=INTONACO, passo=3.0, larghe=False):
    """Le facciate dei corpi del dopoguerra: intonaco liscio, zoccolo grigio, finestre rette
    in fila ogni `passo` (nastri, se larghe), una fila per ogni quota di `file_` (davanzale,
    architrave)."""
    for pts in anelli(g):
        for e in E.edges(pts):
            for t0, t1 in tratti_liberi(e, masse, z_top - 1.0, nome):
                E.panel(S, "#A9A79F", e, rett(t0, t1, 0.0, 0.6), 0.0, 0.05)
                for z0, z1 in file_:
                    if larghe:
                        for t in campate(t0, t1, passo, bordo=0.8):
                            finestra(E, S, e, rett(t - passo / 2 + 0.25, t + passo / 2 - 0.25, z0, z1), telaio=0.06, sporge=0.05)
                    else:
                        for t in campate(t0, t1, passo, bordo=0.9):
                            finestra(E, S, e, rett(t - 0.6, t + 0.6, z0, z1), telaio=0.08, sporge=0.06)
                E.panel(S, "#B9B6AE", e, rett(t0, t1, z_top - 0.3, z_top + 0.4), 0.0, 0.08)


# ------------------------------------------------------------------ l'edificio

# I corpi, dal contorno della pianta del terra e dall'ortofoto (metri, frame del campus).
# Sono gli stessi delle parti della mappa ridisegnata (PR #13), scritti qui perché il modulo
# funzioni anche con la mappa che non le ha.
PARTI = {
    "padiglione": [(24.9, 256.8), (24.9, 246.7), (27.0, 244.6), (40.5, 244.6), (42.7, 246.6), (42.7, 256.8)],
    "nord-ovest": box(11.8, 256.3, 22.1, 268.8), "nord-centro": box(22.1, 256.4, 45.9, 268.8),
    "nord-est": box(45.9, 256.1, 55.9, 268.8), "ovest": box(12.3, 268.8, 22.1, 298.0),
    "est": box(45.6, 268.8, 55.4, 298.0), "mezzo": box(22.1, 287.5, 45.6, 298.0),
    "basso": box(14.7, 298.0, 55.4, 309.5), "aula-sud": box(24.8, 309.5, 44.1, 320.8),
    "aula-sud-ovest": box(14.6, 309.5, 24.8, 325.6), "aula-sud-est": box(44.1, 309.5, 53.8, 325.4),
}
ALBERO = (33.8, 278.5, 5.5)         # l'albero del cortile: una chioma di una decina di metri


def _parti(b):
    return {k: (Polygon(v) if isinstance(v, list) else v).buffer(0) for k, v in PARTI.items()}


def _masse(b):
    """{nome: (poligono, quota in cima)}: i volumi dell'Edificio 5 come nell'ortofoto."""
    pt = _parti(b)
    corpo = unary_union([pt[k] for k in ("nord-ovest", "nord-centro", "nord-est", "ovest", "est", "mezzo")])
    corpo = corpo.buffer(0.15, join_style=2).buffer(-0.15, join_style=2)
    terzo = unary_union([box(19.5, 265.0, 50.0, 268.85), box(26.4, 260.15, 44.0, 265.0)])
    sud = unary_union([pt["aula-sud"], pt["aula-sud-ovest"], pt["aula-sud-est"], box(24.8, 320.4, 44.1, 325.6)]).buffer(0.1, join_style=2).buffer(-0.1, join_style=2)
    cortile_servizio = box(22.6, 297.0, 45.9, 309.8)
    bassi = pt["basso"].difference(cortile_servizio)
    return {
        "corpo": (corpo, GRONDA),
        "padiglione": (pt["padiglione"], GRONDA_PAD),
        "terzo": (terzo, TERZO[1]),
        "sud": (sud, GRONDA_SUD),
        "bassi": (bassi, BASSI),
        "raccordo": (box(55.4, 289.5, 67.3, 298.0), 12.0),
        "raccordo-basso": (unary_union([box(55.4, 298.0, 67.3, 305.9), box(61.5, 276.6, 67.3, 289.5)]), 6.0),
        "capannone": (box(67.3, 276.6, 77.8, 305.9), 11.0),
        "studio": (box(53.8, 305.9, 82.6, 325.2), 10.4),
    }


def guscio(b, E):
    """L'esterno dell'Edificio 5: {chiave: mesh} e la quota più alta."""
    _registra(E)
    S = E.Solidi()
    masse = _masse(b)
    Q = QUOTE
    # le masse piene
    colori = {"corpo": STUCCO, "padiglione": STUCCO, "terzo": GRIGIO, "sud": GIUNTO, "bassi": STUCCO,
              "raccordo": INTONACO, "raccordo-basso": INTONACO, "capannone": INTONACO, "studio": INTONACO}
    for nome, (g, z) in masse.items():
        z0 = GRONDA - 0.3 if nome == "terzo" else 0.0
        for q in E.clean(g):          # con i cortili: extrude_polygon tiene i buchi
            S.solid(colori[nome], trimesh.creation.extrude_polygon(q, z - z0).apply_translation([0, 0, z0]))
    # le facciate storiche
    palazzo(E, S, b, masse["corpo"][0], masse, "corpo", GRONDA,
            [("MIA0105001", Q["MIA0105001"] + 0.9, Q["MIA0105001"] + 3.8, "arco"),
             ("MIA0105002", Q["MIA0105002"] + 0.9, Q["MIA0105002"] + 2.9, "retta")], terra_fuori="retta")
    palazzo(E, S, b, masse["padiglione"][0], masse, "padiglione", GRONDA_PAD,
            [("MIA0105001", Q["MIA0105001"] + 1.2, Q["MIA0105001"] + 4.6, "arco")], passo=3.6)
    aula_celoria(E, S, b, masse["sud"][0], masse, "sud", GRONDA_SUD)
    palazzo(E, S, b, masse["bassi"][0], masse, "bassi", BASSI, [], passo=3.8)
    # il terzo piano: intonaco grigio, finestre rette della pianta
    terzo = masse["terzo"][0]
    for pts in anelli(terzo):
        ws = E.plan_windows(b, "MIA0105003", pts)
        for ie, e in enumerate(E.edges(pts)):
            cc = ws.get(ie) or [(t - 0.6, t + 0.6) for t in campate(0, e[4], 3.4)]
            for a, c in cc:
                finestra(E, S, e, rett(a, c, Q["MIA0105003"] + 0.9, Q["MIA0105003"] + 2.7), telaio=0.08, sporge=0.06)
            E.panel(S, "#B3B5B5", e, rett(0, e[4], TERZO[1] - 0.35, TERZO[1] + 0.25), 0.0, 0.1)
    # i corpi del dopoguerra
    moderno(E, S, masse["raccordo"][0], masse, "raccordo", 12.0, [(4.6, 6.6), (9.2, 11.0)])
    moderno(E, S, masse["raccordo-basso"][0], masse, "raccordo-basso", 6.0, [(3.2, 5.2)])
    moderno(E, S, masse["capannone"][0], masse, "capannone", 11.0, [(4.0, 6.2), (8.0, 10.2)], passo=3.66)
    moderno(E, S, masse["studio"][0], masse, "studio", 10.4, [(4.4, 9.2)], passo=3.6, larghe=True)

    # le porte esterne del seminterrato, a quota del cortile: quelle sui lati delle masse
    porte_esterne(E, S, b, masse)

    # ---- i tetti
    top = 0.0
    corpo = masse["corpo"][0]
    top = max(top, falde(E, S, corpo, GRONDA, sporto=0.6, taglio=terzo.buffer(0.05, join_style=2)))
    top = max(top, falde(E, S, masse["padiglione"][0], GRONDA_PAD, sporto=0.6))
    # i lucernari a filo di falda dell'ortofoto: una fila sulle falde esterne delle ali,
    # qualcuno su quelle verso il cortile
    for x, y, n, filo in lucernari():
        lucernario(E, S, x, y, n, filo, GRONDA)
    # il terzo a T: tetto piano grigio, il frigo a otto ventole, l'unità rossa, i lucernari
    E.prisma(S, TETTO_PIANO, E.ring_ccw(terzo.buffer(0.15, join_style=2)), TERZO[1], TERZO[1] + 0.25)
    zt = TERZO[1] + 0.25
    S.solid(IMPIANTI, E.box_z(40.95, 261.4, 4.7, 2.4, zt, zt + 1.7))
    for i in range(4):
        for j in range(2):
            x, y = 39.2 + i * 1.17, 260.8 + j * 1.2
            S.solid(VENTOLA, trimesh.creation.cylinder(radius=0.48, height=0.08, sections=12).apply_translation([x, y, zt + 1.74]))
    S.solid(ROSSO_UNITA, E.box_z(40.75, 263.8, 2.9, 1.9, zt, zt + 1.3))
    for x, y in ((31.0, 262.0), (33.6, 262.3), (36.0, 266.4)):
        S.solid("#7D8A93", E.box_z(x, y, 1.0, 1.4, zt, zt + 0.35))
    # l'aula sud: tetto a padiglione con la vetrata a nastro nella falda verso via Celoria
    top = max(top, falde(E, S, masse["sud"][0], GRONDA_SUD, pend=0.45, sporto=0.6, vetri=[box(26.6, 320.2, 44.1, 324.6)]))
    # i corpi bassi, il raccordo, la sala studio: tetti piani con il parapetto
    for nome, colore in (("bassi", TETTO_PIANO), ("raccordo", TETTO_BEIGE), ("raccordo-basso", "#7F8386"),
                         ("studio", MEMBRANA)):
        g, z = masse[nome]
        for q in E.clean(g):
            E.prisma(S, colore, E.ring_ccw(q.buffer(-0.25, join_style=2)), z - 0.3, z - 0.05)
    for x, y in ((59.0, 293.0), (61.6, 293.0), (64.2, 293.0)):          # gli impianti sul raccordo
        S.solid(IMPIANTI, E.box_z(x, y, 1.6, 1.6, 11.7, 13.0))
    # la sala studio: la parte nord grigia con i lucernari a punti
    E.prisma(S, "#C9CACA", E.ring_ccw(box(54.3, 306.4, 82.1, 313.6)), 10.08, 10.12)
    for x in np.arange(58.0, 82.0, 6.0):
        for y in (308.0, 311.5):
            S.solid("#9FA7AD", E.box_z(x, y, 0.6, 0.6, 10.1, 10.45))
    # il capannone: lamiera grecata, colmo nord-sud, testata nord a padiglione, sud a capanna
    cap = masse["capannone"][0]
    top = max(top, falde(E, S, cap, 11.0, pend=0.42, sporto=0.3, key=LAMIERA, timpani=[(0, 1)],
                         muro=INTONACO, sotto="#A9ACAD"))
    # il cortile: lastre, l'albero della mappa
    cort = box(22.1, 268.8, 45.6, 287.5).buffer(-0.05)
    E.prisma(S, LASTRE, E.ring_ccw(cort), 0.0, 0.08)
    x, y, r = ALBERO
    S.solid(TRONCO, trimesh.creation.cylinder(radius=0.35, height=8.0, sections=8).apply_translation([x, y, 4.0]))
    chioma = trimesh.creation.icosphere(subdivisions=2, radius=r)
    chioma.apply_scale([1.0, 1.0, 0.85])
    S.solid(CHIOMA, chioma.apply_translation([x, y, 8.0 + r * 0.6]))
    # il cortile di servizio: asfalto
    E.prisma(S, "#7E7F80", E.ring_ccw(box(22.7, 298.1, 45.8, 309.4)), 0.0, 0.04)
    return S.meshes(), top


# ------------------------------------------------------------------ dentro

# le aule senza file nella pianta: la cattedra verso nord nel padiglione (finestre a
# sinistra nella foto della 5.0.1), verso est nelle due aule piane d'angolo (finestre a
# sinistra nelle foto della Beltrami e della Castigliano)
FILE = {"MIA0105000003": ("nord", 0.95), "MIA0105001005a": ("nord", 0.95),
        "MIA0105000052": ("est", None), "MIA0105000059": ("est", None)}


# le aule che la pianta disegna sedile per sedile: la cattedra a sud (il leggio della pianta)
RIDISEGNA = {"MIA0105000062a": 1, "MIA0105000028": 1}


def piante(b, geo, aule, E):
    """Le file delle aule come esporta3d le sa leggere. La 5.02 e la 5.03 hanno le sedute
    ribaltabili disegnate una per una, con due o tre linee lunghe per fila: di ogni fila resta
    la linea verso la cattedra (a sud, dove la pianta mette il leggio), il resto si toglie.
    Alle aule senza file si aggiungono: gradoni ogni 95 cm con il corridoio in mezzo nel
    padiglione; tavoli da 55 cm con 75 cm per le sedie nelle aule piane (il passo sotto i
    70 cm fa dire a esporta3d che sono tavoli). Il cortile di servizio è un cortile, non un
    pozzo: niente parapetto (e nemmeno intorno al cortile grande, se la mappa non lo dice)."""
    for c in ([[22.1, 268.8], [45.6, 268.8], [45.6, 287.5], [22.1, 287.5]],      # il cortile
              [[22.6, 297.4], [45.9, 297.4], [45.9, 309.8], [22.6, 309.8]]):     # quello di servizio
        if not any(Polygon(c).buffer(-0.5).within(Polygon(q).buffer(0.5)) for q in b.setdefault("cortili", [])):
            b["cortili"].append(c)
    for csip, f in geo.items():
        segs = f.setdefault("linee", {}).setdefault("arredi", [])
        for v in f["vani"]:
            if v["csiv"] in RIDISEGNA:
                dentro = E.shape_of(v).buffer(-0.05)
                suoi = [s_ for s_ in segs if dentro.contains(Point(s_[:2]))]
                # le file: i tratti orizzontali raggruppati per quota (banco e sedute di una
                # fila stanno in mezzo metro), tenute quelle con molti pezzi (non il leggio)
                orizz = sorted((s_ for s_ in suoi if abs(s_[1] - s_[3]) < 0.05), key=lambda s_: s_[1])
                file_, gruppo = [], []
                for s_ in orizz:
                    if gruppo and s_[1] - gruppo[-1][1] > 0.3:
                        file_.append(gruppo)
                        gruppo = []
                    gruppo.append(s_)
                if gruppo:
                    file_.append(gruppo)
                y_muro = dentro.bounds[3] if RIDISEGNA[v["csiv"]] > 0 else dentro.bounds[1]
                file_ = [g_ for g_ in file_ if len(g_) >= 20 and abs(g_[-1][1] - y_muro) > 1.8
                         and max(max(q[0], q[2]) for q in g_) - min(min(q[0], q[2]) for q in g_) > 3.0]
                uniti = []                 # due gruppi a meno di 60 cm sono la stessa fila
                for g_ in file_:
                    if uniti and max(q[1] for q in g_) - max(q[1] for q in uniti[-1]) < 0.6:
                        uniti[-1] = uniti[-1] + g_
                    else:
                        uniti.append(g_)
                file_ = uniti
                if len(file_) < 3:
                    continue
                vicino = dentro.buffer(0.15)
                tolti = {id(s_) for s_ in segs if vicino.intersects(LineString([s_[:2], s_[2:4]]))}
                segs[:] = [s_ for s_ in segs if id(s_) not in tolti]
                for gr in file_:
                    y = max(s_[1] for s_ in gr) if RIDISEGNA[v["csiv"]] > 0 else min(s_[1] for s_ in gr)
                    xa = min(min(s_[0], s_[2]) for s_ in gr)
                    xb = max(max(s_[0], s_[2]) for s_ in gr)
                    segs.append([round(xa, 2), round(y, 2), round(xb, 2), round(y, 2)])
                continue
            if v["csiv"] not in FILE or v["csiv"] not in aule.get(csip, {}):
                continue
            verso, passo = FILE[v["csiv"]]
            poly = E.shape_of(v)
            interno = poly.buffer(-0.8, join_style=2)
            if interno.is_empty:
                continue
            ix0, iy0, ix1, iy1 = interno.bounds
            nuovi = []
            if verso == "nord":
                y = iy0 + 3.0
                while y < iy1 - 0.3:
                    riga = LineString([(ix0 - 1, y), (ix1 + 1, y)]).intersection(interno)
                    for g in getattr(riga, "geoms", [riga]):
                        if g.is_empty or g.length < 3:
                            continue
                        xa, xb = sorted([g.coords[0][0], g.coords[-1][0]])
                        m = (xa + xb) / 2
                        for p0, p1 in ((xa + 0.5, m - 0.6), (m + 0.6, xb - 0.5)):
                            if p1 - p0 > 1.5:
                                nuovi.append([round(p0, 2), round(y, 2), round(p1, 2), round(y, 2)])
                    y += passo
            else:
                x = ix1 - 2.6
                k = 0
                while x > ix0 + 0.6:
                    riga = LineString([(x, iy0 - 1), (x, iy1 + 1)]).intersection(interno)
                    for g in getattr(riga, "geoms", [riga]):
                        if g.is_empty or g.length < 2:
                            continue
                        ya, yb = sorted([g.coords[0][1], g.coords[-1][1]])
                        m = (ya + yb) / 2
                        for p0, p1 in ((ya + 0.3, m - 0.5), (m + 0.5, yb - 0.3)):
                            if p1 - p0 > 1.2:
                                nuovi.append([round(x, 2), round(p0, 2), round(x, 2), round(p1, 2)])
                    x -= 0.55 if k % 2 == 0 else 0.75
                    k += 1
            segs.extend(nuovi)
    return geo


# I colori delle foto, aula per aula: (sedute, banchi)
COLORI_AULE = {
    "MIA0105000003": ("#9B2C2C", "#2F2B2A"),     # 5.0.1: banchi scuri, sedute rosse
    "MIA0105001005a": ("#9B2C2C", "#2F2B2A"),    # 5.1.1: lo stesso, a gradoni
    "MIA0105000062a": ("#D2A877", "#CFA270"),    # 5.02: sedute e piani in faggio
    "MIA0105000028": ("#A9ACAE", "#B9BCBE"),     # 5.03: sedute grigie
    "MIA0105000052": ("#C99A64", "#2E3033"),     # Beltrami: tavoli scuri, sedie in faggio
    "MIA0105000059": ("#C99A64", "#2E3033"),     # Castigliano
}
BIANCO_AULA = "#EEEDE8"
TAVOLI = {"MIA0105000052", "MIA0105000059"}


# la vista dentro l'aula: (x del corridoio, y della cattedra, y dell'occhio), in piedi in
# fondo nel corridoio e non in un angolo
SGUARDI = {"MIA0105000003": (34.1, 247.6, 259.6), "MIA0105001005a": (34.1, 248.2, 260.0),
           "MIA0105000062a": (50.6, 288.4, 272.3), "MIA0105000028": (17.45, 288.5, 270.0)}


def _sguardi(meta, E):
    """Le viste dentro le aule a gradoni lungo l'asse dell'aula, verso la cattedra:
    esporta3d sceglie un punto qualsiasi del piano davanti alle file, qui a volte una
    striscia di lato. Le quote restano quelle di esporta3d."""
    for p in meta.get("piani", []):
        for a in p.get("aule", []):
            if a["csiv"] in SGUARDI and "interno" in a:
                x, yg, yo = SGUARDI[a["csiv"]]
                a["interno"]["guarda"] = [x, a["interno"]["guarda"][1], yg]
                a["interno"]["occhio"] = [x, a["interno"]["occhio"][1], yo]


def ritocca(sc, meta, E):
    """Le aule come nelle foto: le sedute e i banchi di ogni aula del suo colore (gli arredi
    di un piano sono una mesh per colore, si dividono per aula), le pareti bianche."""
    geo = E.json.loads((E.SRC / "piante" / f"{CSIE}-geometria.json").read_text())["piani"]
    stanze = {}
    for csip, f in geo.items():
        for v in f["vani"]:
            if v["csiv"] in COLORI_AULE:
                stanze[v["csiv"]] = (csip, E.shape_of(v).buffer(0.3))
    _sguardi(meta, E)
    sedute = {E.SEAT, getattr(E, "SEDIA_ROSSA", None), getattr(E, "SEDIA_VERDE", None)}
    banchi = {E.DESK, getattr(E, "TAVOLO", None)}
    genitori = sc.s.graph.transforms.parents
    for name in list(sc.s.geometry.keys()):
        m = sc.s.geometry[name]
        colore = m.metadata.get("colore")
        if "_Interno_" in name and colore == E.COL["muri"]:
            E.colour(m, BIANCO_AULA)
            continue
        if "_Arredi_" not in name or (colore not in sedute and colore not in banchi and colore != E.CORRIMANO):
            continue
        csip = name.split("_Arredi_")[0]
        c = m.triangles_center
        resto = np.ones(len(c), bool)
        for csiv, (cp, poly) in stanze.items():
            if cp != csip:
                continue
            x0, y0, x1, y1 = poly.bounds
            vicini = np.nonzero(resto & (c[:, 0] > x0) & (c[:, 0] < x1) & (c[:, 2] > y0) & (c[:, 2] < y1))[0]
            dentro = [i for i in vicini if poly.contains(Point(c[i, 0], c[i, 2]))]
            if not dentro:
                continue
            sub = m.submesh([dentro], append=True)
            if colore == E.CORRIMANO:
                # le sedie nere dei tavoli: in faggio, le gambe restano nere
                if csiv not in TAVOLI:
                    continue
                # ogni scatola (E.hexa) sono 12 triangoli di fila: le gambe sono sottili
                sedie, gambe = [], []
                for i in range(0, len(sub.faces), 12):
                    blocco = list(range(i, min(i + 12, len(sub.faces))))
                    ext = np.ptp(sub.vertices[sub.faces[blocco].ravel()], axis=0)
                    (sedie if sorted(ext)[1] > 0.3 else gambe).extend(blocco)
                if not sedie:
                    continue
                if gambe:
                    nere = E.colour(sub.submesh([gambe], append=True), colore)
                    sc.mesh(f"{name}_{csiv}_gambe", genitori.get(name, csip), nere)
                sub = sub.submesh([sedie], append=True)
                E.colour(sub, COLORI_AULE[csiv][0])
            else:
                E.colour(sub, COLORI_AULE[csiv][0 if colore in sedute else 1])
            nodo = f"{name}_{csiv}"
            sc.mesh(nodo, genitori.get(name, csip), sub)
            resto[dentro] = False
        if not resto.all():
            keep = m.submesh([np.nonzero(resto)[0]], append=True) if resto.any() else None
            if keep is None:
                sc.s.delete_geometry(name)
            else:
                E.colour(keep, colore)
                sc.s.geometry[name] = keep
