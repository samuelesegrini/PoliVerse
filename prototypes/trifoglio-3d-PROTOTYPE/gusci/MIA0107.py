"""PROTOTIPO — l'Edificio 7 "Carlo Erba" (MIA0107), l'esterno rifatto da zero.

Fonti, oltre ai contorni di leonardo.json e alle piante:
- l'ortofoto (Esri World Imagery, z19): il corpo lungo su via Ponzio con il tetto a padiglione
  in coppi, largo quanto il primo piano delle piante (15 m); dietro, a ovest, il capannone a un
  piano con nove denti di sega (shed) in coppi, la vetrata rivolta a nord, ogni 5 m; a nord del
  capannone un corpo basso a tetto piano grigio con gli impianti; a sud il corpo a due piani
  dell'aula 7.1.3 con il tetto piano chiaro a teli, e una striscia bassa scura fra i due;
- le piante: le finestre dove le piante le disegnano (`linee.finestre`), piano per piano; le
  porte esterne del terra, a cui si sale con qualche gradino (la scheda dell'aula: "l'entrata
  principale presenta gradini", il terra è rialzato);
- le foto: AIRLab (airlab.deib.polimi.it) per il capannone dentro, alto, con le finestre ad
  arco in alto e i lucernari; il servizio spazi del Politecnico per le aule 7.1.1 (piana, banchi
  scuri e sedute rosse, le finestre ad arco sulla sinistra), 7.1.2 (ad anfiteatro, banchi in
  legno) e 7.1.3 (piana, moderna, banchi e sedie neri); via Ponzio da Wikimedia Commons
  (Jwslubbock, CC BY-SA 3.0) per gli edifici vicini dello stesso tempo: intonaco grigio, finestre
  ad arco, fascia marcapiano, cornicione semplice e tetto in coppi.

Del corpo su via Ponzio non si sono trovate foto: segue gli altri corpi storici del campus e la
mappa (intonaco grigio, finestre ad arco ai due piani, campata di 3,8 m). Le quote sono dedotte:
il seminterrato a -3, il terra rialzato a 1,2 m, il primo a 6,6 m, la gronda a 12,4 m.
Coordinate Z-up del frame del campus: x est, y sud.
"""
import math
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union

CSIE = "MIA0107"
Z_S, Z_T, Z_1 = -3.0, 1.2, 6.6
QUOTE = {"MIA010700S": Z_S, "MIA0107000": Z_T, "MIA0107001": Z_1}
FASCIA = Z_1 - 0.35     # la fascia marcapiano fra terra e primo
GRONDA = 12.4           # il cornicione del corpo su via Ponzio
SHED_GRONDA = 6.4       # il muro del capannone, sotto le finestre del primo del corpo lungo
DENTE = 2.4             # l'altezza della vetrata di ogni dente
PASSO_DENTE = 5.0       # dall'ortofoto: nove denti in 45 m
NORD_TOP = 5.6          # il corpo basso a nord del capannone
LINK_TOP = 5.0          # la striscia scura fra il capannone e il corpo sud
SUD_TOP = 11.4          # il corpo a due piani dell'aula 7.1.3

# le parti, tagliate dal contorno del terra (le x e le y dall'ortofoto e dal primo piano)
X_FRONTE = 119.5
Y_SHED0, Y_SHED1, Y_SUD = 177.0, 222.0, 226.8

INTONACO = "#C9C6BD"    # l'intonaco grigio (mappa, foto di via Ponzio)
INTONACO_SUD = "#DAD6CC"
STUCCO_CHIARO = "#E5E1D7"   # cornici, fasce, cornicione
PIETRA = "#9C9890"      # lo zoccolo
VETRO_SCURO = "#3D4752"
TELAIO = "#F2F0EA"      # i telai bianchi (foto delle aule)
VETRO_SHED = "#9DB0C0"
FERRO = "#2F3236"
TETTO_PIANO = "#8B8E8F"     # il tetto del corpo nord, grigio nell'ortofoto
TETTO_SCURO = "#55585B"     # la striscia bassa
TELI = "#DCDAD3"            # i teli chiari del tetto del corpo sud
IMPIANTI = "#B9BDC2"
LASTRE = "#B9B5AC"
PORTA = "#3A3B3D"
COPPI = "coppi"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    """Sotto il tetto dell'ultimo piano: il controsoffitto delle aule del primo."""
    return SUD_TOP - 0.6


