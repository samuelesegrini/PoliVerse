"""PROTOTIPO — attrezzi comuni ai gusci degli edifici più semplici (quelli che non hanno
bisogno di un modulo tutto loro come il Trifoglio o l'Edificio 41).

Un guscio che li usa si scrive come una descrizione: le quote dei piani, il contorno di ogni
piano dalle piante (o un contorno dato), per ogni lato il rivestimento e le finestre, poi il
tetto. Le finestre, dove le piante le disegnano (`linee.finestre`), cadono dove sono davvero.

    import sys, pathlib
    sys.path.insert(0, str(pathlib.Path(__file__).parent))
    import _kit as K

    def guscio(b, E):
        k = K.Kit(E, "MIA0403")
        k.piano("MIA0403000", 0.0, 4.2, K.Stile(...))
        k.tetto_piano(k.contorno("MIA0403002"), 12.6)
        return k.fine()

Coordinate Z-up del frame del campus: x est, y sud. I colori sono sRGB come nella palette
dell'esportatore. Il nome comincia con _ perché l'esportatore cerca solo gusci/<csie>.py.
"""
import json
import math
import sys
import pathlib
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union
from shapely import affinity

QUI = pathlib.Path(__file__).resolve().parent

VETRO = "#3F4C58"
VETRO_CHIARO = "#9FB4C3"
TELAIO = "#2B2E33"
TELAIO_CHIARO = "#D9DBDC"
GUAINA = "#9EA2A6"          # i tetti piani: guaina grigia
GHIAIA = "#BDB8AE"
COPERTINA = "#C9CBCC"
IMPIANTI = "#A9AEB3"
PRATO = "#8FB46E"
CHIOMA, TRONCO = "#9CBF7E", "#7A6248"
SPESSORE = 0.4              # il nucleo pieno del piano sta così dentro il filo del muro


def rett(t0, t1, z0, z1):
    return Polygon([(t0, z0), (t1, z0), (t1, z1), (t0, z1)])


def mid(e):
    a, c = e[0], e[1]
    return ((a[0] + c[0]) / 2, (a[1] + c[1]) / 2)


def verso(e):
    """Il punto cardinale verso cui guarda un lato: 'N', 'S', 'E', 'O' (y verso sud)."""
    nx, ny = e[3]
    if abs(nx) > abs(ny):
        return "E" if nx > 0 else "O"
    return "S" if ny > 0 else "N"


# ---------------------------------------------------------------- texture

TEXTURE = {"kit_bugnato_grigio": 1.0, "kit_mattone": 0.5, "kit_coppi": 0.8, "kit_pv": 1.0,
           "kit_lamiera": 1.0, "kit_klinker": 0.6}


