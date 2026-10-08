"""PROTOTIPO — l'Edificio 9 "Giuseppe Bruni" (MIA0111), l'esterno rifatto da zero.

Fonti, oltre ai contorni di leonardo.json e alle piante del Politecnico:
- l'ortofoto (Google, zoom 21, 5 cm per pixel): le ali in coppi a padiglione intorno al
  cortile ottagonale, con i displuvi in lamiera verde; l'aula a rombo a nord-ovest col suo
  padiglione; il padiglione che sporge a nord; il blocco est intorno a una terrazza piana
  grigia; il blocco basso della Lista Aperta a sud-est, a tetto piano beige; il corpo lungo a
  sud; sopra di lui la torretta col colmo nord-sud, il lucernario grigio e il tetto tondo in
  piombo della scala a chiocciola, che nelle piante sta proprio lì (106, 306); le macchine
  degli impianti in fila lungo il lato est. Il tetto piano grigio e il tondo della chiocciola
  cadono dove le piante, rimesse a posto, mettono la terrazza e la scala;
- le foto delle aule del sito del Politecnico (spazi, "Accessi, percorsi e foto"): la 9.0.1
  col pavimento rosso, le sedute in legno chiaro in tre blocchi, i due corridoi e le porte
  nere ai lati della cattedra; la 9.0.2 coi banchi in legno scuro e le portefinestre ad arco;
  la 9.1.2 col pavimento grigio, un corridoio in mezzo e due lungo i muri, il soffitto a
  volte.
Delle facciate non si sono trovate foto: seguono le altre ali di Brusconi del campus
(zoccolo in pietra con le bocche di lupo, rialzato bugnato ad archi, piani alti lisci,
cornicione), come dice anche il profilo della mappa.

Le piante pubbliche dell'Edificio 9 non sono specchiate da nord a sud, come le prende la
mappa (`specchio`), ma trasposte: x e y scambiate, cioè ruotate di un quarto e specchiate.
Trasposte, il cortile ottagonale, il corpo lungo a sud, l'ala est e il rombo tornano sotto i
tetti dell'ortofoto (il piano terra copre il contorno di OpenStreetMap al 71%, contro il 51%
della pianta specchiata), e la scala a chiocciola cade sotto il suo tetto tondo. Qui `piante()`
le traspone e poi sposta ogni piano perché le sue scale cadano su quelle del terra; la
mappa resta com'è.

Le quote: il rialzato a 1,2 m (le scale esterne hanno 7-8 alzate), piani da 5,4 e 4,6 m
come le altre ali di Brusconi; il terra alto per le aule grandi, che salgono a gradoni. Il
secondo piano, nelle piante, c'è solo intorno al lato est e nord del cortile e nel corpo
sud: l'ala ovest, il rombo e il corpo fra il cortile e il corpo sud hanno due piani.
Coordinate Z-up del frame del campus: x est, y sud.
"""
import json
import math
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union

CSIE = "MIA0111"

Z_S, Z_R, Z_1, Z_2 = -2.6, 1.2, 6.6, 11.2
QUOTE = {"MIA011100S": Z_S, "MIA0111000": Z_R, "MIA0111001": Z_1, "MIA0111002": Z_2}
G3 = 15.6              # la gronda delle ali a tre piani
G2 = 11.0              # la gronda delle ali a due piani
FASCIA_1, FASCIA_2 = 6.0, 10.6

STUCCO = "#D3CBB8"         # l'intonaco grigio-beige delle ali di Brusconi
BUGNATO = "#C6BDA8"
STUCCO_CHIARO = "#E8E3D6"  # cornici, fasce, cornicione
PIETRA = "#9D9990"         # lo zoccolo
GRIGIO = "#C9CBCB"         # la Lista Aperta, intonaco grigio (profilo della mappa)
VETRO_SCURO = "#3B4652"
TELAIO = "#F2F0EA"
FERRO = "#2F3236"
LASTRE = "#B9B5AC"
TERRAZZA = "#8F9193"       # la terrazza dell'ala est, grigia nell'ortofoto
TETTO_LISTA = "#C8B9A0"    # il tetto piano beige della Lista Aperta
PIOMBO = "#6F7477"         # il tetto tondo della chiocciola
LAMIERA_VERDE = "#8FA394"  # i displuvi in lamiera
IMPIANTI = "#C3C7CB"
COPPI = "coppi"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    """Sotto il tetto dell'ultimo piano."""
    return G3 - 0.4


