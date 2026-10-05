#!/usr/bin/env python3
"""PROTOTIPO — esporta il campus in 3D (USDZ) dagli stessi dati di build-mappa.py.

    python3 esporta3d.py <cartella design/mappa> <cartella di uscita> --edifici=MIA0203 [--glb]

Legge leonardo.json e piante/*.json e scrive:
  campus.usdz      terreno, alberi e volumi di tutti gli edifici (vista campus)
  <csie>.usdz      i piani di un edificio: soletta, muri tagliati, locali per csiv
  <csie>.json      piani, quote e aule di quell'edificio, per l'interfaccia
  con --glb, anche campus.glb e <csie>.glb per un visore web

Assi: X = est, Y = su, Z = sud (metri, frame del campus). I nodi portano i codici
Politecnico, così l'app trova un'aula per csiv: <csie>/Piani/<csip>/<csip>_Locali/<csiv>.

Dipendenze: shapely, trimesh, mapbox_earcut, numpy, usd-core.
"""
import argparse, json, math, pathlib
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString
from shapely.ops import unary_union

ARGS = argparse.ArgumentParser()
ARGS.add_argument("mappa", type=pathlib.Path)
ARGS.add_argument("uscita", type=pathlib.Path)
ARGS.add_argument("--edifici", default="MIA0203")
ARGS.add_argument("--glb", action="store_true")
ARGS = ARGS.parse_args()
SRC, OUT = ARGS.mappa, ARGS.uscita
OUT.mkdir(parents=True, exist_ok=True)

PIANO = 4.0          # m per piano
SOLETTA = 0.3
MURO = 1.5           # muri tagliati ad altezza "casa delle bambole"
H_UNIT = PIANO / 18.0  # le h dei profili sono unità iso (ISO_FLOOR = 18 per piano)

COL = {
    "terreno": "#EEF0EA", "verde": "#D5E8CC", "strada": "#FFFFFF", "percorso": "#F4F7FA",
    "chioma": "#A9CF95", "tronco": "#8A6A48",
    "edificio": "#E9EBEF", "tetto": "#FFFFFF",
    "soletta": "#D4D8DF", "muri": "#AEB4BE",
    "locale": "#FFFFFF", "aula": "#E3ECF5", "scale": "#E6E8EC", "ascensore": "#C9CED6",
    "tecnico": "#ECEDEF", "wc": "#E8EEF2",
}
CLADDING = {"ceramica": "#E6E0D4", "mattone": "#ECE7DE", "fessura": "#4D5D72", "bianco": "#F6F7F9",
            "cemento": "#DCD8D0", "mosaico": "#6B6E75", "stucco": "#E4DFD3", "pietra": "#B4B2AA",
            "intonaco": "#ECE7DC", "grigio": "#CDCFD0", "ocra": "#DDCCA6"}

# Z-up (shapely/trimesh) → Y-up, Z sud. Scambio y/z: determinante -1, quindi si girano le facce.
YUP = np.array([[1, 0, 0, 0], [0, 0, 1, 0], [0, 1, 0, 0], [0, 0, 0, 1]], float)


def rgba(hex_):
    h = hex_.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)] + [255]


def linear(hex_):
    """glTF e UsdPreviewSurface vogliono colori lineari: i #hex della palette sono sRGB."""
    f = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return [f(c / 255) for c in rgba(hex_)[:3]]


def colour(mesh, hex_):
    mesh.visual = trimesh.visual.TextureVisuals(
        material=trimesh.visual.material.PBRMaterial(baseColorFactor=linear(hex_) + [1.0], metallicFactor=0.0,
                                                    roughnessFactor=0.9, name=hex_.lstrip("#")))
    mesh.metadata["colore"] = hex_
    return mesh


def clean(g):
    g = g.simplify(0.05).buffer(0)
    if g.is_empty:
        return []
    return [p for p in getattr(g, "geoms", [g]) if p.geom_type == "Polygon" and p.area > 0.05]


def slab(geom, z0, z1, hex_):
    parts = []
    for p in clean(geom):
        m = trimesh.creation.extrude_polygon(p, z1 - z0, engine="earcut")
        m.apply_translation([0, 0, z0])
        parts.append(m)
    if not parts:
        return None
    m = trimesh.util.concatenate(parts)
    m.apply_transform(YUP)
    m.invert() if m.volume < 0 else None
    return colour(m, hex_)


class Scena:
    def __init__(self, root):
        self.s = trimesh.Scene()
        self.s.graph.update(frame_from=self.s.graph.base_frame, frame_to=root)
        self.nodes = {root}

    def gruppo(self, name, parent):
        if name not in self.nodes:
            self.s.graph.update(frame_from=parent, frame_to=name)
            self.nodes.add(name)
        return name

    def mesh(self, name, parent, m):
        if m is not None:
            self.s.add_geometry(m, node_name=name, geom_name=name, parent_node_name=parent)


def ring(pts):
    return Polygon([tuple(p) for p in pts])


# ---------------------------------------------------------------- guscio

# Il Trifoglio come nelle foto del restauro (Coprat, TeamWork Italy), ad altezze reali.
# Il seminterrato è a quota piazza: nella pianta ha 21 porte verso l'esterno, il terra 5.
BASE_H = 3.5         # il seminterrato: lo zoccolo chiaro di cemento grezzo
MOSAICO_H = 9.0      # terra e primo, nel volume in mosaico delle aule ad anfiteatro
RIENTRO = 0.25       # di quanto lo zoccolo sta sotto il mosaico
RAMPA = BASE_H       # le rampe salgono al terra: nelle piante l'ingresso è al pianerottolo
SPORTO = 1.8         # la lastra del tetto oltre il mosaico
ALA = 1.1            # quanto salgono le punte delle ali del tetto
GLASS, GLASS_DARK, FRAME_GREY, WHITE = "#8FA6BA", "#5C6E80", "#80868E", "#F4F5F7"
BLOCK, METAL, ROOF, PLANT = "#D3DEE7", "#8E949B", "#F2F3F4", "#E3E6EB"
PALE, DOOR, ENTRY, BASE = "#E9E6E0", "#2D3B4F", "#2B3644", "#C9CED6"
TEX = {"mosaico": 1.0, "cemento": 1.5}   # metri coperti da una ripetizione della texture


