"""Edificio 8, Alessandro Amerio (MIA0108): l'esterno ridisegnato dal satellite e dalle foto.

È l'Istituto di Fisica del campus del 1927, oggi il Dipartimento di Fisica. Le misure vengono
da tre fonti:
- le piante del Politecnico (piante/MIA0108-geometria.json): il contorno di ogni piano, le
  finestre, le porte verso l'esterno. Il primo, il secondo e il seminterrato sono importati
  fuori posto rispetto al terra: si riallineano qui (ALLINEA), misurati sull'ortofoto e sugli
  ascensori;
- l'ortofoto (Google, zoom 21, 5 cm per pixel): i tetti a coppi a padiglione delle ali, l'ala
  diagonale verso sud-ovest, il corpo ottagonale basso con il tetto piano bianco e le
  macchine nel cortile fra le ali, la volta di vetro a nord-est dell'ottagono, la terrazza
  pavimentata con le fioriere sopra il corpo a nord (il secondo piano) e il corpo piano a
  est con le due testate a padiglione;
- la foto della testata dell'ala diagonale (sito del Dipartimento di Fisica): tre campate fra
  due smussi, il terra a bugnato con le finestre sotto archi ribassati in un arco a tutto
  sesto, la scritta FISICA SPERIMENTALE, le finestre ad arco del primo, il cornicione con la
  gronda e i pluviali di rame, le porte ad arco negli smussi (la pianta le ha: porte esterne
  in tutti e due gli smussi).

Quote dalla foto (circa 70 px per metro, la testata è larga 12,9 m fra gli smussi) e dalle
scale (32 alzate fra terra e primo): terra a 0,3, primo a 5,9, gronda a 11,0, cornicione fino
a 11,4. Il secondo esiste solo nel corpo a nord, sotto la terrazza: a 10,4, terrazza a 14.
L'interno dell'aula 8.0.1 non ha file disegnate: le file sono aggiunte in piante().

guscio(), quote(), tetto() e piante() sono chiamati da esporta3d.py (E è quel modulo).
"""
import math
import numpy as np
import trimesh
from shapely.geometry import Polygon, Point, LineString, box
from shapely.ops import unary_union
from shapely import affinity

# ---------------------------------------------------------------- misure

QUOTE = {"MIA010800S": -4.2, "MIA0108000": 0.3, "MIA0108001": 5.9, "MIA0108002": 10.4}
TERRA, PRIMO, SECONDO = 0.3, 5.9, 10.4
FASCIA = 5.6            # la fascia fra terra e primo, sopra il bugnato
GRONDA = 11.0           # sotto il cornicione delle ali
CORNICE = 11.4          # il filo del tetto sul muro
SPORTO = 0.7            # la gronda oltre il muro
PENDENZA = 0.38         # coppi: circa 21 gradi
BASSO = 5.9             # i corpi di un piano solo intorno all'ottagono
OTTAGONO_H = 10.4       # il tetto piano dell'ottagono, alla quota del secondo
TERRAZZA = 14.0         # la terrazza sopra il secondo

# Piani importati fuori posto: x' = sx * x + dx, y' = sy * y + dy. Il primo è stirato di 2 cm
# per metro in x (i muri est e ovest cadono sui muri del terra e sulle gronde dell'ortofoto, e
# l'ascensore del primo su quello del terra); il seminterrato è spostato sull'ascensore e sulle
# scale; il secondo sulla terrazza pavimentata dell'ortofoto (14 x 14 m), e il suo ascensore
# cade sul torrino bianco accanto alla terrazza.
ALLINEA = {"MIA010800S": (1.0, 0.9, 1.0, 3.5),
           "MIA0108001": (1.021, 0.9, 1.0, -0.4),
           "MIA0108002": (1.0, 2.95, 1.0, -3.2)}

# Dall'ortofoto: l'ottagono basso nel cortile è il locale 017 della pianta del secondo (il suo
# tetto piano), un rombo a spigoli smussati, spostato sul tetto bianco dell'ortofoto; la volta
# di vetro sta contro il suo lato nord-est, fra la terrazza e l'ala est.
OTTAGONO = Polygon([(110.4, 122.9), (111.2, 122.9), (118.6, 130.3), (118.6, 131.1), (111.2, 138.4),
                    (110.5, 138.4), (103.1, 131.1), (103.1, 130.3)])
VOLTA = Polygon([(111.4, 121.2), (118.6, 121.2), (120.3, 122.9), (120.3, 131.0), (118.9, 131.0),
                 (111.4, 123.4)])
TERRAZZA_PIANTA = box(99.6, 106.4, 114.2, 121.1)    # la terrazza pavimentata dell'ortofoto
# Le falde: poligoni convessi, ognuno un padiglione; dove si incrociano vince il più alto
# (impluvi e displuvi vengono da sé). La testata diagonale ha gli smussi della pianta.
DIAGONALE = [(82.4, 151.8), (82.5, 148.3), (95.5, 135.6), (108.2, 148.3), (95.1, 161.0), (91.6, 161.0)]
PIANTA_DIAGONALE = [(82.4, 151.8), (82.5, 148.3), (91.9, 139.2), (104.9, 150.9), (95.1, 161.0), (91.6, 161.0)]
FALDE = {
    "ovest": [(92.4, 107.6), (102.6, 107.6), (102.6, 142.0), (92.4, 142.0)],
    "nord-est": [(113.3, 107.6), (119.7, 107.6), (119.7, 120.5), (113.3, 120.5)],
    "est": [(119.6, 121.0), (127.6, 121.0), (127.6, 150.9), (119.6, 150.9)],
    "testata-nord": [(122.3, 123.6), (135.6, 123.6), (135.6, 129.0), (122.3, 129.0)],
    "testata-sud": [(122.3, 142.6), (135.6, 142.6), (135.6, 150.7), (122.3, 150.7)],
    "sud": [(100.0, 140.0), (119.6, 140.0), (119.6, 150.9), (100.0, 150.9)],
    "avancorpo": [(116.6, 138.0), (125.5, 138.0), (125.5, 152.7), (116.6, 152.7)],
    "abbaino": [(125.5, 132.8), (130.0, 132.8), (130.0, 136.4), (125.5, 136.4)],
    "diagonale": DIAGONALE,
}
CAPPE = {"testata-nord": None, "testata-sud": None}
TESTATA = ((91.6, 161.0), (82.4, 151.8))        # la facciata della foto, da sud-est a nord-ovest