# ------------------------------------------------------------------ piante

# Dalle piante salvate (specchiate) a quelle giuste: x e y scambiate, poi una rotazione di
# mezzo grado attorno a PERNO e uno spostamento, trovati facendo coincidere il terra e il
# primo col contorno di OpenStreetMap. Poi ogni piano si sposta perché le sue scale cadano
# su quelle del terra (il seminterrato, salvato con lo spostamento sbagliato, di 6,5 m).
PERNO = (100.0, 280.0)
ROTAZIONE = -0.5
SPOSTA = (-169.342, 177.096)
PER_PIANO = {"MIA011100S": (6.5, 6.75), "MIA0111000": (0.0, 0.0), "MIA0111001": (0.5, 0.5),
             "MIA0111002": (-0.75, -0.5)}


def _punto(x, y, d):
    x, y = y, x
    a = math.radians(ROTAZIONE)
    x, y = x - PERNO[0], y - PERNO[1]
    x, y = x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)
    return round(x + PERNO[0] + SPOSTA[0] + d[0], 2), round(y + PERNO[1] + SPOSTA[1] + d[1], 2)


def _trasponi(o, d):
    """Ogni coppia di coordinate di un piano, anche dentro i segmenti [x1, y1, x2, y2, ...]."""
    if isinstance(o, list):
        if o and all(isinstance(v, (int, float)) for v in o):
            if len(o) == 2:
                return list(_punto(*o, d))
            return list(_punto(*o[:2], d)) + list(_punto(*o[2:4], d)) + o[4:]
        return [_trasponi(v, d) for v in o]
    if isinstance(o, dict):
        return {k: (v if k in ("csiv", "tipo", "livello_osm") else _trasponi(v, d)) for k, v in o.items()}
    return o


_GEO = {}


def geometria(E, geo=None):
    """Le piante al loro posto. Senza geo le legge dal file (per il guscio)."""
    if geo is None:
        if "tutte" not in _GEO:
            raw = json.loads((E.SRC / "piante" / f"{CSIE}-geometria.json").read_text())["piani"]
            _GEO["tutte"] = {c: _trasponi(f, PER_PIANO.get(c, (0, 0))) for c, f in raw.items()}
        return _GEO["tutte"]
    return {c: _trasponi(f, PER_PIANO.get(c, (0, 0))) for c, f in geo.items()}


CORTILE = Polygon([(105.7, 276.8), (116.7, 276.8), (118.9, 278.9), (119.0, 289.9), (116.8, 291.8),
                   (106.1, 292.0), (103.6, 289.9), (103.7, 278.3)])

# Il cortile come lo tagliano le ali: ottagonale, con gli smussi di circa 2,5 m dell'ortofoto.
CORTE = Polygon([(105.7, 277.0), (117.6, 277.0), (120.0, 279.4), (120.0, 289.6), (117.6, 292.0), (106.1, 292.0),
                 (103.6, 289.5), (103.6, 279.1)])

AULA_1, AULA_2, AULA_3, AULA_4 = "MIA0111000040", "MIA0111000043", "MIA0111000008", "MIA0111000003"
AULA_12 = "MIA0111001045"


def _file(poly, n, primo, passo, ultimo, corridoi=(), coppie=False):
    """Le file di banchi di un'aula, come segmenti: parallele al muro della cattedra, n
    verso il fondo, la prima a `primo` m dal muro, una ogni `passo` fino a `ultimo` m dal
    muro di fondo. corridoi: (frazione della larghezza, larghezza) dove le file si
    interrompono. coppie: i due bordi di un tavolo, a 60 cm (aule piane)."""
    n = np.array(n, float) / np.linalg.norm(n)
    u = np.array([-n[1], n[0]])
    pts = [np.array(p) for p in poly.exterior.coords]
    q0 = min(float(np.dot(p, n)) for p in pts)
    q1 = max(float(np.dot(p, n)) for p in pts)
    t0 = min(float(np.dot(p, u)) for p in pts)
    t1 = max(float(np.dot(p, u)) for p in pts)
    dentro = poly.buffer(-0.5, join_style=2)
    tagli = unary_union([LineString([tuple(u * (t0 + (t1 - t0) * f) + n * (q0 - 5)),
                                     tuple(u * (t0 + (t1 - t0) * f) + n * (q1 + 5))]).buffer(w / 2, cap_style=2)
                         for f, w in corridoi]) if corridoi else None
    segs = []
    q = q0 + primo
    while q < q1 - ultimo:
        for dq in ((0.0, 0.6) if coppie else (0.0,)):
            riga = LineString([tuple(u * (t0 - 5) + n * (q + dq)), tuple(u * (t1 + 5) + n * (q + dq))]).intersection(dentro)
            if tagli is not None:
                riga = riga.difference(tagli)
            for g in getattr(riga, "geoms", [riga]):
                if g.is_empty or g.length < 1.2:
                    continue
                a, c = g.coords[0], g.coords[-1]
                segs.append([round(a[0], 2), round(a[1], 2), round(c[0], 2), round(c[1], 2)])
        q += passo
    return segs