def _texture(name):
    """(colore, normali) PIL generate: bugnato grigio (corsi da 50 cm), mattoni a vista
    (25 x 6,5 cm), coppi, pannelli fotovoltaici, lamiera grecata, klinker."""
    from PIL import Image
    rng = np.random.default_rng(7)
    size = 256
    y, x = np.mgrid[0:size, 0:size] / size
    if name == "kit_bugnato_grigio":
        course = np.floor(y * 2)
        xs = (x + 0.5 * course) % 1.0
        dy = np.minimum((y * 2) % 1.0, 1 - (y * 2) % 1.0) * 0.5
        d = np.minimum(np.minimum(xs, 1 - xs), dy)
        height = np.clip(d / 0.03, 0, 1)
        rgb = np.array([0.66, 0.66, 0.64])[None, None] * (0.7 + 0.3 * height + rng.normal(0, 0.03, (size, size)))[..., None]
        strength = 5.0
    elif name in ("kit_mattone", "kit_klinker"):
        rows = 7 if name == "kit_mattone" else 8          # 0,5 m: 7 corsi da 7 cm
        cols = 2 if name == "kit_mattone" else 2.4
        course = np.floor(y * rows)
        xs = (x * cols + 0.5 * (course % 2)) % 1.0
        joint = (np.minimum((y * rows) % 1, 1 - (y * rows) % 1) < 0.08) | (np.minimum(xs, 1 - xs) < 0.03)
        k = (np.floor(x * cols + 0.5 * (course % 2)) + 7 * course).astype(int)
        base = np.array([0.62, 0.33, 0.24]) if name == "kit_mattone" else np.array([0.55, 0.36, 0.28])
        tone = rng.normal(0, 0.06, 64)[k % 64]
        rgb = base[None, None] * (0.95 + tone)[..., None]
        rgb[joint] = [0.72, 0.70, 0.66]
        height = np.where(joint, 0.0, 1.0)
        strength = 3.0
    elif name == "kit_coppi":
        cx = (x * 4) % 1.0
        row = (y * 2) % 1.0
        height = np.sqrt(np.clip(1 - (2 * cx - 1) ** 2, 0, 1)) * (0.75 + 0.25 * row)
        k = (np.floor(x * 4) + 4 * np.floor(y * 2)).astype(int)
        tone = rng.normal(0, 0.06, 8)[k % 8]
        rgb = np.array([0.63, 0.35, 0.25])[None, None] * (0.78 + 0.32 * height + tone)[..., None]
        rgb[row < 0.04] *= 0.6
        strength = 6.0
    elif name == "kit_pv":
        cell = ((x * 6) % 1 < 0.06) | ((y * 6) % 1 < 0.06)
        frame = (x < 0.025) | (x > 0.975) | (y < 0.025) | (y > 0.975)
        rgb = np.zeros((size, size, 3)) + np.array([0.12, 0.16, 0.27])
        rgb[cell] = [0.20, 0.24, 0.34]
        rgb[frame] = [0.72, 0.74, 0.77]
        height = np.where(frame, 1.0, 0.0)
        strength = 2.0
    else:                                                  # kit_lamiera: greche ogni 25 cm
        g = (x * 4) % 1.0
        height = np.clip(1.6 - np.abs(g - 0.5) * 4, 0, 1)
        rgb = np.array([0.70, 0.72, 0.73])[None, None] * (0.85 + 0.15 * height)[..., None]
        strength = 4.0
    gy, gx = np.gradient(height)
    nrm = np.dstack([-gx * strength, gy * strength, np.ones_like(height)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    to8 = lambda a: Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return to8(rgb), to8(nrm * 0.5 + 0.5)


def registra(E):
    for name, metri in TEXTURE.items():
        E.TEX.setdefault(name, metri)
        if name not in E._TEXTURES:
            E._TEXTURES[name] = _texture(name)


# ---------------------------------------------------------------- lo stile di una facciata

class Stile:
    """Come è fatto un piano su un lato.

    muro       colore (o texture kit_*) del rivestimento
    finestre   'pianta' (dove le disegna la pianta), ('passo', passo, larghezza), 'nastro'
               (una fascia continua), 'vetrata' (facciata continua), None (cieco)
    davanzale, architrave  quote delle finestre sopra il pavimento del piano
    telaio, vetro           colori
    sguincio   quanto è arretrato il vetro (m)
    cornice    colore di una cornice intorno a ogni finestra (None: niente)
    marcapiano (altezza, sporgenza, colore) di una fascia in basso, sul filo del solaio
    tende      colore delle tende da sole avvolte sopra le finestre (None: niente)
    passo_montanti  per 'nastro' e 'vetrata'
    """

    def __init__(self, muro="#D8D4CC", finestre="pianta", davanzale=0.9, architrave=2.7,
                 telaio=TELAIO, vetro=VETRO, sguincio=0.18, cornice=None, marcapiano=None,
                 tende=None, passo_montanti=1.5, minima=0.6, montante=1.4, reach=1.2):
        self.muro, self.finestre, self.davanzale, self.architrave = muro, finestre, davanzale, architrave
        self.telaio, self.vetro, self.sguincio, self.cornice = telaio, vetro, sguincio, cornice
        self.marcapiano, self.tende, self.passo_montanti = marcapiano, tende, passo_montanti
        self.minima, self.montante, self.reach = minima, montante, reach

    def con(self, **kw):
        s = Stile.__new__(Stile)
        s.__dict__.update(self.__dict__)
        s.__dict__.update(kw)
        return s


# ---------------------------------------------------------------- il kit

class Kit:
    def __init__(self, E, csie, geo=None):
        self.E, self.csie = E, csie
        self.S = E.Solidi()
        registra(E)
        p = E.SRC / "piante" / f"{csie}-geometria.json"
        self.geo = geo if geo is not None else (json.loads(p.read_text())["piani"] if p.exists() else {})
        self.top = 0.0

    # ---------------------------------------------------------- contorni

    def contorni(self, csip, semplifica=0.08, minimo=2.0):
        out = []
        for r in self.geo[csip]["contorno"]:
            p = Polygon(r).buffer(0).simplify(semplifica)
            if p.area > minimo:
                out.append(max(getattr(p, "geoms", [p]), key=lambda g: g.area))
        return sorted(out, key=lambda p: -p.area)

    def contorno(self, csip, chiudi=0.0, **kw):
        """Il contorno del piano (tutti i pezzi uniti), con le rientranze strette chiuse."""
        g = unary_union(self.contorni(csip, **kw))
        if chiudi:
            g = g.buffer(chiudi, join_style=2).buffer(-chiudi, join_style=2)
        return g

    @staticmethod
    def squadra(g, passo=0.5, angolo=None):
        """Il contorno ridisegnato ad angoli retti, nell'orientamento dell'edificio, con il
        passo dato: toglie i lati storti e i dentini di pochi centimetri delle piante."""
        if angolo is None:
            r = g.minimum_rotated_rectangle
            c = list(r.exterior.coords)
            l = max(((c[i], c[i + 1]) for i in range(4)), key=lambda s: math.dist(*s))
            angolo = math.degrees(math.atan2(l[1][1] - l[0][1], l[1][0] - l[0][0]))
        o = g.centroid
        q = affinity.rotate(g, -angolo, origin=o)
        x0, y0, x1, y1 = q.bounds
        celle = []
        for i in range(int((x1 - x0) / passo) + 1):
            for j in range(int((y1 - y0) / passo) + 1):
                cx, cy = x0 + (i + 0.5) * passo, y0 + (j + 0.5) * passo
                if q.contains(Point(cx, cy)):
                    celle.append(box(cx - passo / 2, cy - passo / 2, cx + passo / 2, cy + passo / 2))
        u = unary_union(celle).buffer(0.01, join_style=2).buffer(-0.01, join_style=2).simplify(0.02)
        return affinity.rotate(u, angolo, origin=o)

    def pezzi(self, g, minimo=1.0):
        return [p for p in self.E.clean(g) if p.area > minimo]

    # ---------------------------------------------------------- finestre

    def finestre_pianta(self, csip, e, reach=1.2, minima=0.5):
        """Gli intervalli [t0, t1] delle finestre della pianta su questo lato."""
        a, c, u, n, L, _ = e
        iv = []
        if csip not in self.geo:
            return iv
        for s in self.geo[csip]["linee"].get("finestre", []):
            p, q = np.array(s[:2]), np.array(s[2:])
            d = q - p
            ln = np.linalg.norm(d)
            if ln < 0.25 or abs(np.dot(d / ln, u)) < 0.95:
                continue
            ds = [float(np.dot(r - np.array(a), np.array(n))) for r in (p, q)]
            if not all(-reach < v < 0.35 for v in ds):
                continue
            ts = sorted(float(np.dot(r - np.array(a), np.array(u))) for r in (p, q))
            if ts[1] < 0.1 or ts[0] > L - 0.1:
                continue
            iv.append((max(0.0, ts[0]), min(L, ts[1])))
        iv.sort()
        out = []
        for t0, t1 in iv:
            if out and t0 < out[-1][1] + 0.08:
                out[-1] = (out[-1][0], max(out[-1][1], t1))
            else:
                out.append((t0, t1))
        return [(max(0.15, t0), min(L - 0.15, t1)) for t0, t1 in out if t1 - t0 > minima]

    @staticmethod
    def finestre_passo(L, passo, larghezza, margine=0.8):
        k = int((L - 2 * margine + (passo - larghezza)) // passo)
        if k <= 0:
            return []
        tot = k * passo - (passo - larghezza)
        t = (L - tot) / 2
        return [(t + i * passo, t + i * passo + larghezza) for i in range(k)]

    # ---------------------------------------------------------- pezzi di facciata

    def pannello(self, colore, e, forma, d0, d1):
        self.E.panel(self.S, colore, e, forma, d0, d1)

    def foro(self, e, t0, t1, z0, z1, st):
        """Una finestra nel muro: lo sguincio, il vetro arretrato, il telaio con i montanti,
        il davanzale che sporge."""
        P, S = self.pannello, st
        dv = -S.sguincio
        P(S.vetro, e, rett(t0, t1, z0, z1), dv - 0.02, dv)
        tel = rett(t0, t1, z0, z1).difference(rett(t0 + 0.06, t1 - 0.06, z0 + 0.06, z1 - 0.06))
        P(S.telaio, e, tel, dv, dv + 0.06)
        k = max(1, round((t1 - t0) / S.montante))
        for i in range(1, k):
            t = t0 + (t1 - t0) * i / k
            P(S.telaio, e, rett(t - 0.03, t + 0.03, z0, z1), dv, dv + 0.05)
        if z1 - z0 > 1.9:
            zt = z1 - 0.55
            P(S.telaio, e, rett(t0, t1, zt - 0.03, zt + 0.03), dv, dv + 0.05)
        if z0 > 0.2 + getattr(self, "_zpiano", 0):
            P(COPERTINA if S.cornice is None else S.cornice, e, rett(t0 - 0.05, t1 + 0.05, z0 - 0.05, z0), -0.05, 0.06)
        if S.cornice:
            P(S.cornice, e, rett(t0 - 0.14, t1 + 0.14, z0 - 0.05, z1 + 0.14).difference(rett(t0, t1, z0, z1)), 0.0, 0.05)
        if S.tende:
            P(S.tende, e, rett(t0 - 0.05, t1 + 0.05, z1 - 0.22, z1), 0.0, 0.18)

    def nastro(self, e, t0, t1, z0, z1, st):
        P = self.pannello
        P(st.vetro, e, rett(t0, t1, z0, z1), -0.12, -0.08)
        k = max(1, round((t1 - t0) / st.passo_montanti))
        for i in range(k + 1):
            t = t0 + (t1 - t0) * i / k
            P(st.telaio, e, rett(max(t0, t - 0.035), min(t1, t + 0.035), z0, z1), -0.1, -0.02)
        for z in (z0, z1):
            P(st.telaio, e, rett(t0, t1, max(z0, z - 0.04), min(z1, z + 0.04)), -0.1, -0.02)
        P(COPERTINA, e, rett(t0, t1, z0 - 0.05, z0), -0.08, 0.05)

    def vetrata(self, e, z0, z1, st, t0=0.0, t1=None, traversi=()):
        a, c, u, n, L, _ = e
        t1 = L if t1 is None else t1
        P = self.pannello
        P(st.vetro, e, rett(t0, t1, z0, z1), -0.02, 0.02)
        k = max(1, round((t1 - t0) / st.passo_montanti))
        for i in range(k + 1):
            t = t0 + (t1 - t0) * i / k
            P(st.telaio, e, rett(max(t0, t - 0.03), min(t1, t + 0.03), z0, z1), 0.0, 0.12)
        for z in (z0, z1, *traversi):
            P(st.telaio, e, rett(t0, t1, max(z0, z - 0.04), min(z1, z + 0.04)), 0.0, 0.09)

    def muro(self, e, z0, z1, colore, buchi=(), d=0.06, dentro=SPESSORE):
        """La pelle del muro su un lato, con i buchi (t0, t1, z0, z1): spessa quanto il
        muro, così i buchi fanno da sguinci."""
        forma = rett(0.0, e[4], z0, z1)
        if buchi:
            forma = forma.difference(unary_union([rett(*b) for b in buchi]))
        self.pannello(colore, e, forma, -dentro, d)

    def porta(self, e, t0, t1, z0, h=2.6, telaio=TELAIO, vetro=VETRO_CHIARO, pensilina=None):
        P = self.pannello
        P(vetro, e, rett(t0, t1, z0, z0 + h), -0.2, -0.16)
        tel = rett(t0, t1, z0, z0 + h).difference(rett(t0 + 0.07, t1 - 0.07, z0, z0 + h - 0.07))
        P(telaio, e, tel, -0.2, -0.1)
        tm = (t0 + t1) / 2
        P(telaio, e, rett(tm - 0.03, tm + 0.03, z0, z0 + h), -0.2, -0.12)
        if pensilina:
            colore, sporto = pensilina
            P(colore, e, rett(t0 - 0.6, t1 + 0.6, z0 + h + 0.25, z0 + h + 0.45), 0.0, sporto)

    # ---------------------------------------------------------- un piano

    def piano(self, poly, z0, z1, stile, csip=None, lati=None, porte=False):
        """Il corpo di un piano: il nucleo pieno e, lato per lato, la pelle con le finestre.
        stile è uno Stile o una funzione (lato, centro) -> Stile (None: il lato resta nudo).
        csip: il piano della pianta da cui prendere le finestre."""
        polys = [poly] if isinstance(poly, Polygon) else self.pezzi(poly)
        self._zpiano = z0
        for q in polys:
            pts = self.E.ring_ccw(q)
            for c in self.pezzi(q.buffer(-SPESSORE + 0.02, join_style=2), 0.5):
                self.E.prisma(self.S, "#55595F", self.E.ring_ccw(c), z0, z1)
            for e in self.E.edges(pts):
                st = stile(e, mid(e)) if callable(stile) else stile
                if st is None:
                    continue
                self.lato(e, z0, z1, st, csip)
                if porte and csip:
                    for t0, t1 in self.porte_esterne(csip, e):
                        self.porta(e, t0, t1, z0)
        self.top = max(self.top, z1)

    def lato(self, e, z0, z1, st, csip=None):
        L = e[4]
        zf0, zf1 = z0 + st.davanzale, min(z1 - 0.15, z0 + st.architrave)
        if st.finestre == "vetrata":
            self.vetrata(e, z0, z1, st, traversi=(z0 + st.architrave,) if st.architrave < z1 - z0 - 0.2 else ())
            return
        if st.finestre == "nastro":
            iv = [(0.25, L - 0.25)] if L > 1.2 else []
        elif st.finestre == "pianta":
            iv = self.finestre_pianta(csip, e, st.reach, st.minima) if csip else []
        elif isinstance(st.finestre, tuple) and st.finestre[0] == "passo":
            iv = self.finestre_passo(L, st.finestre[1], st.finestre[2])
        elif isinstance(st.finestre, list):
            iv = st.finestre
        else:
            iv = []
        buchi = [(t0, t1, zf0, zf1) for t0, t1 in iv]
        self.muro(e, z0, z1, st.muro, buchi)
        for t0, t1 in iv:
            (self.nastro if st.finestre == "nastro" else self.foro)(e, t0, t1, zf0, zf1, st)
        if st.marcapiano:
            h, sp, col = st.marcapiano
            self.pannello(col, e, rett(0.0, L, z0 - h / 2, z0 + h / 2), 0.0, sp)

    def porte_esterne(self, csip, e, near=0.7):
        """Le porte della pianta che danno fuori, su questo lato: intervalli lungo il lato."""
        a, c, u, n, L, _ = e
        out = []
        for d in self.geo.get(csip, {}).get("porte", []):
            if not d.get("esterna"):
                continue
            for p, q in ((d["cardine"], d["chiusa"]),):
                p, q = np.array(p), np.array(q)
                ds = [float(np.dot(r - np.array(a), np.array(n))) for r in (p, q)]
                if not all(abs(v) < near for v in ds):
                    continue
                ts = sorted(float(np.dot(r - np.array(a), np.array(u))) for r in (p, q))
                if ts[0] > 0.1 and ts[1] < L - 0.1 and ts[1] - ts[0] > 0.6:
                    out.append((ts[0] - 0.05, ts[1] + 0.05))
        return out

    # ---------------------------------------------------------- tetti

    def tetto_piano(self, poly, z, parapetto=0.9, colore=GUAINA, muro=None, copertina=COPERTINA, spessore=0.3):
        """Un tetto piano: il manto e il parapetto tutto intorno con la copertina."""
        for q in self.pezzi(poly):
            dentro = q.buffer(-spessore, join_style=2)
            for d in self.pezzi(dentro):
                self.E.prisma(self.S, colore, self.E.ring_ccw(d), z, z + 0.08)
            for r in self.pezzi(q.difference(dentro), 0.05):
                if parapetto > 0:
                    if muro:
                        self.S.solid(muro, trimesh.creation.extrude_polygon(r, parapetto).apply_translation([0, 0, z]))
                    self.S.solid(copertina, trimesh.creation.extrude_polygon(r, 0.06).apply_translation([0, 0, z + parapetto]))
            if muro and parapetto > 0:
                for e in self.E.edges(self.E.ring_ccw(q)):
                    self.pannello(muro, e, rett(0, e[4], z, z + parapetto), 0.0, 0.06)
        self.top = max(self.top, z + parapetto + 0.06)

    def impianto(self, x, y, dx, dy, z, h=1.6, colore=IMPIANTI, angolo=0.0):
        """Un blocco di impianti (UTA, torri evaporative) sul tetto, con la griglia sopra."""
        m = self.E.box_z(0, 0, dx, dy, z, z + h)
        m.apply_transform(trimesh.transformations.rotation_matrix(math.radians(angolo), [0, 0, 1]))
        m.apply_translation([x, y, 0])
        self.S.solid(colore, m)
        g = self.E.box_z(0, 0, dx * 0.85, dy * 0.85, z + h, z + h + 0.06)
        g.apply_transform(trimesh.transformations.rotation_matrix(math.radians(angolo), [0, 0, 1]))
        g.apply_translation([x, y, 0])
        self.S.solid("#6E7378", g)
        self.top = max(self.top, z + h + 0.06)

    def fotovoltaico(self, zona, z, angolo=0.0, file_=1.0, passo=1.6):
        """File di pannelli su un tetto piano, inclinati di 10°, una ogni passo."""
        c = zona.centroid
        r = affinity.rotate(zona, -angolo, origin=c)
        x0, y0, x1, y1 = r.bounds
        y = y0 + 0.3
        while y + file_ <= y1 - 0.3:
            seg = r.intersection(box(x0, y, x1, y + file_))
            for p in self.pezzi(seg, 0.8):
                px0, _, px1, _ = p.bounds
                m = self.E.box_z((px0 + px1) / 2, y + file_ / 2, px1 - px0, file_, z + 0.25, z + 0.3)
                m.apply_transform(trimesh.transformations.rotation_matrix(math.radians(10), [1, 0, 0], [(px0 + px1) / 2, y + file_ / 2, z + 0.3]))
                m.apply_transform(trimesh.transformations.rotation_matrix(math.radians(angolo), [0, 0, 1], [c.x, c.y, 0]))
                self.S.solid("kit_pv", m)
            y += passo

    def falde(self, rett_, z, pendenza=0.55, sporto=0.6, colore="kit_coppi", gronda="#E6E1D6", angolo=None, padiglione=True):
        """Un tetto a padiglione (o a capanna) in coppi sopra un rettangolo, anche ruotato:
        rett_ è un poligono di 4 lati. I tetti di più rettangoli che si toccano si
        compenetrano e fanno da soli i compluvi."""
        r = rett_.minimum_rotated_rectangle if not isinstance(rett_, tuple) else box(*rett_)
        pts = list(r.exterior.coords)[:4]
        # l'asse lungo
        l01 = math.dist(pts[0], pts[1])
        l12 = math.dist(pts[1], pts[2])
        if l12 > l01:
            pts = pts[1:] + pts[:1]
        A, B, C, D = [np.array(p, float) for p in pts]
        u = (B - A) / np.linalg.norm(B - A)
        v = (D - A) / np.linalg.norm(D - A)
        A, B, C, D = A - u * sporto - v * sporto, B + u * sporto - v * sporto, C + u * sporto + v * sporto, D - u * sporto + v * sporto
        w = np.linalg.norm(D - A)
        h = w / 2 * pendenza
        k = w / 2 if padiglione else 0.0
        r0 = (A + D) / 2 + u * k
        r1 = (B + C) / 2 - u * k
        P = lambda p, zz: (float(p[0]), float(p[1]), zz)
        top = z + h
        Sx = self.S
        c = (A + C) / 2

        def tri_or_quad(pts3, n):
            uvs = [(float(np.dot(np.array(p[:2]) - A, u)), float(np.dot(np.array(p[:2]) - A, v)) * 1.1 + (p[2] - z)) for p in pts3]
            (Sx.quad if len(pts3) == 4 else Sx.tri)(colore, pts3, (float(n[0]), float(n[1]), 1.0), uvs)

        tri_or_quad([P(A, z), P(B, z), P(r1, top), P(r0, top)], -v)
        tri_or_quad([P(C, z), P(D, z), P(r0, top), P(r1, top)], v)
        if padiglione:
            tri_or_quad([P(B, z), P(C, z), P(r1, top)], u)
            tri_or_quad([P(D, z), P(A, z), P(r0, top)], -u)
        else:
            for a_, b_, rr, n in ((B, C, r1, u), (D, A, r0, -u)):
                Sx.tri(gronda, [P(a_, z), P(b_, z), P(rr, top)], (float(n[0]), float(n[1]), 0.0))
        Sx.quad(gronda, [P(A, z - 0.02), P(B, z - 0.02), P(C, z - 0.02), P(D, z - 0.02)], (0, 0, -1))
        # il canale di gronda
        for a_, b_ in ((A, B), (B, C), (C, D), (D, A)):
            if not padiglione and ((a_ is B) or (a_ is D)):
                continue
            self.E.trave(Sx, "#8E8F8C", P(a_, z - 0.05), P(b_, z - 0.05), 0.12)
        self.top = max(self.top, top)
        return top

    def volta(self, rett_, z, freccia, colore="kit_lamiera", segmenti=12):
        """Una copertura a botte sopra un rettangolo (lungo l'asse lungo)."""
        r = rett_.minimum_rotated_rectangle
        pts = list(r.exterior.coords)[:4]
        if math.dist(pts[1], pts[2]) > math.dist(pts[0], pts[1]):
            pts = pts[1:] + pts[:1]
        A, B, C, D = [np.array(p, float) for p in pts]
        v = D - A
        prof = []
        for i in range(segmenti + 1):
            f = i / segmenti
            prof.append((f, z + freccia * 4 * f * (1 - f)))
        for (f0, z0), (f1, z1) in zip(prof, prof[1:]):
            q = [(*(A + v * f0), z0), (*(B + v * f0), z0), (*(B + v * f1), z1), (*(A + v * f1), z1)]
            q = [tuple(map(float, p)) for p in q]
            nrm = np.cross(np.array(q[1]) - np.array(q[0]), np.array(q[3]) - np.array(q[0]))
            if nrm[2] < 0:
                nrm = -nrm
            uvs = [(float(np.dot(np.array(p[:2]) - A, (B - A) / np.linalg.norm(B - A))), f * np.linalg.norm(v)) for p, f in zip(q, (f0, f0, f1, f1))]
            self.S.quad(colore, q, tuple(nrm), uvs)
        for a_, f_ in ((A, 0), (B, 0)):
            tri = [(*map(float, a_ + v * f), zz) for f, zz in prof]
            for i in range(1, len(tri) - 1):
                self.S.tri("#D8D6D0", [tri[0], tri[i], tri[i + 1]], (0, 0, 0.0) if False else tuple(map(float, np.append((A - B) if a_ is A else (B - A), 0))))
        self.top = max(self.top, z + freccia)

    # ---------------------------------------------------------- intorno

    def albero(self, x, y, r=2.2, h=None):
        h = h or r * 2.2
        self.S.solid(TRONCO, trimesh.creation.cylinder(radius=0.15, height=h * 0.55, sections=6).apply_translation([x, y, h * 0.27]))
        self.S.solid(CHIOMA, trimesh.creation.icosphere(subdivisions=1, radius=r).apply_translation([x, y, h * 0.55 + r * 0.7]))

    def fine(self):
        return self.S.meshes(), round(self.top, 2)


# ---------------------------------------------------------------- banchi

def completa_piante(geo, aule_info, salta=()):
    """Le file di banchi delle aule che le piante non disegnano, come per l'Edificio 2
    (`file_aula` di gusci/MIA0102.py): gradoni a 90 cm nelle aule fitte, tavoli altrove."""
    sys.path.insert(0, str(QUI))
    import MIA0102
    for csip, f in geo.items():
        aule = aule_info.get(csip, {})
        arredi = f.setdefault("linee", {}).setdefault("arredi", [])
        for v in f["vani"]:
            info = aule.get(v["csiv"])
            if not info or not info.get("posti") or v["csiv"] in salta:
                continue
            poly = unary_union([Polygon(r).buffer(0) for r in v["forma"]])
            if poly.geom_type != "Polygon":
                poly = max(poly.geoms, key=lambda g: g.area)
            poly = poly.simplify(0.05)
            if any(poly.contains(Point((s[0] + s[2]) / 2, (s[1] + s[3]) / 2)) for s in arredi):
                continue
            porte = [((d["cardine"][0] + d["chiusa"][0]) / 2, (d["cardine"][1] + d["chiusa"][1]) / 2)
                     for d in f.get("porte", [])]
            porte = [p for p in porte if poly.exterior.distance(Point(p)) < 0.6]
            try:
                arredi += MIA0102.file_aula(poly, info["posti"], porte)
            except (ZeroDivisionError, ValueError):
                pass
    return geo