# Colori dalla foto: intonaco a graniglia grigio-beige, cornici più chiare, rame, vetri scuri.
MURO = "#C9BFAD"
MURO_OMBRA = "#B5AB98"
CORNICI = "#DDD5C6"
CORTILE = "#D6D0C4"           # i muri sui cortili e l'ottagono, più chiari
VETRO = "#3C4852"
TELAIO = "#EEEEEA"
RAME = "#A5683F"
LASTRICO = "#9C9890"          # i tetti piani
TETTO_BIANCO = "#DEDBD3"      # il tetto dell'ottagono nell'ortofoto
PAVIMENTO = "#8E6F5E"         # la terrazza: piastrelle rossicce
VERDE = "#5E7F3F"
FIORIERA = "#C8C4BA"
VOLTA_VETRO = "#A9BDC9"
GRIGIO_TECNICO = "#9EA2A3"
CORTE = "#77736B"             # il fondo dei cortili, quasi sempre in ombra


# ---------------------------------------------------------------- texture

def _coppi():
    """I coppi: canali lungo la falda ogni 16 cm, file sovrapposte ogni 40 cm, toni del cotto
    (come nel guscio dell'Edificio 1: le due ortofoto hanno lo stesso cotto)."""
    from PIL import Image
    rng = np.random.default_rng(1)
    size = 512
    y, x = np.mgrid[0:size, 0:size]
    u, v = x / size, y / size
    ch = (u * 6.25) % 1.0
    row = (v * 2.5) % 1.0
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