def piante(b, geo, aule, E):
    geo = geometria(E, geo)
    # la rampa a gradini che la pianta del terra disegna in diagonale attraverso il cortile,
    # all'aperto sotto gli alberi: né un vano né una scala dell'edificio
    geo["MIA0111000"]["vani"] = [v for v in geo["MIA0111000"]["vani"] if v["csiv"] != "MIA0111000054"]
    t = geo["MIA0111000"]["linee"]
    t["scale"] = [s for s in t.get("scale", []) if not CORTILE.buffer(-0.5).contains(
        LineString([s[:2], s[2:4]]).centroid)]
    forma = lambda c, csiv: next(E.shape_of(v) for v in geo[c]["vani"] if v["csiv"] == csiv)
    # Il rombo: la cattedra contro il lato sud-est (porte nere ai due capi, nelle foto), le
    # file salgono verso il vertice nord-ovest, dove si entra. Nord-ovest è (-1, -1).
    t = geo["MIA0111000"].setdefault("linee", {}).setdefault("arredi", [])
    t += _file(forma("MIA0111000", AULA_1), (-1, -1), 3.6, 0.92, 0.9, corridoi=((0.35, 1.1), (0.65, 1.1)))
    # 9.0.2: la cattedra a est, la portafinestra ad arco subito a sinistra; un corridoio a sud
    t += _file(forma("MIA0111000", AULA_2), (-1, 0), 3.0, 0.95, 0.8, corridoi=((0.88, 1.0),))
    # 9.0.3 e 9.0.4: aule piane coi tavoli, la cattedra a nord
    t += _file(forma("MIA0111000", AULA_3), (0, 1), 2.6, 1.35, 0.8, corridoi=((0.5, 1.0),), coppie=True)
    t += _file(forma("MIA0111000", AULA_4), (0, 1), 2.6, 1.45, 0.8, coppie=True)
    # 9.1.2, sopra la 9.0.1: un corridoio in mezzo e due lungo i muri (foto)
    t = geo["MIA0111001"].setdefault("linee", {}).setdefault("arredi", [])
    p12 = forma("MIA0111001", AULA_12)
    t += _file(p12.buffer(-0.9, join_style=2), (-1, -1), 3.0, 0.88, 0.2, corridoi=((0.5, 1.2),))
    return geo


LEGNO_CHIARO, LEGNO_SEDUTA = "#D2AE7E", "#C79A66"      # le sedute della 9.0.1 e della 9.1.2
ROSSO_PAVIMENTO = "#B0493A"                              # il pavimento della 9.0.1
GRIGIO_PAVIMENTO = "#A8ACAD"                             # il pavimento della 9.1.2
BIANCO_AULA = "#EEEDE8"


def ritocca(sc, meta, E):
    """I colori delle foto: legno chiaro su ferro grigio nelle aule grandi, il pavimento
    rosso della 9.0.1 e grigio della 9.1.2, muri e soffitti bianchi."""
    for name, m in sc.s.geometry.items():
        colore = m.metadata.get("colore")
        nuovo = None
        if name.startswith(("MIA0111000_Arredi_", "MIA0111001_Arredi_")):
            nuovo = {E.SEAT: LEGNO_SEDUTA, E.DESK: LEGNO_CHIARO}.get(colore)
        elif name == AULA_1:
            nuovo = ROSSO_PAVIMENTO
        elif name == AULA_12:
            nuovo = GRIGIO_PAVIMENTO
        elif "_Interno_" in name and colore in (E.COL["muri"], E.CEMENTO_SOFF):
            nuovo = BIANCO_AULA
        if nuovo:
            E.colour(m, nuovo)


# ------------------------------------------------------------------ coppi

