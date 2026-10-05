"""L'Edificio 2 (Bruno Finzi, MIA0102) in 3D, rifatto da foto aeree e fotografie.

Uno dei due corpi ai lati del Rettorato su Piazza Leonardo da Vinci: un palazzo eclettico a
corte. Dalla foto aerea (Esri World Imagery) e dalle foto della piazza:

- i due padiglioni d'angolo sulla piazza (nord e sud): ordine gigante di lesene su terra e
  primo, terra bugnato con finestre ad arco, primo con finestre ad arco e balconi,
  cornicione su mensole, balaustra con le sfere sui pilastrini e gli obelischi sugli spigoli
  verso la piazza; il portone ad arco sul lato corto con il balcone sopra;
- il fronte fra i padiglioni, più fitto (campate da 2,8 m come le finestre delle piante),
  con il tetto piano e gli impianti sopra;
- le ali nord e sud e le aule che sporgono nella corte, in ocra, con il tetto a padiglione
  in coppi; padiglione e ala sono un tetto solo, come nella foto aerea;
- le due torri scale e l'ala est su via Golgi, più alte di un piano, intonaco chiaro; sul
  tetto dell'ala est i campi di pannelli fotovoltaici sulle due falde.

Le fasce di `leonardo.json` (`parti`, `profilo`) dicono quale parte ha quali finestre,
rivestimento, cornicione e copertura; le altezze sono quelle vere, non le unità della
mappa, e i piani delle piante stanno alle stesse quote (`quote()`). Le finestre seguono le
finestre delle piante dove su una facciata sono in fila regolare, altrimenti la campata.

Si usa dall'esportatore: `guscio(b, E)` torna ({colore o texture: mesh}, quota del tetto),
dove E è il modulo esporta3d con le sue primitive.
"""
import math
import numpy as np
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union

CSIE = "MIA0102"
CORRENTE = None       # l'edificio in esportazione, per leggere le sue piante

# Quote vere (m, piazza a 0): zoccolo di pietra con le finestre del seminterrato, terra
# alto 5,6 m, piano nobile 5,4 m, secondo piano solo nell'ala est e nelle torri.
Z_TERRA, Z_PRIMO, Z_SECONDO, Z_TERZO = 1.6, 7.2, 12.6, 16.4
QUOTE = {"MIA010200S": -2.2, "MIA0102000": Z_TERRA, "MIA0102001": Z_PRIMO, "MIA0102002": Z_SECONDO}
CORNICE = 0.8          # altezza del cornicione
PELLE = 0.35           # spessore del muro di facciata: le finestre stanno in fondo
FALDA = 0.40           # pendenza dei tetti in coppi (circa 22°)

# Colori dalle foto (cielo coperto, corretti verso il chiaro delle foto al sole).
OCRA = "#D6C29A"
INTONACO = "#ECE4D0"
PIETRA = "#ABA79D"
STUCCO = "#EAE1CB"     # cornici, lesene, balaustre: un tono più chiaro del muro
STUCCO_CHIARO = "#F4EFE4"
VETRO = "#4C5A68"
INFISSO = "#EEE9DF"
LEGNO = "#4A3A2E"
FERRO = "#2F3236"
TERRAZZA = "#9C9A93"
IMPIANTI = "#C7CBD0"
LATTONERIA = "#8A8F96"

# La foto aerea corregge la mappa: l'ala est ha il tetto piano, chiaro, con un camminamento
# lungo il parapetto e tre campi di pannelli fotovoltaici (x0, y0, x1, y1 in metri, misurati
# sulla foto, che qui coincide con il contorno della mappa); non le falde in coppi.
TETTI_PIANI = {"est": {"tipo": "terrazza", "colore": "#CFC9BC", "fotovoltaico": [
    (-25.3, 98.3, -11.2, 111.7), (-21.1, 114.5, -11.0, 161.3), (-24.6, 164.4, -10.7, 172.3)]}}

TEXTURE = {   # metri coperti da una ripetizione
    "coppi": 0.8, "fotovoltaico": 1.0, "bugnato_ocra": 1.0, "bugnato_chiaro": 1.0}


def quote(b):
    return {c: QUOTE[c] for c in b.get("livelli", []) if c in QUOTE}


# ---------------------------------------------------------------- texture