# ------------------------------------------------------------------ coppi

def _coppi_texture():
    """Coppi rossi in file, 0,5 m per ripetizione: il dorso tondo di ogni coppo, le
    sovrapposizioni, toni un po' diversi (come per l'Edificio 3)."""
    from PIL import Image
    rng = np.random.default_rng(7)
    size = 256
    y, x = np.mgrid[0:size, 0:size]
    col = 4
    w = size // col
    fx = (x % w) / w
    ridge = np.sin(fx * math.pi)
    lap = (y / size * 1.25) % 1.0
    shade = 0.82 + 0.18 * ridge - 0.12 * (lap > 0.9)
    tone = rng.normal(0, 0.05, col * 2)[(x // w) % (col * 2)]
    base = np.array([0.72, 0.42, 0.29])
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


def falde(E, S, x0, y0, x1, y1, z, pendenza=0.5, sporto=0.6):
    """Un tetto a padiglione in coppi su un rettangolo allineato agli assi: le falde lunghe
    fino al colmo, le testate a triangolo; sotto, il soffitto della gronda."""
    x0, y0, x1, y1 = x0 - sporto, y0 - sporto, x1 + sporto, y1 + sporto
    w, d = x1 - x0, y1 - y0
    h = min(w, d) / 2 * pendenza
    if w >= d:
        r0, r1 = (x0 + d / 2, (y0 + y1) / 2), (x1 - d / 2, (y0 + y1) / 2)
    else:
        r0, r1 = ((x0 + x1) / 2, y0 + w / 2), ((x0 + x1) / 2, y1 - w / 2)
    c = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    top = lambda p: (p[0], p[1], z + h)
    for i in range(4):
        a, b_ = c[i], c[(i + 1) % 4]
        mid = ((a[0] + b_[0]) / 2, (a[1] + b_[1]) / 2)
        ra, rb = sorted([r0, r1], key=lambda r: math.dist(r, a))
        if math.dist(ra, rb) < 1e-6 or abs((b_[0] - a[0]) * (rb[1] - ra[1]) - (b_[1] - a[1]) * (rb[0] - ra[0])) > 1e-6:
            pts = [(*a, z), (*b_, z), top(min([r0, r1], key=lambda r: math.dist(r, mid)))]
        else:
            pts = [(*a, z), (*b_, z), top(rb), top(ra)]
        L = math.dist(a, b_)
        u = ((b_[0] - a[0]) / L, (b_[1] - a[1]) / L)
        n = (u[1], -u[0])
        if (mid[0] - (x0 + x1) / 2) * n[0] + (mid[1] - (y0 + y1) / 2) * n[1] < 0:
            n = (-n[0], -n[1])
        dist = lambda p: abs((p[0] - a[0]) * n[0] + (p[1] - a[1]) * n[1])
        uv = lambda p: ((p[0] - a[0]) * u[0] + (p[1] - a[1]) * u[1], dist(p) + (p[2] - z) * 0.4)
        want = (n[0], n[1], 1.0)
        if len(pts) == 4:
            S.quad(COPPI, pts, want, [uv(p) for p in pts])
        else:
            S.tri(COPPI, pts, want, [uv(p) for p in pts])
    S.quad(STUCCO_CHIARO, [(*p, z - 0.01) for p in c], (0, 0, -1))
    return z + h


# ------------------------------------------------------------------ facciate

def arco(t0, t1, z0, zs, seg=8):
    """Una finestra ad arco a tutto sesto: rettangolo fino all'imposta e mezzo cerchio."""
    r = (t1 - t0) / 2
    c = t0 + r
    return Polygon([(t0, z0), (t1, z0)] + [(c + r * math.cos(math.pi * k / seg), zs + r * math.sin(math.pi * k / seg))
                                          for k in range(seg + 1)])


def rett(t0, t1, z0, z1):
    return Polygon([(t0, z0), (t1, z0), (t1, z1), (t0, z1)])


def finestra(E, S, e, shape, cornice=0.15, sporge=0.1, vetro=VETRO_SCURO):
    """Il vetro scuro appena dentro il filo, la cornice chiara intorno, montante e traverso
    bianchi."""
    E.panel(S, vetro, e, shape, 0.0, 0.02)
    E.panel(S, STUCCO_CHIARO, e, shape.buffer(cornice, join_style=2).difference(shape), 0.0, sporge)
    t0, z0, t1, z1 = shape.bounds
    tm = (t0 + t1) / 2
    zt = z0 + (z1 - z0) * 0.62
    bars = unary_union([rett(tm - 0.03, tm + 0.03, z0, z1), rett(t0, t1, zt - 0.03, zt + 0.03)])
    E.panel(S, TELAIO, e, bars.intersection(shape), 0.0, 0.05)


def libero(e, altre):
    """I tratti [t0, t1] del lato che non toccano un'altra parte (le facce in vista)."""
    a, c, u, n, L, _ = e
    seg = LineString([(a[0] + n[0] * 0.3, a[1] + n[1] * 0.3), (c[0] + n[0] * 0.3, c[1] + n[1] * 0.3)])
    tratti = [(0.0, L)]
    coperto = seg.intersection(unary_union([p.buffer(0.05) for p in altre])) if altre else None
    if coperto is not None and not coperto.is_empty:
        for g in getattr(coperto, "geoms", [coperto]):
            if g.length < 0.2:
                continue
            ts = sorted(float(np.dot(np.array(q) - np.array(a), np.array(u))) for q in g.coords)
            nuovi = []
            for t0, t1 in tratti:
                if ts[-1] <= t0 or ts[0] >= t1:
                    nuovi.append((t0, t1))
                    continue
                if ts[0] > t0:
                    nuovi.append((t0, ts[0]))
                if ts[-1] < t1:
                    nuovi.append((ts[-1], t1))
            tratti = nuovi
    return [(t0, t1) for t0, t1 in tratti if t1 - t0 > 0.8]


def dentro(t0, t1, tratti, margine=0.2):
    return any(a - 0.01 <= t0 - margine and t1 + margine <= b + 0.01 for a, b in tratti)


def finestre_pianta(b, E, csip, pts):
    """Le finestre della pianta di un piano sui lati di pts: {indice del lato: [(t0, t1)]}.
    Le aperture più larghe di 2,2 m sono divise come fa la pianta con le vetrate."""
    out = {}
    for i, spans in E.plan_windows(b, csip, pts, reach=0.9).items():
        for t0, t1 in spans:
            w = t1 - t0
            if w < 0.5:
                continue
            if w > 2.2:
                k = math.ceil(w / 1.8)
                for j in range(k):
                    out.setdefault(i, []).append((t0 + j * w / k + 0.15, t0 + (j + 1) * w / k - 0.15))
            else:
                out.setdefault(i, []).append((t0, t1))
    return out


def facciata(E, S, b, pts, altre, piani, top, tinta=INTONACO, ad_arco=True, base=0.0, fascia=True):
    """Le facciate di una parte: lo zoccolo in pietra con le bocche del seminterrato sotto
    le finestre del terra, le finestre dove le disegnano le piante (ad arco nel corpo storico,
    rette nel corpo sud), la fascia marcapiano, la cornice sotto la gronda.
    piani: [(csip, quota del davanzale, quota dell'imposta, parti che coprono quel piano)]"""
    es = E.edges(pts)
    for csip, z_sill, z_imp, coprono in piani:
        fin = finestre_pianta(b, E, csip, pts)
        for i, e in enumerate(es):
            tratti = libero(e, coprono)
            for t0, t1 in fin.get(i, []):
                if not dentro(t0, t1, tratti):
                    continue
                w = t1 - t0
                if ad_arco and w <= 2.2:
                    g = arco(t0, t1, z_sill, z_imp)
                else:
                    g = rett(t0, t1, z_sill, z_imp + (w / 2 if ad_arco else 0.0))
                finestra(E, S, e, g)
                E.panel(S, STUCCO_CHIARO, e, rett(t0 - 0.25, t1 + 0.25, z_sill - 0.12, z_sill), 0.0, 0.16)   # il davanzale
                if csip.endswith("000"):     # la bocca del seminterrato sotto la finestra del terra
                    E.panel(S, "#2A2E33", e, rett(t0 + 0.1, t1 - 0.1, base + 0.25, Z_T - 0.2), 0.0, 0.03)
                    for k in range(1, 4):
                        tt = t0 + 0.1 + (w - 0.2) * k / 4
                        E.panel(S, FERRO, e, rett(tt - 0.02, tt + 0.02, base + 0.25, Z_T - 0.2), 0.0, 0.06)
    for e in es:
        for t0, t1 in libero(e, altre):
            E.panel(S, PIETRA, e, rett(t0, t1, base - 0.3, Z_T + 0.1), -0.05, 0.08)       # lo zoccolo
            if fascia and top > FASCIA + 1:
                E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, FASCIA, FASCIA + 0.3), 0.0, 0.14)
            E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, top - 0.7, top - 0.5), 0.0, 0.1)      # la cornice