def _coppi_texture():
    """Coppi rossi in file, 0,5 m per ripetizione (come gli Edifici 3 e 6)."""
    from PIL import Image
    rng = np.random.default_rng(9)
    size = 256
    y, x = np.mgrid[0:size, 0:size]
    col = 4
    w = size // col
    ridge = np.sin((x % w) / w * math.pi)
    lap = ((y / size) * 1.25) % 1.0
    shade = 0.82 + 0.18 * ridge - 0.12 * (lap > 0.9)
    tone = rng.normal(0, 0.05, (col * 2,))[(x // w) % (col * 2)]
    base = np.array([0.71, 0.40, 0.30])
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


def padiglione(E, S, poly, z, pendenza=0.55, sporto=0.6, displuvi=True, togli=None):
    """Un tetto a padiglione in coppi su un poligono convesso: ogni lato ha la sua falda, in
    ogni punto vale la più bassa. I displuvi coperti di lamiera verde (ortofoto). Torna la
    quota del colmo."""
    P = poly.buffer(sporto, join_style=2)
    pts = E.ring_ccw(P)
    es = E.edges(pts)
    top = z
    falde = []
    for i, (a, c, u, n, L, _) in enumerate(es):
        reg = P
        di0 = float(np.dot(a, n))
        for j, (a2, c2, u2, n2, L2, _) in enumerate(es):
            if j == i or abs(float(np.dot(n, n2)) - 1) < 1e-9:
                continue
            reg = reg.intersection(_semipiano(np.array(n2) - np.array(n), float(np.dot(a2, n2)) - di0))
            if reg.is_empty:
                break
        d = lambda p, di0=di0, n=n: di0 - (p[0] * n[0] + p[1] * n[1])
        if togli is not None:          # gli smussi del cortile: lì il tetto non c'è
            reg = reg.difference(togli)
        for q in E.clean(reg):
            ring = list(q.exterior.coords)[:-1]
            if len(ring) < 3:
                continue
            P3 = [(p[0], p[1], z + pendenza * d(p)) for p in ring]
            uv = [((p[0] - a[0]) * u[0] + (p[1] - a[1]) * u[1], d(p) * math.hypot(1, pendenza)) for p in ring]
            want = (n[0] * pendenza, n[1] * pendenza, 1.0)
            for k in range(1, len(ring) - 1):
                S.tri(COPPI, [P3[0], P3[k], P3[k + 1]], want, [uv[0], uv[k], uv[k + 1]])
            top = max(top, max(p[2] for p in P3))
            falde.append((q, d))
    if displuvi:
        # le linee fra due falde che salgono dagli angoli: una lista di lamiera
        from shapely.ops import linemerge
        for i, (q1, d1) in enumerate(falde):
            for q2, d2 in falde[i + 1:]:
                lin = q1.boundary.intersection(q2.boundary)
                segs = [g for g in getattr(lin, "geoms", [lin]) if g.geom_type == "LineString"]
                if not segs:
                    continue
                lin = linemerge(segs) if len(segs) > 1 else segs[0]
                for g in getattr(lin, "geoms", [lin]):
                    if g.length < 0.5 or (togli is not None and togli.contains(g.centroid)):
                        continue
                    a_, c_ = g.coords[0], g.coords[-1]
                    if abs(d1(a_) - d1(c_)) < 0.3:        # il colmo, orizzontale
                        continue
                    E.trave(S, LAMIERA_VERDE, (*a_, z + pendenza * d1(a_) + 0.06), (*c_, z + pendenza * d1(c_) + 0.06), 0.3)
    E.prisma(S, STUCCO_CHIARO, pts if togli is None else E.ring_ccw(max(E.clean(P.difference(togli)), key=lambda q: q.area)),
             z - 0.14, z - 0.01)
    return top


def falda(E, S, tri, z, pendenza, sporto):
    """Il tetto di un angolo del cortile: una falda sola che scende verso lo smusso (il lato
    lungo del triangolo) e sale verso l'angolo, dove incontra le falde delle due ali."""
    pts = E.ring_ccw(tri)
    a, c = max(zip(pts, pts[1:] + pts[:1]), key=lambda e: math.dist(*e))
    L = math.dist(a, c)
    u = ((c[0] - a[0]) / L, (c[1] - a[1]) / L)
    n = (u[1], -u[0])                      # verso fuori, verso il cortile
    P = tri.buffer(sporto, join_style=2)
    d = lambda p: (a[0] - p[0]) * n[0] + (a[1] - p[1]) * n[1] + sporto
    for q in E.clean(P):
        ring = list(q.exterior.coords)[:-1]
        P3 = [(p[0], p[1], z + pendenza * max(0.0, d(p))) for p in ring]
        uv = [((p[0] - a[0]) * u[0] + (p[1] - a[1]) * u[1], max(0.0, d(p)) * math.hypot(1, pendenza)) for p in ring]
        for k in range(1, len(ring) - 1):
            S.tri(COPPI, [P3[0], P3[k], P3[k + 1]], (n[0] * pendenza, n[1] * pendenza, 1.0), [uv[0], uv[k], uv[k + 1]])


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


def finestre_piano(e, geo, csip, t0, t1):
    """I centri e le larghezze delle finestre che la pianta di un piano disegna lungo questo
    lato fra t0 e t1: [(t, larghezza)]. None se la pianta non ha quel piano qui."""
    a, c, u, n, L, _ = e
    lato = LineString([a, c])
    out = []
    for s_ in geo.get(csip, {}).get("linee", {}).get("finestre", []):
        p, q = np.array(s_[:2]), np.array(s_[2:4])
        if np.linalg.norm(q - p) < 0.6:
            continue
        if abs(float(np.dot((q - p) / np.linalg.norm(q - p), u))) < 0.9:
            continue
        m = (p + q) / 2
        if lato.distance(Point(m)) > 1.3:
            continue
        tm = float(np.dot(m - np.array(a), np.array(u)))
        if t0 + 0.4 < tm < t1 - 0.4:
            out.append((tm, float(np.linalg.norm(q - p))))
    # due segmenti vicini (i due battenti) sono una finestra
    out.sort()
    uniti = []
    for tm, w in out:
        if uniti and tm - uniti[-1][0] < 1.0:
            t_, w_ = uniti[-1]
            uniti[-1] = ((t_ + tm) / 2, max(w_, w, abs(tm - t_) + min(w, w_)))
        else:
            uniti.append((tm, w))
    return uniti


def cornicione(E, S, pts, z, sporto, h=0.8, colore=STUCCO_CHIARO):
    """Il cornicione: un gradino sotto e la lastra che sporge."""
    E.prisma(S, colore, E.ring_ccw(Polygon(pts).buffer(sporto * 0.4, join_style=2)), z - h, z - h * 0.45)
    E.prisma(S, colore, E.ring_ccw(Polygon(pts).buffer(sporto, join_style=2)), z - h * 0.45, z)


def ala(E, S, geo, pts, altre, piani, gronda, alte=False, grigia=False):
    """Le facciate di un'ala, alla Brusconi: lo zoccolo in pietra con le bocche del
    seminterrato, il rialzato bugnato con le finestre ad arco, la fascia, il primo liscio, il
    secondo con finestre rette, il fregio e le mensole sotto la gronda. Le finestre dove le
    piante le disegnano, piano per piano. alte: le finestre ad arco anche al primo, alte,
    per le aule del rombo. grigia: la Lista Aperta, intonaco grigio e finestre rette."""
    for e in E.edges(pts):
        for t0, t1 in libero(e, altre):
            fin0 = finestre_piano(e, geo, "MIA0111000", t0, t1) or [(t0 + p, 1.4) for p in campate(t1 - t0, 4.0)]
            # lo zoccolo, con le bocche di lupo del seminterrato sotto le finestre del terra
            bocche = [rett(p - 0.55, p + 0.55, 0.2, Z_R - 0.25) for p, _ in fin0]
            E.panel(S, PIETRA, e, rett(t0, t1, 0.0, Z_R).difference(unary_union(bocche)), 0.0, 0.1)
            for f in bocche:
                E.panel(S, "#2A2E33", e, f, 0.0, 0.02)
                x0, z0, x1, z1 = f.bounds
                for k in range(1, 6):
                    tt = x0 + (x1 - x0) * k / 6
                    E.panel(S, FERRO, e, rett(tt - 0.02, tt + 0.02, z0, z1), 0.0, 0.07)
            if grigia:
                E.panel(S, GRIGIO, e, rett(t0, t1, Z_R, gronda - 0.6), 0.0, 0.03)
                for zz, csip in ((Z_R, "MIA0111000"), (Z_1 - 1.0, "MIA0111001")):
                    for p, w in finestre_piano(e, geo, csip, t0, t1) or [(t0 + p, 1.6) for p in campate(t1 - t0, 3.6)]:
                        w = min(max(w, 1.2), 2.4)
                        finestra(E, S, e, rett(p - w / 2, p + w / 2, zz + 0.9, zz + 3.0), cornice=0.08, colore="#DCDDDB")
                continue
            # il rialzato bugnato, corsi da 50 cm, interrotti dagli archi
            archi = []
            for p, w in fin0:
                w = min(max(w, 1.2), 1.9)
                archi.append(arco(p - w / 2, p + w / 2, Z_R + 0.8, Z_R + 3.4 - w / 2))
            fori = unary_union([g.buffer(0.2, join_style=2) for g in archi]) if archi else Polygon()
            z = Z_R
            while z < FASCIA_1 - 0.05:
                E.panel(S, BUGNATO, e, rett(t0, t1, z, min(FASCIA_1, z + 0.45)).difference(fori), 0.0, 0.06)
                z += 0.5
            for g in archi:
                finestra(E, S, e, g)
                cx = (g.bounds[0] + g.bounds[2]) / 2
                E.panel(S, STUCCO_CHIARO, e, Polygon([(cx - 0.16, g.bounds[3] - 0.05), (cx + 0.16, g.bounds[3] - 0.05),
                                                       (cx + 0.22, g.bounds[3] + 0.35), (cx - 0.22, g.bounds[3] + 0.35)]), 0.0, 0.15)
            E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, FASCIA_1, FASCIA_1 + 0.4), 0.0, 0.22)
            # il primo
            fin1 = finestre_piano(e, geo, "MIA0111001", t0, t1)
            for p, w in fin1:
                w = min(max(w, 1.2), 1.8)
                if alte:
                    g = arco(p - w / 2, p + w / 2, Z_1 + 0.9, gronda - 1.9 - w / 2)
                else:
                    g = rett(p - w / 2, p + w / 2, Z_1 + 0.8, Z_1 + 3.1)
                    E.panel(S, STUCCO_CHIARO, e, rett(p - w / 2 - 0.25, p + w / 2 + 0.25, Z_1 + 3.25, Z_1 + 3.45), 0.0, 0.2)
                finestra(E, S, e, g)
                E.panel(S, STUCCO_CHIARO, e, rett(p - w / 2 - 0.2, p + w / 2 + 0.2, Z_1 + 0.65, Z_1 + 0.8), 0.0, 0.18)
            if piani == 3:
                E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, FASCIA_2, FASCIA_2 + 0.3), 0.0, 0.18)
                for p, w in finestre_piano(e, geo, "MIA0111002", t0, t1):
                    w = min(max(w, 1.0), 1.5)
                    finestra(E, S, e, rett(p - w / 2, p + w / 2, Z_2 + 0.8, Z_2 + 2.6))
                    E.panel(S, STUCCO_CHIARO, e, rett(p - w / 2 - 0.2, p + w / 2 + 0.2, Z_2 + 0.65, Z_2 + 0.8), 0.0, 0.16)
            E.panel(S, STUCCO_CHIARO, e, rett(t0, t1, gronda - 0.95, gronda - 0.8), 0.0, 0.1)
            for k in range(int((t1 - t0) / 0.9)):
                t = t0 + 0.45 + k * 0.9
                E.panel(S, STUCCO_CHIARO, e, rett(t - 0.1, t + 0.1, gronda - 0.75, gronda - 0.35), 0.0, 0.45)