def _texture(name):
    """(colore, normali) PIL: i coppi in file da 40 cm, il fotovoltaico a celle con la
    cornice d'alluminio, il bugnato (corsi da 50 cm, conci da 1 m sfalsati, giunti
    profondi)."""
    from PIL import Image
    rng = np.random.default_rng(2)
    if name == "coppi":
        size = 256                                    # 0,8 m: 4 canali da 20 cm, 2 file
        y, x = np.mgrid[0:size, 0:size] / size
        cx = (x * 4) % 1.0
        row = (y * 2) % 1.0
        height = np.sqrt(np.clip(1 - (2 * cx - 1) ** 2, 0, 1)) * (0.75 + 0.25 * row)
        k = (np.floor(x * 4) + 4 * np.floor(y * 2)).astype(int)
        tone = rng.normal(0, 0.06, 8)[k % 8]
        base = np.array([0.63, 0.35, 0.25])
        rgb = base[None, None] * (0.78 + 0.32 * height + tone)[..., None]
        rgb[row < 0.04] *= 0.6
        strength = 6.0
    elif name == "fotovoltaico":
        size = 256                                    # 1 m: un modulo da 6 x 6 celle
        y, x = np.mgrid[0:size, 0:size] / size
        cell = ((x * 6) % 1 < 0.06) | ((y * 6) % 1 < 0.06)
        frame = (x < 0.025) | (x > 0.975) | (y < 0.025) | (y > 0.975)
        rgb = np.zeros((size, size, 3)) + np.array([0.12, 0.16, 0.27])
        rgb[cell] = [0.20, 0.24, 0.34]
        rgb[frame] = [0.72, 0.74, 0.77]
        height = np.where(frame, 1.0, 0.0)
        strength = 2.0
    else:
        size = 256                                    # 1 m: 2 corsi da 50 cm
        tinta = np.array([0.80, 0.72, 0.56]) if name == "bugnato_ocra" else np.array([0.90, 0.87, 0.80])
        y, x = np.mgrid[0:size, 0:size] / size
        course = np.floor(y * 2)
        xs = (x + 0.5 * course) % 1.0
        dy = np.minimum((y * 2) % 1.0, 1 - (y * 2) % 1.0) * 0.5
        dx = np.minimum(xs, 1 - xs)
        d = np.minimum(dx, dy)
        height = np.clip(d / 0.03, 0, 1)              # giunti larghi 3 cm, spigoli smussati
        noise = rng.normal(0, 0.03, (size, size))
        rgb = tinta[None, None] * (0.72 + 0.28 * height + noise)[..., None]
        strength = 5.0
    gy, gx = np.gradient(height)
    nrm = np.dstack([-gx * strength, gy * strength, np.ones_like(height)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    to8 = lambda a: Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return to8(rgb), to8(nrm * 0.5 + 0.5)


def registra_texture(E):
    """Aggiunge le texture dell'Edificio 2 a quelle dell'esportatore."""
    for name, metri in TEXTURE.items():
        E.TEX.setdefault(name, metri)
        if name not in E._TEXTURES:
            E._TEXTURES[name] = _texture(name)


# ---------------------------------------------------------------- parti

class Parte:
    """Una parte rettangolare del palazzo, con i suoi piani dalle fasce della mappa."""

    def __init__(self, p, E):
        self.nome = p["nome"]
        self.raw = p
        self.pts = E.ring_ccw(Polygon(p["pianta"]).buffer(0))
        self.poly = Polygon(self.pts)
        prof = p.get("profilo", [])
        self.storeys = [x for x in prof if x["tipo"] == "palazzo"]
        self.cornice = next((x for x in prof if x["tipo"] == "cornicione"), {})
        self.balaustra = next((x for x in prof if x["tipo"] == "balaustra"), None)
        cop = [x for x in prof if x["tipo"] in ("coppi", "terrazza")]
        self.copertura = TETTI_PIANI.get(self.nome) or (cop[-1] if cop else {"tipo": "terrazza"})
        self.wall_top = Z_TERZO if len(self.storeys) >= 3 else Z_SECONDO
        self.top = self.wall_top + CORNICE
        riv = self.storeys[0].get("rivestimento", "ocra") if self.storeys else "ocra"
        self.muro = OCRA if riv == "ocra" else INTONACO
        self.bugnato = "bugnato_ocra" if riv == "ocra" else "bugnato_chiaro"
        self.ordine = any(s.get("ordine") for s in self.storeys)

    def fasce(self):
        """[(z0, z1, fascia)] dal terra in su."""
        zs = [Z_TERRA, Z_PRIMO, Z_SECONDO, Z_TERZO]
        return [(zs[i], zs[i + 1], s) for i, s in enumerate(self.storeys[:3])]


def esposti(parte, parti, e, z):
    """Gli intervalli (t0, t1) del lato e della parte che a quota z danno sull'esterno: non
    coperti da un'altra parte che sale almeno fin lì."""
    a, c, u, n, L, _ = e
    blk = [q.poly for q in parti if q is not parte and q.top > z + 0.3]
    seg = LineString([a, c])
    if blk:
        seg = seg.difference(unary_union(blk).buffer(0.08, join_style=2))
    out = []
    for g in getattr(seg, "geoms", [seg]):
        if g.is_empty or g.length < 0.05:
            continue
        p0, p1 = g.coords[0], g.coords[-1]
        t0 = (p0[0] - a[0]) * u[0] + (p0[1] - a[1]) * u[1]
        t1 = (p1[0] - a[0]) * u[0] + (p1[1] - a[1]) * u[1]
        out.append((min(t0, t1), max(t0, t1)))
    return sorted(out)


def finestre_pianta(E, b, e, csips):
    """Per un lato del guscio, i centri delle finestre della pianta di ogni piano."""
    a, c, u, n, L, _ = e
    edge = LineString([a, c])
    out = {}
    for csip in csips:
        cs = []
        for s in E.plan_floor(b, csip).get("linee", {}).get("finestre", []):
            seg = LineString([s[:2], s[2:4]])
            if seg.length < 0.4 or edge.distance(seg) > 0.9:
                continue
            if abs(((s[2] - s[0]) * u[0] + (s[3] - s[1]) * u[1]) / seg.length) < 0.9:
                continue
            cs.append(((s[0] + s[2]) / 2 - a[0]) * u[0] + ((s[1] + s[3]) / 2 - a[1]) * u[1])
        cs.sort()
        merged = []
        for t in cs:                                  # le linee doppie di una finestra
            if merged and t - merged[-1][-1] < 0.9:
                merged[-1].append(t)
            else:
                merged.append([t])
        out[csip] = [sum(m) / len(m) for m in merged]
    return out


def campate(E, b, e, t0, t1, campata, ordine=False):
    """I centri delle finestre su un tratto di facciata: quelli della pianta se un piano li
    ha in fila regolare (almeno tre, passo costante), altrimenti la campata della mappa.
    Gli stessi per tutti i piani, come in un palazzo. Con l'ordine gigante (i padiglioni)
    vale sempre la campata: le lesene la scandiscono."""
    best = []
    if ordine:
        return _regolari(t0, t1, campata)
    for cs in finestre_pianta(E, b, e, ["MIA0102001", "MIA0102000", "MIA0102002"]).values():
        cs = [t for t in cs if t0 + 0.8 < t < t1 - 0.8]
        if len(cs) < 3:
            continue
        d = np.diff(cs)
        if d.min() > 1.6 and d.std() < 0.25 * d.mean() and len(cs) > len(best):
            best = cs
    if best:
        step = float(np.median(np.diff(best)))
        # completa la fila verso i bordi del tratto, con lo stesso passo
        while best[0] - step > t0 + 0.9:
            best.insert(0, best[0] - step)
        while best[-1] + step < t1 - 0.9:
            best.append(best[-1] + step)
        return best, step
    return _regolari(t0, t1, campata)


def _regolari(t0, t1, campata):
    span = t1 - t0
    k = max(1, round(span / campata))
    step = span / k
    return [t0 + (i + 0.5) * step for i in range(k)], step


# ---------------------------------------------------------------- facciate

def arco(t, w, za, zb):
    """Un'apertura ad arco a tutto sesto: da za all'imposta, la chiave a zb."""
    r = w / 2
    return unary_union([box(t - r, za, t + r, zb - r), Point(t, zb - r).buffer(r, 6).intersection(
        box(t - r, zb - r, t + r, zb))])


def rett(t, w, za, zb):
    return box(t - w / 2, za, t + w / 2, zb)


class Facciata:
    """Disegna un tratto di facciata (lato e, da t0 a t1) di una parte."""

    def __init__(self, E, S, parte, e, t0, t1, door=None, cortile=False):
        self.E, self.S, self.p, self.e, self.t0, self.t1 = E, S, parte, e, t0, t1
        self.door = door
        self.cortile = cortile         # verso la corte: finestre senza cornici, niente dentelli

    def pan(self, key, shape, d0, d1):
        if shape is not None and not shape.is_empty:
            self.E.panel(self.S, key, self.e, shape, d0, d1)

    def box(self, key, ta, tb, za, zb, d0, d1):
        self.S.solid(key, self.E.box3(self.e[0], self.e[1], self.e[3], ta, tb, za, zb, d0, d1))

    def finestra(self, shape, w, za, zb, telaio=True):
        """Il vetro in fondo al muro, l'infisso a croce, la cornice intorno."""
        tc = (shape.bounds[0] + shape.bounds[2]) / 2
        self.pan(VETRO, shape, -PELLE, -PELLE + 0.04)
        bar = 0.06
        cross = unary_union([box(tc - bar / 2, za, tc + bar / 2, zb),
                             box(tc - w / 2, za + (zb - za) * 0.62, tc + w / 2, za + (zb - za) * 0.62 + bar)])
        self.pan(INFISSO, cross.intersection(shape), -PELLE + 0.04, -PELLE + 0.1)
        if telaio:
            self.pan(STUCCO, shape.buffer(0.16, 4, join_style=2).difference(shape), 0.0, 0.07)

    def disegna(self, campata_default):
        p, E, e = self.p, self.E, self.e
        t0, t1 = self.t0, self.t1
        span = t1 - t0
        fasce = p.fasce()
        top = p.wall_top
        porta = self.door
        cs, step = ([], 0)
        if span > 2.2:
            camp = fasce[0][2].get("campata", campata_default) if fasce else campata_default
            cs, step = campate(E, CORRENTE, e, t0, t1, camp, p.ordine)
            if porta is not None:
                cs = [c for c in cs if abs(c - porta) > 2.6]
        w = min(1.6, max(0.9, step * 0.48)) if cs else 0

        # lo zoccolo di pietra, un po' in fuori, con le finestrelle del seminterrato
        z_ = box(t0, 0, t1, Z_TERRA)
        holes = [rett(c, min(1.1, w), 0.3, 1.2) for c in cs]
        if porta is not None:
            holes.append(arco(porta, 3.2, 0, 5.4))
        self.pan(PIETRA, z_.difference(unary_union(holes)) if holes else z_, -PELLE, 0.1)
        for c in cs:
            h = rett(c, min(1.1, w), 0.3, 1.2)
            self.pan(VETRO, h, -PELLE, -PELLE + 0.04)
            for k in range(1, 5):                               # le inferriate
                x = c - min(1.1, w) / 2 + min(1.1, w) * k / 5
                self.pan(FERRO, box(x - 0.02, 0.3, x + 0.02, 1.2), -0.2, -0.16)
        self.box(STUCCO, t0, t1, Z_TERRA - 0.15, Z_TERRA + 0.1, 0, 0.18)       # la cimasa dello zoccolo

        for i, (za, zb, f) in enumerate(fasce):
            tipo = f.get("finestre", "rette")
            bug = f.get("bugnato")
            key = p.bugnato if bug else p.muro
            aperture = []
            if i == 0:
                sill, head = za + 1.2, zb - 1.0
            elif i == 1:
                sill, head = za + 0.8, zb - 1.0
            else:
                sill, head = za + 0.8, zb - 0.9
            for c in cs:
                if tipo == "balconi":
                    shape = arco(c, w, za + 0.15, head) if p.ordine else rett(c, w, za + 0.15, head)
                elif tipo == "archi":
                    shape = arco(c, w, sill, head)
                else:
                    shape = rett(c, w * 0.92, sill, head - 0.2)
                aperture.append((c, shape))
            if porta is not None and i == 1:              # la porta finestra sul balcone del portone
                aperture.append((porta, arco(porta, 1.7, za + 0.15, head)))
            muro = box(t0, za, t1, zb)
            fori = [s for _, s in aperture]
            if porta is not None and i == 0:
                fori.append(arco(porta, 3.2, 0, 5.4))
            self.pan(key, muro.difference(unary_union(fori)) if fori else muro, -PELLE, 0.0)
            for c, shape in aperture:
                b0 = shape.bounds
                self.finestra(shape, b0[2] - b0[0], b0[1], b0[3], not self.cortile)
                if tipo == "archi" or (tipo == "balconi" and p.ordine):
                    self.box(STUCCO_CHIARO, c - 0.18, c + 0.18, b0[3] - 0.45, b0[3] + 0.12, 0, 0.14)  # la chiave
                if tipo == "rette":
                    self.box(STUCCO, c - w * 0.46 - 0.25, c + w * 0.46 + 0.25, b0[3] + 0.14, b0[3] + 0.32, 0, 0.2)
                if tipo == "balconi":
                    self.balcone(c - w / 2 - 0.35, c + w / 2 + 0.35, za + 0.15, 0.75)
                else:
                    self.box(STUCCO, c - w / 2 - 0.2, c + w / 2 + 0.2, b0[1] - 0.12, b0[1] + 0.02, 0, 0.16)  # il davanzale
                    if i == 1 and tipo == "archi":           # la specchiatura sotto il davanzale
                        self.box(STUCCO, c - w / 2, c + w / 2, b0[1] - 0.95, b0[1] - 0.15, 0, 0.05)
                        self.box(STUCCO_CHIARO, c - w / 2 + 0.12, c + w / 2 - 0.12, b0[1] - 0.83, b0[1] - 0.27, 0, 0.08)
            if i < len(fasce) - 1:                      # la fascia marcapiano
                self.box(STUCCO, t0, t1, zb - 0.18, zb + 0.14, 0, 0.12)

        # lesene: l'ordine gigante dei padiglioni, altrove solo sugli spigoli
        if span > 0.6:
            if p.ordine and cs:
                xs = [t0 + 0.45] + [(a_ + b_) / 2 for a_, b_ in zip(cs, cs[1:])] + [t1 - 0.45]
                for x in xs:
                    if porta is not None and abs(x - porta) < 2.0:
                        continue
                    self.box(STUCCO, x - 0.42, x + 0.42, Z_TERRA, Z_SECONDO, 0, 0.22)
                    self.box(STUCCO, x - 0.52, x + 0.52, Z_TERRA, Z_TERRA + 0.5, 0, 0.3)      # la base
                    self.box(STUCCO_CHIARO, x - 0.55, x + 0.55, Z_SECONDO - 0.55, Z_SECONDO, 0, 0.32)  # il capitello
            else:
                for x in (t0 + 0.35, t1 - 0.35):
                    self.box(STUCCO, x - 0.35, x + 0.35, Z_TERRA, top, 0, 0.1)

        if porta is not None:
            self.portone(porta)

        # il cornicione: fascia, mensole o dentelli, gocciolatoio
        cor = p.cornice
        sp = cor.get("sporto", 0.6)
        self.box(STUCCO, t0, t1, top, top + 0.3, 0, 0.15)
        passo = 0.9 if cor.get("mensole") else 0.7
        k = int(span / passo)
        for j in range(k):
            x = t0 + (j + 0.5) * span / k
            if cor.get("mensole"):
                self.box(STUCCO_CHIARO, x - 0.12, x + 0.12, top + 0.25, top + 0.55, 0, sp * 0.85)
            elif cor.get("decoro") and not self.cortile:
                self.box(STUCCO_CHIARO, x - 0.08, x + 0.08, top + 0.3, top + 0.45, 0, sp * 0.55)

    def balaustrini(self, ta, tb, za, zb, d0, d1, passo):
        """Una fila di balaustrini (a sezione quadra) fra uno zoccolo e un corrimano di pietra."""
        self.box(STUCCO, ta, tb, za, za + 0.12, d0, d1)
        self.box(STUCCO, ta, tb, zb - 0.12, zb, d0 - 0.02, d1 + 0.02)
        k = max(1, int((tb - ta) / passo))
        dm = (d0 + d1) / 2
        r = min(0.07, (d1 - d0) * 0.4)
        for j in range(k):
            t = ta + (j + 0.5) * (tb - ta) / k
            self.box(STUCCO_CHIARO, t - r, t + r, za + 0.12, zb - 0.12, dm - r, dm + r)

    def balcone(self, ta, tb, z, prof):
        """Un balconcino: la lastra su due mensole e la balaustra."""
        self.box(STUCCO, ta, tb, z - 0.18, z, 0, prof)
        for x in (ta + 0.2, tb - 0.2):
            self.box(STUCCO, x - 0.1, x + 0.1, z - 0.6, z - 0.18, 0, prof * 0.8)
        self.balaustrini(ta + 0.05, tb - 0.05, z, z + 1.0, prof - 0.2, prof - 0.05, 0.2)
        for x in (ta + 0.05, tb - 0.05):                   # i fianchi
            self.box(STUCCO, x - 0.06, x + 0.06, z, z + 1.0, 0, prof)

    def portone(self, t):
        """Il portone ad arco dei padiglioni, alto quasi tutto il terra, con la cornice a
        conci, le ante di legno e il balcone grande sopra."""
        sh = arco(t, 3.2, 0, 5.4)
        self.pan(LEGNO, sh, -PELLE, -PELLE + 0.1)
        for x in (t - 0.05, t + 0.05):
            self.pan(FERRO, box(x - 0.02, 0, x + 0.02, 4.0), -PELLE + 0.1, -PELLE + 0.13)
        self.pan(STUCCO, sh.buffer(0.45, 4, join_style=2).difference(sh).intersection(box(t - 5, 0, t + 5, 6)), 0, 0.14)
        self.box(STUCCO_CHIARO, t - 0.3, t + 0.3, 4.95, 5.95, 0, 0.2)
        self.balcone(t - 3.0, t + 3.0, Z_PRIMO, 1.2)
        for x in (t - 2.4, t, t + 2.4):                    # le mensole grandi
            self.box(STUCCO_CHIARO, x - 0.18, x + 0.18, Z_PRIMO - 1.1, Z_PRIMO - 0.18, 0, 1.0)


# ---------------------------------------------------------------- coperture

def tetto_padiglione(E, S, x0, y0, x1, y1, z):
    """Un tetto a padiglione in coppi su un rettangolo, gronda a quota z: due falde a
    trapezio, due a triangolo; i coppi corrono lungo la pendenza."""
    lungo_x = (x1 - x0) >= (y1 - y0)
    swap = not lungo_x                                # ruota: si lavora con il lato lungo su x
    xs, ys = ((y0, y1), (x0, x1)) if swap else ((x0, x1), (y0, y1))
    X0, X1 = xs
    Y0, Y1 = ys
    half = (Y1 - Y0) / 2
    zr = z + half * FALDA
    ym = (Y0 + Y1) / 2
    r0, r1 = (X0 + half, ym, zr), (X1 - half, ym, zr)
    if r1[0] < r0[0]:
        r0 = r1 = ((X0 + X1) / 2, ym, zr)
    A, B, C, D = (X0, Y0, z), (X1, Y0, z), (X1, Y1, z), (X0, Y1, z)

    def W(p):
        return (p[1], p[0], p[2]) if swap else p

    def faccia(pts, down):
        """down: la direzione in pianta verso la gronda (unitaria)."""
        pts = [W(p) for p in pts]
        dn = W((down[0], down[1], 0))
        along = (-dn[1], dn[0])
        cosf = 1 / math.sqrt(1 + FALDA ** 2)
        uvs = [((p[0] * along[0] + p[1] * along[1]),
                -(p[0] * dn[0] + p[1] * dn[1]) / cosf) for p in pts]
        normal = (dn[0] * FALDA, dn[1] * FALDA, 1.0)
        if len(pts) == 3:
            S.tri("coppi", pts, normal, uvs)
        else:
            S.quad("coppi", pts, normal, uvs)
        return pts

    faccia([A, B, r1, r0], (0, -1))
    faccia([C, D, r0, r1], (0, 1))
    faccia([B, C, r1], (1, 0))
    faccia([D, A, r0], (-1, 0))
    # il sottogronda e il canale
    base = [W(p) for p in (A, B, C, D)]
    S.quad(STUCCO, base, (0, 0, -1))
    for p, q in zip(base, base[1:] + base[:1]):
        E.trave(S, LATTONERIA, (p[0], p[1], z - 0.05), (q[0], q[1], z - 0.05), 0.16)
    E.trave(S, "#9E4E31", W(r0), W(r1), 0.22)              # il colmo
    for c in (A, B, C, D):
        E.trave(S, "#9E4E31", W(c), W(r0 if c in (A, D) else r1), 0.18)   # i displuvi
    return zr


def unisci_rettangoli(rs):
    """Unisce i rettangoli (x0, y0, x1, y1, z) affiancati con la stessa gronda che insieme
    fanno ancora un rettangolo: padiglione e ala sotto un tetto solo."""
    rs = list(rs)
    changed = True
    while changed:
        changed = False
        for i in range(len(rs)):
            for j in range(i + 1, len(rs)):
                a, b_ = rs[i], rs[j]
                if abs(a[4] - b_[4]) > 0.01:
                    continue
                u = box(*a[:4]).union(box(*b_[:4]))
                if abs(u.area - u.envelope.area) < 0.5 and u.geom_type == "Polygon":
                    rs[i] = (*u.bounds, a[4], a[5] + b_[5])
                    del rs[j]
                    changed = True
                    break
            if changed:
                break
    return rs


# ---------------------------------------------------------------- il guscio

def guscio(b, E):
    registra_texture(E)
    global CORRENTE
    CORRENTE = b
    S = E.Solidi()
    parti = [Parte(p, E) for p in b["parti"]]
    corte = unary_union([Polygon(c).buffer(0) for c in b.get("cortili", [])] or [Polygon()])
    tetti = []
    for p in parti:
        # il nucleo: il volume pieno dietro le facciate
        E.prisma(S, p.muro, E.ring_ccw(p.poly.buffer(-PELLE + 0.02, join_style=2)), 0, p.wall_top)
        porta = (p.raw.get("portoni") or {}).get("punto")
        for e in E.edges(p.pts):
            dp = None
            if porta and LineString([e[0], e[1]]).distance(Point(porta)) < 0.5:
                dp = (porta[0] - e[0][0]) * e[2][0] + (porta[1] - e[0][1]) * e[2][1]
            for t0, t1 in esposti(p, parti, e, Z_TERRA + 0.5):
                d = dp if dp is not None and t0 + 2 < dp < t1 - 2 else None
                mid = ((e[0][0] + e[1][0]) / 2 + e[3][0] * 2, (e[0][1] + e[1][1]) / 2 + e[3][1] * 2)
                Facciata(E, S, p, e, t0, t1, d, corte.contains(Point(mid))).disegna(4.2)
            # sopra le parti basse vicine: il piano in più dell'ala est e delle torri
            if p.wall_top > Z_SECONDO + 0.1:
                low = esposti(p, parti, e, Z_SECONDO + CORNICE + 0.5)
                done = esposti(p, parti, e, Z_TERRA + 0.5)
                for t0, t1 in low:
                    rest = LineString([(t0, 0), (t1, 0)]).difference(
                        unary_union([LineString([(a_, 0), (b_, 0)]) for a_, b_ in done]).buffer(0.01)) if done else None
                    for g in ([] if rest is None else getattr(rest, "geoms", [rest])):
                        if g.is_empty or g.length < 0.3:
                            continue
                        ta, tb = sorted((g.coords[0][0], g.coords[-1][0]))
                        f = Facciata(E, S, p, e, ta, tb)
                        f.parte_alta()
        # il cornicione tutto intorno, che corre anche sugli spigoli
        sp = p.cornice.get("sporto", 0.6)
        inner = p.poly.buffer(-0.4, join_style=2)
        for d, z0, z1 in ((sp, p.wall_top + 0.5, p.top), (sp * 0.5, p.wall_top + 0.3, p.wall_top + 0.5)):
            anello = p.poly.buffer(d, join_style=2).difference(inner)
            S.solid(STUCCO, E.trimesh.creation.extrude_polygon(anello, z1 - z0).apply_translation([0, 0, z0]))
        if p.copertura["tipo"] == "coppi":
            x0, y0, x1, y1 = p.poly.bounds
            tetti.append((x0, y0, x1, y1, p.top, [p]))
        else:
            terrazza(E, S, p)
        if p.balaustra:
            punte = []
            for x, y, *_ in p.raw.get("pinnacoli", []):
                # sul pilastrino d'angolo della balaustra più vicino
                cx, cy = min(p.pts, key=lambda q: math.dist(q, (x, y)))
                ox, oy = (x - cx), (y - cy)
                k = math.hypot(ox, oy) or 1
                punte.append((cx - ox / k * 0.31, cy - oy / k * 0.31))
            balaustra(E, S, p, parti, punte)
            for x, y in punte:
                obelisco(E, S, x, y, p.top + 1.2)
    top = max(p.top for p in parti)
    for x0, y0, x1, y1, z, ps in unisci_rettangoli(tetti):
        if any(q.balaustra for q in ps):
            # dietro la balaustra la gronda non sporge: il tetto parte da dentro il muro
            zr = tetto_padiglione(E, S, x0 + 0.3, y0 + 0.3, x1 - 0.3, y1 - 0.3, z + 0.25)
        else:
            sp = 0.45
            zr = tetto_padiglione(E, S, x0 - sp, y0 - sp, x1 + sp, y1 + sp, z)
        top = max(top, zr)
    return S.meshes(), top


def _parte_alta(self):
    """Il piano in più dell'ala est e delle torri dove guarda sopra i tetti delle ali: muro,
    finestre rettangolari, lesene sugli spigoli; la fascia del cornicione delle ali sotto."""
    p, E, e = self.p, self.E, self.e
    t0, t1 = self.t0, self.t1
    za, zb = Z_SECONDO + CORNICE, p.wall_top
    muro = box(t0, Z_SECONDO, t1, zb)
    cs = []
    if t1 - t0 > 2.2:
        cs, step = campate(E, CORRENTE, e, t0, t1, 3.0)
    w = min(1.3, max(0.8, (step if cs else 3) * 0.45))
    fori = [rett(c, w, za + 0.5, zb - 0.9) for c in cs]
    self.pan(p.muro, muro.difference(unary_union(fori)) if fori else muro, -PELLE, 0.0)
    for c, sh in zip(cs, fori):
        b0 = sh.bounds
        self.finestra(sh, w, b0[1], b0[3])
        self.box(STUCCO, c - w / 2 - 0.2, c + w / 2 + 0.2, b0[1] - 0.12, b0[1] + 0.02, 0, 0.16)
    for x in (t0 + 0.35, t1 - 0.35):
        self.box(STUCCO, x - 0.35, x + 0.35, Z_SECONDO, zb, 0, 0.1)
    self.box(STUCCO, t0, t1, zb, zb + 0.3, 0, 0.15)


Facciata.parte_alta = _parte_alta


def terrazza(E, S, p):
    """Il tetto piano del fronte, delle torri e dell'ala est: il pavimento, l'attico pieno
    che fa da parapetto, gli impianti della mappa, i campi fotovoltaici della foto aerea."""
    inner = p.poly.buffer(-0.35, join_style=2)
    E.prisma(S, p.copertura.get("colore", TERRAZZA), E.ring_ccw(inner), p.top - 0.15, p.top - 0.05)
    for x0, y0, x1, y1 in p.copertura.get("fotovoltaico", []):
        campo = box(x0, y0, x1, y1).intersection(inner.buffer(-0.6, join_style=2))
        if not campo.is_empty:
            E.prisma(S, "fotovoltaico", E.ring_ccw(campo), p.top - 0.05, p.top + 0.3)
    att = p.poly.buffer(0.05, join_style=2).difference(inner)
    for g in getattr(att, "geoms", [att]):
        S.solid(STUCCO, E.trimesh.creation.extrude_polygon(g, 0.75).apply_translation([0, 0, p.top]))
    for x, y, w, d, h in p.copertura.get("impianti", []):
        hh = 1.2 + h * 0.15
        E.prisma(S, IMPIANTI, [(x, y), (x + w, y), (x + w, y + d), (x, y + d)], p.top - 0.05, p.top + hh)
        E.prisma(S, LATTONERIA, [(x + 0.4, y + 0.4), (x + w - 0.4, y + 0.4), (x + w - 0.4, y + d - 0.4), (x + 0.4, y + d - 0.4)],
                 p.top + hh, p.top + hh + 0.12)


def balaustra(E, S, p, parti, punte=()):
    """La balaustra dei padiglioni sul cornicione: zoccolo, balaustrini, cimasa, i
    pilastrini a ogni campata con la sfera di pietra sopra."""
    z = p.top
    h = 1.1
    passo = p.balaustra.get("passo_sfere", 3.8)
    for e in E.edges(p.pts):
        for t0, t1 in esposti(p, parti, e, Z_PRIMO):
            f = Facciata(E, S, p, e, t0, t1)
            f.balaustrini(t0, t1, z, z + h, 0.05, 0.4, 0.22)
            k = max(1, round((t1 - t0) / passo))
            for j in range(k + 1):
                t = t0 + (t1 - t0) * j / k
                ta, tb = max(t0, t - 0.28), min(t1, t + 0.28)
                f.box(STUCCO, ta, tb, z, z + h + 0.1, 0.0, 0.45)
                a, _, u, n, _, _ = e
                x, y = a[0] + u[0] * (ta + tb) / 2 + n[0] * 0.22, a[1] + u[1] * (ta + tb) / 2 + n[1] * 0.22
                if any(math.dist((x, y), q) < 1.0 for q in punte):
                    continue
                ped = E.trimesh.creation.cylinder(radius=0.16, height=0.18, sections=12)
                ped.apply_translation([x, y, z + h + 0.19])
                S.solid(STUCCO_CHIARO, ped)
                ball = E.trimesh.creation.icosphere(subdivisions=1, radius=0.26)
                ball.apply_translation([x, y, z + h + 0.52])
                S.solid(STUCCO_CHIARO, ball)


def obelisco(E, S, x, y, z):
    """Un obelisco di pietra su piedistallo, sugli spigoli dei padiglioni verso la piazza."""
    E.prisma(S, STUCCO, [(x - 0.5, y - 0.5), (x + 0.5, y - 0.5), (x + 0.5, y + 0.5), (x - 0.5, y + 0.5)], z, z + 0.9)
    E.prisma(S, STUCCO_CHIARO, [(x - 0.58, y - 0.58), (x + 0.58, y - 0.58), (x + 0.58, y + 0.58), (x - 0.58, y + 0.58)], z + 0.9, z + 1.05)
    a, h = 0.32, 3.4
    bot = [(x - a, y - a, z + 1.05), (x + a, y - a, z + 1.05), (x + a, y + a, z + 1.05), (x - a, y + a, z + 1.05)]
    k = 0.11
    top = [(x - k, y - k, z + 1.05 + h), (x + k, y - k, z + 1.05 + h), (x + k, y + k, z + 1.05 + h), (x - k, y + k, z + 1.05 + h)]
    S.solid(STUCCO_CHIARO, E.hexa(bot, top))
    tip = E.trimesh.creation.cone(radius=k * 1.42, height=0.35, sections=4)
    tip.apply_transform(E.trimesh.transformations.rotation_matrix(math.pi / 4, [0, 0, 1]))
    tip.apply_translation([x, y, z + 1.05 + h])
    S.solid(STUCCO_CHIARO, tip)


# ---------------------------------------------------------------- arredi delle aule

DENSE = 0.75           # posti per m² oltre i quali l'aula è a gradoni


def _asse_aula(poly, porte):
    """(asse dal palco verso il fondo, perpendicolare) di un'aula. Le aule a ventaglio (2.0.1,
    2.0.2) hanno il palco dal lato stretto; le rettangolari guardano il lato corto lontano
    dalle porte, che stanno in fondo."""
    r = poly.minimum_rotated_rectangle
    c = list(r.exterior.coords)[:4]
    sides = [np.array(c[1]) - np.array(c[0]), np.array(c[2]) - np.array(c[1])]
    best = None
    for d in sides:
        a = d / np.linalg.norm(d)
        u = np.array([-a[1], a[0]])
        s = [float(np.dot(p, a)) for p in poly.exterior.coords]
        s0, s1 = min(s), max(s)

        def larghezza(sv):
            line = LineString([tuple(a * sv + u * -500), tuple(a * sv + u * 500)]).intersection(poly)
            return line.length
        w0, w1 = larghezza(s0 + 0.12 * (s1 - s0)), larghezza(s0 + 0.88 * (s1 - s0))
        asym = abs(w0 - w1) / max(w0, w1)
        if best is None or asym > best[0]:
            best = (asym, a, u, w0, w1, s1 - s0)
    asym, a, u, w0, w1, depth = best
    if asym > 0.12:
        a = a if w0 < w1 else -a                      # dal lato stretto verso il largo
    else:
        # rettangolo: le file parallele al lato corto, il palco lontano dalle porte
        long_ = max(sides, key=lambda d: np.linalg.norm(d))
        a = long_ / np.linalg.norm(long_)
        mid = np.array(poly.centroid.coords[0])
        if porte:
            pd = np.mean([np.dot(np.array(p) - mid, a) for p in porte])
            a = -a if pd < 0 else a                    # le porte in fondo
    u = np.array([-a[1], a[0]])
    return a, u


def file_aula(poly, posti, porte):
    """Le file di banchi di un'aula che la pianta non disegna, come linee della pianta:
    gradoni a 90 cm nelle aule fitte, tavoli da 50 cm a 1,25 m nelle altre; corridoi ai
    lati e uno in mezzo nelle aule larghe; tante file quante servono per i posti."""
    a, u = _asse_aula(poly, porte)
    fitta = posti / poly.area > DENSE
    s = [float(np.dot(p, a)) for p in poly.exterior.coords]
    s0, s1 = min(s), max(s)
    passo = 0.9 if fitta else 1.25
    davanti = 3.0 if fitta else 2.4
    dentro = poly.buffer(-0.6, join_style=2)      # le file si allungano di 70 cm, fino ai muri
    segs, seats, k = [], 0, 0
    sv = s0 + davanti
    while sv < s1 - 0.8 - (0.5 if not fitta else 0) and (seats < posti * 1.02 or k < 3):
        line = LineString([tuple(a * sv + u * -500), tuple(a * sv + u * 500)]).intersection(dentro)
        pieces = [g for g in getattr(line, "geoms", [line]) if not g.is_empty and g.length > 1.2]
        row = []
        for g in pieces:
            p0, p1 = np.array(g.coords[0]), np.array(g.coords[-1])
            if g.length > 11:                         # il corridoio centrale
                m = (p0 + p1) / 2
                d = (p1 - p0) / g.length
                row += [(p0, m - d * 0.6), (m + d * 0.6, p1)]
            else:
                row.append((p0, p1))
        for p0, p1 in row:
            seats += int(np.linalg.norm(p1 - p0) / 0.55)
            segs.append([*map(float, p0), *map(float, p1)])
            if not fitta:                             # il bordo dietro del tavolo
                q0, q1 = p0 + a * 0.5, p1 + a * 0.5
                segs.append([*map(float, q0), *map(float, q1)])
        sv += passo
        k += 1
    return [[round(v, 2) for v in sg] for sg in segs]


def completa_piante(geo, aule_info):
    """Le piante dell'Edificio 2 non disegnano i banchi (`linee.arredi` è vuota): li
    ricava per ogni aula dalla forma, dalle porte e dai posti, così le aule hanno file,
    cattedra e interno come quelle del Trifoglio. L'EDUCAFE resta com'è."""
    for csip, f in geo.items():
        aule = aule_info.get(csip, {})
        lin = f.setdefault("linee", {})
        arredi = lin.setdefault("arredi", [])
        for v in f["vani"]:
            info = aule.get(v["csiv"])
            if not info or not info.get("posti") or "CAFE" in (info.get("sigla") or "").upper():
                continue
            poly = unary_union([Polygon(r).buffer(0) for r in v["forma"]])
            if poly.geom_type != "Polygon":
                poly = max(poly.geoms, key=lambda g: g.area)
            if any(poly.contains(Point((s[0] + s[2]) / 2, (s[1] + s[3]) / 2)) for s in arredi):
                continue
            porte = [((d["cardine"][0] + d["chiusa"][0]) / 2, (d["cardine"][1] + d["chiusa"][1]) / 2)
                     for d in f.get("porte", [])]
            porte = [p for p in porte if poly.exterior.distance(Point(p)) < 0.6]
            arredi += file_aula(poly, info["posti"], porte)