def cornicione(E, S, pts, z, sporto, h=0.6, colore=STUCCO_CHIARO):
    """Il cornicione: un gradino sotto e la lastra che sporge."""
    E.prisma(S, colore, E.ring_ccw(Polygon(pts).buffer(sporto * 0.4, join_style=2)), z - h, z - h * 0.45)
    E.prisma(S, colore, E.ring_ccw(Polygon(pts).buffer(sporto, join_style=2)), z - h * 0.45, z)


def parapetto(E, S, poly, z, h=0.9, colore=STUCCO_CHIARO, spesso=0.3):
    """Il bordo di un tetto piano."""
    anello = poly.difference(poly.buffer(-spesso, join_style=2))
    for q in E.clean(anello):
        S.solid(colore, trimesh.creation.extrude_polygon(q, h).apply_translation([0, 0, z]))


# ------------------------------------------------------------------ shed

def denti(E, S, poly, z, y0, y1, passo=PASSO_DENTE, h=DENTE):
    """Il tetto a denti di sega del capannone: per ogni dente la vetrata verticale rivolta a
    nord (y minore) e la falda in coppi che scende verso sud; le testate a triangolo."""
    n = max(1, round((y1 - y0) / passo))
    p = (y1 - y0) / n
    for k in range(n):
        ya, yb = y0 + k * p, y0 + (k + 1) * p
        for q in E.clean(poly.intersection(box(-1e4, ya, 1e4, yb))):
            x0, _, x1, _ = q.bounds
            if x1 - x0 < 1.0:
                continue
            A, B = (x0, ya, z), (x1, ya, z)
            At, Bt = (x0, ya, z + h), (x1, ya, z + h)
            C, D = (x1, yb, z), (x0, yb, z)
            L = math.hypot(yb - ya, h)
            S.quad(COPPI, [At, Bt, C, D], (0, h, yb - ya), [(x0, 0.0), (x1, 0.0), (x1, L), (x0, L)])
            S.quad(INTONACO, [(x0, yb, z - 0.01), (x1, yb, z - 0.01), (x1, ya, z - 0.01), (x0, ya, z - 0.01)], (0, 0, -1))
            # la vetrata: vetro, telaio in basso e in alto, montanti ogni 1,25 m
            S.quad(VETRO_SHED, [A, B, Bt, At], (0, -1, 0))
            S.solid(TELAIO, E.box_z((x0 + x1) / 2, ya - 0.04, x1 - x0, 0.1, z, z + 0.15))
            S.solid(TELAIO, E.box_z((x0 + x1) / 2, ya - 0.04, x1 - x0, 0.1, z + h - 0.12, z + h))
            for i in range(int((x1 - x0) / 1.25) + 1):
                x = x0 + min(x1 - x0, i * 1.25)
                S.solid(TELAIO, E.box_z(x, ya - 0.04, 0.08, 0.08, z, z + h))
            for x, s in ((x0, -1), (x1, 1)):        # le testate
                S.tri(INTONACO, [(x, ya, z), (x, yb, z), (x, ya, z + h)], (s, 0, 0))
            S.solid(STUCCO_CHIARO, E.box_z((x0 + x1) / 2, ya, x1 - x0 + 0.2, 0.25, z + h, z + h + 0.12))   # il colmo