# ------------------------------------------------------------------ guscio

def parti(geo):
    """Le ali: {nome: (poligono, piani, gronda, tetto)}. tetto: "coppi" (padiglione),
    "terrazza" o "piano". Dalle piante rimesse a posto e dall'ortofoto."""
    aula = next(Polygon(v["forma"][0]).buffer(0) for v in geo["MIA0111000"]["vani"] if v["csiv"] == AULA_1)
    rombo = aula.minimum_rotated_rectangle.buffer(0.7, join_style=2)
    return {
        "rombo": (rombo, 2, G3, "coppi"),
        # l'angolo fra il rombo, l'ala nord e l'ala ovest, con lo smusso del cortile
        "nodo": (Polygon([(94.5, 280.6), (106.6, 268.9), (106.6, 277.0), (103.0, 281.0), (94.5, 281.0)]),
                 3, G3, "coppi"),
        "nord": (box(106.2, 267.5, 120.0, 277.0), 3, G3, "coppi"),
        "padiglione-nord": (box(117.4, 262.8, 128.0, 268.0), 3, G3, "coppi"),
        "angolo-nord-est": (box(128.0, 259.3, 137.4, 264.4), 2, Z_1 + 4.2, "piano"),
        "est-nord": (box(120.0, 264.4, 137.4, 274.6), 3, G3, "coppi"),
        "est-ovest": (box(120.0, 274.6, 130.6, 283.8), 3, G3, "coppi"),
        "est-terrazza": (box(130.6, 274.6, 137.4, 283.8), 3, G3, "terrazza"),
        "est-sud": (box(120.0, 283.8, 137.4, 294.8), 3, G3, "coppi"),
        # gli angoli del cortile, fuori dagli smussi: una falda sola, verso lo smusso
        "angolo-ne": (Polygon([(117.6, 277.0), (120.0, 277.0), (120.0, 279.4)]), 3, G3, "angolo"),
        "angolo-se": (Polygon([(120.0, 289.6), (120.0, 292.0), (117.6, 292.0)]), 3, G3, "angolo"),
        "angolo-so": (Polygon([(106.1, 292.0), (103.6, 292.0), (103.6, 289.5)]), 2, G2, "angolo"),
        "ovest": (box(94.4, 281.0, 103.6, 292.4), 2, G2, "coppi"),
        "sud-ovest": (box(91.2, 292.4, 100.0, 302.0), 2, G2, "coppi"),
        "sud-mezzo": (box(100.0, 292.0, 121.8, 302.0), 2, G2, "coppi"),
        "sud": (box(93.3, 302.0, 122.9, 322.7), 3, G3, "coppi"),
        "lista-aperta": (box(128.4, 294.8, 137.6, 307.6), 2, Z_1 + 4.2, "piano"),
    }