class Solidi:
    """Mesh raccolte per colore o per texture, con le facce girate verso dove guardano."""

    def __init__(self):
        self.v, self.f, self.uv = {}, {}, {}

    def tri(self, key, pts, want, uvs=None):
        p = np.array(pts, float)
        if np.dot(np.cross(p[1] - p[0], p[2] - p[0]), want) < 0:
            p, uvs = p[[0, 2, 1]], ([uvs[0], uvs[2], uvs[1]] if uvs else None)
        v, f = self.v.setdefault(key, []), self.f.setdefault(key, [])
        f.append([len(v), len(v) + 1, len(v) + 2])
        v.extend(p.tolist())
        self.uv.setdefault(key, []).extend(uvs or [(0, 0)] * 3)

    def quad(self, key, pts, want, uvs=None):
        self.tri(key, pts[:3], want, uvs[:3] if uvs else None)
        self.tri(key, [pts[0], pts[2], pts[3]], want, [uvs[0], uvs[2], uvs[3]] if uvs else None)

    def solid(self, key, m):
        """Una mesh trimesh già chiusa e girata bene. Se ha una texture, la proietta faccia
        per faccia: dall'alto sulle facce orizzontali, di lato sulle altre."""
        for face in m.faces:
            p = m.vertices[face]
            n = np.cross(p[1] - p[0], p[2] - p[0])
            uvs = None
            if key in TEX:
                k = np.linalg.norm(n) or 1
                if abs(n[2]) / k > 0.7:
                    uvs = [(q[0], q[1]) for q in p]
                else:
                    h = np.array([-n[1], n[0], 0]) / (np.linalg.norm(n[:2]) or 1)
                    uvs = [(float(np.dot(q, h)), q[2]) for q in p]
            self.tri(key, p, n, uvs)

    def meshes(self):
        out = {}
        for key, v in self.v.items():
            m = trimesh.Trimesh(np.array(v), np.array(self.f[key]), process=False)
            m.apply_transform(YUP)          # trimesh gira da sé le facce di una riflessione
            if key in TEX:
                uv = np.array(self.uv[key]) / TEX[key]
                m.visual = trimesh.visual.TextureVisuals(uv=uv, material=trimesh.visual.material.PBRMaterial(
                    baseColorTexture=texture(key)[0], normalTexture=texture(key)[1],
                    metallicFactor=0.0, roughnessFactor=0.9, name=key))
                m.metadata.update(textura=key, uv=uv, colore="#FFFFFF")
            else:
                colour(m, key)
            out[key] = m
        return out


_TEXTURES = {}