# ------------------------------------------------------------------ ingressi

def ingressi(b, E, S, contorno):
    """Le porte esterne del terra: la porta scura nel muro e, fuori, il pianerottolo e i
    gradini fino al marciapiede (il terra è rialzato di 1,2 m)."""
    pts = E.ring_ccw(contorno)
    es = E.edges(pts)
    porte = E.plan_floor(b, CSIE + "000").get("porte", [])
    fatte = []
    for d in porte:
        if not d.get("esterna"):
            continue
        p = np.array(d["cardine"], float)
        if any(np.linalg.norm(p - q) < 3.2 for q in fatte):
            continue
        fatte.append(p)
        i = min(range(len(es)), key=lambda k: LineString([es[k][0], es[k][1]]).distance(Point(p)))
        a, c, u, n, L, _ = es[i]
        if LineString([a, c]).distance(Point(p)) > 1.5:
            continue
        t = float(np.dot(p - np.array(a), np.array(u)))
        vicine = [float(np.dot(np.array(q["cardine"]) - np.array(a), np.array(u))) for q in porte
                  if q.get("esterna") and np.linalg.norm(np.array(q["cardine"]) - p) < 3.2]
        t0, t1 = max(0.3, min(vicine) - 0.2), min(L - 0.3, max(vicine) + 0.2)
        if t1 - t0 < 1.2:
            m = (t0 + t1) / 2
            t0, t1 = m - 0.6, m + 0.6
        e = es[i]
        E.panel(S, PORTA, e, rett(t0, t1, Z_T, Z_T + 2.6), 0.0, 0.03)
        E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, Z_T, Z_T + 2.6).buffer(0.2, join_style=2).difference(
            rett(t0, t1, Z_T - 1, Z_T + 2.6)), 0.0, 0.14)
        # pianerottolo da 1,2 m e gradini da 17 x 30 cm verso fuori
        E.panel(S, LASTRE, e, rett(t0 - 0.3, t1 + 0.3, -0.05, Z_T), 0.0, 1.2)
        k = int(Z_T / 0.17)
        for j in range(k):
            E.panel(S, LASTRE, e, rett(t0 - 0.3, t1 + 0.3, -0.05, Z_T - (j + 1) * Z_T / (k + 1)), 1.2 + j * 0.3, 1.5 + j * 0.3)
        for s in (t0 - 0.3, t1 + 0.3):           # i corrimano
            E.trave(S, FERRO, (*E.on_face(e, s, 1.2, Z_T + 1.0)[:2], Z_T + 1.0),
                    (*E.on_face(e, s, 1.2 + k * 0.3, 1.0)[:2], 1.0), 0.05)