def scalinate(E, S, geo, corpo):
    """Le scale esterne del rialzato, dove la pianta del terra le disegna fuori dal contorno:
    un blocco di gradini dal giardino al rialzato, che scende allontanandosi dal muro."""
    lin = geo["MIA0111000"]["linee"].get("scale", [])
    fuori = [LineString([s_[:2], s_[2:4]]) for s_ in lin if not corpo.buffer(0.3).contains(Point(s_[:2]))
             and corpo.distance(Point(s_[:2])) < 3.0]
    if not fuori:
        return
    gruppi = unary_union([l.buffer(0.35) for l in fuori])
    for gr in E.clean(gruppi):
        if gr.area < 1.5:
            continue
        hull = gr.convex_hull.buffer(-0.3, join_style=2)
        if hull.is_empty:
            continue
        p_muro = corpo.exterior.interpolate(corpo.exterior.project(hull.centroid))
        d = np.array(hull.centroid.coords[0]) - np.array(p_muro.coords[0])
        d = d / (np.linalg.norm(d) or 1)
        q = [float(np.dot(np.array(c), d)) for c in hull.exterior.coords]
        q0, q1 = min(q), max(q)
        n = 7
        for k in range(n):
            fetta = hull.intersection(_semipiano(d, q0 + (q1 - q0) * (k + 1) / n))
            for f in E.clean(fetta):
                E.prisma(S, LASTRE, E.ring_ccw(f), 0.0 if k == 0 else Z_R * (n - k) / n - Z_R / n, Z_R * (n - k) / n)