def _scritta_tex():
    """FISICA SPERIMENTALE: lettere di bronzo scuro sull'intonaco, come nella foto."""
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
    W, H = 2048, 128
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    font = None
    for f in ("/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
              "/usr/share/fonts/truetype/liberation/LiberationSerif-Regular.ttf"):
        try:
            font = ImageFont.truetype(f, 84)
            break
        except OSError:
            pass
    font = font or ImageFont.load_default()
    txt = "F I S I C A     S P E R I M E N T A L E"
    w = d.textlength(txt, font=font)
    d.text(((W - w) / 2, 18), txt, fill=255, font=font)
    a = np.asarray(img.filter(ImageFilter.GaussianBlur(0.8)), float) / 255
    base = np.array([0.79, 0.75, 0.68])
    rgb = base[None, None] * (1 - 0.78 * a)[..., None]
    gy, gx = np.gradient(a)
    nrm = np.dstack([gx * 3, -gy * 3, np.ones_like(a)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    to8 = lambda x: Image.fromarray(np.clip(x * 255, 0, 255).astype(np.uint8))
    return to8(rgb), to8(nrm * 0.5 + 0.5)


def _registra(E):
    if "coppi" not in E._TEXTURES:
        E._TEXTURES["coppi"] = _coppi()
    if "mia0108_scritta" not in E._TEXTURES:
        E._TEXTURES["mia0108_scritta"] = _scritta_tex()
    E.TEX.setdefault("coppi", 1.0)
    E.TEX["mia0108_scritta"] = 1.0


# ---------------------------------------------------------------- le piante, riallineate

def _sposta(csip):
    sx, dx, sy, dy = ALLINEA.get(csip, (1.0, 0.0, 1.0, 0.0))
    return lambda p: [round(p[0] * sx + dx, 2), round(p[1] * sy + dy, 2)] + list(p[2:])


def _punti(x, T):
    """Ogni punto [x, y] dentro liste annidate, portato con T."""
    if isinstance(x, list) and len(x) >= 2 and all(isinstance(v, (int, float)) for v in x[:2]):
        return T(x)
    return [_punti(y, T) for y in x] if isinstance(x, list) else x


def _riallinea(csip, f):
    """Un piano della geometria con le coordinate riallineate al terra."""
    if csip not in ALLINEA:
        return f
    T = _sposta(csip)
    seg = lambda s: T(s[:2]) + T(s[2:4])[:2] + list(s[4:])
    anelli = lambda rr: [[T(p) for p in r] for r in rr]
    out = dict(f)
    out["contorno"] = anelli(f.get("contorno", []))
    out["vani"] = [dict(v, forma=anelli(v["forma"]), etichetta=T(v["etichetta"])) for v in f.get("vani", [])]
    out["porte"] = [{k: (T(v) if isinstance(v, list) else v) for k, v in d.items()} for d in f.get("porte", [])]
    out["linee"] = {k: [seg(s) for s in ls] for k, ls in f.get("linee", {}).items()}
    for k in ("vuoti", "acqua"):
        if k in f:
            out[k] = _punti(f[k], T)
    if "percorso_accessibile" in f:
        out["percorso_accessibile"] = [seg(s) for s in f["percorso_accessibile"]]
    return out


_PIANI = {}


def piano(b, E, csip):
    """La geometria di un piano, riallineata (cache)."""
    if csip not in _PIANI:
        _PIANI[csip] = _riallinea(csip, E.plan_floor(b, csip))
    return _PIANI[csip]


def _anelli(f, k):
    out = []
    for r in f.get(k, []):
        r = r[0] if r and isinstance(r[0][0], list) else r
        if len(r) >= 3:
            out.append(Polygon(r).buffer(0))
    return out


def liscio(g, r=1.0):
    """Un contorno senza le mazzette delle finestre e le lesene della pianta (risalti larghi
    meno di 2 r): chiuso, aperto e semplificato, così ogni lato del guscio è un muro intero."""
    g = g.buffer(0.6, join_style=2).buffer(-0.6, join_style=2)
    g = g.buffer(-r, join_style=2).buffer(r, join_style=2)
    return g.simplify(0.25)


def impronte(b, E):
    """(terra, primo, vuoti del primo, secondo) come poligoni, riallineati."""
    t = piano(b, E, "MIA0108000")
    p = piano(b, E, "MIA0108001")
    s = piano(b, E, "MIA0108002")
    terra = liscio(unary_union([Polygon(r).buffer(0) for r in t["contorno"]]))
    # l'ala diagonale come nella pianta e nella foto: la testata fra i due smussi, dritta
    a, c = (91.9, 139.2), (104.9, 150.9)
    sud_ovest = Polygon([a, c, (c[0] - 60, c[1] + 60), (a[0] - 60, a[1] + 60)])
    terra = terra.difference(Polygon(PIANTA_DIAGONALE).buffer(1.5, join_style=2).intersection(sud_ovest))
    terra = terra.union(Polygon(PIANTA_DIAGONALE)).buffer(0.01, join_style=2).buffer(-0.01, join_style=2)
    vuoti1 = unary_union(_anelli(p, "vuoti")).buffer(0.25, join_style=2)
    # il primo sui muri del terra, dove gli è vicino (la pianta del primo disegna le lesene)
    primo = liscio(unary_union([Polygon(r).buffer(0) for r in p["contorno"]]))
    primo = primo.buffer(0.45, join_style=2).intersection(terra).difference(vuoti1)
    primo = unary_union([g for g in getattr(primo, "geoms", [primo]) if g.area > 5]).simplify(0.2)
    otto = [v for v in s["vani"] if v["csiv"].endswith("017")]
    secondo = unary_union([Polygon(r).buffer(0) for r in s["contorno"]])
    if otto:
        secondo = secondo.difference(Polygon(otto[0]["forma"][0]).buffer(0.4, join_style=2))
    secondo = max(E.clean(secondo.buffer(-0.05, join_style=2).buffer(0.05, join_style=2)), key=lambda g: g.area)
    return terra, primo, vuoti1, secondo


# ---------------------------------------------------------------- tetti a padiglione

def _piano_falda(a, c, z0, k):
    """Il piano di una falda che parte dal lato a→c (anello antiorario) a quota z0:
    z = A x + B y + C, salendo di k per metro verso l'interno."""
    L = math.dist(a, c)
    nx, ny = -(c[1] - a[1]) / L, (c[0] - a[0]) / L         # verso l'interno
    return (k * nx, k * ny, z0 - k * (nx * a[0] + ny * a[1]))


def _sotto(p1, p2, big=2000.0):
    """Il semipiano dove il piano p1 sta sotto (o pari a) p2, come poligono grande."""
    a, b_, c = p1[0] - p2[0], p1[1] - p2[1], p1[2] - p2[2]
    n = math.hypot(a, b_)
    if n < 1e-9:
        return box(-big, -big, big, big) if c <= 1e-9 else Polygon()
    ux, uy = a / n, b_ / n
    d = -c / n                      # ux x + uy y <= d
    px, py = ux * d, uy * d
    tx, ty = -uy, ux
    return Polygon([(px + tx * big, py + ty * big), (px - tx * big, py - ty * big),
                    (px - tx * big - ux * big, py - ty * big - uy * big),
                    (px + tx * big - ux * big, py + ty * big - uy * big)])


def _z(p, pl):
    return pl[0] * p[0] + pl[1] * p[1] + pl[2]


def falde(parti, z0, k, cappe=None):
    """[(poligono, piano, è_tetto_piano)]: le falde visibili di un insieme di padiglioni su
    poligoni convessi (allargati della gronda), il più alto vince dove si sovrappongono."""
    cappe = cappe or {}
    tetti = {}
    for nome, pts in parti.items():
        P = Polygon(pts).buffer(SPORTO, join_style=2)
        pts = list(P.exterior.coords)[:-1]
        if not Polygon(pts).exterior.is_ccw:
            pts = pts[::-1]
        piani = [(_piano_falda(a, c, z0, k), False) for a, c in zip(pts, pts[1:] + pts[:1]) if math.dist(a, c) > 0.05]
        if cappe.get(nome) is not None:
            piani.append(((0.0, 0.0, cappe[nome]), True))
        tetti[nome] = (P, piani)
    out = []
    for nome, (P, piani) in tetti.items():
        for i, (pl, piatto) in enumerate(piani):
            f = P
            for j, (pl2, _) in enumerate(piani):
                if j != i:
                    f = f.intersection(_sotto(pl, pl2))
                    if f.is_empty:
                        break
            if f.is_empty or f.area < 0.01:
                continue
            # tolto dove un altro padiglione sta più in alto
            for nome2, (P2, piani2) in tetti.items():
                if nome2 == nome or not P2.intersects(f):
                    continue
                sopra = P2
                for pl2, _ in piani2:
                    sopra = sopra.intersection(_sotto(pl, pl2))       # qui pl sta sotto tutto P2
                    if sopra.is_empty:
                        break
                if not sopra.is_empty:
                    f = f.difference(sopra)
                if f.is_empty:
                    break
            for g in getattr(f, "geoms", [f]):
                if g.geom_type == "Polygon" and g.area > 0.01:
                    out.append((g, pl, piatto))
    return out


def stendi(S, poly, pl, key, uv=False):
    """Un poligono orizzontale portato sul piano pl, triangolato; uv in metri lungo la gronda
    e lungo la falda se uv."""
    vs, fs = trimesh.creation.triangulate_polygon(poly, engine="earcut")
    g = np.array([pl[0], pl[1]])
    n = np.linalg.norm(g)
    up = (-pl[0], -pl[1], 1.0)
    if n > 1e-9:
        d = g / n                                # in salita
        u = np.array([-d[1], d[0]])              # lungo la gronda
        s = math.sqrt(1 + n * n)
    for f in fs:
        p = [(vs[i][0], vs[i][1], _z(vs[i], pl)) for i in f]
        uvs = None
        if uv and n > 1e-9:
            uvs = [(float(np.dot(q[:2], u)), float(np.dot(q[:2], d)) * s) for q in p]
        S.tri(key, p, up, uvs)


def tetti(E, S, b, primo):
    """Le falde a coppi delle ali, con la gronda, il sottogronda e il tetto piano sotto."""
    pezzi = falde(FALDE, CORNICE - SPORTO * PENDENZA, PENDENZA,
                  {k: v for k, v in CAPPE.items() if v is not None})
    for g, pl, piatto in pezzi:
        stendi(S, g, pl, LASTRICO if piatto else "coppi", uv=not piatto)
    # sotto la gronda: un piano orizzontale chiaro, dove la falda sporge oltre il muro
    sporgenze = unary_union([Polygon(p).buffer(SPORTO, join_style=2) for p in FALDE.values()]).difference(primo.buffer(-0.05))
    for g in E.clean(sporgenze):
        stendi(S, g, (0, 0, CORNICE - SPORTO * PENDENZA - 0.02), CORNICI)
    # il tetto piano dove le falde non arrivano (il corpo est fra le due testate)
    piatti = primo.difference(unary_union([Polygon(p) for p in FALDE.values()])).difference(VOLTA)
    for g in E.clean(piatti.buffer(-0.02)):
        if g.area > 0.5:
            solido(E, S, LASTRICO, g, GRONDA, CORNICE + 0.1)
    return pezzi


# ---------------------------------------------------------------- facciate

class Facciata:
    """Un lato del guscio con le coordinate della foto: t lungo il lato, z in altezza, d
    verso l'esterno."""

    def __init__(self, E, S, e):
        self.E, self.S, self.e = E, S, e
        self.fori = []

    def piatto(self, key, shape, d0, d1):
        self.E.panel(self.S, key, self.e, shape, d0, d1)

    def rett(self, key, t0, t1, z0, z1, d0, d1):
        if t1 - t0 > 0.01 and z1 - z0 > 0.01:
            self.piatto(key, box(t0, z0, t1, z1), d0, d1)

    def punto(self, t, d, z):
        a, _, u, n, _, _ = self.e
        return np.array([a[0] + u[0] * t + n[0] * d, a[1] + u[1] * t + n[1] * d, z])


def arco(t0, t1, z0, zi, ribassato=False):
    """Un'apertura con l'arco a tutto sesto (o ribassato) impostato a zi."""
    w = t1 - t0
    if ribassato:
        r = w * 0.85
        c = Point((t0 + t1) / 2, zi - r + w * 0.22).buffer(r, 48)
        return unary_union([box(t0, z0, t1, zi), c.intersection(box(t0, zi, t1, zi + w))])
    c = Point((t0 + t1) / 2, zi).buffer(w / 2, 48)
    return unary_union([box(t0, z0, t1, zi), c.intersection(box(t0, zi, t1, zi + w))])


def serramento(F, s, t0, t1, z0, traverso):
    """Vetro scuro e telaio bianco: due ante, il traverso, il bordo."""
    F.piatto(VETRO, s, 0.0, 0.02)
    tc = (t0 + t1) / 2
    bars = [box(tc - 0.04, z0, tc + 0.04, 20), box(t0, traverso - 0.04, t1, traverso + 0.04)]
    F.piatto(TELAIO, unary_union(bars).intersection(s), 0.0, 0.05)
    F.piatto(TELAIO, s.difference(s.buffer(-0.07)), 0.0, 0.06)


def finestra_terra(F, tc, w=1.45):
    """Il terra della foto: finestra rettangolare con la lunetta ad arco ribassato, dentro un
    arco a tutto sesto incassato nel bugnato, con la chiave e il davanzale."""
    t0, t1 = tc - w / 2, tc + w / 2
    z0, zi = 1.6, 3.9
    s = arco(t0, t1, z0, zi, ribassato=True)
    nicchia = arco(t0 - 0.22, t1 + 0.22, z0 - 0.05, zi, ribassato=False)
    F.fori.append(nicchia.buffer(0.05))
    serramento(F, s, t0, t1, z0, zi)
    F.piatto(MURO_OMBRA, nicchia.difference(s), 0.0, 0.012)
    F.piatto(CORNICI, nicchia.buffer(0.18).difference(nicchia).difference(box(t0 - 1, 0, t1 + 1, zi)), 0.0, 0.1)
    r = (t1 - t0) / 2 + 0.22
    F.piatto(CORNICI, Polygon([(tc - 0.16, zi + r - 0.05), (tc + 0.16, zi + r - 0.05), (tc + 0.22, zi + r + 0.32),
                               (tc - 0.22, zi + r + 0.32)]), 0.0, 0.14)
    F.rett(CORNICI, t0 - 0.3, t1 + 0.3, z0 - 0.15, z0, 0.0, 0.14)


def finestra_primo(F, tc, z, w=1.4):
    """Il primo della foto: finestra ad arco a tutto sesto con la cornice liscia, il
    davanzale su due mensole."""
    t0, t1 = tc - w / 2, tc + w / 2
    z0, zi = z + 1.0, z + 3.25
    s = arco(t0, t1, z0, zi)
    F.fori.append(s.buffer(0.2))
    serramento(F, s, t0, t1, z0, zi)
    F.piatto(CORNICI, s.buffer(0.16).difference(s).difference(box(t0 - 1, 0, t1 + 1, z0)), 0.0, 0.08)
    F.rett(CORNICI, t0 - 0.35, t1 + 0.35, z0 - 0.14, z0, 0.0, 0.2)
    for tm in (t0 - 0.2, t1 + 0.05):
        F.rett(CORNICI, tm, tm + 0.15, z0 - 0.45, z0 - 0.14, 0.0, 0.16)


def finestra_rett(F, tc, z0, z1, w=1.3, key=CORNICI):
    t0, t1 = tc - w / 2, tc + w / 2
    s = box(t0, z0, t1, z1)
    F.fori.append(s.buffer(0.15))
    serramento(F, s, t0, t1, z0, z0 + (z1 - z0) * 0.72)
    F.piatto(key, s.buffer(0.12, join_style=2).difference(s), 0.0, 0.07)
    F.rett(key, t0 - 0.2, t1 + 0.2, z0 - 0.12, z0, 0.0, 0.14)


def portone(F, tc, w=1.6):
    """Una porta verso l'esterno: arco a tutto sesto, battenti scuri, la cornice."""
    t0, t1 = tc - w / 2, tc + w / 2
    s = arco(t0, t1, TERRA, 3.0)
    F.fori.append(s.buffer(0.25))
    F.piatto("#4A3F36", s, 0.0, 0.03)
    F.piatto(VETRO, s.difference(box(t0, 0, t1, 3.05)).buffer(-0.08), 0.0, 0.04)
    F.piatto(CORNICI, s.buffer(0.2).difference(s).difference(box(t0 - 1, -1, t1 + 1, TERRA)), 0.0, 0.12)


def bugnato(F, t0, t1, z0, z1, alto=0.5):
    """Il bugnato del terra: corsi orizzontali staccati da un giunto in ombra."""
    fori = unary_union(F.fori) if F.fori else Polygon()
    z = z0
    while z < z1 - 0.1:
        F.piatto(MURO, box(t0, z + 0.05, t1, min(z1, z + alto)).difference(fori), 0.0, 0.05)
        z += alto


def cornicione(F, L, z, sporto=SPORTO, key=CORNICI):
    """Il cornicione a gola sotto la gronda: tre gradini che sporgono fino al filo del tetto."""
    F.rett(key, -0.05, L + 0.05, z - 0.55, z - 0.35, 0.0, 0.12)
    F.rett(key, -0.2, L + 0.2, z - 0.35, z - 0.15, 0.0, 0.35)
    F.rett(key, -sporto, L + sporto, z - 0.15, z + 0.05, 0.0, sporto)


def finestre_pianta(lines, anello, near=0.9):
    """Le finestre della pianta su un anello: {indice del lato: [(t0, t1)]}."""
    es = []
    for a, c in zip(anello, anello[1:] + anello[:1]):
        L = math.dist(a, c)
        if L >= 0.3:
            es.append((a, c, ((c[0] - a[0]) / L, (c[1] - a[1]) / L), L))
    out = {}
    for s in lines:
        p, q = s[:2], s[2:4]
        if math.dist(p, q) < 0.5:
            continue
        mid = Point((p[0] + q[0]) / 2, (p[1] + q[1]) / 2)
        dv = ((q[0] - p[0]) / math.dist(p, q), (q[1] - p[1]) / math.dist(p, q))
        best = None
        for i, (a, c, u, L) in enumerate(es):
            dd = LineString([a, c]).distance(mid)
            if dd > near or abs(dv[0] * u[0] + dv[1] * u[1]) < 0.9:
                continue
            t0 = (p[0] - a[0]) * u[0] + (p[1] - a[1]) * u[1]
            t1 = (q[0] - a[0]) * u[0] + (q[1] - a[1]) * u[1]
            t0, t1 = max(0.4, min(t0, t1)), min(L - 0.4, max(t0, t1))
            if t1 - t0 > 0.5 and (best is None or dd < best[0]):
                best = (dd, i, t0, t1)
        if best:
            out.setdefault(best[1], []).append((best[2], best[3]))
    for i, spans in out.items():
        spans.sort()
        merged = [list(spans[0])]
        for t0, t1 in spans[1:]:
            if t0 - merged[-1][1] < 0.35:
                merged[-1][1] = max(merged[-1][1], t1)
            else:
                merged.append([t0, t1])
        out[i] = merged
    return out, es


def centri(spans, passo=2.9):
    """I centri delle finestre di una fila di aperture della pianta: le lunghe divise."""
    out = []
    for t0, t1 in spans:
        n = max(1, round((t1 - t0) / passo))
        out += [t0 + (t1 - t0) * (k + 0.5) / n for k in range(n)]
    return out


def _e(a, c):
    L = math.dist(a, c)
    u = ((c[0] - a[0]) / L, (c[1] - a[1]) / L)
    return (a, c, u, (u[1], -u[0]), L, 0.0)


def facciate(E, S, b, terra, primo):
    """Le facciate esterne: due piani dove c'è il primo, uno solo altrove, con le finestre e
    le porte della pianta."""
    tutto = terra.union(primo).buffer(0.15, join_style=2).buffer(-0.15, join_style=2)
    tutto = liscio(max(E.clean(tutto), key=lambda g: g.area))
    anello = E.ring_ccw(Polygon(tutto.exterior))
    f0 = piano(b, E, "MIA0108000")
    f1 = piano(b, E, "MIA0108001")
    win0, es = finestre_pianta(f0["linee"].get("finestre", []), anello)
    win1, _ = finestre_pianta(f1["linee"].get("finestre", []), anello)
    porte = {}
    for d in f0.get("porte", []):
        if not d.get("esterna"):
            continue
        m = Point(d["chiusa"])
        for i, (a, c, u, L) in enumerate(es):
            if LineString([a, c]).distance(m) < 1.4:
                porte.setdefault(i, []).append((m.x - a[0]) * u[0] + (m.y - a[1]) * u[1])
                break
    testata = LineString(TESTATA)
    for i, (a, c, u, L) in enumerate(es):
        e = _e(a, c)
        F = Facciata(E, S, e)
        mid = Point((a[0] + c[0]) / 2 - u[1] * 0.6, (a[1] + c[1]) / 2 + u[0] * 0.6)
        alto = primo.buffer(0.3).contains(mid)
        # le porte, unite quando sono i due battenti della stessa
        ps = []
        for t in sorted(porte.get(i, [])):
            if ps and t - ps[-1] < 1.6:
                ps[-1] = (ps[-1] + t) / 2
            else:
                ps.append(t)
        ps = [min(max(t, 1.0), L - 1.0) for t in ps if L > 1.8]
        for t in ps:
            portone(F, t)
        if L > 2.2:
            for t in centri(win0.get(i, [])):
                if all(abs(t - p) > 1.9 for p in ps) and 1.0 < t < L - 1.0:
                    finestra_terra(F, t, w=min(1.45, L - 1.4))
        if alto:
            for t in centri(win1.get(i, [])):
                if 1.0 < t < L - 1.0:
                    finestra_primo(F, t, PRIMO, w=min(1.4, L - 1.4))
        fori = unary_union(F.fori) if F.fori else Polygon()
        F.rett(MURO_OMBRA, 0, L, 0.0, TERRA + 0.3, 0.0, 0.08)            # lo zoccolo
        bugnato(F, 0, L, TERRA + 0.3, FASCIA)
        F.rett(CORNICI, -0.1, L + 0.1, FASCIA, FASCIA + 0.3, 0.0, 0.18)    # la fascia del primo
        if alto:
            F.rett(CORNICI, 0, L, 3.85, 3.95, 0.0, 0.06)                   # l'imposta degli archi
            cornicione(F, L, CORNICE)
            if L > 6:                                                      # i pannelli fra le finestre
                F.piatto(MURO, box(0.4, PRIMO + 0.4, L - 0.4, GRONDA - 0.7).difference(fori.buffer(0.25)), 0.0, 0.03)
        else:
            F.rett(CORNICI, -0.1, L + 0.1, BASSO - 0.25, BASSO + 0.15, 0.0, 0.3)
            F.rett(MURO, 0, L, BASSO + 0.15, BASSO + 0.9, -0.15, 0.1)      # il parapetto del tetto piano
            F.rett(CORNICI, -0.05, L + 0.05, BASSO + 0.9, BASSO + 1.0, -0.18, 0.13)
        # la scritta sopra le finestre del terra, sulla testata della foto
        if alto and testata.distance(Point(a)) < 1.0 and testata.distance(Point(c)) < 1.0 and L > 10:
            t0, t1 = L / 2 - 3.6, L / 2 + 3.6
            p = [F.punto(t0, 0.035, 5.95), F.punto(t1, 0.035, 5.95), F.punto(t1, 0.035, 6.4), F.punto(t0, 0.035, 6.4)]
            S.quad("mia0108_scritta", p, (e[3][0], e[3][1], 0), [(1, 0), (0, 0), (0, 1), (1, 1)])
        # pluviali di rame agli spigoli delle ali
        if alto and L > 8:
            for t in (L - 0.35,):
                p = F.punto(t, 0.12, 0)
                S.solid(RAME, trimesh.creation.cylinder(0.055, segment=[(p[0], p[1], 0.2), (p[0], p[1], CORNICE - 0.3)], sections=8))
    return anello


def cortili(E, S, b, vuoti1):
    """I muri sui cortili interni (le pareti del vuoto del primo): finestre rettangolari al
    primo sopra i corpi bassi, la gronda."""
    f1 = piano(b, E, "MIA0108001")
    for g in E.clean(vuoti1):
        pts = E.ring_ccw(g)[::-1]                # orario: la normale guarda nel cortile
        win, es = finestre_pianta(f1["linee"].get("finestre", []), pts, near=1.0)
        for i, (a, c, u, L) in enumerate(es):
            F = Facciata(E, S, _e(a, c))
            for t in centri(win.get(i, []), 2.4):
                if 0.9 < t < L - 0.9:
                    finestra_rett(F, t, PRIMO + 1.0, PRIMO + 3.6, w=min(1.2, L - 1.2))
            F.rett(CORNICI, -0.1, L + 0.1, GRONDA - 0.25, GRONDA, 0.0, 0.25)


# ---------------------------------------------------------------- i corpi nel cortile

def ottagono(E, S):
    """Il corpo ottagonale basso: muri chiari, finestre alte, tetto piano bianco con le
    macchine dell'ortofoto."""
    pts = E.ring_ccw(OTTAGONO)
    E.prisma(S, CORTILE, pts, 0.0, OTTAGONO_H)
    for e in E.edges(pts):
        F = Facciata(E, S, e)
        L = e[4]
        n = max(1, int(L / 2.6))
        for k in range(n):
            t = L * (k + 0.5) / n
            finestra_rett(F, t, PRIMO + 0.6, PRIMO + 3.4, w=1.2)
        F.rett(CORNICI, -0.1, L + 0.1, OTTAGONO_H - 0.2, OTTAGONO_H + 0.1, 0.0, 0.3)
        F.rett(CORTILE, 0, L, OTTAGONO_H + 0.1, OTTAGONO_H + 0.85, -0.18, 0.05)
        F.rett(CORNICI, -0.05, L + 0.05, OTTAGONO_H + 0.85, OTTAGONO_H + 0.95, -0.2, 0.08)
    E.prisma(S, TETTO_BIANCO, E.ring_ccw(OTTAGONO.buffer(-0.15, join_style=2)), OTTAGONO_H, OTTAGONO_H + 0.12)
    z = OTTAGONO_H + 0.12
    for x, y in ((106.0, 129.0), (106.0, 130.1), (106.0, 131.2), (106.0, 132.3),
                 (116.3, 129.6), (116.3, 130.7), (116.3, 131.8)):              # le unità esterne
        E.prisma(S, "#D4D6D6", [(x - 0.5, y - 0.52), (x + 0.5, y - 0.52), (x + 0.5, y + 0.52), (x - 0.5, y + 0.52)], z, z + 0.9)
        S.solid("#55595C", trimesh.creation.cylinder(0.38, 0.05, 16).apply_translation((x, y, z + 0.92)))
    E.prisma(S, GRIGIO_TECNICO, [(104.6, 134.2), (107.4, 136.9), (106.0, 138.3), (103.2, 135.6)], 0.0, z + 0.6)   # il vano scala vetrato
    E.prisma(S, TETTO_BIANCO, [(110.0, 125.4), (112.0, 125.4), (112.0, 126.2), (110.0, 126.2)], z, z + 0.7)
    S.solid("#3F6D9A", trimesh.creation.cylinder(0.45, 1.0, 16).apply_translation((110.8, 137.4, z + 0.5)))


def volta(E, S):
    """La volta di vetro a nord-est dell'ottagono: falde vetrate su un reticolo bianco a
    rombi, come nell'ortofoto, fra il corpo basso e l'ala."""
    z0 = GRONDA - 0.4
    E.prisma(S, CORTILE, E.ring_ccw(VOLTA), 0.0, z0)
    pezzi = falde({"volta": list(VOLTA.buffer(-SPORTO, join_style=2).exterior.coords)[:-1]}, z0, 0.45)
    for g, pl, _ in pezzi:
        stendi(S, g, (pl[0], pl[1], pl[2] + 0.02), VOLTA_VETRO)
        x0, y0, x1, y1 = g.bounds
        for k in np.arange(-30, 30, 1.4):                 # il reticolo a rombi
            for sgn in (1, -1):
                ln = LineString([(x0 - 30, y0 + k - 30 * sgn), (x0 + 30, y0 + k + 30 * sgn)])
                seg = ln.intersection(g.buffer(-0.05))
                for s_ in getattr(seg, "geoms", [seg]):
                    if s_.geom_type == "LineString" and s_.length > 0.2:
                        p, q = s_.coords[0], s_.coords[-1]
                        E.trave(S, TELAIO, (p[0], p[1], _z(p, pl) + 0.06), (q[0], q[1], _z(q, pl) + 0.06), 0.06)
    for e in E.edges(E.ring_ccw(VOLTA)):
        F = Facciata(E, S, e)
        F.rett(TELAIO, -0.05, e[4] + 0.05, z0 - 0.2, z0, 0.0, 0.1)


def secondo(E, S, b, sec):
    """Il corpo a nord sopra il primo: il secondo piano con le sue finestre, la terrazza
    pavimentata sopra, con le fioriere lungo il bordo ovest e sud, il padiglione grigio e le
    pergole bianche dell'ortofoto."""
    f2 = piano(b, E, "MIA0108002")
    sec = sec.intersection(TERRAZZA_PIANTA)
    pts = E.ring_ccw(sec)
    E.prisma(S, MURO, pts, PRIMO, TERRAZZA)
    win, es = finestre_pianta(f2["linee"].get("finestre", []), pts, near=1.0)
    for i, (a, c, u, L) in enumerate(es):
        F = Facciata(E, S, _e(a, c))
        for t in centri(win.get(i, []), 2.6):
            if 0.8 < t < L - 0.8:
                finestra_rett(F, t, SECONDO + 0.9, SECONDO + 2.9, w=min(1.3, L - 1.2))
        F.rett(CORNICI, -0.1, L + 0.1, SECONDO - 0.2, SECONDO + 0.1, 0.0, 0.15)
        F.rett(CORNICI, -0.1, L + 0.1, TERRAZZA - 0.25, TERRAZZA, 0.0, 0.3)
        F.rett(MURO, 0, L, TERRAZZA, TERRAZZA + 0.9, -0.2, 0.05)
        F.rett(TELAIO, -0.05, L + 0.05, TERRAZZA + 0.9, TERRAZZA + 1.0, -0.22, 0.08)
    E.prisma(S, PAVIMENTO, E.ring_ccw(sec.buffer(-0.2, join_style=2)), TERRAZZA - 0.1, TERRAZZA + 0.05)
    z = TERRAZZA + 0.05
    x0, y0, x1, y1 = sec.bounds
    for q in (box(x0 + 0.25, y0 + 0.4, x0 + 0.9, y1 - 3.4), box(x0 + 0.4, y1 - 4.1, x1 - 3.0, y1 - 3.45),
              box(x0 + 2.0, y0 + 0.25, x0 + 7.2, y0 + 0.85)):
        E.prisma(S, FIORIERA, E.ring_ccw(q), z, z + 0.55)
        E.prisma(S, VERDE, E.ring_ccw(q.buffer(-0.06)), z + 0.55, z + 0.95)
    # il padiglione grigio con le due fasce bianche e le pergole
    E.prisma(S, MURO, [(105.6, 111.4), (113.8, 111.4), (113.8, 115.2), (105.6, 115.2)], z, z + 2.5)
    E.prisma(S, LASTRICO, [(105.5, 111.3), (113.9, 111.3), (113.9, 115.3), (105.5, 115.3)], z + 2.5, z + 2.65)
    for y in (110.7, 115.6):
        E.prisma(S, TELAIO, [(105.6, y - 0.4), (111.0, y - 0.4), (111.0, y + 0.4), (105.6, y + 0.4)], z + 2.4, z + 2.6)
    for (px0, py0, px1, py1) in ((101.2, 109.6, 105.2, 117.4), (105.6, 116.2, 111.4, 119.6)):
        for xx in (px0, px1):
            for yy in (py0, py1):
                E.prisma(S, TELAIO, [(xx - 0.07, yy - 0.07), (xx + 0.07, yy - 0.07), (xx + 0.07, yy + 0.07), (xx - 0.07, yy + 0.07)], z, z + 2.4)
        for yy in np.arange(py0, py1 + 0.01, 0.8):
            E.trave(S, TELAIO, (px0, yy, z + 2.45), (px1, yy, z + 2.45), 0.08)
    # il torrino dell'ascensore accanto alla terrazza
    E.prisma(S, TETTO_BIANCO, [(115.4, 117.6), (117.6, 117.6), (117.6, 120.6), (115.4, 120.6)], PRIMO, TERRAZZA + 2.4)


# ---------------------------------------------------------------- l'edificio

def solido(E, S, key, geom, z0, z1):
    """Un prisma per ogni poligono (con i suoi buchi) di una geometria shapely."""
    for g in E.clean(geom):
        if g.area > 0.05:
            S.solid(key, trimesh.creation.extrude_polygon(g, z1 - z0).apply_translation([0, 0, z0]))


def guscio(b, E):
    """({colore: mesh}, quota più alta) dell'Edificio 8."""
    _registra(E)
    S = E.Solidi()
    terra, primo, vuoti1, sec = impronte(b, E)
    basso = terra.difference(primo).difference(OTTAGONO).difference(VOLTA)
    # i cortili a terra: il fondo
    f0 = piano(b, E, "MIA0108000")
    for g in E.clean(unary_union(_anelli(f0, "vuoti")).union(vuoti1.difference(OTTAGONO).difference(VOLTA))):
        solido(E, S, CORTE, g, 0.0, 0.05)
    for g in E.clean(basso.buffer(-0.05, join_style=2)):
        if g.area > 1:
            solido(E, S, MURO, g, 0.0, BASSO)
            solido(E, S, "#77756F", g.buffer(-0.1, join_style=2), BASSO, BASSO + 0.08)
    for g in E.clean(primo.difference(VOLTA)):
        solido(E, S, MURO, Polygon(g.exterior), 0.0, GRONDA)
    facciate(E, S, b, terra, primo)
    cortili(E, S, b, vuoti1)
    ottagono(E, S)
    volta(E, S)
    secondo(E, S, b, sec)
    tetti(E, S, b, primo)
    return S.meshes(), TERRAZZA + 2.4


def quote(b, E):
    return {c: QUOTE.get(c, 0.0) for c in b.get("livelli", [])}


def tetto(b, E):
    """Sotto il tetto dell'ultimo piano (il secondo, sotto la terrazza)."""
    return TERRAZZA - 0.5


# ---------------------------------------------------------------- piante

AULA = "MIA0108000011"     # l'aula 8.0.1, 260 posti, tutta l'ala diagonale


def piante(b, geo, aule, E):
    """Le piante riallineate al terra (primo, secondo, seminterrato), senza l'ottagono del
    secondo (è il tetto piano del corpo ottagonale, non un locale), e le file dell'aula 8.0.1,
    che la pianta non disegna: parallele alla testata, ogni 95 cm, con un corridoio in mezzo
    e ai lati; la cattedra verso l'ingresso interno, a nord-est, le file che salgono verso la
    testata con le porte negli smussi."""
    out = {c: _riallinea(c, f) for c, f in geo.items()}
    if "MIA0108002" in out:
        out["MIA0108002"]["vani"] = [v for v in out["MIA0108002"]["vani"] if not v["csiv"].endswith("017")]
    f = out.get("MIA0108000")
    if f is None:
        return out
    v = next((v for v in f["vani"] if v["csiv"] == AULA), None)
    if v is None:
        return out
    poly = E.shape_of(v)
    # coordinate dell'aula: u lungo le file (parallele alla testata), w dal fondo alla cattedra
    a, c = TESTATA
    L = math.dist(a, c)
    u = np.array([(c[0] - a[0]) / L, (c[1] - a[1]) / L])
    w = np.array([-u[1], u[0]])                     # verso nord-est, dentro l'ala
    o = np.array(a)
    loc = affinity.affine_transform(poly, [u[0], u[1], w[0], w[1], -float(np.dot(o, u)), -float(np.dot(o, w))])
    interno = loc.buffer(-0.9, join_style=2)
    ix0, iy0, ix1, iy1 = interno.bounds
    fondo, davanti = iy0 + 0.6, iy1 - 3.4           # dietro, verso la testata; la cattedra a nord-est
    segs = f["linee"].setdefault("arredi", [])
    y = davanti
    while y > fondo:
        riga = LineString([(ix0 - 1, y), (ix1 + 1, y)]).intersection(interno)
        for g in getattr(riga, "geoms", [riga]):
            if g.is_empty or g.length < 3:
                continue
            x0_, x1_ = sorted((g.coords[0][0], g.coords[-1][0]))
            m = (x0_ + x1_) / 2
            for p0, p1 in ((x0_ + 0.3, m - 0.6), (m + 0.6, x1_ - 0.3)):
                if p1 - p0 > 1.5:
                    P = o + u * p0 + w * y
                    Q = o + u * p1 + w * y
                    segs.append([round(P[0], 2), round(P[1], 2), round(Q[0], 2), round(Q[1], 2)])
        y -= 0.95
    return out