# ------------------------------------------------------------------ guscio

def parti(b, E):
    """Le parti dal contorno del terra: il corpo su via Ponzio, il corpo basso a nord, il
    capannone, la striscia bassa, il corpo sud a due piani (che al primo coincide con il
    contorno del primo)."""
    terra = unary_union([E.ring(r).buffer(0) for r in E.plan_floor(b, CSIE + "000")["contorno"]]).buffer(0.05).buffer(-0.05)
    # semplificate di 30 cm: i lati quasi dritti della pianta diventano un lato solo, così
    # fasce e cornicioni non fanno gradini
    taglia = lambda x0, y0, x1, y1: terra.intersection(box(x0, y0, x1, y1)).simplify(0.3).buffer(0.01, join_style=2).buffer(-0.01, join_style=2)
    grandi = lambda g: max(E.clean(g), key=lambda q: q.area)
    return terra, {
        "fronte": grandi(taglia(X_FRONTE, 160, 150, 260)),
        "nord": grandi(taglia(90, 160, X_FRONTE, Y_SHED0)),
        "shed": grandi(taglia(90, Y_SHED0, X_FRONTE, Y_SHED1)),
        "link": grandi(taglia(90, Y_SHED1, X_FRONTE, Y_SUD)),
        "sud": grandi(taglia(90, Y_SUD, X_FRONTE, 260)),
    }