def guscio(b, E):
    """L'esterno dell'Edificio 9: {chiave: mesh} e la quota più alta."""
    _registra(E)
    S = E.Solidi()
    geo = geometria(E)
    P = parti(geo)
    forme = {k: v[0] for k, v in P.items()}
    top = 0.0
    massa = {k: max(E.clean(v[0].difference(CORTE)), key=lambda q: q.area) for k, v in P.items()}
    for nome, (g, piani, gronda, tipo) in P.items():
        pts = E.ring_ccw(massa[nome])
        grigia = nome in ("lista-aperta", "angolo-nord-est")
        E.prisma(S, GRIGIO if grigia else STUCCO, pts, 0.0, gronda - 0.05)
        # le facce in vista: quelle che non toccano un'ala più alta o pari
        altre = [massa[k] for k, (h, _, gr, _) in P.items() if k != nome and gr >= gronda - 0.1]
        ala(E, S, geo, pts, altre, piani, gronda, alte=(nome == "rombo"), grigia=grigia)
    for nome, (g, piani, gronda, tipo) in P.items():
        pts = E.ring_ccw(massa[nome])
        if tipo == "coppi":
            cornicione(E, S, pts, gronda, 0.6)
            top = max(top, padiglione(E, S, g, gronda, 0.6 if nome == "rombo" else 0.55, 0.5))
        elif tipo == "angolo":
            cornicione(E, S, pts, gronda, 0.6)
            falda(E, S, g, gronda, 0.55, 0.5)
        elif tipo == "terrazza":
            E.prisma(S, STUCCO_CHIARO, pts, gronda - 0.05, gronda + 0.95)
            E.prisma(S, TERRAZZA, E.ring_ccw(g.buffer(-0.3, join_style=2)), gronda - 0.05, gronda + 1.0)
            E.trave(S, FERRO, (g.bounds[0] + 0.3, g.bounds[1] + 0.2, gronda + 1.1), (g.bounds[2] - 0.3, g.bounds[1] + 0.2, gronda + 1.1), 0.05)
        else:
            E.prisma(S, "#E2E1DC", E.ring_ccw(g.buffer(0.25, join_style=2)), gronda - 0.4, gronda - 0.05)
            E.prisma(S, "#E2E1DC", pts, gronda - 0.05, gronda + 0.6)
            E.prisma(S, TETTO_LISTA, E.ring_ccw(g.buffer(-0.25, join_style=2)), gronda - 0.05, gronda + 0.65)
            if nome == "lista-aperta":      # i torrini di ventilazione dell'ortofoto
                for k in range(3):
                    S.solid(IMPIANTI, E.box_z(131.0 + k * 2.8, 300.0 + (k % 2) * 3.5, 1.0, 1.0, gronda + 0.6, gronda + 1.2))
        top = max(top, gronda)
    # la torretta col colmo nord-sud sopra il corpo sud (ortofoto): un po' più alta
    torretta = box(100.6, 300.0, 104.8, 310.0)
    E.prisma(S, STUCCO, E.ring_ccw(torretta), G3 - 1.0, G3 + 1.2)
    cornicione(E, S, E.ring_ccw(torretta), G3 + 1.2, 0.45, h=0.6)
    top = max(top, padiglione(E, S, torretta, G3 + 1.2, 0.6, 0.4))
    # il lucernario grigio sulla scala del corpo fra cortile e corpo sud
    S.solid("#A7ABAD", E.box_z(105.3, 295.8, 4.4, 3.6, G2 + 0.5, G2 + 3.0))
    # il tetto tondo in piombo della scala a chiocciola (ortofoto; nelle piante a 106, 306)
    cil = trimesh.creation.cylinder(radius=2.1, height=2.6, sections=24).apply_translation([106.3, 306.3, G3 + 0.5])
    S.solid(STUCCO, cil)
    S.solid(PIOMBO, trimesh.creation.cone(radius=2.4, height=1.4, sections=24).apply_translation([106.3, 306.3, G3 + 1.8]))
    # gli alberi fitti del cortile (ortofoto): chiome tonde su tronchi
    for x, y, r in ((108.5, 281.5, 3.2), (114.5, 282.0, 3.0), (110.0, 287.8, 3.4), (115.5, 287.5, 2.6)):
        S.solid("#8A6A48", trimesh.creation.cylinder(radius=0.25, height=6.0, sections=8).apply_translation([x, y, 3.0]))
        S.solid("#7FA866", trimesh.creation.icosphere(subdivisions=2, radius=r).apply_scale([1, 1, 1.25]).apply_translation([x, y, 6.0 + r]))
    # le macchine degli impianti in fila lungo il lato est, a terra (ortofoto)
    for y0, y1 in ((271.5, 277.0), (278.0, 284.5), (285.5, 291.5)):
        S.solid(IMPIANTI, E.box_z(139.0, (y0 + y1) / 2, 2.2, y1 - y0, 0.0, 2.1))
        for k in range(int((y1 - y0) / 1.3)):
            S.solid("#7E848A", trimesh.creation.cylinder(radius=0.45, height=0.3, sections=12).apply_translation(
                [139.0, y0 + 0.7 + k * 1.3, 2.25]))
    # le scale esterne del rialzato
    corpo = unary_union([g.buffer(0.02) for g in forme.values()]).buffer(-0.02)
    scalinate(E, S, geo, max(E.clean(corpo), key=lambda q: q.area))
    return S.meshes(), round(top, 2)