def texture(name):
    """(colore, normali) come immagini PIL, generate: il mosaico a punta di diamante di Ponti,
    tessere da 5 cm grigio scuro, e il cemento bocciardato del basamento."""
    if name in _TEXTURES:
        return _TEXTURES[name]
    from PIL import Image, ImageFilter
    rng = np.random.default_rng(13)
    if name == "mosaico":
        n, px = 20, 26                       # 20 tessere da 5 cm per metro
        size = n * px
        y, x = np.mgrid[0:size, 0:size]
        fx, fy = (x % px) / px - 0.5, (y % px) / px - 0.5
        height = 1 - 2 * np.maximum(np.abs(fx), np.abs(fy))          # una piramide per tessera
        grout = (np.abs(fx) > 0.46) | (np.abs(fy) > 0.46)
        tone = rng.normal(0, 0.07, (n, n))[y // px, x // px]
        base = np.array([0.37, 0.38, 0.41])
        shade = 1 + tone + 0.18 * (-np.sign(fx) * (np.abs(fx) >= np.abs(fy)) - np.sign(fy) * (np.abs(fy) > np.abs(fx))) * 0.5
        rgb = base[None, None] * shade[..., None]
        rgb[grout] = [0.55, 0.55, 0.55]
        height[grout] = 0
        strength = 3.0
    else:
        size = 256
        noise = Image.fromarray((rng.random((size, size)) * 255).astype(np.uint8))
        fine = np.asarray(noise.filter(ImageFilter.GaussianBlur(0.8)), float) / 255
        coarse = np.asarray(noise.filter(ImageFilter.GaussianBlur(4)), float) / 255
        height = fine * 0.7 + coarse * 0.3
        rgb = np.array([0.80, 0.79, 0.76])[None, None] * (0.9 + 0.2 * height)[..., None]
        strength = 6.0
    gy, gx = np.gradient(height)
    nrm = np.dstack([-gx * strength, gy * strength, np.ones_like(height)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    to8 = lambda a: Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    _TEXTURES[name] = (to8(rgb), to8(nrm * 0.5 + 0.5))
    return _TEXTURES[name]


def ring_ccw(poly):
    pts = list(poly.exterior.coords)[:-1]
    return pts if Polygon(pts).exterior.is_ccw else pts[::-1]


def offset_ring(pts, d):
    """Ogni vertice spostato di d verso l'esterno lungo la bisettrice: stesso numero di punti,
    così due anelli si collegano lato per lato. pts in senso antiorario."""
    out = []
    for i, p in enumerate(pts):
        a, c = pts[i - 1], pts[(i + 1) % len(pts)]
        n1 = normal_out(a, p)
        n2 = normal_out(p, c)
        bis = np.array(n1) + np.array(n2)
        k = np.linalg.norm(bis)
        bis = bis / k if k > 1e-6 else np.array(n1)
        scale = min(3.0, 1 / max(0.3, np.dot(bis, n1)))
        out.append((p[0] + bis[0] * d * scale, p[1] + bis[1] * d * scale))
    return out


def normal_out(a, c):
    """La normale verso l'esterno del lato a→c di un anello antiorario."""
    L = math.dist(a, c) or 1
    return ((c[1] - a[1]) / L, -(c[0] - a[0]) / L)


def edges(pts):
    """(a, c, u, n, lunghezza, t di partenza lungo il perimetro) per ogni lato."""
    out, t = [], 0.0
    for a, c in zip(pts, pts[1:] + pts[:1]):
        L = math.dist(a, c)
        if L < 0.3:
            t += L
            continue
        out.append((a, c, ((c[0] - a[0]) / L, (c[1] - a[1]) / L), normal_out(a, c), L, t))
        t += L
    return out


def on_face(e, t, d, z):
    a, _, u, n, _, _ = e
    return (a[0] + u[0] * t + n[0] * d, a[1] + u[1] * t + n[1] * d, z)


def panel(S, key, e, shape, d0, d1):
    """Un poligono (t, z) sulla faccia, estruso da d0 a d1 verso l'esterno."""
    for p in clean(shape):
        m = trimesh.creation.extrude_polygon(p, d1 - d0)
        _, _, u, n, _, _ = e
        a = e[0]
        M = np.array([[u[0], 0, n[0], a[0] + n[0] * d0], [u[1], 0, n[1], a[1] + n[1] * d0],
                      [0, 1, 0, 0], [0, 0, 0, 1]], float)
        m.apply_transform(M)
        m.invert() if m.volume < 0 else None
        S.solid(key, m)


def window(S, e, t0, t1, z0, z1):
    """Una finestra di Ponti: un esagono allungato a punte smussate, telaio grigio, montanti."""
    k = min(0.3, (z1 - z0) * 0.3)
    zc = (z0 + z1) / 2
    hexa_ = Polygon([(t0, zc), (t0 + k, z0), (t1 - k, z0), (t1, zc), (t1 - k, z1), (t0 + k, z1)])
    panel(S, FRAME_GREY, e, hexa_.buffer(0.09, join_style=2).difference(hexa_), 0.0, 0.1)
    panel(S, GLASS, e, hexa_, 0.0, 0.03)
    bars = max(1, round((t1 - t0) / 0.8))
    for i in range(1, bars):
        t = t0 + (t1 - t0) * i / bars
        panel(S, FRAME_GREY, e, Polygon([(t - 0.03, z0), (t + 0.03, z0), (t + 0.03, z1), (t - 0.03, z1)]).intersection(hexa_), 0.0, 0.07)


def glass_blocks(S, e, t0, t1, z0, z1):
    """Una fila di vetrocemento: quadretti chiari in una cornice."""
    panel(S, FRAME_GREY, e, Polygon([(t0, z0), (t1, z0), (t1, z1), (t0, z1)]), 0.0, 0.02)
    step = 0.2
    for i in range(int((t1 - t0) / step)):
        for j in range(int((z1 - z0) / step)):
            x, y = t0 + i * step + 0.02, z0 + j * step + 0.02
            panel(S, BLOCK, e, Polygon([(x, y), (x + 0.16, y), (x + 0.16, y + 0.16), (x, y + 0.16)]), 0.0, 0.04)


def stair_glazing(b, pts):
    """Le vetrate alte a griglia bianca dei vani scala che toccano il perimetro, per lato:
    {indice del lato: [(t0, t1)]}."""
    geo = SRC / "piante" / f"{b['csie']}-geometria.json"
    if not geo.exists():
        return {}
    floor = json.loads(geo.read_text())["piani"].get(b["csie"] + "000", {})
    out = {}
    es = edges(pts)
    for v in floor.get("vani", []):
        if v["tipo"] != "scale":
            continue
        poly = unary_union([ring(r).buffer(0) for r in v["forma"]])
        best = None
        for i, e in enumerate(es):
            a, c, u, n, L, _ = e
            if LineString([a, c]).distance(poly) > 1.5:
                continue
            ts = [((x - a[0]) * u[0] + (y - a[1]) * u[1]) for x, y in poly.exterior.coords] if poly.geom_type == "Polygon" else []
            if not ts:
                continue
            t0, t1 = max(0.8, min(ts)), min(L - 0.8, max(ts))
            if t1 - t0 > 2 and (best is None or t1 - t0 > best[2] - best[1]):
                best = (i, t0, t1)
        if best:
            out.setdefault(best[0], []).append(best[1:])
    return out


def exits(b, pts):
    """Le porte esterne del seminterrato, per lato: {indice del lato: [(t0, t1)]}, le porte
    a meno di 2 m l'una dall'altra unite in un'unica apertura."""
    geo = SRC / "piante" / f"{b['csie']}-geometria.json"
    if not geo.exists():
        return {}
    floor = json.loads(geo.read_text())["piani"].get(b["csie"] + "00S", {})
    es = edges(pts)
    hits = {}
    for d in floor.get("porte", []):
        if not d.get("esterna"):
            continue
        p = np.array(d["cardine"])
        best = min(range(len(es)), key=lambda i: LineString([es[i][0], es[i][1]]).distance(Polygon([p, p + 1e-3, p + [0, 1e-3]]).centroid))
        a, c, u, n, L, _ = es[best]
        t = (p[0] - a[0]) * u[0] + (p[1] - a[1]) * u[1]
        hits.setdefault(best, []).append(min(max(t, 1.0), L - 1.0))
    out = {}
    for i, ts in hits.items():
        ts.sort()
        groups = [[ts[0], ts[0]]]
        for t in ts[1:]:
            if t - groups[-1][1] < 2.0:
                groups[-1][1] = t
            else:
                groups.append([t, t])
        out[i] = [(max(0.6, g0 - 0.9), min(es[i][4] - 0.6, g1 + 0.9)) for g0, g1 in groups]
    return out


def ingresso(b, S, zg):
    """Gli ingressi del lato ovest, come nelle piante: al terra dal pianerottolo, in cima a due
    rampe piene di cemento grezzo che salgono lungo il muro, chiuse da un parapetto pieno con
    il corrimano in metallo; al seminterrato, a quota piazza, dalla vetrata sotto il
    pianerottolo, che sta sui pilastri."""
    ent = b.get("ingresso") or {}
    r = ent.get("rampa")
    if not r or "lato" not in ent:
        return
    poly = ring(b["pianta"]).buffer(0)
    raw = [tuple(p) for p in b["pianta"]]
    a, c = raw[ent["lato"]], raw[(ent["lato"] + 1) % len(raw)]
    pts = ring_ccw(poly)
    e = min(edges(pts), key=lambda e: min(math.dist(e[0], a) + math.dist(e[1], c), math.dist(e[0], c) + math.dist(e[1], a)))
    mid = ent["t"] * e[4] if math.dist(e[0], a) < math.dist(e[0], c) else (1 - ent["t"]) * e[4]
    land = Polygon(r["pianerottolo"]).buffer(0)
    S.solid("cemento", trimesh.creation.extrude_polygon(land, 0.35).apply_translation([0, 0, zg - 0.35]))
    walls = []
    ring_ = ring_ccw(land)
    for p0, p1 in zip(ring_, ring_[1:] + ring_[:1]):
        midp = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
        if poly.exterior.distance(Polygon([midp, (midp[0] + 1e-3, midp[1]), (midp[0], midp[1] + 1e-3)]).centroid) > 1.0 \
                and math.dist(p0, p1) > 3:
            walls.append(((*p0, zg), (*p1, zg)))             # il lato verso la piazza
            for k in range(5):                                # e i pilastri sotto
                f = (k + 0.5) / 5
                x, y = p0[0] + (p1[0] - p0[0]) * f, p0[1] + (p1[1] - p0[1]) * f
                S.solid("cemento", trimesh.creation.box(extents=[0.4, 0.4, zg - 0.35]).apply_translation([x, y, (zg - 0.35) / 2]))
    for q in r["rampe"]:
        # I primi due vertici toccano il pianerottolo, gli ultimi due il suolo.
        top = [(*q[0], zg), (*q[1], zg), (*q[2], 0.02), (*q[3], 0.02)]
        S.solid("cemento", hexa([(x, y, 0.0) for x, y, _ in top], top))
        far = max(((q[0], q[3]), (q[1], q[2])), key=lambda s_: poly.exterior.distance(LineString([s_[0], s_[1]])))
        walls.append(((*far[0], zg), (*far[1], 0.02)))
    for p0, p1 in walls:
        p0, p1 = np.array(p0), np.array(p1)
        L2 = np.linalg.norm(p1[:2] - p0[:2])
        side = np.array([-(p1[1] - p0[1]), p1[0] - p0[0], 0]) / L2 * 0.12
        # Lungo le rampe il parapetto scende a terra; sul pianerottolo resta sopra la soletta.
        floor_ = 0.0 if p0[2] != p1[2] else zg - 0.35
        foot0, foot1 = np.array([*p0[:2], floor_]), np.array([*p1[:2], floor_])
        # Il parapetto pieno, alto 1 m sul piano della rampa, fino a terra.
        S.solid("cemento", hexa([foot0 - side, foot1 - side, foot1 + side, foot0 + side],
                                [p0 - side + [0, 0, 1.0], p1 - side + [0, 0, 1.0], p1 + side + [0, 0, 1.0], p0 + side + [0, 0, 1.0]]))
        # Il corrimano in metallo, poco sopra.
        rail = side / 0.12 * 0.03
        h0, h1 = p0 + [0, 0, 1.1], p1 + [0, 0, 1.1]
        S.solid(METAL, hexa([h0 - rail, h1 - rail, h1 + rail, h0 + rail],
                            [h0 - rail + [0, 0, 0.05], h1 - rail + [0, 0, 0.05], h1 + rail + [0, 0, 0.05], h0 + rail + [0, 0, 0.05]]))
        for k in range(int(L2 / 1.5) + 1):
            p = h0 + (h1 - h0) * (k / max(1, int(L2 / 1.5)))
            S.solid(METAL, trimesh.creation.box(extents=[0.04, 0.04, 0.12]).apply_translation(p - [0, 0, 0.05]))
    S.solid(DOOR, box3(e[0], e[1], e[3], mid - 1.5, mid + 1.5, zg, zg + 2.6, 0, 0.08))
    # La vetrata del seminterrato sotto il pianerottolo, sullo zoccolo.
    half = r.get("sotto", 3.5)
    t0, t1, top = mid - half, mid + half, zg - 0.5
    shift = lambda q: (q[0] - e[3][0] * RIENTRO, q[1] - e[3][1] * RIENTRO)
    be = (shift(e[0]), shift(e[1]), e[2], e[3], e[4], e[5])
    panel(S, ENTRY, be, Polygon([(t0, 0.12), (t1, 0.12), (t1, top), (t0, top)]), 0.0, 0.05)
    k = max(1, round((t1 - t0) / 1.2))
    bars = [Polygon([(t0 + (t1 - t0) * j / k - 0.05, 0.12), (t0 + (t1 - t0) * j / k + 0.05, 0.12),
                     (t0 + (t1 - t0) * j / k + 0.05, top), (t0 + (t1 - t0) * j / k - 0.05, top)]) for j in range(k + 1)]
    bars.append(Polygon([(t0, top - 0.08), (t1, top - 0.08), (t1, top + 0.08), (t0, top + 0.08)]))
    bars.append(Polygon([(t0, 2.4), (t1, 2.4), (t1, 2.48), (t0, 2.48)]))
    panel(S, FRAME_GREY, be, unary_union(bars), 0.0, 0.09)


def hexa(bottom, top):
    """Un solido a sei facce da quattro angoli in basso e i quattro sopra, nello stesso giro."""
    v = np.array(list(bottom) + list(top), float)
    f = [[0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7]]
    for i in range(4):
        j = (i + 1) % 4
        f += [[i, j, j + 4], [i, j + 4, i + 4]]
    m = trimesh.Trimesh(v, f, process=False)
    m.invert() if m.volume < 0 else None
    return m


def box3(a, c, n, t0, t1, z0, z1, d0, d1):
    """Una lastra appoggiata alla faccia a→c: da t0 a t1 lungo la faccia, da z0 a z1 in
    altezza, da d0 a d1 verso l'esterno (n). Coordinate Z-up."""
    L = math.dist(a, c)
    u = ((c[0] - a[0]) / L, (c[1] - a[1]) / L)
    at = lambda t, d: (a[0] + u[0] * t + n[0] * d, a[1] + u[1] * t + n[1] * d)
    q = [at(t0, d0), at(t1, d0), at(t1, d1), at(t0, d1)]
    return hexa([(*p, z0) for p in q], [(*p, z1) for p in q])


def guscio(b):
    """L'esterno del Trifoglio come nelle foto: {chiave: mesh}, e la quota del tetto.

    Dal basso: lo zoccolo del seminterrato, a quota piazza, in cemento grezzo con finestre,
    porte vetrate e portali fra pareti inclinate; il volume di terra e primo
    in mosaico a punta di diamante con le finestre esagonali di Ponti e il vetrocemento; le
    vetrate a griglia bianca dei vani scala; la lastra bianca del tetto, che sale verso le
    punte delle ali; gli impianti; l'ingresso con le rampe."""
    S = Solidi()
    poly = ring(b["pianta"]).buffer(0)
    pts = ring_ccw(poly)
    up = np.array([0, 0, 1.0])
    z_base, z_mos = BASE_H, BASE_H + MOSAICO_H
    centre = np.array(poly.centroid.coords[0])
    reach = max(math.dist(p, centre) for p in offset_ring(pts, SPORTO))
    lift = lambda p: ALA * (math.dist(p, centre) / reach) ** 2

    # Lo zoccolo del seminterrato, appena rientrato sotto il mosaico: cemento grezzo con le
    # sue finestre, le porte vetrate dove la pianta ha le porte esterne, e dove le porte
    # sono vicine un portale largo vetrato fra due pareti inclinate.
    base = poly.buffer(-RIENTRO, join_style=2)
    bpts = ring_ccw(base)
    S.solid(BASE, trimesh.creation.extrude_polygon(poly.buffer(0.3, join_style=2), 0.12))
    doors = exits(b, bpts)
    for i, e in enumerate(edges(bpts)):
        a, c, u, n, L, t_start = e
        S.quad("cemento", [(*a, 0), (*c, 0), (*c, z_base), (*a, z_base)], np.array([n[0], n[1], 0]),
               [(t_start, 0), (t_start + L, 0), (t_start + L, z_base), (t_start, z_base)])
        spans = doors.get(i, [])
        for t0, t1 in spans:
            portal = t1 - t0 > 3
            top = 3.3 if portal else 2.6
            panel(S, ENTRY, e, Polygon([(t0, 0.12), (t1, 0.12), (t1, top), (t0, top)]), 0.0, 0.04)
            k = max(1, round((t1 - t0) / 1.2))
            bars = [Polygon([(t0 + (t1 - t0) * j / k - 0.04, 0.12), (t0 + (t1 - t0) * j / k + 0.04, 0.12),
                             (t0 + (t1 - t0) * j / k + 0.04, top), (t0 + (t1 - t0) * j / k - 0.04, top)]) for j in range(k + 1)]
            bars.append(Polygon([(t0, top - 0.06), (t1, top - 0.06), (t1, top + 0.06), (t0, top + 0.06)]))
            panel(S, FRAME_GREY, e, unary_union(bars), 0.0, 0.08)
            if portal:
                # Le pareti inclinate ai lati del portale, che si allargano fino al mosaico.
                for side, t in ((-1, t0), (1, t1)):
                    w0, w1 = (t - 0.9, t) if side < 0 else (t, t + 0.9)
                    bottom = [on_face(e, w0, 0.0, 0), on_face(e, w1, 0.0, 0), on_face(e, w1, 0.5, 0), on_face(e, w0, 0.5, 0)]
                    topq = [on_face(e, w0, 0.0, z_base), on_face(e, w1, 0.0, z_base),
                            on_face(e, w1, RIENTRO + 0.05, z_base), on_face(e, w0, RIENTRO + 0.05, z_base)]
                    S.solid("cemento", hexa(bottom, topq))
        # Le finestre dello zoccolo, una ogni 4,2 m dove non ci sono porte.
        k = int((L - 2) / 4.2)
        pad = (L - k * 4.2) / 2 if k else 0
        for j in range(k):
            t = pad + j * 4.2
            if any(t0 - 0.6 < t + 4.2 and t < t1 + 0.6 for t0, t1 in spans) or (i + j) % 3 == 1:
                continue
            w0, w1 = t + 1.2, t + 3.0
            panel(S, FRAME_GREY, e, Polygon([(w0 - 0.08, 1.92), (w1 + 0.08, 1.92), (w1 + 0.08, 3.08), (w0 - 0.08, 3.08)]), 0.0, 0.05)
            panel(S, GLASS, e, Polygon([(w0, 2.0), (w1, 2.0), (w1, 3.0), (w0, 3.0)]), 0.0, 0.07)
    # Il sottosquadro del mosaico, sopra lo zoccolo.
    soffit_v, soffit_f = trimesh.creation.triangulate_polygon(poly, engine="earcut")
    for f in soffit_f:
        q = [(*soffit_v[i], z_base) for i in f]
        S.tri("cemento", q, -up, [(x, y) for x, y, _ in q])

    # Il volume in mosaico, con la sommità che segue il tetto.
    glazing = stair_glazing(b, pts)
    for i, e in enumerate(edges(pts)):
        a, c, u, n, L, t_start = e
        za, zc = z_mos + lift(a), z_mos + lift(c)
        q = [(*a, z_base), (*c, z_base), (*c, zc), (*a, za)]
        S.quad("mosaico", q, np.array([n[0], n[1], 0]), [(t_start, z_base), (t_start + L, z_base), (t_start + L, zc), (t_start, za)])
        spans = glazing.get(i, [])
        for t0, t1 in spans:
            top = z_mos - 0.4
            panel(S, GLASS, e, Polygon([(t0, 0.3), (t1, 0.3), (t1, top), (t0, top)]), 0.0, 0.04)
            frame = Polygon([(t0 - 0.12, 0.2), (t1 + 0.12, 0.2), (t1 + 0.12, top + 0.12), (t0 - 0.12, top + 0.12)])
            grid = [frame.difference(Polygon([(t0, 0.3), (t1, 0.3), (t1, top), (t0, top)]))]
            cols = max(1, round((t1 - t0) / 1.2))
            grid += [Polygon([(t0 + (t1 - t0) * j / cols - 0.05, 0.3), (t0 + (t1 - t0) * j / cols + 0.05, 0.3),
                              (t0 + (t1 - t0) * j / cols + 0.05, top), (t0 + (t1 - t0) * j / cols - 0.05, top)]) for j in range(1, cols)]
            grid += [Polygon([(t0, zz - 0.05), (t1, zz - 0.05), (t1, zz + 0.05), (t0, zz + 0.05)])
                     for zz in np.arange(1.5, top, 1.5)]
            panel(S, WHITE, e, unary_union(grid), 0.0, 0.12)
        # Le finestre: campate da 3,2 m su tre file, esagoni di larghezze diverse, qualche
        # campata cieca e qualche fila di vetrocemento, sempre nello stesso ordine.
        step = 3.2
        k = int((L - 1.6) / step)
        pad = (L - k * step) / 2 if k else 0
        for j in range(k):
            t = pad + j * step
            if any(t0 - 0.5 < t + step and t < t1 + 0.5 for t0, t1 in spans):
                continue
            seed = (i * 7 + j * 5 + int(L)) % 11
            for r, zr in enumerate((z_base + 1.3, z_base + 4.1, z_base + 6.9)):
                s = (seed + r * 4) % 11
                if s in (0, 3, 7):
                    continue                                              # cieca
                if s == 5:
                    glass_blocks(S, e, t + 0.4, t + 2.8, zr + 0.2, zr + 0.6)
                    continue
                w = (1.6, 2.4, 2.8)[s % 3]
                window(S, e, t + (step - w) / 2, t + (step + w) / 2, zr, zr + 1.15)

    # Il tetto: una lastra bianca sottile oltre il mosaico, che sale verso le punte.
    eave = offset_ring(pts, SPORTO)
    wall_top = [(*p, z_mos + lift(p)) for p in pts]
    eave_lo = [(*p, z_mos + lift(p) + 0.05) for p in eave]
    eave_hi = [(x, y, z + 0.3) for x, y, z in eave_lo]
    centre3 = np.array([*centre, z_mos + 2])
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        mid = (np.array(eave_lo[i]) + np.array(eave_lo[j])) / 2
        out_ = np.array([*(mid[:2] - centre), 0])
        S.quad(ROOF, [wall_top[i], wall_top[j], eave_lo[j], eave_lo[i]], -up)
        S.quad(ROOF, [eave_lo[i], eave_lo[j], eave_hi[j], eave_hi[i]], out_)
    tv, tf = trimesh.creation.triangulate_polygon(Polygon(eave), engine="earcut")
    for f in tf:
        S.tri(ROOF, [(*tv[x], z_mos + lift(tv[x]) + 0.35) for x in f], up)
    for x, y, w, d in b.get("impianti", []):
        zr = z_mos + lift((x + w / 2, y + d / 2)) + 0.3
        S.solid(PLANT, trimesh.creation.box(extents=[w, d, 1.6]).apply_translation([x + w / 2, y + d / 2, zr + 0.8]))
    ingresso(b, S, RAMPA)
    return S.meshes(), z_mos + ALA


def dettagliato(b):
    return b["csie"] in ARGS.edifici.split(",") and [p["tipo"] for p in b.get("profilo", [])][:1] == ["fessura"]


# ---------------------------------------------------------------- campus

def volumi(b):
    """(pianta, altezza, colore) per ogni volume dell'esterno."""
    def h_profilo(prof):
        return sum(p.get("h", 18) for p in prof) * H_UNIT

    def tinta(prof):
        for p in prof:
            if p.get("rivestimento") in CLADDING and p.get("tipo") == "pieno":
                return CLADDING[p["rivestimento"]]
        return COL["edificio"]

    if b.get("parti"):
        return [(ring(p["pianta"]), h_profilo(p.get("profilo", [])) or PIANO * b.get("piani", 2),
                 tinta(p.get("profilo", []))) for p in b["parti"]]
    if b.get("profilo"):
        return [(ring(b["pianta"]), h_profilo(b["profilo"]), tinta(b["profilo"]))]
    n = len(b.get("piani_3d", [])) or b.get("piani", 2)
    return [(ring(b["pianta"]), n * PIANO, COL["edificio"])]


def campus(c):
    sc = Scena("Campus")
    terr = sc.gruppo("Terreno", "Campus")
    ed = sc.gruppo("Edifici", "Campus")
    xs = [p[0] for b in c["edifici"] for p in b["pianta"]]
    ys = [p[1] for b in c["edifici"] for p in b["pianta"]]
    box = Polygon([(min(xs) - 80, min(ys) - 80), (max(xs) + 80, min(ys) - 80),
                   (max(xs) + 80, max(ys) + 80), (min(xs) - 80, max(ys) + 80)])
    k = c["contesto"]
    sc.mesh("Suolo", terr, slab(box, -0.4, 0.0, COL["terreno"]))
    verde = unary_union([ring(v).buffer(0) for v in k["verde"]]).intersection(box)
    sc.mesh("Verde", terr, slab(verde, 0.0, 0.04, COL["verde"]))
    strade = unary_union([LineString(s["punti"]).buffer(s.get("larghezza", 6) / 2, cap_style=2)
                          for s in k["strade"]]).intersection(box)
    sc.mesh("Strade", terr, slab(strade, 0.0, 0.05, COL["strada"]))
    perc = unary_union([LineString(p).buffer(1.2) for p in k["percorsi"] if len(p) > 1]).intersection(box)
    sc.mesh("Percorsi", terr, slab(perc.difference(strade), 0.0, 0.06, COL["percorso"]))
    chiome, tronchi = [], []
    for x, y, r in k["alberi"]:
        s = trimesh.creation.icosphere(subdivisions=1, radius=r)
        s.apply_translation([x, y, 2.2 + r * 0.8])
        chiome.append(s)
        t = trimesh.creation.cylinder(radius=0.18, height=2.4, sections=6)
        t.apply_translation([x, y, 1.2])
        tronchi.append(t)
    for name, parts, hex_ in (("Chiome", chiome, COL["chioma"]), ("Tronchi", tronchi, COL["tronco"])):
        m = trimesh.util.concatenate(parts)
        m.apply_transform(YUP)
        m.invert() if m.volume < 0 else None
        sc.mesh(name, terr, colour(m, hex_))
    for b in c["edifici"]:
        if b["csie"].startswith("osm-"):
            g = sc.gruppo(b["csie"].replace("-", "_"), ed)
            sc.mesh(b["csie"].replace("-", "_") + "_Esterno", g, slab(ring(b["pianta"]), 0, b.get("piani", 3) * PIANO, "#DADDE3"))
            continue
        g = sc.gruppo(b["csie"], ed)
        if dettagliato(b):
            for key, m in guscio(b)[0].items():
                sc.mesh(f"{b['csie']}_Esterno_{key.lstrip('#')}", g, m)
            continue
        for i, (poly, h, hex_) in enumerate(volumi(b)):
            sc.mesh(f"{b['csie']}_Esterno_{i}", g, slab(poly, 0, h, hex_))
            sc.mesh(f"{b['csie']}_Tetto_{i}", g, slab(poly.buffer(-0.6), h, h + 0.35, COL["tetto"]))
    return sc


# ---------------------------------------------------------------- piani

def quote(b):
    """Quota (m) del pavimento di ogni piano: il terra (…000) a zero, o sopra lo zoccolo
    del seminterrato dove il guscio lo disegna."""
    liv = b.get("livelli", [])
    g = next((i for i, c in enumerate(liv) if c.endswith("000")), 0)
    if dettagliato(b):
        # Il seminterrato a quota piazza, terra e primo nel mosaico, sopra lo zoccolo.
        return {c: BASE_H + (i - g) * PIANO for i, c in enumerate(liv)}
    return {c: (i - g) * PIANO for i, c in enumerate(liv)}


def edificio(b, aule_info):
    geo = json.loads((SRC / "piante" / f"{b['csie']}-geometria.json").read_text())["piani"]
    sc = Scena(b["csie"])
    piani = sc.gruppo("Piani", b["csie"])
    zs = quote(b)
    meta = {"csie": b["csie"], "nome": b.get("nome"), "numero": b.get("numero"), "piani": []}
    for csip, z in zs.items():
        if csip not in geo:
            continue
        f = geo[csip]
        aule = aule_info.get(csip, {})
        gp = sc.gruppo(csip, piani)
        shell = unary_union([ring(r).buffer(0) for r in f["contorno"]])
        rooms, by_type = [], {}
        locali = sc.gruppo(csip + "_Locali", gp)
        stanze = []
        for v in f["vani"]:
            poly = unary_union([ring(r).buffer(0) for r in v["forma"]])
            if poly.is_empty:
                continue
            rooms.append(poly)
            tipo = "aula" if v["csiv"] in aule else v["tipo"]
            if v["csiv"] in aule:
                m = slab(poly.buffer(-0.02), z + SOLETTA, z + SOLETTA + 0.05, COL["aula"])
                sc.mesh(v["csiv"], locali, m)
                c = poly.representative_point()
                stanze.append({"csiv": v["csiv"], "sigla": aule[v["csiv"]]["sigla"],
                               "posti": aule[v["csiv"]].get("posti"), "centro": [round(c.x, 2), round(z + 1, 2), round(c.y, 2)]})
            else:
                by_type.setdefault(COL.get(tipo, COL["locale"]), []).append(poly.buffer(-0.02))
        for hex_, polys in by_type.items():
            sc.mesh(f"{csip}_Locali_{hex_.lstrip('#')}", locali, slab(unary_union(polys), z + SOLETTA, z + SOLETTA + 0.04, hex_))
        sc.mesh(csip + "_Soletta", gp, slab(shell, z, z + SOLETTA, COL["soletta"]))
        muri = shell.difference(unary_union(rooms).buffer(0.0))
        sc.mesh(csip + "_Muri", gp, slab(muri, z + SOLETTA, z + SOLETTA + MURO, COL["muri"]))
        meta["piani"].append({"csip": csip, "quota": z, "aule": stanze})
    return sc, meta


# ---------------------------------------------------------------- USD

def usdz(sc, path):
    from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, UsdUtils
    usda = path.with_suffix(".usdc")
    st = Usd.Stage.CreateNew(str(usda))
    UsdGeom.SetStageUpAxis(st, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(st, 1.0)
    mats = {}
    tex_dir = path.parent / "textures"

    def textured(name):
        """Colore e normali dalla texture, ripetuta: il mosaico e il cemento del Trifoglio."""
        if name not in mats:
            tex_dir.mkdir(exist_ok=True)
            colore, normali = texture(name)
            colore.save(tex_dir / f"{name}.png")
            normali.save(tex_dir / f"{name}_n.png")
            m = UsdShade.Material.Define(st, f"/Materiali/{name}")
            sh = UsdShade.Shader.Define(st, m.GetPath().AppendChild("PBR"))
            sh.CreateIdAttr("UsdPreviewSurface")
            sh.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.9)
            reader = UsdShade.Shader.Define(st, m.GetPath().AppendChild("st"))
            reader.CreateIdAttr("UsdPrimvarReader_float2")
            reader.CreateInput("varname", Sdf.ValueTypeNames.Token).Set("st")
            for suffix, slot, raw in (("", "diffuseColor", False), ("_n", "normal", True)):
                t = UsdShade.Shader.Define(st, m.GetPath().AppendChild("tex" + suffix.replace("_", "")))
                t.CreateIdAttr("UsdUVTexture")
                t.CreateInput("file", Sdf.ValueTypeNames.Asset).Set(f"textures/{name}{suffix}.png")
                t.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(reader.ConnectableAPI(), "result")
                t.CreateInput("wrapS", Sdf.ValueTypeNames.Token).Set("repeat")
                t.CreateInput("wrapT", Sdf.ValueTypeNames.Token).Set("repeat")
                if raw:
                    t.CreateInput("sourceColorSpace", Sdf.ValueTypeNames.Token).Set("raw")
                    t.CreateInput("scale", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(2, 2, 2, 1))
                    t.CreateInput("bias", Sdf.ValueTypeNames.Float4).Set(Gf.Vec4f(-1, -1, -1, 0))
                sh.CreateInput(slot, Sdf.ValueTypeNames.Normal3f if raw else Sdf.ValueTypeNames.Color3f).ConnectToSource(
                    t.ConnectableAPI(), "rgb")
            m.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), "surface")
            mats[name] = m
        return mats[name]

    def material(hex_):
        if hex_ not in mats:
            m = UsdShade.Material.Define(st, f"/Materiali/c{hex_.lstrip('#')}")
            sh = UsdShade.Shader.Define(st, m.GetPath().AppendChild("PBR"))
            sh.CreateIdAttr("UsdPreviewSurface")
            sh.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(*linear(hex_)))
            sh.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.9)
            m.CreateSurfaceOutput().ConnectToSource(sh.ConnectableAPI(), "surface")
            mats[hex_] = m
        return mats[hex_]

    g = sc.s.graph
    def path_of(node):
        chain = []
        while node != g.base_frame:
            chain.append(node)
            node = g.transforms.parents[node]
        return "/" + "/".join(reversed(chain))

    for node in g.nodes:
        if node == g.base_frame:
            continue
        p = path_of(node)
        geom = g[node][1]
        if geom is None:
            UsdGeom.Xform.Define(st, p)
            continue
        m = sc.s.geometry[geom]
        mesh = UsdGeom.Mesh.Define(st, p)
        mesh.CreatePointsAttr([Gf.Vec3f(*v) for v in m.vertices.tolist()])
        mesh.CreateFaceVertexCountsAttr([3] * len(m.faces))
        mesh.CreateFaceVertexIndicesAttr(m.faces.flatten().tolist())
        mesh.CreateSubdivisionSchemeAttr("none")
        if "textura" in m.metadata:
            st_ = UsdGeom.PrimvarsAPI(mesh).CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex)
            st_.Set([Gf.Vec2f(*uv) for uv in m.metadata["uv"].tolist()])
            UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(textured(m.metadata["textura"]))
        else:
            UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(material(m.metadata.get("colore", "#CCCCCC")))
    st.SetDefaultPrim(st.GetPrimAtPath(path_of(next(n for n in g.nodes if g.transforms.parents.get(n) == g.base_frame))))
    st.GetRootLayer().Save()
    UsdUtils.CreateNewUsdzPackage(str(usda), str(path))
    usda.unlink()
    if tex_dir.exists():
        for f in tex_dir.iterdir():
            f.unlink()
        tex_dir.rmdir()


def main():
    c = json.loads((SRC / "leonardo.json").read_text())
    cs = campus(c)
    usdz(cs, OUT / "campus.usdz")
    if ARGS.glb:
        cs.s.export(OUT / "campus.glb")
    for csie in ARGS.edifici.split(","):
        b = next(e for e in c["edifici"] if e["csie"] == csie)
        info = SRC / "piante" / f"{csie}.json"
        aule = {f["csip"]: f.get("aule", {}) for f in json.loads(info.read_text())["piani"]} if info.exists() else {}
        sc, meta = edificio(b, aule)
        meta["centro"] = [round(v, 2) for v in ring(b["pianta"]).centroid.coords[0]]
        meta["altezza"] = round(guscio(b)[1] if dettagliato(b) else max(h for _, h, _ in volumi(b)), 2)
        usdz(sc, OUT / f"{csie}.usdz")
        if ARGS.glb:
            sc.s.export(OUT / f"{csie}.glb")
        (OUT / f"{csie}.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n")
        print(csie, b.get("nome", ""), len(meta["piani"]), "piani",
              sum(len(p["aule"]) for p in meta["piani"]), "aule")


if __name__ == "__main__":
    main()