def guscio(b, E):
    """L'esterno dell'Edificio 7: {chiave: mesh} e la quota più alta."""
    _registra(E)
    S = E.Solidi()
    terra, P = parti(b, E)
    top = {"fronte": GRONDA, "nord": NORD_TOP, "shed": SHED_GRONDA, "link": LINK_TOP, "sud": SUD_TOP}
    tinta = {"fronte": INTONACO, "nord": INTONACO, "shed": INTONACO, "link": INTONACO, "sud": INTONACO_SUD}
    for k, g in P.items():
        E.prisma(S, tinta[k], E.ring_ccw(g), -0.3, top[k])
    T, U = CSIE + "000", CSIE + "001"
    for k, g in P.items():
        altre = [h for j, h in P.items() if j != k]
        coprono_t = [h for j, h in P.items() if j != k and top[j] > Z_T + 1]
        coprono_1 = [h for j, h in P.items() if j != k and top[j] > Z_1 + 1]
        if k == "fronte":
            piani = [(T, Z_T + 0.9, Z_T + 3.1, coprono_t), (U, Z_1 + 0.9, Z_1 + 3.3, coprono_1)]
            facciata(E, S, b, E.ring_ccw(g), altre, piani, GRONDA)
        elif k == "shed":
            # le finestre del capannone sono alte, ad arco, come nella foto dell'AIRLab
            facciata(E, S, b, E.ring_ccw(g), altre, [(T, Z_T + 1.4, Z_T + 3.6, coprono_t)], SHED_GRONDA, fascia=False)
        elif k == "sud":
            piani = [(T, Z_T + 0.9, Z_T + 3.2, coprono_t), (U, Z_1 + 0.9, Z_1 + 3.3, coprono_1)]
            facciata(E, S, b, E.ring_ccw(g), altre, piani, SUD_TOP, tinta=INTONACO_SUD, ad_arco=False)
        else:
            facciata(E, S, b, E.ring_ccw(g), altre, [(T, Z_T + 0.9, Z_T + 2.9, coprono_t)], top[k], ad_arco=False, fascia=False)
    ingressi(b, E, S, terra)
    # il corpo su via Ponzio: cornicione e tetto a padiglione in coppi
    f = P["fronte"]
    cornicione(E, S, E.ring_ccw(f), GRONDA, 0.6, h=0.8)
    x0, y0, x1, y1 = f.bounds
    colmo = falde(E, S, x0, y0, x1, y1, GRONDA, pendenza=0.5, sporto=0.35)
    # il capannone: il bordo e i denti di sega
    g = P["shed"]
    cornicione(E, S, E.ring_ccw(g), SHED_GRONDA, 0.3, h=0.4)
    denti(E, S, g.buffer(-0.3, join_style=2), SHED_GRONDA, g.bounds[1] + 0.3, g.bounds[3] - 0.3)
    # il corpo nord e la striscia: tetti piani scuri con il parapetto e gli impianti (ortofoto)
    for k, colore in (("nord", TETTO_PIANO), ("link", TETTO_SCURO)):
        g = P[k]
        E.prisma(S, colore, E.ring_ccw(g.buffer(-0.3, join_style=2)), top[k], top[k] + 0.05)
        parapetto(E, S, g, top[k], h=0.6)
    gx0, gy0, gx1, gy1 = P["nord"].bounds
    for cx, cy, w, d in ((gx0 + 3.0, gy0 + 3.5, 3.0, 2.2), (gx0 + 3.0, gy0 + 6.7, 3.0, 2.2), (gx0 + 6.5, gy0 + 5.0, 1.6, 1.6)):
        S.solid(IMPIANTI, E.box_z(cx, cy, w, d, NORD_TOP, NORD_TOP + 1.3))
    # il corpo sud: tetto piano chiaro a teli, con le giunte
    g = P["sud"]
    E.prisma(S, TELI, E.ring_ccw(g.buffer(-0.3, join_style=2)), SUD_TOP, SUD_TOP + 0.05)
    parapetto(E, S, g, SUD_TOP, h=0.7)
    sx0, sy0, sx1, sy1 = g.bounds
    for x in np.arange(sx0 + 1.6, sx1 - 0.5, 1.6):
        for q in E.clean(g.buffer(-0.35, join_style=2).intersection(box(x - 0.03, sy0, x + 0.03, sy1))):
            E.prisma(S, "#C4C1B8", E.ring_ccw(q), SUD_TOP + 0.05, SUD_TOP + 0.09)
    return S.meshes(), round(colmo, 2)


# ------------------------------------------------------------------ piante

AULE = {
    # csiv: (verso della cattedra in y, passo delle file, tavoli, larghezza dei blocchi)
    "MIA0107001014": (1, 1.2, True, None),     # 7.1.1: cattedra a sud, finestre a sinistra (foto)
    "MIA0107001017": (-1, 0.95, False, 4.0),   # 7.1.2: anfiteatro, porte a sinistra della cattedra (foto)
    "MIA0107001020": (1, 1.2, True, None),     # 7.1.3: cattedra a sud fra le due porte (foto)
}


SPOSTA_S = (-9.6, -9.9)     # il seminterrato sotto il terra (vedi piante())


def _sposta(o, dx, dy):
    """Una geometria della pianta spostata: i punti, i segmenti [x0, y0, x1, y1(, …)] e gli
    anelli, ricorsivamente."""
    if isinstance(o, dict):
        return {k: (_sposta(v, dx, dy) if k not in ("csiv", "tipo", "esterna", "livello_osm") else v) for k, v in o.items()}
    if isinstance(o, list):
        if o and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in o):
            return [round(v + (dx if i % 2 == 0 else dy), 3) if i < 4 else v for i, v in enumerate(o)]
        return [_sposta(v, dx, dy) for v in o]
    return o


def piante(b, geo, aule, E):
    """Due correzioni alle piante:
    - il seminterrato spostato sotto il terra. La pianta CAD lo ha fuori posto: l'ascensore
      del seminterrato (126,9-129,0; 183,3-185,6) e quello del terra (117,1-119,8; 173,0-175,9)
      e l'ala est del seminterrato (129,2-144,2; 179,5-256,6) con il corpo su via Ponzio del
      terra e del primo (119,5-134,6; 169,7-246,7) danno (-9,6; -9,9). Lo spostamento della mappa
      (`spostamenti`, -7,76; 0) lascia l'ala est 1,8 m fuori dalla facciata e 10 m a sud;
    - le file delle aule del primo, che le piante non disegnano. 7.1.1 e 7.1.3 sono piane con
      i banchi (due bordi a 45 cm l'uno dall'altro, come le aule con i tavoli dell'Edificio 11),
      in due blocchi con il corridoio in mezzo; 7.1.2 è ad anfiteatro, file ogni 95 cm in un
      blocco solo."""
    if CSIE + "00S" in geo:
        geo[CSIE + "00S"] = _sposta(geo[CSIE + "00S"], *SPOSTA_S)
    for csip, f in geo.items():
        segs = f.setdefault("linee", {}).setdefault("arredi", [])
        for v in f["vani"]:
            if v["csiv"] not in AULE or v["csiv"] not in aule.get(csip, {}):
                continue
            verso, passo, tavoli, blocco = AULE[v["csiv"]]
            poly = E.shape_of(v)
            interno = poly.buffer(-0.7, join_style=2)
            if interno.is_empty:
                continue
            x0, y0, x1, y1 = interno.bounds
            y_front = y1 - 2.4 if verso > 0 else y0 + 2.4
            y_back = y0 if verso > 0 else y1
            n = int(abs(y_front - y_back) / passo)
            for k in range(n):
                y = y_front - verso * passo * k
                riga = LineString([(x0 - 1, y), (x1 + 1, y)]).intersection(interno)
                for g in getattr(riga, "geoms", [riga]):
                    if g.is_empty or g.length < 2:
                        continue
                    a, c = sorted([g.coords[0][0], g.coords[-1][0]])
                    m = (a + c) / 2
                    pezzi = [(m - blocco / 2, m + blocco / 2)] if blocco else [(a + 0.2, m - 0.5), (m + 0.5, c - 0.2)]
                    for p0, p1 in pezzi:
                        if p1 - p0 < 1.5:
                            continue
                        segs.append([round(p0, 2), round(y, 2), round(p1, 2), round(y, 2)])
                        if tavoli:      # il bordo dietro del banco
                            segs.append([round(p0, 2), round(y - verso * 0.45, 2), round(p1, 2), round(y - verso * 0.45, 2)])
    return geo


BANCO_SCURO, ROSSO_SEDUTA = "#3E4044", "#9E3A35"     # 7.1.1 e 7.1.3 (foto)
LEGNO, LEGNO_SEDUTA = "#C08A50", "#B47E48"            # i banchi in legno della 7.1.2 (foto)
BIANCO_AULA = "#EEEDE8"


def ritocca(sc, meta, E):
    """I colori delle foto delle aule del primo: nella 7.1.1 e nella 7.1.3 banchi scuri e
    sedie nere, con le sedute rosse della 7.1.1 qua e là (le verdi dei tavoli dell'Edificio
    11 non ci sono); nella 7.1.2 i banchi in legno; le pareti bianche."""
    for name, m in sc.s.geometry.items():
        colore = m.metadata.get("colore")
        if "_Arredi_" in name:
            nuovo = {E.TAVOLO: BANCO_SCURO, E.SEDIA_VERDE: ROSSO_SEDUTA, E.SEDIA_ROSSA: ROSSO_SEDUTA,
                     E.DESK: LEGNO, E.SEAT: LEGNO_SEDUTA}.get(colore)
        elif "_Interno_" in name and colore == E.COL["muri"]:
            nuovo = BIANCO_AULA
        else:
            nuovo = None
        if nuovo:
            E.colour(m, nuovo)
