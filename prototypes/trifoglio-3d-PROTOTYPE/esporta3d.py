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
import argparse, json, math, pathlib, sys
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union, polygonize

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
TEX = {"mosaico": 1.0, "cemento": 1.5, "cubetti": 1.2, "piastrelle": 1.2}   # metri coperti da una ripetizione


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
    tessere da 5 cm grigio scuro, il cemento bocciardato del basamento e i cubetti chiari dei
    pavimenti interni."""
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
    elif name == "cubetti":
        # Il pavimento delle aule e dell'Aula Magna nelle foto: cubetti di pietra chiara a
        # correre, file da 10 cm e pezzi da 12-26 cm, chiari e poco contrastati, giunti sottili.
        size, rows = 384, 12                       # 1,2 m: 12 file da 10 cm
        rh = size // rows
        rgb = np.zeros((size, size, 3))
        height = np.ones((size, size))
        for r in range(rows):
            x0 = int(rng.integers(0, 40))
            cuts = [x0]
            while cuts[-1] < x0 + size:
                cuts.append(cuts[-1] + int(rng.integers(38, 84)))
            cuts[-1] = x0 + size                   # la fila si richiude sul bordo
            for a_, b_ in zip(cuts, cuts[1:]):
                tone = np.array([0.90, 0.90, 0.88]) + rng.normal(0, 0.025)
                cols = np.arange(a_, b_) % size
                rgb[r * rh:(r + 1) * rh, cols] = tone
                height[r * rh:(r + 1) * rh, a_ % size] = 0
            height[r * rh, :] = 0
        rgb[height == 0] = [0.80, 0.80, 0.78]
        strength = 1.5
    elif name == "piastrelle":
        # Il rivestimento dell'Edificio 11 di Ponti, restaurato nel 2021 (foto Urbanfile):
        # piastrelle chiare da 20 x 10 cm a correre, lisce, a punta di diamante o rigate.
        px = 32                                    # 10 cm
        size, rows, cols = 12 * px, 12, 6          # 1,2 m
        rgb = np.zeros((size, size, 3))
        height = np.zeros((size, size))
        y, x = np.mgrid[0:px, 0:2 * px]
        for r in range(rows):
            off = (r % 2) * px
            for c in range(cols):
                kind = int(rng.integers(0, 5))
                tone = np.array([0.88, 0.85, 0.79]) + rng.normal(0, 0.025)
                if kind <= 1:                      # punta di diamante, 8 x 4 punte
                    fx, fy = (x % 8) / 8 - 0.5, (y % 8) / 8 - 0.5
                    h = 1 - 2 * np.maximum(np.abs(fx), np.abs(fy))
                elif kind == 2:                    # rigata
                    h = ((y // 4) % 2).astype(float)
                else:
                    h = np.ones_like(x, float) * 0.6
                h = h.copy()
                h[:, :2] = h[:, -2:] = h[:2, :] = h[-2:, :] = 0      # il giunto
                xs = (np.arange(2 * px) + c * 2 * px + off) % size
                rgb[r * px:(r + 1) * px][:, xs] = tone * (0.92 + 0.12 * h)[..., None]
                height[r * px:(r + 1) * px][:, xs] = h
        rgb[height == 0] = [0.78, 0.76, 0.71]
        strength = 2.0
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


def plan_floor(b, csip):
    """La geometria di un piano dalle piante, o {} se manca."""
    geo = SRC / "piante" / f"{b['csie']}-geometria.json"
    return json.loads(geo.read_text())["piani"].get(csip, {}) if geo.exists() else {}


def pilastri(v):
    """I pilastri di un locale: gli anelli piccoli (sotto 1,5 m²) che la pianta disegna
    dentro il suo contorno. Quadrati nell'atrio del seminterrato, tondi (ottagoni) nelle
    aule del primo."""
    rings = [ring(r).buffer(0) for r in v["forma"]]
    return [r for r in rings if r.area < 1.5 and any(o is not r and o.area > 5 and o.contains(r) for o in rings)]


def shape_of(v):
    cols = pilastri(v)
    rings = [r for r in (ring(q).buffer(0) for q in v["forma"]) if not any(r.equals(c) for c in cols)]
    return unary_union(rings).difference(unary_union(cols)) if cols else unary_union(rings)


def plan_windows(b, csip, pts, reach=1.2):
    """Le finestre della pianta di un piano, portate sul lato del guscio più vicino:
    {indice del lato: [(t0, t1)]}, le linee vicine unite, le aperture lunghe divise in
    finestre da circa 2,8 m come nelle foto."""
    lines = plan_floor(b, csip).get("linee", {}).get("finestre", [])
    es = edges(pts)
    hits = {}
    for x0, y0, x1, y1 in (s_[:4] for s_ in lines):
        seg = LineString([(x0, y0), (x1, y1)])
        if seg.length < 0.2:
            continue
        i = min(range(len(es)), key=lambda k: LineString([es[k][0], es[k][1]]).distance(seg))
        a, c, u, n, L, _ = es[i]
        if LineString([a, c]).distance(seg) > reach:
            continue
        d = ((x1 - x0) * u[0] + (y1 - y0) * u[1]) / seg.length
        if abs(d) < 0.9:
            continue                                  # non parallela al muro
        ts = sorted(((x0 - a[0]) * u[0] + (y0 - a[1]) * u[1], (x1 - a[0]) * u[0] + (y1 - a[1]) * u[1]))
        hits.setdefault(i, []).append((max(0.5, ts[0]), min(L - 0.5, ts[1])))
    out = {}
    for i, spans in hits.items():
        spans.sort()
        merged = [list(spans[0])]
        for t0, t1 in spans[1:]:
            if t0 - merged[-1][1] < 0.4:
                merged[-1][1] = max(merged[-1][1], t1)
            else:
                merged.append([t0, t1])
        for t0, t1 in merged:
            if t1 - t0 < 0.6:
                continue
            k = max(1, round((t1 - t0) / 3.2))
            w = (t1 - t0) / k
            for j in range(k):
                out.setdefault(i, []).append((t0 + j * w + (0.2 if k > 1 else 0), t0 + (j + 1) * w - (0.2 if k > 1 else 0)))
    return out


def outside_parts(b, csip):
    """I vani della pianta di un piano fuori dal contorno dell'edificio, tolti quelli della
    rampa e del pianerottolo: la torre scale a nord con il suo ponte, le scale di
    sicurezza e i balconi sulle punte."""
    poly = ring(b["pianta"]).buffer(0)
    r = (b.get("ingresso") or {}).get("rampa") or {}
    ramp = unary_union([Polygon(q) for q in r.get("rampe", [])] + ([Polygon(r["pianerottolo"])] if r else []))
    ramp = ramp.buffer(1.0) if not ramp.is_empty else ramp
    out = []
    for v in plan_floor(b, csip).get("vani", []):
        g = shape_of(v)
        if g.is_empty or poly.contains(g.representative_point()):
            continue
        if not ramp.is_empty and ramp.intersects(g):
            continue
        out.append(g.difference(poly).buffer(0))
    return [g for g in out if not g.is_empty and g.area > 1.5]


def is_tower(g):
    """La torre scale a nord e il suo ponte: dove le piante disegnano le due rampe di scale
    fuori dall'edificio, oltre la facciata nord."""
    x0, y0, x1, y1 = g.bounds
    return y1 < -9 and 7 < (x0 + x1) / 2 < 25


def glazed_storey(S, g, z0, z1, roof=False):
    """Un piano vetrato a griglia bianca sulla pianta g: soletta, vetri, montanti, traversi."""
    for part in getattr(g, "geoms", [g]):
        part = part.simplify(0.25).buffer(0)
        if part.is_empty or part.area < 1:
            continue
        S.solid(BASE, trimesh.creation.extrude_polygon(part, 0.25).apply_translation([0, 0, z0]))
        for e in edges(ring_ccw(part)):
            L = e[4]
            panel(S, GLASS, e, Polygon([(0, z0 + 0.25), (L, z0 + 0.25), (L, z1), (0, z1)]), -0.06, 0.0)
            cols = max(1, round(L / 1.2))
            grid = [Polygon([(L * j / cols - 0.05, z0 + 0.25), (L * j / cols + 0.05, z0 + 0.25),
                             (L * j / cols + 0.05, z1), (L * j / cols - 0.05, z1)]) for j in range(cols + 1)]
            grid += [Polygon([(0, zz - 0.05), (L, zz - 0.05), (L, zz + 0.05), (0, zz + 0.05)])
                     for zz in (z0 + 0.3, (z0 + z1) / 2, z1 - 0.05)]
            panel(S, WHITE, e, unary_union(grid).intersection(Polygon([(0, z0), (L, z0), (L, z1 + 0.1), (0, z1 + 0.1)])), 0.0, 0.1)
        if roof:
            S.solid(ROOF, trimesh.creation.extrude_polygon(part.buffer(0.3, join_style=2), 0.3).apply_translation([0, 0, z1]))


def railing(S, p0, p1):
    """Un parapetto in metallo da p0 a p1 (punti 3D sul piano di calpestio)."""
    p0, p1 = np.array(p0, float), np.array(p1, float)
    L = np.linalg.norm(p1[:2] - p0[:2])
    if L < 0.3:
        return
    side = np.array([-(p1[1] - p0[1]), p1[0] - p0[0], 0]) / L * 0.03
    h0, h1 = p0 + [0, 0, 1.05], p1 + [0, 0, 1.05]
    S.solid(METAL, hexa([h0 - side, h1 - side, h1 + side, h0 + side],
                        [h0 - side + [0, 0, 0.05], h1 - side + [0, 0, 0.05], h1 + side + [0, 0, 0.05], h0 + side + [0, 0, 0.05]]))
    k = max(1, int(L / 1.2))
    for j in range(k + 1):
        q = p0 + (p1 - p0) * (j / k)
        S.solid(METAL, trimesh.creation.box(extents=[0.05, 0.05, 1.05]).apply_translation(q + [0, 0, 0.525]))


def outer_edges(g, poly, near=0.6):
    """I lati di g che non toccano l'edificio."""
    pts = ring_ccw(g.simplify(0.2).buffer(0))
    for a, c in zip(pts, pts[1:] + pts[:1]):
        if LineString([a, c]).distance(poly) > near or LineString([a, c]).length > 0 and \
                poly.exterior.distance(LineString([a, c]).interpolate(0.5, normalized=True)) > near:
            yield a, c


def balcony(S, g, z, poly):
    """Un balcone sulla punta: soletta e parapetto in metallo sui lati liberi."""
    S.solid("cemento", trimesh.creation.extrude_polygon(g.simplify(0.2).buffer(0), 0.3).apply_translation([0, 0, z - 0.3]))
    for a, c in outer_edges(g, poly):
        railing(S, (*a, z), (*c, z))


def outdoor_stair(S, g, z_top, poly, centre):
    """Una scala di sicurezza sulla punta: scende lungo il suo lato lungo dal piano z_top
    fino alla piazza, dalla parte verso il centro dell'edificio a quella verso la punta."""
    rect = g.minimum_rotated_rectangle
    c = list(rect.exterior.coords)[:4]
    sides = [(c[i], c[(i + 1) % 4]) for i in range(4)]
    long_ = max(sides, key=lambda s_: math.dist(*s_))
    axis = np.array(long_[1]) - np.array(long_[0])
    axis /= np.linalg.norm(axis)
    proj = [float(np.dot(np.array(p), axis)) for p in c]
    s0, s1 = min(proj), max(proj)
    # La parte alta è quella più vicina al centro dell'edificio.
    if abs(float(np.dot(centre, axis)) - s0) > abs(float(np.dot(centre, axis)) - s1):
        axis, s0, s1 = -axis, -s1, -s0
    n_steps = max(4, round(z_top / 0.175))
    normal = np.array([-axis[1], axis[0]])
    big = 200
    for k in range(n_steps):
        a0 = s0 + (s1 - s0) * k / n_steps
        a1 = s0 + (s1 - s0) * (k + 1) / n_steps
        band = Polygon([tuple(axis * a0 + normal * big), tuple(axis * a1 + normal * big),
                        tuple(axis * a1 - normal * big), tuple(axis * a0 - normal * big)])
        tread = g.intersection(band)
        top = z_top * (1 - k / n_steps)
        for part in getattr(tread, "geoms", [tread]):
            if part.geom_type == "Polygon" and part.area > 0.05:
                S.solid("cemento", trimesh.creation.extrude_polygon(part, max(0.2, top)))
    # I parapetti lungo i due lati lunghi, inclinati come la scala.
    for sgn in (1, -1):
        edge_pts = sorted(c, key=lambda p: float(np.dot(np.array(p), normal)) * sgn)[-2:]
        p_hi = min(edge_pts, key=lambda p: float(np.dot(np.array(p), axis)))
        p_lo = max(edge_pts, key=lambda p: float(np.dot(np.array(p), axis)))
        if LineString([p_hi, p_lo]).distance(poly) > 0.5:
            railing(S, (*p_hi, z_top), (*p_lo, 0.2))


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
            ts = [((x - a[0]) * u[0] + (y - a[1]) * u[1]) for part in getattr(poly, "geoms", [poly]) for x, y in part.exterior.coords]
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
    base_windows = plan_windows(b, b["csie"] + "00S", bpts, reach=1.5)
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
        # Le finestre dello zoccolo, dove la pianta del seminterrato le disegna.
        for w0, w1 in base_windows.get(i, []):
            if any(t0 - 0.3 < w1 and w0 < t1 + 0.3 for t0, t1 in spans):
                continue
            panel(S, FRAME_GREY, e, Polygon([(w0 - 0.08, 1.02), (w1 + 0.08, 1.02), (w1 + 0.08, 2.48), (w0 - 0.08, 2.48)]), 0.0, 0.05)
            panel(S, GLASS, e, Polygon([(w0, 1.1), (w1, 1.1), (w1, 2.4), (w0, 2.4)]), 0.0, 0.07)
    # Il sottosquadro del mosaico, sopra lo zoccolo.
    soffit_v, soffit_f = trimesh.creation.triangulate_polygon(poly, engine="earcut")
    for f in soffit_f:
        q = [(*soffit_v[i], z_base) for i in f]
        S.tri("cemento", q, -up, [(x, y) for x, y, _ in q])

    # Il volume in mosaico, con la sommità che segue il tetto.
    glazing = stair_glazing(b, pts)
    mosaic_windows = [plan_windows(b, b["csie"] + "000", pts), plan_windows(b, b["csie"] + "001", pts)]
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
        # Le finestre, dove le piante di terra e primo le disegnano: esagoni di Ponti a metà
        # di ogni piano; nelle aule alte del primo, dove il muro sopra è cieco, una fila di
        # vetrocemento ogni tanto, come nelle foto.
        for row, (csip, zf) in enumerate(((b["csie"] + "000", z_base), (b["csie"] + "001", z_base + PIANO))):
            for w0, w1 in mosaic_windows[row].get(i, []):
                if any(t0 - 0.5 < w1 and w0 < t1 + 0.5 for t0, t1 in spans):
                    continue
                window(S, e, w0, w1, zf + 1.2, zf + 2.35)
                if row == 1 and int(w0 * 7 + i) % 3 == 0 and z_mos - (zf + 3.3) > 1.0:
                    glass_blocks(S, e, (w0 + w1) / 2 - 1.2, (w0 + w1) / 2 + 1.2, zf + 3.3, zf + 3.7)

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
    # Fuori dal contorno, come nelle piante: la torre scale vetrata a nord con il suo ponte,
    # le scale di sicurezza sulle punte al terra e i balconi del primo.
    levels = [(b["csie"] + "00S", 0.0), (b["csie"] + "000", z_base), (b["csie"] + "001", z_base + PIANO)]
    tower_top = {}
    for k, (csip, zf) in enumerate(levels):
        for g in outside_parts(b, csip):
            if is_tower(g):
                glazed_storey(S, g, zf, zf + (levels[k + 1][1] - zf if k + 1 < len(levels) else PIANO))
                tower_top[k] = g
            elif k == 1:
                outdoor_stair(S, g, zf, poly, centre)
            elif k == 2:
                balcony(S, g, zf, poly)
    if tower_top:
        k = max(tower_top)
        top = levels[k][1] + PIANO
        S.solid(ROOF, trimesh.creation.extrude_polygon(tower_top[k].simplify(0.25).buffer(0.3, join_style=2), 0.3).apply_translation([0, 0, top]))
    return S.meshes(), z_mos + ALA


def dettagliato(b):
    return b["csie"] in ARGS.edifici.split(",") and [p["tipo"] for p in b.get("profilo", [])][:1] == ["fessura"]


# ---------------------------------------------------------------- profili

STEEL, STEEL_RED = "#23272E", "#C0503B"      # l'acciaio nero e rosso di Viganò
ARANCIO = "#E2672A"                          # i parapetti del portico
CONDOTTI = ("#C9CED5", "#9AA2AC")
VETRO_SCURO = "#5D7088"                      # il vetro fumé fra i telai neri
SOLAIO_BORDO = "#F2F3F6"


def profilo_parti(b):
    """Le parti di un edificio con il loro profilo: [(nome, anello ccw, profilo, parte)]."""
    if b.get("parti"):
        return [(p["nome"], ring_ccw(ring(p["pianta"]).buffer(0)), p.get("profilo", []), p)
                for p in b["parti"] if not p.get("ciminiera")]
    return [("", ring_ccw(ring(b["pianta"]).buffer(0)), b.get("profilo", []), b)]


def profilato(b):
    """Gli edifici portati in 3D dalle fasce della mappa (`profilo`, `parti`), come le
    disegna build-mappa.py, tranne il Trifoglio che ha il suo guscio."""
    return b["csie"] in ARGS.edifici.split(",") and not dettagliato(b) and bool(b.get("parti") or b.get("profilo"))


def quote_profilo(b):
    """Quota di ogni piano dalle fasce della parte con l'ingresso (o della prima): la fascia
    del piano parte dove la sua base; il seminterrato a fessura sta sotto terra, con la
    fessura in cima. Mai meno di 3 m fra un piano e il successivo."""
    parti = profilo_parti(b)
    _, _, prof, _ = next((x for x in parti if x[3].get("ingresso")), parti[0])
    z, start = 0.0, {}
    for band in prof:
        h = band.get("h", 18) * H_UNIT
        if band.get("piano") and band["piano"] not in start:
            start[band["piano"]] = z + h - PIANO if band["tipo"] == "fessura" else z
        z += h
    out, last = {}, None
    for c in b.get("livelli", []):
        q = start.get(c)
        if q is None:
            q = (last + PIANO) if last is not None else 0.0
        if last is not None and q < last + 3.0:
            q = last + 3.0
        out[c], last = round(q, 2), q
    return out


def trave_z(out, p, q, w):
    """Una barra quadrata da p a q, in una lista di mesh."""
    p, q = np.array(p, float), np.array(q, float)
    if np.linalg.norm(q - p) > 0.05:
        out.append(trimesh.creation.cylinder(radius=w / math.sqrt(2), segment=[p, q], sections=4))


def trave(S, key, p, q, w=0.3):
    """Una trave quadrata da p a q (punti 3D)."""
    p, q = np.array(p, float), np.array(q, float)
    if np.linalg.norm(q - p) < 0.05:
        return
    m = trimesh.creation.cylinder(radius=w / math.sqrt(2), segment=[p, q], sections=4)
    S.solid(key, m)


def prisma(S, key, pts, z0, z1):
    for q in clean(Polygon(pts).buffer(0)):
        S.solid(key, trimesh.creation.extrude_polygon(q, z1 - z0).apply_translation([0, 0, z0]))


def piano_vetro(S, pts, z, h, telaio=None):
    """Un piano vetrato: il bordo bianco del solaio, il vetro arretrato di 40 cm, i montanti
    sottili ogni 1,25 m e più grossi ogni 5 m (neri dove la mappa dà il telaio)."""
    prisma(S, SOLAIO_BORDO, pts, z, z + 0.5)
    vetro = ring_ccw(Polygon(pts).buffer(-0.4, join_style=2)) if Polygon(pts).buffer(-0.4).area > 1 else pts
    prisma(S, VETRO_SCURO if telaio else VETRO, vetro, z + 0.5, z + h)
    col = telaio or "#FFFFFF"
    for a, c, u, n, L, _ in edges(ring_ccw(Polygon(pts).buffer(-0.35, join_style=2))):
        k = max(1, round(L / 1.25))           # i montanti fitti delle foto, ogni 1,25 m circa
        for i in range(k + 1):
            x, y = a[0] + u[0] * L * i / k, a[1] + u[1] * L * i / k
            trave(S, col, (x, y, z + 0.5), (x, y, z + h), 0.08 if i % 4 else 0.14)
        trave(S, col, (*a, z + h - 0.06), (*c, z + h - 0.06), 0.12)


def esoscheletro(S, pts, top, altre, z_tiranti=4.5):
    """L'acciaio di Viganò, come nelle foto (MiBACT 2020): pilastri a croce staccati di
    1,8 m dalle facciate libere, che salgono 6 m sopra il tetto; in cima a ognuno una trave
    lungo la facciata, larga 4 m, retta da due puntoni, da cui pendono i due tiranti che
    reggono i piani; dalla cima una trave torna giù obliqua sul tetto; sotto il tetto la trave
    longitudinale da pilastro a pilastro."""
    zt = top + 6.0
    for a, c, u, n, L, _ in edges(pts):
        mid = Point((a[0] + c[0]) / 2, (a[1] + c[1]) / 2)
        if L < 6 or any(o.exterior.distance(mid) < 1.0 for o in altre):
            continue
        k = max(1, round(L / 7.2))
        teste = []
        for i in range(k + 1):
            t = i * L / k
            x, y = a[0] + u[0] * t + n[0] * 1.8, a[1] + u[1] * t + n[1] * 1.8
            for d in ((0.32, 0.08), (0.08, 0.32)):        # il pilastro a croce, con la punta
                q = [(x - d[0], y - d[1]), (x + d[0], y - d[1]), (x + d[0], y + d[1]), (x - d[0], y + d[1])]
                prisma(S, STEEL, q, 0, zt + 1.0)
            zc = zt - 0.6
            ends = [(x - u[0] * 2.0, y - u[1] * 2.0), (x + u[0] * 2.0, y + u[1] * 2.0)]
            trave(S, STEEL, (*ends[0], zc), (*ends[1], zc), 0.3)
            for e in ends:
                trave(S, STEEL, (x, y, zc - 2.6), (*e, zc), 0.18)       # i puntoni
                trave(S, STEEL, (*e, zc), (*e, z_tiranti), 0.16)       # i tiranti
                trave(S, STEEL, (*e, zc + 0.1), (*e, zc + 0.9), 0.14)  # le punte dei tiranti
            trave(S, STEEL, (x, y, zc), (x - n[0] * 7.0, y - n[1] * 7.0, top + 0.4), 0.22)
            teste.append((x, y))
        for p_, q_ in zip(teste, teste[1:]):
            trave(S, STEEL, (*p_, top - 0.9), (*q_, top - 0.9), 0.35)


def scultura_a(S, pts, at, top):
    """La "A" di architettura davanti all'ingresso di Via Ampère: una gamba nera spessa che
    passa un po' oltre il vertice, una rossa più sottile e la traversa rossa sull'apertura."""
    e = min(edges(pts), key=lambda e_: LineString([e_[0], e_[1]]).distance(Point(at)))
    a, c, u, n, L, _ = e
    t_at = float(np.dot(np.array(at) - np.array(a), np.array(u)))
    P = lambda t, z, d=4.5: (a[0] + u[0] * t + n[0] * d, a[1] + u[1] * t + n[1] * d, z)
    zx = top * 0.92
    half = zx / math.sqrt(3)
    apex = t_at + 3.2
    tb, tr = apex + half, apex - half

    def gamba(t0, t1, z1, w, key):
        q0 = [P(t0 - w / 2, 0, 4.25), P(t0 + w / 2, 0, 4.25), P(t0 + w / 2, 0, 4.75), P(t0 - w / 2, 0, 4.75)]
        q1 = [P(t1 - w / 2, z1, 4.25), P(t1 + w / 2, z1, 4.25), P(t1 + w / 2, z1, 4.75), P(t1 - w / 2, z1, 4.75)]
        S.solid(key, hexa(q0, q1))
    f = lambda t0, t1, k: t0 + (t1 - t0) * k
    gamba(tb, f(tb, apex, 1.12), zx * 1.12, 2.2 * 0.5, STEEL)
    gamba(tr, apex, zx, 1.4 * 0.5, STEEL_RED)
    zp = 23 * H_UNIT
    k0, k1 = zp / zx, zp / zx + 0.09
    q0 = [P(f(tr, apex, k0), zp, 4.3), P(f(tb, apex, k0), zp, 4.3), P(f(tb, apex, k0), zp, 4.7), P(f(tr, apex, k0), zp, 4.7)]
    q1 = [P(f(tr, apex, k1), zx * k1, 4.3), P(f(tb, apex, k1), zx * k1, 4.3), P(f(tb, apex, k1), zx * k1, 4.7), P(f(tr, apex, k1), zx * k1, 4.7)]
    S.solid(STEEL_RED, hexa(q0, q1))


def profilo_3d(b):
    """L'esterno di un edificio dalle fasce della mappa, dal basso: `vetro` (piano vetrato),
    `portico` (vetro arretrato sotto i piani sopra, parapetti arancio, condotti), `pieno` e
    `fessura` (volumi chiusi), `sporto` (pieno che sporge), `sagoma: propria` (il piano sul
    suo contorno, arretrato sul tetto di sotto); l'esoscheletro e la A dove la mappa li
    disegna. Torna ({colore: mesh}, quota del tetto)."""
    S = Solidi()
    parti = profilo_parti(b)
    contorni = {}
    geo_p = SRC / "piante" / f"{b['csie']}-geometria.json"
    geo = json.loads(geo_p.read_text())["piani"] if geo_p.exists() else {}
    top_all = 0.0
    for nome, pts, prof, part in parti:
        z, below, roofed = 0.0, pts, False
        for band in prof:
            kind, h = band["tipo"], band.get("h", 18) * H_UNIT
            if kind in ("terrazza", "volta", "denti", "coppi"):
                continue
            own = pts
            if band.get("sagoma") == "propria" and band.get("piano") in geo:
                anelli = geo[band["piano"]]["contorno"]
                g = max((ring(r).buffer(0) for r in anelli), key=lambda g_: g_.area).simplify(0.6)
                g = g.intersection(Polygon(pts).buffer(0.0))
                if g.geom_type != "Polygon":
                    g = max(clean(g), key=lambda g_: g_.area)
                own = ring_ccw(g)
            if own is not pts and not roofed:
                prisma(S, COL["tetto"], below, z, z + 0.4)
                for a, c, *_ in edges(below):
                    trave(S, "#AEB4BE", (*a, z + 1.05), (*c, z + 1.05), 0.05)
                z, roofed = z + 0.4, True
            if kind == "vetro":
                piano_vetro(S, own, z, h, band.get("telaio"))
            elif kind == "portico":
                prisma(S, "#C3C8CF", own, z, z + 0.05)
                dentro = ring_ccw(Polygon(own).buffer(-band.get("arretrato", 3.0), join_style=2))
                piano_vetro(S, dentro, z, h, band.get("telaio"))
                # i grossi condotti argentati sotto il soffitto del portico (foto MiBACT)
                for k_, d_ in enumerate((0.7, 1.5, 2.3)):
                    giro = ring_ccw(Polygon(own).buffer(-d_, join_style=2))
                    for a, c, *_ in edges(giro):
                        S.solid(CONDOTTI[k_ % 2], trimesh.creation.cylinder(
                            radius=0.36, segment=[(*a, z + h - 0.5), (*c, z + h - 0.5)], sections=10))
                for a, c, *_ in edges(own):
                    for zz in (0.5, 0.95):
                        trave(S, ARANCIO, (*a, z + zz), (*c, z + zz), 0.06)
            elif kind == "sporto":
                # Come nelle foto della parte di Ponti: il volume sporge e le sue facce si
                # aprono salendo, di 1 m in tutta l'altezza; sotto, l'intradosso bianco.
                sp = band.get("sporto", 0.9)
                giu = offset_ring(own, sp)
                su = offset_ring(own, sp + 1.0)
                chiave = "piastrelle" if band.get("rivestimento") in ("mattone", "ceramica") else CLADDING[band.get("rivestimento", "mattone")]
                for i_ in range(len(own)):
                    j_ = (i_ + 1) % len(own)
                    nn = normal_out(giu[i_], giu[j_])
                    quad = [(*giu[i_], z), (*giu[j_], z), (*su[j_], z + h), (*su[i_], z + h)]
                    S.quad(chiave, quad, (nn[0], nn[1], 0.15),
                           [(0, z), (math.dist(giu[i_], giu[j_]), z), (math.dist(giu[i_], giu[j_]), z + h), (0, z + h)])
                prisma(S, "#F2F2EF", giu, z - 0.02, z)
                prisma(S, COL["tetto"], su, z + h - 0.01, z + h)
                own = su
            else:
                colore = CLADDING["fessura" if kind == "fessura" else band.get("rivestimento", "ceramica")]
                if kind == "pieno" and band.get("rivestimento", "ceramica") in ("ceramica", "mattone"):
                    colore = "piastrelle"
                prisma(S, colore, own, z, z + h)
            z += h
            below = own
        prisma(S, COL["tetto"], below, z, z + 0.4)
        top = z
        top_all = max(top_all, top)
        altre = [Polygon(o) for n2, o, _, _ in parti if n2 != nome]
        if part.get("esoscheletro"):
            esoscheletro(S, pts, top, altre)
        ent = b.get("ingresso") or {}
        if ent.get("scultura") == "A" and part.get("ingresso") and ent.get("punto"):
            scultura_a(S, pts, ent["punto"], top)
    return S.meshes(), top_all + 0.4



# ---------------------------------------------------------------- gusci propri

# Un edificio può avere l'esterno disegnato a mano in gusci/<csie>.py, con
#   guscio(b, E) -> ({colore: mesh}, quota del tetto)   E è questo modulo, con i suoi attrezzi
#   quote(b, E)  -> {csip: quota}                       facoltativo: le quote dei piani
#   arredi(b, E, csip, z, piano) -> {colore: [mesh]}    facoltativo: arredi in più su un piano
#   interno(b, E, csiv, poly, z, porte) -> come interno() facoltativo: l'interno di un'aula
#                                                       senza file nella pianta
#   piante(b, E, geo, aule) -> None                     facoltativo: completa le piante prima
#                                                       dell'esportazione (es. le file di banchi)
GUSCI = pathlib.Path(__file__).resolve().parent / "gusci"


def guscio_proprio(b):
    """Il modulo gusci/<csie>.py dell'edificio, se esiste e l'edificio è fra quelli esportati."""
    p = GUSCI / f"{b['csie']}.py"
    if b["csie"] not in ARGS.edifici.split(",") or not p.exists():
        return None
    if p.stem not in sys.modules:
        import importlib.util
        spec = importlib.util.spec_from_file_location(p.stem, p)
        sys.modules[p.stem] = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(sys.modules[p.stem])
    return sys.modules[p.stem]


_ESTERNI = {}


def esterno(b):
    """({colore: mesh}, quota del tetto) dell'esterno dettagliato, o None per le estrusioni."""
    if b["csie"] not in _ESTERNI:
        _ESTERNI[b["csie"]] = (guscio_proprio(b).guscio(b, sys.modules[__name__]) if guscio_proprio(b)
                               else guscio(b) if dettagliato(b) else profilo_3d(b) if profilato(b) else None)
    return _ESTERNI[b["csie"]]



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
        if esterno(b):
            for key, m in esterno(b)[0].items():
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
    if guscio_proprio(b) and hasattr(guscio_proprio(b), "quote"):
        return guscio_proprio(b).quote(b, sys.modules[__name__])
    if dettagliato(b):
        # Il seminterrato a quota piazza, terra e primo nel mosaico, sopra lo zoccolo.
        return {c: BASE_H + (i - g) * PIANO if i >= g else BASE_H * (i - g + 1) for i, c in enumerate(liv)}
    if profilato(b):
        return quote_profilo(b)
    return {c: (i - g) * PIANO for i, c in enumerate(liv)}


DESK, SEAT, LEAF, LIFT = "#F1F1EF", "#D6D9D2", "#B9BDC4", "#C9CED6"
SCHERMO = "#3A3E44"
CORRIMANO = "#2B2D30"     # i corrimano neri dei corridoi nelle aule
SCALINO = "#5E6268"       # i gradini grigio scuro dei corridoi nelle aule
PILASTRO = "#F3F3F0"      # pilastri intonacati bianchi, come nelle foto delle aule
METALLO, VETRO = "#8E949B", "#BFD3E3"
RISE = 0.17          # alzata di una fila di gradoni


def band(axis, a0, a1, big=300):
    normal = np.array([-axis[1], axis[0]])
    return Polygon([tuple(axis * a0 + normal * big), tuple(axis * a1 + normal * big),
                    tuple(axis * a1 - normal * big), tuple(axis * a0 - normal * big)])


CENTRO = None       # il centro dell'edificio in esportazione


def file_di_banchi(poly, segs):
    """Le file di banchi disegnate in un'aula: (asse dalla cattedra verso il fondo, file).
    Ogni fila è (segmento, normale verso il fondo, indice): i settori a ventaglio hanno
    ciascuno la sua direzione, e in ogni settore le file si contano dalla cattedra, che sta
    dal lato con più spazio libero."""
    inner = poly.buffer(-0.05)
    rows = [tuple(s_[:4]) for s_ in segs if math.dist(s_[:2], s_[2:4]) > 0.8 and inner.contains(LineString([s_[:2], s_[2:4]]).centroid)]
    if len(rows) < 3:
        return None
    unit = lambda r: (np.array(r[2:4]) - np.array(r[:2])) / math.dist(r[:2], r[2:4])
    d = np.zeros(2)
    for r in rows:
        d += unit(r) if np.dot(unit(r), d) >= 0 else -unit(r)
    d /= np.linalg.norm(d)
    axis = np.array([-d[1], d[0]])
    mid = lambda r: (np.array(r[:2]) + np.array(r[2:4])) / 2
    pos = [float(np.dot(mid(r), axis)) for r in rows]
    ext = [float(np.dot(np.array(p), axis)) for p in poly.exterior.coords]
    davanti, dietro = min(pos) - min(ext), max(ext) - max(pos)
    if abs(davanti - dietro) < 1.0 and CENTRO is not None:
        # spazio pari ai due lati: le file salgono verso l'esterno dell'edificio, come le aule
        # sopra e sotto (altrimenti il gradino in cima finirebbe sotto il fronte dell'aula di
        # sopra) e come le ali del tetto
        if np.dot(np.array(poly.centroid.coords[0]) - CENTRO, axis) < 0:
            axis = -axis
    elif davanti < dietro:
        axis = -axis
    # settori: file parallele che si sovrappongono lungo la loro direzione
    sectors = []
    for r in rows:
        u = unit(r)
        for sec in sectors:
            v = unit(sec[0])
            span = lambda q: sorted([float(np.dot(np.array(q[:2]), v)), float(np.dot(np.array(q[2:4]), v))])
            a, b = span(r), span(sec[0])
            if abs(np.dot(u, v)) > 0.995 and min(a[1], b[1]) - max(a[0], b[0]) > 0.5:
                sec.append(r)
                break
        else:
            sectors.append([r])
    out = []
    for sec in sectors:
        u = unit(sec[0])
        n = np.array([-u[1], u[0]])
        n = n if np.dot(n, axis) >= 0 else -n
        sec.sort(key=lambda r: float(np.dot(mid(r), n)))
        k, last = 0, None
        for r in sec:
            q = float(np.dot(mid(r), n))
            if last is not None and q - last > 0.35:
                k += 1
            last = q
            out.append((r, n, k, k == 0))
        out = [(r, n_, k_, k_ == k) if n_ is n else (r, n_, k_, last_) for r, n_, k_, last_ in out]
    return axis, out


def passo_file(out):
    """La distanza tipica fra due file consecutive dello stesso settore (m)."""
    per_n = {}
    for seg, n, _, _ in out:
        per_n.setdefault(id(n), []).append(float(np.dot((np.array(seg[:2]) + np.array(seg[2:4])) / 2, n)))
    gaps = []
    for qs in per_n.values():
        qs = sorted(set(round(q, 2) for q in qs))
        gaps += [b - a for a, b in zip(qs, qs[1:]) if b - a > 0.35]
    return float(np.median(gaps)) if gaps else 1.0


TAVOLO, SEDIA_ROSSA, SEDIA_VERDE = "#C4C7C8", "#C8463A", "#4E9A5B"


def tavoli(rows, height, out):
    """Le aule con i tavoli: due linee a 60 cm sono i bordi di un tavolo; dietro, le sedie.
    Come nella foto delle aule dell'Edificio 11 (MiBACT 2020): piani grigi su gambe nere,
    sedie nere con qualcuna rossa o verde."""
    per_n = {}
    for seg, n, k, _ in rows:
        per_n.setdefault(id(n), (n, []))[1].append(seg)
    for n, segs in per_n.values():
        segs.sort(key=lambda r: float(np.dot((np.array(r[:2]) + np.array(r[2:4])) / 2, n)))
        i = 0
        while i < len(segs):
            r = segs[i]
            q0 = float(np.dot((np.array(r[:2]) + np.array(r[2:4])) / 2, n))
            depth = 0.6
            if i + 1 < len(segs):
                r2 = segs[i + 1]
                q1 = float(np.dot((np.array(r2[:2]) + np.array(r2[2:4])) / 2, n))
                if 0.35 < q1 - q0 < 0.8:
                    depth, i = q1 - q0, i + 1
            i += 1
            a, c = np.array(r[:2], float), np.array(r[2:4], float)
            L = np.linalg.norm(c - a)
            u = (c - a) / L
            zf = height((a + c) / 2)
            q = lambda d0, d1: [tuple(a + n * d0), tuple(c + n * d0), tuple(c + n * d1), tuple(a + n * d1)]
            out[TAVOLO].append(hexa([(*p, zf + 0.72) for p in q(0, depth)], [(*p, zf + 0.76) for p in q(0, depth)]))
            for e in (a + n * depth / 2 + u * 0.05, c + n * depth / 2 - u * 0.05):
                out[CORRIMANO].append(box_z(e[0], e[1], 0.05, 0.05, zf, zf + 0.72))
            posti = max(1, int(L / 0.6))
            for j in range(posti):
                b = a + u * (L / posti * (j + 0.5) - 0.22)
                e = b + u * 0.44
                rr = lambda d0, d1: [tuple(b + n * d0), tuple(e + n * d0), tuple(e + n * d1), tuple(b + n * d1)]
                sedia = (SEDIA_ROSSA, SEDIA_VERDE, *[CORRIMANO] * 8)[int(abs(b[0] * 7.3 + b[1] * 3.1)) % 10]
                out[sedia].append(hexa([(*p, zf + 0.42) for p in rr(depth + 0.15, depth + 0.6)], [(*p, zf + 0.47) for p in rr(depth + 0.15, depth + 0.6)]))
                out[sedia].append(hexa([(*p, zf + 0.47) for p in rr(depth + 0.55, depth + 0.6)], [(*p, zf + 0.9) for p in rr(depth + 0.55, depth + 0.6)]))


def gradoni(poly, z, segs):
    """Il pavimento di un'aula: piano, o a gradoni se la pianta disegna le file di banchi.
    Ogni fila sta su un gradino che sale di RISE da quello davanti; davanti alla prima fila
    il piano della cattedra. Torna (mesh, quota di un punto)."""
    floor = z + SOLETTA
    rows = file_di_banchi(poly, segs)
    base = poly.buffer(-0.02)
    if not rows:
        return slab(base, floor, floor + 0.05, COL["aula"]), (lambda p: floor + 0.05)
    _, out = rows
    if passo_file(out) < 0.7:
        # File a 60 cm: la pianta disegna i due bordi di tavoli, non gradoni (le aule con i
        # tavoli dell'Edificio 11). Pavimento piano.
        def piano_(p):
            return floor + 0.05
        piano_.rise = 0
        piano_.levels = {0: (base, floor + 0.05)}
        asse = sum(np.array(n, float) for _, n, _, _ in out)
        piano_.asse = asse / (np.linalg.norm(asse) or 1)
        piano_.tavoli = True
        return slab(base, floor, floor + 0.05, COL["aula"]), piano_
    rise = min(RISE, 2.6 / (1 + max(k for _, _, k, _ in out)))
    strips = {}
    for r, n, k, last in out:
        a, c = np.array(r[:2]), np.array(r[2:4])
        u = (c - a) / np.linalg.norm(c - a)
        a, c = a - u * 0.7, c + u * 0.7          # i corridoi tra i settori salgono con le file
        depth = 6 if last else 0.95
        strips.setdefault(k + 1, []).append(Polygon([tuple(a - n * 0.05), tuple(c - n * 0.05), tuple(c + n * depth), tuple(a + n * depth)]))
    levels, taken = {}, Polygon()
    for k in sorted(strips, reverse=True):
        reg = unary_union(strips[k]).intersection(base).difference(taken)
        taken = taken.union(reg)
        levels[k] = reg
    levels[0] = base.difference(taken)
    parts = [slab(reg, floor, floor + 0.05 + k * rise, COL["aula"]) for k, reg in levels.items() if not reg.is_empty]
    parts = [m for m in parts if m is not None]

    def height(p):
        pt = Point(p[:2])
        for k, reg in levels.items():
            if reg.distance(pt) < 0.01:
                return floor + 0.05 + k * rise
        return floor + 0.05
    height.rise = rise
    asse = sum(np.array(n, float) for _, n, _, _ in out)
    height.asse = asse / (np.linalg.norm(asse) or 1)    # dalla cattedra verso il fondo, in media
    height.levels = {k: (reg, floor + 0.05 + k * rise) for k, reg in levels.items()}
    height.fronte = (levels[0], floor + 0.05)      # il piano della cattedra, davanti alle file
    return colour(trimesh.util.concatenate(parts), COL["aula"]), height


def banchi(rows, height, out):
    """Quello che le foto mostrano in ogni fila: il parapetto bianco del banco sul bordo del
    gradino, il piano del banco, e dietro le sedie una per una, larghe mezzo metro."""
    for (x0, y0, x1, y1), n, _, _ in rows:
        a, c = np.array([x0, y0]), np.array([x1, y1])
        L = np.linalg.norm(c - a)
        u = (c - a) / L
        zf = height((a + c) / 2 + n * 0.5)
        q = lambda d0, d1: [tuple(a + n * d0), tuple(c + n * d0), tuple(c + n * d1), tuple(a + n * d1)]
        out[DESK].append(hexa([(*p, zf + 0.72) for p in q(-0.05, 0.4)], [(*p, zf + 0.76) for p in q(-0.05, 0.4)]))
        out[DESK].append(hexa([(*p, zf) for p in q(-0.08, -0.04)], [(*p, zf + 0.72) for p in q(-0.08, -0.04)]))
        posti = max(1, int(L / 0.6))
        passo = L / posti
        for i in range(posti):
            b = a + u * (passo * (i + 0.5) - 0.23)
            e = b + u * 0.46
            r = lambda d0, d1: [tuple(b + n * d0), tuple(e + n * d0), tuple(e + n * d1), tuple(b + n * d1)]
            out[SEAT].append(hexa([(*p, zf + 0.42) for p in r(0.5, 0.95)], [(*p, zf + 0.47) for p in r(0.5, 0.95)]))
            out[SEAT].append(hexa([(*p, zf + 0.47) for p in r(0.9, 0.95)], [(*p, zf + 0.92) for p in r(0.9, 0.95)]))


def scalette(poly, segs, height, out):
    """I corridoi delle aule a gradoni: la pianta disegna in ogni fila un rettangolo (circa
    1,3 x 0,3 m), il gradino intermedio che divide in due l'alzata della fila. Come nelle foto,
    i gradini del corridoio sono grigio scuro e il corrimano nero corre sul lato dei banchi,
    lontano dal muro, su un montante per gradino. La riga in mezzo ai rettangoli è la freccia
    di percorrenza della pianta, non un corrimano."""
    rise = getattr(height, "rise", 0)
    if not rise:
        return
    inner = poly.buffer(-0.05)
    lines = [LineString([s_[:2], s_[2:4]]) for s_ in segs if inner.contains(LineString([s_[:2], s_[2:4]]).centroid)]
    pezzi = [g for g in polygonize(unary_union(lines)) if 0.1 < g.area < 1.0]
    if not pezzi:
        return
    uniti = unary_union([g.buffer(0.03) for g in pezzi]).buffer(-0.03)
    steps = [g for g in getattr(uniti, "geoms", [uniti]) if 0.25 < g.area < 1.0 and g.minimum_rotated_rectangle.area < 1.3 * g.area]
    posti = []
    for g in steps:
        corners = list(g.minimum_rotated_rectangle.exterior.coords)[:4]
        z0 = min(height(c) for c in corners)          # il gradino sta sul gradone davanti
        top = z0 + rise / 2
        m = trimesh.creation.extrude_polygon(clean(g)[0], top - (z0 - 0.05)).apply_translation([0, 0, z0 - 0.05])
        out[SCALINO].append(m)
        # il lato lungo del gradino; il corrimano sta all'estremo più lontano dal muro
        sides = [(corners[k], corners[(k + 1) % 4]) for k in range(4)]
        a_, b_ = max(sides, key=lambda s_: math.dist(*s_))
        mid_short = lambda p_, q_: ((p_[0] + q_[0]) / 2, (p_[1] + q_[1]) / 2)
        e0 = mid_short(corners[0], corners[3]) if math.dist(corners[0], corners[1]) > math.dist(corners[1], corners[2]) else mid_short(corners[0], corners[1])
        e1 = mid_short(corners[1], corners[2]) if math.dist(corners[0], corners[1]) > math.dist(corners[1], corners[2]) else mid_short(corners[2], corners[3])
        far = max((e0, e1), key=lambda e: poly.exterior.distance(Point(e)))
        c = g.centroid
        posti.append((c.x + (far[0] - c.x) * 0.85, c.y + (far[1] - c.y) * 0.85, top))
    # i gradini dello stesso corridoio, uno per fila, a meno di 1,3 m l'uno dall'altro
    left = list(range(len(posti)))
    while left:
        chain = [left.pop(0)]
        frontier = list(chain)
        while frontier:
            k = frontier.pop()
            for j_ in [j_ for j_ in left if math.dist(posti[k][:2], posti[j_][:2]) < 1.3]:
                left.remove(j_)
                chain.append(j_)
                frontier.append(j_)
        if len(chain) < 3:
            continue
        chain.sort(key=lambda j_: posti[j_][2])
        for a_, b_ in zip(chain, chain[1:]):
            (x0, y0, z0), (x1, y1, z1) = posti[a_], posti[b_]
            d = np.array([x1 - x0, y1 - y0])
            if np.linalg.norm(d) < 0.3:
                continue
            nrm = np.array([-d[1], d[0]]) / np.linalg.norm(d) * 0.025
            q = [(x0 - nrm[0], y0 - nrm[1]), (x1 - nrm[0], y1 - nrm[1]), (x1 + nrm[0], y1 + nrm[1]), (x0 + nrm[0], y0 + nrm[1])]
            zz = [z0, z1, z1, z0]
            out[CORRIMANO].append(hexa([(*p_, h + 0.88) for p_, h in zip(q, zz)], [(*p_, h + 0.92) for p_, h in zip(q, zz)]))
        for j_ in chain:
            x, y, zt = posti[j_]
            post = [(x - 0.02, y - 0.02), (x + 0.02, y - 0.02), (x + 0.02, y + 0.02), (x - 0.02, y + 0.02)]
            out[CORRIMANO].append(hexa([(*p_, zt) for p_ in post], [(*p_, zt + 0.9) for p_ in post]))


# L'Aula Magna Giampiero Pesenti (2020): due aule e l'atrio fra loro, uniti. Le piante del
# Politecnico non la nominano; la riconosciamo al primo piano, dove T.2.1 e T.2.2 si guardano
# con i pilastri tondi davanti, come nelle foto: colonne bianche, sedute bianche sciolte sul
# pavimento piano in mezzo, le gradonate ai lati, il palco con il leggio e lo schermo.
AULA_MAGNA = ("MIA0203001006", "MIA0203001026")
POLTRONA, TELO, PALCO = "#F6F6F4", "#ECEEF0", "#2A2C2F"    # il palco è nero nelle foto


def aula_magna(fronti, atrio, colonne, z, out):
    """Le poltrone bianche in file sul piano fra le due aule, rivolte al palco a ovest."""
    if len(fronti) < 2:
        return Polygon()
    a, b = fronti[0][0].centroid, fronti[1][0].centroid
    piano = unary_union([g for g, _ in fronti] + [atrio.intersection(box(min(a.x, b.x) - 8, min(a.y, b.y), max(a.x, b.x) + 2, max(a.y, b.y)))])
    piano = piano.buffer(0.3).buffer(-0.3)
    zf = max(zz for _, zz in fronti)
    x0, y0, x1, y1 = piano.bounds
    yc = (y0 + y1) / 2
    x0 = asse_magna(piano, yc)[0]      # l'estremo ovest della fascia fra le due aule
    # il palco: 3 m all'estremo ovest, alto 30 cm, con il leggio e lo schermo
    palco = piano.intersection(box(x0 - 10, yc - 5, x0 + 3.0, yc + 5))
    for g in clean(palco):
        out[PALCO].append(trimesh.creation.extrude_polygon(g, 0.3).apply_translation([0, 0, zf]))
    out[DESK].append(box_z(x0 + 1.6, yc + 1.2, 0.5, 0.7, zf + 0.3, zf + 1.45))
    out[TELO].append(box_z(x0 + 0.4, yc, 0.06, 4.0, zf + 1.5, zf + 1.5 + 2.2))     # il telo bianco appeso
    libero = piano.buffer(-0.5).difference(unary_union(colonne).buffer(0.5) if colonne else Polygon())
    x = x0 + 4.5
    while x < x1 - 0.6:
        y = y0
        while y < y1:
            if abs(y + 0.3 - yc) > 0.7 and libero.contains(box(x, y, x + 0.6, y + 0.6)):
                out[POLTRONA].append(box_z(x + 0.3, y + 0.3, 0.55, 0.58, zf, zf + 0.45))
                out[POLTRONA].append(box_z(x + 0.52, y + 0.3, 0.12, 0.58, zf + 0.45, zf + 0.95))
            y += 0.62
        x += 0.95
    return piano


def asse_magna(piano, yc):
    """Dove la linea di mezzo dell'Aula Magna (y = yc) entra ed esce dalla sala: (ovest, est)."""
    x0, _, x1, _ = piano.bounds
    tratto = piano.intersection(LineString([(x0 - 1, yc), (x1 + 1, yc)]))
    tratti = [g for g in getattr(tratto, "geoms", [tratto]) if g.length > 0]
    if not tratti:
        return x0, x1
    lungo = max(tratti, key=lambda g: g.length)
    xs = [c[0] for c in lungo.coords]
    return min(xs), max(xs)


def box_z(cx, cy, dx, dy, z0, z1):
    q = [(cx - dx / 2, cy - dy / 2), (cx + dx / 2, cy - dy / 2), (cx + dx / 2, cy + dy / 2), (cx - dx / 2, cy + dy / 2)]
    return hexa([(*p, z0) for p in q], [(*p, z1) for p in q])


CABINA = "#858C95"        # le cabine in acciaio


def ascensori(segs, corridoi, z, out):
    """Gli ascensori: la pianta disegna su ogni piano la croce del vano (linee.ascensori).
    Ogni croce è un vano: pareti sottili tutt'intorno, la porta sul lato che dà sul corridoio
    (o sul lato lungo), la cabina in acciaio dentro. Tagliati all'altezza dei muri."""
    if not segs:
        return []
    croci = unary_union([LineString([s_[:2], s_[2:4]]).buffer(0.05) for s_ in segs])
    vani = []
    for g in getattr(croci, "geoms", [croci]):
        h = g.convex_hull
        if h.area < 1.0:
            continue
        rect = h.minimum_rotated_rectangle
        vani.append(rect)
        c = list(rect.exterior.coords)[:4]
        lati = [(c[k], c[(k + 1) % 4]) for k in range(4)]
        centro = np.array(rect.centroid.coords[0])

        def fuori(lato, d=0.7):
            m = (np.array(lato[0]) + np.array(lato[1])) / 2
            v = m - centro
            return Point(*(m + v / (np.linalg.norm(v) or 1) * d))
        porta = max(lati, key=lambda l_: (corridoi.contains(fuori(l_)), math.dist(*l_)))
        pareti = rect.buffer(0.12, join_style=2).difference(rect)
        a_, b_ = np.array(porta[0]), np.array(porta[1])
        m = (a_ + b_) / 2
        u = (b_ - a_) / np.linalg.norm(b_ - a_)
        varco = LineString([tuple(m - u * 0.45), tuple(m + u * 0.45)]).buffer(0.3, cap_style=2)
        for q in clean(pareti.difference(varco)):
            out[COL["muri"]].append(trimesh.creation.extrude_polygon(q, MURO).apply_translation([0, 0, z]))
        for q in clean(rect.buffer(-0.08, join_style=2)):
            out[CABINA].append(trimesh.creation.extrude_polygon(q, MURO - 0.05).apply_translation([0, 0, z]))
    return vani


def cattedra(poly, rows, height, out):
    """Davanti alla prima fila: il leggio e, sulla parete di fondo, lo schermo scuro."""
    prime = [(r, n) for r, n, k, _ in rows if k == 0]
    if not prime:
        return
    r, n = max(prime, key=lambda t: math.dist(t[0][:2], t[0][2:4]))
    a, c = np.array(r[:2]), np.array(r[2:4])
    u = (c - a) / np.linalg.norm(c - a)
    mid = (a + c) / 2
    dentro = poly.buffer(-0.25)
    muro = max((t / 10 for t in range(10, 150) if dentro.contains(Point(mid - n * t / 10))), default=0)
    for dist_, (w, d, h, key) in ((2.0, (0.7, 0.35, 1.15, DESK)), (muro, (3.2, 0.12, 1.6, SCHERMO))):
        p0 = mid - n * dist_
        if dist_ < 1.5 or not dentro.contains(Point(p0)):
            continue
        zf = height(p0)
        base = [tuple(p0 - u * w / 2 - n * d / 2), tuple(p0 + u * w / 2 - n * d / 2),
                tuple(p0 + u * w / 2 + n * d / 2), tuple(p0 - u * w / 2 + n * d / 2)]
        z0 = zf + (1.0 if key is SCHERMO else 0)
        out[key].append(hexa([(*p, z0) for p in base], [(*p, z0 + h) for p in base]))


def rampe(segs, inside):
    """Le rampe disegnate nella pianta: pedate parallele, una dietro l'altra a 25-45 cm, che
    si sovrappongono per tutta la larghezza. Ogni rampa: direzione delle pedate u, direzione
    di salita n, estensione [lo, hi] lungo u e posizione q di ogni pedata lungo n."""
    T = []
    for s_ in segs:
        a, c = np.array(s_[:2], float), np.array(s_[2:4], float)
        L = float(np.linalg.norm(c - a))
        if not 0.7 < L < 4.5 or not inside.contains(Point((a + c) / 2)):
            continue
        u = (c - a) / L
        if u[int(abs(u[1]) > abs(u[0]))] < 0:
            a, c, u = c, a, -u
        T.append((a, c, u, L))
    used, out = [False] * len(T), []
    for i in range(len(T)):
        if used[i]:
            continue
        used[i] = True
        group, frontier = [i], [i]
        while frontier:
            a, c, u, L = T[frontier.pop()]
            n = np.array([-u[1], u[0]])
            span = sorted([float(np.dot(a, u)), float(np.dot(c, u))])
            for j, (b, e, v, M) in enumerate(T):
                if used[j] or abs(np.dot(u, v)) < 0.99:
                    continue
                if not 0.15 < abs(float(np.dot((b + e) / 2 - (a + c) / 2, n))) < 0.45:
                    continue
                other = sorted([float(np.dot(b, u)), float(np.dot(e, u))])
                if min(span[1], other[1]) - max(span[0], other[0]) > 0.75 * min(L, M):
                    used[j] = True
                    group.append(j)
                    frontier.append(j)
        u = T[group[0]][2]
        n = np.array([-u[1], u[0]])
        qs = []
        for q in sorted(float(np.dot((T[k][0] + T[k][1]) / 2, n)) for k in group):
            if not qs or q - qs[-1] > 0.15:      # pedate disegnate due volte
                qs.append(q)
        if len(qs) < 3:
            continue
        ends = [float(np.dot(p_, u)) for k in group for p_ in T[k][:2]]
        out.append({"u": u, "n": n, "lo": min(ends), "hi": max(ends), "q": qs,
                    "t": float(np.median(np.diff(qs)))})
    return out


def _sovrapposti(a0, a1, b0, b1):
    return min(a1, b1) - max(a0, b0)


def scale(segs, inside, corridoi, z, H, out):
    """Le scale vere, dalle rampe della pianta. Rampe allineate una dopo l'altra fanno una
    scala dritta con i pianerottoli in mezzo; due scale affiancate fanno una scala a due
    rampe (a U) quando insieme salgono un piano con alzate di 15-24 cm: la prima sale dal lato
    aperto verso il corridoio, il pianerottolo a metà piano, la seconda torna indietro e
    arriva al piano di sopra. Le altre salgono da sole, con alzate fra 12 e 18 cm. Gradini
    pieni in pietra chiara, corrimano in metallo su entrambi i lati. Torna le impronte."""
    F = rampe(segs, inside)
    # scale dritte: rampe in fila lungo la salita
    runs = [[f] for f in F]
    merged = True
    while merged:
        merged = False
        for a in runs:
            for b in runs:
                if a is b:
                    continue
                fa, fb = a[-1], b[0]
                if abs(np.dot(fa["n"], fb["n"])) < 0.99 or _sovrapposti(fa["lo"], fa["hi"], fb["lo"], fb["hi"]) < 0.5 * min(fa["hi"] - fa["lo"], fb["hi"] - fb["lo"]):
                    continue
                if fb["n"].dot(fa["n"]) < 0:
                    fb.update(n=-fb["n"], u=-fb["u"], q=sorted(-q for q in fb["q"]), lo=-fb["hi"], hi=-fb["lo"])
                if -0.5 < fb["q"][0] - fa["q"][-1] <= 0.4:
                    # la stessa rampa spezzata dalla linea di taglio della pianta
                    qs = []
                    for q in sorted(fa["q"] + fb["q"]):
                        if not qs or q - qs[-1] > 0.15:
                            qs.append(q)
                    fa.update(q=qs, lo=min(fa["lo"], fb["lo"]), hi=max(fa["hi"], fb["hi"]))
                    a.extend(b[1:])
                    runs = [r for r in runs if r is not b]
                    merged = True
                    break
                if 0.4 < fb["q"][0] - fa["q"][-1] < 3.0:
                    a.extend(b)
                    runs = [r for r in runs if r is not b]
                    merged = True
                    break
            if merged:
                break
    alzate = lambda r: sum(len(f["q"]) + 1 for f in r) - sum(1 for x, y in zip(r, r[1:]) if y["q"][0] - x["q"][-1] - x["t"] < 0.3)
    span = lambda r: (r[0]["q"][0], r[-1]["q"][-1] + r[-1]["t"])
    lat = lambda r: (min(f["lo"] for f in r), max(f["hi"] for f in r))
    n_of = lambda r: r[0]["n"]
    R = H / 0.17
    coppie, sole = [], list(runs)
    for a in runs:
        for b in runs:
            if a is b or not any(r is a for r in sole) or not any(r is b for r in sole) or abs(np.dot(n_of(a), n_of(b))) < 0.99:
                continue
            if np.dot(n_of(a), n_of(b)) < 0:
                continue
            la, lb = lat(a), lat(b)
            sa, sb = span(a), span(b)
            gap = max(la[0], lb[0]) - min(la[1], lb[1])
            if -0.1 < gap < 1.0 and _sovrapposti(*sa, *sb) > 0.5 * min(sa[1] - sa[0], sb[1] - sb[0]) \
                    and 0.7 * R <= alzate(a) + alzate(b) <= 1.4 * R:
                coppie.append((a, b))
                sole = [r for r in sole if r is not a and r is not b]
    impronte = []

    def gradini(run, z0, rise, d, lat_):
        """Una scala dritta che sale nel verso d (+1 lungo n, -1 contro) da quota z0."""
        u, n = run[0]["u"], run[0]["n"]
        fl = run if d > 0 else list(reversed(run))
        h, prev = z0, None
        for f in fl:
            qs = f["q"] if d > 0 else sorted(f["q"], reverse=True)
            if prev is not None and abs(qs[0] - prev) > 0.3:
                land = sorted([prev, qs[0] if d > 0 else qs[0] - f["t"]])   # pianerottolo intermedio
                out[COL["scale"]].append(blocco(u, n, f["lo"], f["hi"], land[0], land[1], z, h))
            for q in qs:
                if d < 0:
                    q -= f["t"]
                h += rise
                out[COL["scale"]].append(blocco(u, n, f["lo"], f["hi"], q, q + f["t"], z, h))
            prev = qs[-1] + d * f["t"]
            # corrimano sui due lati della rampa, inclinato come i gradini
            for side in (f["lo"] + 0.05, f["hi"] - 0.05):
                q0, q1 = qs[0], qs[-1]
                h0, h1 = h - rise * (len(qs) - 1), h
                bar = [tuple(u * (side - 0.025) + n * q0), tuple(u * (side - 0.025) + n * q1),
                       tuple(u * (side + 0.025) + n * q1), tuple(u * (side + 0.025) + n * q0)]
                zz = [h0, h1, h1, h0]
                out[METALLO].append(hexa([(*p, zh + 0.9) for p, zh in zip(bar, zz)], [(*p, zh + 0.95) for p, zh in zip(bar, zz)]))
                for qq, hh in ((q0, h0), (q1, h1)):
                    post = [tuple(u * (side - 0.02) + n * (qq - 0.02)), tuple(u * (side + 0.02) + n * (qq - 0.02)),
                            tuple(u * (side + 0.02) + n * (qq + 0.02)), tuple(u * (side - 0.02) + n * (qq + 0.02))]
                    out[METALLO].append(hexa([(*p, hh) for p in post], [(*p, hh + 0.9) for p in post]))
        return h

    def lato_aperto(q_lo, q_hi, centre_lat, u, n):
        """+1 se il lato aperto (verso il corridoio) è quello in basso lungo n."""
        pt = lambda q: Point(*(u * centre_lat + n * q))
        d_lo = corridoi.distance(pt(q_lo - 0.8)) if not corridoi.is_empty else 0
        d_hi = corridoi.distance(pt(q_hi + 0.8)) if not corridoi.is_empty else 1
        return 1 if d_lo <= d_hi else -1

    for a, b in coppie:
        u, n = a[0]["u"], n_of(a)
        lo = min(span(a)[0], span(b)[0])
        hi = max(span(a)[1], span(b)[1])
        la, lb = lat(a), lat(b)
        d = lato_aperto(lo, hi, (min(la[0], lb[0]) + max(la[1], lb[1])) / 2, u, n)
        rise = H / (alzate(a) + alzate(b))
        mid = gradini(a, z, rise, d, la)
        # pianerottolo a metà piano, in fondo alle due rampe
        depth = min(1.8, max(la[1] - la[0], lb[1] - lb[0]))
        land = (hi, hi + depth) if d > 0 else (lo - depth, lo)
        land_poly = Polygon([tuple(u * min(la[0], lb[0]) + n * land[0]), tuple(u * max(la[1], lb[1]) + n * land[0]),
                             tuple(u * max(la[1], lb[1]) + n * land[1]), tuple(u * min(la[0], lb[0]) + n * land[1])])
        if inside.buffer(0.5).contains(land_poly.centroid):
            out[COL["scale"]].append(blocco(u, n, min(la[0], lb[0]), max(la[1], lb[1]), land[0], land[1], z, mid + rise))
        gradini(b, mid + rise, rise, -d, lb)
        impronte.append(unary_union([poly_run(a), poly_run(b), land_poly]))
    for r in sole:
        u, n = r[0]["u"], r[0]["n"]
        s0, s1 = span(r)
        l0, l1 = lat(r)
        rise = min(0.18, max(0.12, H / alzate(r))) if len(r) > 1 or sum(len(f["q"]) for f in r) > 6 else 0.17
        top = gradini(r, z, rise, lato_aperto(s0, s1, (l0 + l1) / 2, u, n), (l0, l1))
        impronte.append(poly_run(r))
    return impronte


def poly_run(run):
    u, n = run[0]["u"], run[0]["n"]
    q0, q1 = run[0]["q"][0], run[-1]["q"][-1] + run[-1]["t"]
    l0, l1 = min(f["lo"] for f in run), max(f["hi"] for f in run)
    return Polygon([tuple(u * l0 + n * q0), tuple(u * l1 + n * q0), tuple(u * l1 + n * q1), tuple(u * l0 + n * q1)])


def blocco(u, n, l0, l1, q0, q1, z0, z1):
    q = [tuple(u * l0 + n * q0), tuple(u * l1 + n * q0), tuple(u * l1 + n * q1), tuple(u * l0 + n * q1)]
    return hexa([(*p, z0) for p in q], [(*p, z1) for p in q])


CEMENTO_SOFF, LUCE = "#D8D7D2", "#FBFBF8"


def fodera(poly, z, top, porte, vetri, out, muro=None, maschera=None):
    """I muri di un locale a tutta altezza: una fodera di 6 cm dentro, così non tocca i muri
    tagliati, con i varchi delle porte (muro sopra i 2,3 m) e le finestre (davanzale a 0,9 m,
    vetro fino a 2,05 m)."""
    muro = muro or COL["muri"]
    f_ = poly.difference(poly.buffer(-0.06, join_style=2))
    if maschera is not None:          # solo un tratto, per un muro di altro colore
        f_ = f_.intersection(maschera)
    varchi = f_.intersection(porte.buffer(0.1)) if not porte.is_empty else Polygon()
    vetrate = f_.intersection(vetri.buffer(0.3)).difference(varchi) if not vetri.is_empty else Polygon()
    for q in clean(f_.difference(varchi).difference(vetrate)):
        out[muro].append(trimesh.creation.extrude_polygon(q, top - z).apply_translation([0, 0, z]))
    for q in clean(varchi):
        out[muro].append(trimesh.creation.extrude_polygon(q, top - z - 2.3).apply_translation([0, 0, z + 2.3]))
    for q in clean(vetrate):
        out[muro].append(trimesh.creation.extrude_polygon(q, 0.9).apply_translation([0, 0, z]))
        out[VETRO].append(trimesh.creation.extrude_polygon(q, 1.15).apply_translation([0, 0, z + 0.9]))
        out[muro].append(trimesh.creation.extrude_polygon(q, top - z - 2.05).apply_translation([0, 0, z + 2.05]))


def griglia(region, passo, largo, angolo):
    """Strisce parallele e incrociate su una regione, ruotate di un angolo (gradi)."""
    from shapely import affinity
    c = region.centroid
    r = affinity.rotate(region, -angolo, origin=c)
    x0, y0, x1, y1 = r.bounds
    linee = [LineString([(x, y0 - 1), (x, y1 + 1)]).buffer(largo / 2, cap_style=2) for x in np.arange(x0, x1, passo)]
    return [affinity.rotate(g, angolo, origin=c) for g in linee]


CEMENTO_PARETE = "#A8A7A2"     # i pannelli di cemento della parete dell'Aula Magna
PATIO = "#8F9295"              # il pavimento grigio scuro del patio dell'Edificio 11


def interno_magna(sala, piano, z, z_tetto, porte, vetri):
    """L'Aula Magna da dentro, come nelle foto: il soffitto a cassettoni in cemento in
    diagonale con le luci lineari che lo attraversano, i muri bianchi a tutta altezza e la
    parete di pannelli di cemento vicino al palco, a ovest. L'occhio in fondo, nel corridoio
    centrale fra le poltrone, verso il palco."""
    out = {COL["muri"]: [], CEMENTO_SOFF: [], LUCE: [], VETRO: [], CEMENTO_PARETE: []}
    top = z_tetto
    for q in clean(sala):
        out[CEMENTO_SOFF].append(trimesh.creation.extrude_polygon(q, 0.25).apply_translation([0, 0, top - 0.25]))
    dentro = sala.buffer(-0.1)
    nerv = unary_union(griglia(sala, 1.3, 0.16, 45) + griglia(sala, 1.3, 0.16, -45)).intersection(dentro)
    for q in clean(nerv):
        out[CEMENTO_SOFF].append(trimesh.creation.extrude_polygon(q, 0.4).apply_translation([0, 0, top - 0.65]))
    for g_ in griglia(sala, 5.2, 0.08, 30):
        for q in clean(g_.intersection(sala.buffer(-1.0))):
            out[LUCE].append(trimesh.creation.extrude_polygon(q, 0.05).apply_translation([0, 0, top - 0.75]))
    _, y0, _, y1 = piano.bounds
    yc = (y0 + y1) / 2
    x0, x1 = asse_magna(piano, yc)
    palco = box(x0 - 10, yc - 6, x0 + 4, yc + 6)
    fodera(sala, z, top, porte, vetri, out, maschera=sala.buffer(1).difference(palco))
    fodera(sala, z, top, porte, vetri, out, CEMENTO_PARETE, maschera=palco)
    occhio = [round(x1 - 1.2, 2), round(z + 1.65, 2), round(yc, 2)]
    guarda = [round(x0 + 0.5, 2), round(z + 2.2, 2), round(yc, 2)]
    return out, occhio, guarda


def interno(poly, height, sopra, z, z_tetto, porte, vetri, travi=False):
    """Quello che si vede entrando in un'aula a gradoni (le foto delle aule e dell'Aula
    Magna): i muri a tutta altezza, foderati da dentro, con le porte e le finestre; il
    soffitto, a cassettoni in cemento dove sopra c'è il tetto, altrimenti il sotto delle
    gradonate dell'aula di sopra, che salgono come queste; le luci lineari appese.
    Torna ({colore: [mesh]}, occhio, guarda): l'occhio in piedi dietro l'ultima fila, lo
    sguardo sulla cattedra."""
    out = {COL["muri"]: [], CEMENTO_SOFF: [], LUCE: [], VETRO: [], STEEL: [], "#F4F4F1": []}
    levels = getattr(height, "levels", None)
    if not levels:
        return None
    # il soffitto: sotto le gradonate dell'aula di sopra, o piano sotto il tetto; mai a meno
    # di 2,6 m dal gradino sotto (le piante non quotano le alzate, che qui sono stimate)
    pezzi, coperto = [], Polygon()
    for reg_up, z_up in sopra:
        part = reg_up.intersection(poly)
        if part.area > 0.5:
            coperto = coperto.union(part)
            for reg, z_low in levels.values():
                pp = part.intersection(reg)
                if pp.area > 0.05:
                    pezzi.append((pp, max(z_up - 0.4, z_low + 2.6)))
    resto = poly.difference(coperto)
    if resto.area > 0.5:
        for reg, z_low in levels.values():
            pp = resto.intersection(reg)
            if pp.area > 0.05:
                pezzi.append((pp, max(z_tetto, z_low + 2.6)))
    if coperto.is_empty:          # sotto il tetto: un soffitto piano unico, a cassettoni
        pezzi = [(poly, max(zc for _, zc in pezzi))]
    for g_, zc in pezzi:
        for q in clean(g_):
            out["#F4F4F1" if travi else CEMENTO_SOFF].append(trimesh.creation.extrude_polygon(q, 0.25).apply_translation([0, 0, zc - 0.25]))
    if travi and getattr(height, "asse", None) is not None:
        # Le aule dell'Edificio 11 (foto MiBACT): soffitto bianco e travi d'acciaio nere a
        # vista, di traverso alle file, ogni 3,6 m.
        asse = height.asse
        c0 = np.array(poly.centroid.coords[0])
        lato = np.array([-asse[1], asse[0]])
        for t in np.arange(-40, 40, 3.6):
            a_, b_ = c0 + asse * t - lato * 60, c0 + asse * t + lato * 60
            for g_, zc in pezzi:
                for q in clean(LineString([tuple(a_), tuple(b_)]).buffer(0.15, cap_style=2).intersection(g_)):
                    out[STEEL].append(trimesh.creation.extrude_polygon(q, 0.35).apply_translation([0, 0, zc - 0.6]))
    piatto_ok = not travi
    piatto = resto if coperto.is_empty else Polygon()
    z_cass = max((zc for _, zc in pezzi), default=z_tetto)
    if piatto.area > 10 and piatto_ok:
        # i cassettoni: nervature ogni 1,2 m nelle due direzioni delle file
        x0, y0, x1, y1 = piatto.bounds
        ribs = [LineString([(x, y0 - 1), (x, y1 + 1)]).buffer(0.09) for x in np.arange(x0, x1, 1.2)]
        ribs += [LineString([(x0 - 1, y), (x1 + 1, y)]).buffer(0.09) for y in np.arange(y0, y1, 1.2)]
        for q in clean(unary_union(ribs).intersection(piatto.buffer(-0.1))):
            out[CEMENTO_SOFF].append(trimesh.creation.extrude_polygon(q, 0.4).apply_translation([0, 0, z_cass - 0.65]))
    # le luci lineari, appese 45 cm sotto il soffitto, dove resta spazio sopra le teste
    x0, y0, x1, y1 = poly.bounds
    for g_, zc in pezzi:
        for y in np.arange(y0 + 1.5, y1 - 1, 2.4):
            for q in clean(LineString([(x0, y), (x1, y)]).buffer(0.05, cap_style=2).intersection(g_.buffer(-1.0))):
                if zc - 0.5 - height(tuple(q.representative_point().coords[0])) > 2.4:
                    out[LUCE].append(trimesh.creation.extrude_polygon(q, 0.05).apply_translation([0, 0, zc - 0.5]))
    fodera(poly, z, max(zc for _, zc in pezzi), porte, vetri, out)
    fronte, z_f = levels[0]
    k_max = max(levels)
    fondo, z_b = levels[k_max]
    if k_max == 0 and getattr(height, "asse", None) is not None:
        # aula piana: la cattedra sul lato d'inizio delle file, l'occhio sul lato opposto
        asse = height.asse
        c0 = poly.representative_point()
        pts_ = [Point(q) for g_ in clean(poly.buffer(-0.6)) for q in g_.exterior.coords]
        lato = np.array([-asse[1], asse[0]])
        rel = lambda q: np.array([q.x - c0.x, q.y - c0.y])
        dav = min(pts_, key=lambda q: float(np.dot(rel(q), asse)) + 2 * abs(float(np.dot(rel(q), lato))))
        fronte = Point(dav.x + asse[0] * 1.0, dav.y + asse[1] * 1.0).buffer(0.1)
    # in piedi in cima, dietro l'ultima fila: il punto dell'ultimo gradino più lontano dalla
    # cattedra, mezzo metro verso di essa
    f_c = fronte.representative_point()
    bordo = [Point(q) for g_ in clean(fondo.buffer(-0.4)) for q in g_.exterior.coords] or [fondo.representative_point()]
    asse = getattr(height, "asse", None)
    if asse is None:
        b_c = max(bordo, key=lambda q: q.distance(f_c))
    else:
        # in fondo lungo l'asse dell'aula, non in un angolo: guardando la cattedra di fronte
        rel = lambda q: np.array([q.x - f_c.x, q.y - f_c.y])
        lato = np.array([-asse[1], asse[0]])
        b_c = max(bordo, key=lambda q: float(np.dot(rel(q), asse)) - 2 * abs(float(np.dot(rel(q), lato))))
    d_ = np.array([f_c.x - b_c.x, f_c.y - b_c.y])
    b_xy = np.array([b_c.x, b_c.y]) + d_ / (np.linalg.norm(d_) or 1) * 0.5
    guarda = [round(f_c.x, 2), round(z_f + 1.2, 2), round(f_c.y, 2)]
    occhio = [round(float(b_xy[0]), 2), round(z_b + 1.65, 2), round(float(b_xy[1]), 2)]
    return out, occhio, guarda


def vuoti_di(f, shell=None):
    """Dove la pianta non disegna locali per più di un muro (oltre 1,6 m di spessore): il
    piano è aperto su quello sotto, come il pozzo sotto la A di Viganò o il patio."""
    shell = shell if shell is not None else unary_union([ring(r).buffer(0) for r in f["contorno"]])
    rooms = [shape_of(v) for v in f["vani"] if not shape_of(v).is_empty]
    cols = [c for v in f["vani"] for c in pilastri(v)]
    pieno = shell.difference(unary_union(rooms + cols).buffer(0.05))
    return unary_union([g_ for g_ in clean(pieno.buffer(-0.8, join_style=2).buffer(0.8, join_style=2)) if g_.area > 20])


def griglia_pilastri(piani):
    """Le file dei pilastri cruciformi dell'Edificio 11: la pianta del seminterrato ne
    disegna il piede, nella linea delle scale, come due squadre che fanno un quadrato di
    circa 2 m, ma solo lungo i bordi. Piano per piano, perché le linee degli altri piani non
    li tocchino. Torna (xs, ys): le file, a passo costante."""
    squadre = []
    for linee in piani:
        u = unary_union([LineString([s[:2], s[2:4]]).buffer(0.03) for s in linee if math.dist(s[:2], s[2:4]) > 0.01])
        squadre += [c for c in getattr(u, "geoms", [u]) if c.area < 0.6
                    and 1.6 < c.bounds[2] - c.bounds[0] < 2.4 and 1.6 < c.bounds[3] - c.bounds[1] < 2.4]
    centri, presi = [], set()
    for i, a in enumerate(squadre):
        if i in presi:
            continue
        gruppo = [b_ for j, b_ in enumerate(squadre) if j not in presi and a.centroid.distance(b_.centroid) < 3.0]
        presi.update(j for j, b_ in enumerate(squadre) if b_ in gruppo)
        x0, y0, x1, y1 = unary_union(gruppo).bounds
        if abs((x1 - x0) - (y1 - y0)) < 0.4 and x1 - x0 < 2.6:
            centri.append(((x0 + x1) / 2, (y0 + y1) / 2))

    def file(vs):
        # una fila per ogni gruppo di piedi allineati; dove fra due file ne mancano (la
        # pianta disegna il piede solo lungo i bordi), le file a passo costante, 8,5 m
        vs, gr = sorted(vs), []
        for v in vs:
            if gr and v - gr[-1][-1] < 0.8:
                gr[-1].append(v)
            else:
                gr.append([v])
        fs = [sum(g_) / len(g_) for g_ in gr]
        passi = sorted(b_ - a_ for a_, b_ in zip(fs, fs[1:]) if b_ - a_ > 5)
        if not passi:
            return fs
        passo = passi[len(passi) // 2]
        # un piede isolato fuori dal passo di tutte le altre file non fa una fila
        a_passo = lambda d: d > 5 and abs(d / passo - round(d / passo)) * passo < 0.4
        fs = [f_ for f_, g_ in zip(fs, gr) if len(g_) >= 2 or any(a_passo(abs(f_ - o)) for o in fs)]
        out = fs[:1]
        for a_, b_ in zip(fs, fs[1:]):
            n = round((b_ - a_) / passo)
            if n >= 2 and abs((b_ - a_) / n - passo) < 0.3:
                out += [a_ + (b_ - a_) * i / n for i in range(1, n)]
            out.append(b_)
        return out
    return file([c[0] for c in centri]), file([c[1] for c in centri])


def cruciforme(x, y, z0, z1, largo=0.9, spesso=0.22):
    """Un pilastro a croce, due lame incrociate (quelli neri del patio, fatti di squadre)."""
    return [box3d(x - largo / 2, y - spesso / 2, x + largo / 2, y + spesso / 2, z0, z1),
            box3d(x - spesso / 2, y - largo / 2, x + spesso / 2, y + largo / 2, z0, z1)]


def box3d(x0, y0, x1, y1, z0, z1):
    return trimesh.creation.box(extents=[x1 - x0, y1 - y0, z1 - z0]).apply_translation([(x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2])


def vetrata(g, z0, z1, out, passo=1.25):
    """Una vetrata lungo il bordo di una regione: vetro, montanti neri ogni passo, uno
    zoccolo di cemento di 30 cm."""
    for q in clean(g):
        cs = list(q.exterior.coords)
        for a, c in zip(cs, cs[1:]):
            L = math.dist(a, c)
            if L < 0.3:
                continue
            seg = LineString([a, c])
            for p_ in clean(seg.buffer(0.03, cap_style=2)):
                out[VETRO].append(trimesh.creation.extrude_polygon(p_, z1 - z0 - 0.3).apply_translation([0, 0, z0 + 0.3]))
            for p_ in clean(seg.buffer(0.12, cap_style=2)):
                out[CEMENTO_SOFF].append(trimesh.creation.extrude_polygon(p_, 0.3).apply_translation([0, 0, z0]))
            for k in range(int(L / passo) + 1):
                x_, y_ = a[0] + (c[0] - a[0]) * k * passo / L, a[1] + (c[1] - a[1]) * k * passo / L
                trave_z(out[STEEL], (x_, y_, z0), (x_, y_, z1), 0.08)
            trave_z(out[STEEL], (*a, z1 - 0.05), (*c, z1 - 0.05), 0.12)


def tavoli_patio(linee, P, z, out):
    """I tavolini del patio, come li disegna la pianta (60 × 106 cm, a coppie o a
    quattro): piano grigio su gambe nere, e una sedia su ogni lato lungo libero, rossa,
    arancio o verde come nelle foto del MiBACT."""
    ls = [LineString([s[:2], s[2:4]]) for s in linee if math.dist(s[:2], s[2:4]) > 0.05]
    ls = [l_ for l_ in ls if P.intersects(l_)]
    piani = []
    for q in polygonize(unary_union(ls)) if ls else []:
        r = q.minimum_rotated_rectangle
        c = list(r.exterior.coords)
        a, b_ = sorted((math.dist(c[0], c[1]), math.dist(c[1], c[2])))
        if 0.5 < a < 1.0 and 0.9 < b_ < 1.6 and q.area / r.area > 0.95 and P.buffer(-0.3).contains(q.centroid):
            piani.append(r)
    tutti = unary_union(piani).buffer(0.05) if piani else Polygon()
    for r in piani:
        c = [np.array(p_) for p_ in r.exterior.coords[:4]]
        lati = sorted(range(4), key=lambda i: -np.linalg.norm(c[(i + 1) % 4] - c[i]))[:2]
        out[TAVOLO].append(trimesh.creation.extrude_polygon(r, 0.04).apply_translation([0, 0, z + 0.72]))
        for p_ in r.buffer(-0.06, join_style=2).exterior.coords[:4]:
            out[CORRIMANO].append(box_z(p_[0], p_[1], 0.04, 0.04, z, z + 0.72))
        m_ = np.array(r.centroid.coords[0])
        for i in lati:
            a, e = c[i], c[(i + 1) % 4]
            mid = (a + e) / 2
            n = (mid - m_) / (np.linalg.norm(mid - m_) or 1)
            s = mid + n * 0.35
            if tutti.contains(Point(*s)):
                continue                     # il lato tocca un altro tavolo
            u = (e - a) / np.linalg.norm(e - a)
            sedia = (SEDIA_ROSSA, SEDIA_VERDE, ARANCIO)[int(abs(s[0] * 7.3 + s[1] * 3.1)) % 3]
            rr = lambda d0, d1: [tuple(s - u * 0.21 + n * d0), tuple(s + u * 0.21 + n * d0), tuple(s + u * 0.21 + n * d1), tuple(s - u * 0.21 + n * d1)]
            out[sedia].append(hexa([(*p_, z + 0.42) for p_ in rr(-0.2, 0.2)], [(*p_, z + 0.47) for p_ in rr(-0.2, 0.2)]))
            out[sedia].append(hexa([(*p_, z + 0.47) for p_ in rr(0.16, 0.21)], [(*p_, z + 0.88) for p_ in rr(0.16, 0.21)]))
            for d_ in (-0.15, 0.15):
                for v_ in (-0.17, 0.17):
                    g_ = s + u * v_ + n * d_
                    out[CORRIMANO].append(box_z(g_[0], g_[1], 0.02, 0.02, z, z + 0.42))


def togli(g, h):
    """g senza h; senza toccare g quando h è vuoto (gli altri edifici restano identici)."""
    return g.difference(h) if not h.is_empty else g


def tonda(g):
    """Se una pianta è più o meno un cerchio (o un settore): la scala elicoidale."""
    x0, y0, x1, y1 = g.bounds
    w, h = x1 - x0, y1 - y0
    return w > 3 and abs(w - h) < 0.25 * max(w, h) and g.area > 0.45 * math.pi * (max(w, h) / 2) ** 2


CEMENTO_SCALA = "#B4B2AC"      # il cemento a vista della scala elicoidale del patio


def elica(g, P, z0, z1, basso, alto, giro=300):
    """La scala elicoidale del patio dell'Edificio 11, come nella foto del MiBACT: gradini
    di cemento a sbalzo su una soletta che sale a spirale, il parapetto esterno in lamiera
    arancio e quello interno in cemento. Sale in senso antiorario per `giro` gradi e
    arriva sul lato del vuoto più vicino, dove un pianerottolo la lega al ballatoio.
    I gradini fino all'altezza dei muri tagliati vanno in `basso` (la casa delle bambole),
    gli altri in `alto` (l'interno del patio)."""
    for d_ in (basso, alto):
        for k_ in (CEMENTO_SCALA, ARANCIO, STEEL):
            d_.setdefault(k_, [])
    x0, y0, x1, y1 = g.bounds
    c = np.array([(x0 + x1) / 2, (y0 + y1) / 2])
    r1 = max(x1 - x0, y1 - y0) / 2
    r0 = 0.8
    bordo = P.exterior
    q = bordo.interpolate(bordo.project(Point(*c)))
    th1 = math.atan2(q.y - c[1], q.x - c[0])
    n = max(8, round((z1 - z0) / 0.175))
    h = (z1 - z0) / n
    dth = math.radians(giro) / n
    taglio = z0 + MURO
    P2 = lambda r, th: tuple(c + r * np.array([math.cos(th), math.sin(th)]))
    for i in range(n):
        a, b_ = th1 - (n - i) * dth, th1 - (n - i - 1) * dth
        zt = z0 + (i + 1) * h
        out = basso if zt <= taglio else alto
        za, zb = z0 + i * h, zt          # la spirale sotto e i parapetti salgono lisci
        # il gradino sulla soletta: sopra piano, sotto inclinato, spesso 35 cm
        sotto_a, sotto_b = max(z0, za - 0.35), max(z0, zb - 0.35)
        pts = [P2(r0, a), P2(r1, a), P2(r1, b_), P2(r0, b_)]
        out[CEMENTO_SCALA].append(hexa([(*pts[0], sotto_a), (*pts[1], sotto_a), (*pts[2], sotto_b), (*pts[3], sotto_b)],
                                       [(*p_, zt) for p_ in pts]))
        # i parapetti, alti 90 cm sulla linea dei gradini: fuori la lamiera arancio, dentro il cemento
        alto_a, alto_b = za + 0.9, zb + 0.9
        if out is basso:
            alto_a, alto_b = min(alto_a, taglio), min(alto_b, taglio)
        for ra, rb, col in ((r1 - 0.05, r1, ARANCIO), (r0, r0 + 0.12, CEMENTO_SCALA)):
            q_ = [P2(ra, a), P2(rb, a), P2(rb, b_), P2(ra, b_)]
            out[col].append(hexa([(*q_[0], za), (*q_[1], za), (*q_[2], zb), (*q_[3], zb)],
                                 [(*q_[0], alto_a), (*q_[1], alto_a), (*q_[2], alto_b), (*q_[3], alto_b)]))
        if out is alto:
            trave_z(out[STEEL], (*P2(r1 - 0.1, a), za + 0.95), (*P2(r1 - 0.1, b_), zb + 0.95), 0.05)
    # il pianerottolo d'arrivo, dal bordo della scala al ballatoio, coi parapetti arancio
    u = np.array([math.cos(th1), math.sin(th1)])
    v = np.array([-u[1], u[0]])
    p0 = c + u * (r0 + 0.1)
    p1 = np.array(q.coords[0]) + u * 0.3
    pian = Polygon([tuple(p0 + v * 0.1), tuple(p1 + v * 0.1), tuple(p1 - v * (r1 - r0)), tuple(p0 - v * (r1 - r0))])
    alto[CEMENTO_SCALA].append(trimesh.creation.extrude_polygon(pian, 0.45).apply_translation([0, 0, z1 - 0.45]))
    for s_ in (0.1, -(r1 - r0)):
        lato = LineString([tuple(p0 + v * s_), tuple(p1 + v * s_)]).buffer(0.025, cap_style=2)
        alto[ARANCIO].append(trimesh.creation.extrude_polygon(lato, 1.0).apply_translation([0, 0, z1]))


def interno_patio(P, sopra, z, z_sopra, z_tetto, xs, ys):
    """Il patio ribassato dell'Edificio 11 da dentro, come nelle foto del MiBACT: alto due
    piani, dal seminterrato al soffitto nero sotto il primo piano, con le travi nere sulle
    file dei pilastri; i pilastri cruciformi neri, con i grappoli di faretti; il ballatoio del
    piano terra tutto intorno al vuoto, con il parapetto; vetrate nere sui due livelli.
    Il bordo esterno (5 m oltre il vuoto) è un'approssimazione: la pianta lo apre su atri
    e corridoi. Torna ({colore: [mesh]}, occhio, guarda)."""
    out = {STEEL: [], METALLO: [], VETRO: [], CEMENTO_SOFF: [], LUCE: [], CONDOTTI[0]: [], COL["soletta"]: []}
    E = P.buffer(5, join_style=2).intersection(sopra.union(P))
    gall = E.difference(P)
    for q in clean(gall):
        out[COL["soletta"]].append(trimesh.creation.extrude_polygon(q, SOLETTA).apply_translation([0, 0, z_sopra]))
        out[STEEL].append(trimesh.creation.extrude_polygon(q, 0.02).apply_translation([0, 0, z_sopra - 0.02]))
    # il parapetto sul vuoto: corrimano nero a 1 m, montanti ogni 1,5 m
    zg = z_sopra + SOLETTA
    for q in clean(P):
        cs = list(q.exterior.coords)
        for a, c in zip(cs, cs[1:]):
            if math.dist(a, c) < 0.2:
                continue
            trave_z(out[STEEL], (*a, zg + 1.0), (*c, zg + 1.0), 0.06)
            trave_z(out[METALLO], (*a, zg + 0.5), (*c, zg + 0.5), 0.03)
            k_ = max(1, int(math.dist(a, c) / 1.5))
            for j in range(k_):
                x_, y_ = a[0] + (c[0] - a[0]) * j / k_, a[1] + (c[1] - a[1]) * j / k_
                trave_z(out[STEEL], (x_, y_, zg), (x_, y_, zg + 1.0), 0.05)
    # le vetrate tutto intorno, sotto il ballatoio e sopra
    vetrata(E, z, z_sopra, out)
    vetrata(E, zg, z_tetto, out)
    # il soffitto nero e le travi sulle file dei pilastri
    for q in clean(E):
        out[STEEL].append(trimesh.creation.extrude_polygon(q, 0.1).apply_translation([0, 0, z_tetto - 0.1]))
    x0, y0, x1, y1 = E.bounds
    linee = [LineString([(x, y0), (x, y1)]) for x in xs if x0 < x < x1] + [LineString([(x0, y), (x1, y)]) for y in ys if y0 < y < y1]
    for l_ in linee:
        for q in clean(l_.buffer(0.2, cap_style=2).intersection(E.buffer(-0.1))):
            out[STEEL].append(trimesh.creation.extrude_polygon(q, 0.7).apply_translation([0, 0, z_tetto - 0.8]))
    # i pilastri, e sui pilastri del vuoto i grappoli di quattro faretti
    for x in xs:
        for y in ys:
            if not E.buffer(-0.5).contains(Point(x, y)):
                continue
            out[STEEL].extend(cruciforme(x, y, z, z_tetto - 0.8))
            if P.buffer(-0.5).contains(Point(x, y)):
                for zf in (z + 4.2, zg + 3.5):
                    for dx, dy in ((0.35, 0.35), (-0.35, 0.35), (0.35, -0.35), (-0.35, -0.35)):
                        out[CONDOTTI[0]].append(trimesh.creation.cylinder(radius=0.09, height=0.45, sections=12).apply_translation([x + dx, y + dy, zf]))
                        out[LUCE].append(trimesh.creation.cylinder(radius=0.07, height=0.02, sections=12).apply_translation([x + dx, y + dy, zf - 0.235]))
    # in piedi in un angolo del vuoto, verso quello opposto: la scala elicoidale in mezzo
    x0, y0, x1, y1 = P.bounds
    dentro = P.buffer(-2.0)
    pts_ = [Point(x, y) for x in np.arange(x0, x1, 0.5) for y in np.arange(y0, y1, 0.5) if dentro.contains(Point(x, y))]
    lontani = [q for q in pts_ if all(q.distance(Point(x, y)) > 3.0 for x in xs for y in ys)] or pts_
    a = max(lontani, key=lambda q: q.x + q.y)
    b_ = min(pts_, key=lambda q: q.x + q.y)
    occhio = [round(a.x, 2), round(z + 1.65, 2), round(a.y, 2)]
    guarda = [round(b_.x, 2), round(z + 3.5, 2), round(b_.y, 2)]
    return out, occhio, guarda


def aperture(f):
    """Le porte della pianta come varchi nei muri: larghe quanto l'anta, profonde 0,9 m."""
    cuts = []
    for d in f.get("porte", []):
        h, c = d["cardine"], d["chiusa"]
        ux, uy = c[0] - h[0], c[1] - h[1]
        n = math.hypot(ux, uy) or 1
        nx, ny = -uy / n * 0.45, ux / n * 0.45
        cuts.append(Polygon([(h[0] + nx, h[1] + ny), (c[0] + nx, c[1] + ny), (c[0] - nx, c[1] - ny), (h[0] - nx, h[1] - ny)]))
    return unary_union(cuts) if cuts else Polygon()


def edificio(b, aule_info):
    geo = json.loads((SRC / "piante" / f"{b['csie']}-geometria.json").read_text())["piani"]
    if hasattr(guscio_proprio(b), "piante"):                      # piante completate a mano
        guscio_proprio(b).piante(b, sys.modules[__name__], geo, aule_info)
    sc = Scena(b["csie"])
    piani = sc.gruppo("Piani", b["csie"])
    zs = quote(b)
    centre = np.array(ring(b["pianta"]).centroid.coords[0])
    global CENTRO
    CENTRO = centre
    meta = {"csie": b["csie"], "nome": b.get("nome"), "numero": b.get("numero"), "piani": []}
    sotto = []
    # Le gradonate di ogni piano, per il soffitto delle aule sotto.
    gradonate = {}
    for csip, z in zs.items():
        if csip in geo:
            ai = aule_info.get(csip, {})
            for v in geo[csip]["vani"]:
                if v["csiv"] in ai and not shape_of(v).is_empty:
                    _, h_ = gradoni(shape_of(v), z, geo[csip].get("linee", {}).get("arredi", []))
                    gradonate.setdefault(csip, []).extend(getattr(h_, "levels", {}).values())
    # I patii: i vuoti grandi del piano sopra (oltre 300 m²), che fanno di un locale un
    # cortile alto due piani. Solo nell'Edificio 11, con i suoi pilastri cruciformi.
    aperti = {csip: vuoti_di(geo[csip]) for csip in zs if csip in geo}
    griglia = griglia_pilastri([f_.get("linee", {}).get("scale", []) for f_ in geo.values()]) if profilato(b) else ([], [])
    for csip, z in zs.items():
        if csip not in geo:
            continue
        f = geo[csip]
        aule = aule_info.get(csip, {})
        gp = sc.gruppo(csip, piani)
        shell = unary_union([ring(r).buffer(0) for r in f["contorno"]])
        rooms, by_type = [], {}
        lin = f.get("linee", {})
        arredi = {DESK: [], SEAT: [], LEAF: [], LIFT: [], METALLO: [], SCHERMO: [], COL["scale"]: [], VETRO: [], PILASTRO: [], CORRIMANO: [], SCALINO: [], POLTRONA: [], TELO: [], PALCO: [], CABINA: [], COL["muri"]: [], FRAME_GREY: [], STEEL: [], TAVOLO: [], SEDIA_ROSSA: [], SEDIA_VERDE: []}
        locali = sc.gruppo(csip + "_Locali", gp)
        stanze, colonne, dentro_aule, magna_aule = [], [], [], []
        palladiana, palladiana_aule, fronti = [], [], []
        for v in f["vani"]:
            poly = shape_of(v)
            if poly.is_empty:
                continue
            rooms.append(poly)
            for col in pilastri(v):
                colonne.append(col)
                tondo = len(col.exterior.coords) - 1 >= 8     # la pianta disegna i tondi come ottagoni
                if tondo:
                    m = trimesh.creation.cylinder(radius=math.sqrt(col.area / math.pi), height=MURO, sections=20)
                    m.apply_translation([col.centroid.x, col.centroid.y, z + SOLETTA + MURO / 2])
                else:
                    m = trimesh.creation.extrude_polygon(col, MURO).apply_translation([0, 0, z + SOLETTA])
                arredi[STEEL if profilato(b) else PILASTRO].append(m)      # neri nell'Edificio 11, come nelle foto
            tipo = "aula" if v["csiv"] in aule else v["tipo"]
            if v["csiv"] in aule:
                m, height = gradoni(poly, z, lin.get("arredi", []))
                if getattr(height, "fronte", None) is not None:
                    palladiana_aule.append(height.fronte)
                    if v["csiv"] in AULA_MAGNA:
                        fronti.append(height.fronte)
                rows = file_di_banchi(poly, lin.get("arredi", []))
                if rows:
                    (tavoli if getattr(height, "tavoli", False) else banchi)(rows[1], height, arredi)
                    if v["csiv"] not in AULA_MAGNA:      # l'Aula Magna ha un palco solo, sotto
                        cattedra(poly, rows[1], height, arredi)
                    scalette(poly, lin.get("scale", []), height, arredi)
                sc.mesh(v["csiv"], locali, m)
                if v["csiv"] not in AULA_MAGNA:
                    dentro_aule.append((v["csiv"], poly, height))
                else:
                    magna_aule.append(poly)
                c = poly.representative_point()
                stanze.append({"csiv": v["csiv"], "sigla": aule[v["csiv"]]["sigla"],
                               "posti": aule[v["csiv"]].get("posti"), "centro": [round(c.x, 2), round(z + 1, 2), round(c.y, 2)]})
            elif tipo == "ascensore":
                pass                      # i vani veri vengono dalle croci della pianta, sotto
            else:
                by_type.setdefault(COL.get(tipo, COL["locale"]), []).append(poly.buffer(-0.02))
                if tipo == "corridoio" or (tipo == "locale" and poly.area > 400):
                    palladiana.append(poly.buffer(-0.02))       # corridoi e atri (S011, 001023)
        torre = unary_union([shape_of(v) for v in f["vani"] if is_tower(shape_of(v)) and not shell.contains(shape_of(v).representative_point())])
        dentro = shell.buffer(0.2).union(torre.buffer(0.3)).difference(unary_union([shape_of(v) for v in f["vani"] if v["csiv"] in aule]))
        corridoi = unary_union([shape_of(v) for v in f["vani"] if v.get("tipo") == "corridoio"])
        nxt = [zz for cc, zz in zs.items() if zz > z]
        sopra_csip = min(((zz, cc) for cc, zz in zs.items() if zz > z), default=(None, None))[1]
        # il vuoto del piano sopra lascia fuori la scala elicoidale che vi sale: chiuso di
        # 4 m, il patio la comprende; la scala la disegna elica(), non scale()
        patii = [g_.buffer(4, join_style=2).buffer(-4, join_style=2).intersection(shell)
                 for g_ in clean(aperti.get(sopra_csip, Polygon())) if g_.area > 300] if griglia[0] else []
        orma = unary_union(patii) if patii else Polygon()
        eliche = [shape_of(v) for v in f["vani"] if v.get("tipo") == "scale" and orma.buffer(1).contains(shape_of(v).centroid)
                  and tonda(shape_of(v))]
        if eliche:
            dentro = dentro.difference(unary_union(eliche).buffer(0.3))
        H = (min(nxt) - z) if nxt else PIANO
        # All'ultimo piano le rampe disegnate sopra le scale del piano sotto ne sono l'arrivo.
        arrivo = unary_union(sotto) if sotto else Polygon()
        impronte = scale(lin.get("scale", []), dentro if nxt else dentro.difference(arrivo.buffer(0.2)),
                         corridoi, z + SOLETTA, H, arredi)
        # Il solaio si apre sopra le scale che salgono dal piano sotto.
        foro = arrivo.buffer(-0.05).difference(unary_union(impronte)) if not arrivo.is_empty else Polygon()
        sotto = impronte
        vano_scale = unary_union(impronte + [arrivo]).buffer(0.3) if impronte or not arrivo.is_empty else Polygon()
        # I vuoti: dove la pianta non disegna locali per più di un muro (oltre 1,6 m di
        # spessore) il piano è aperto su quello sotto, come il pozzo sotto la A di Viganò.
        pieno = shell.difference(unary_union(rooms + colonne).buffer(0.05))
        vuoti = unary_union([g_ for g_ in clean(pieno.buffer(-0.8, join_style=2).buffer(0.8, join_style=2)) if g_.area > 20])
        foro = foro.union(vuoti) if not vuoti.is_empty else foro
        for g_ in clean(vuoti):
            for a_, c_ in zip(g_.exterior.coords, g_.exterior.coords[1:]):
                if math.dist(a_, c_) < 0.2:
                    continue
                trave_z(arredi[METALLO], (*a_, z + SOLETTA + 1.0), (*c_, z + SOLETTA + 1.0), 0.05)
                k_ = max(1, int(math.dist(a_, c_) / 1.5))
                for j_ in range(k_):
                    x_, y_ = a_[0] + (c_[0] - a_[0]) * j_ / k_, a_[1] + (c_[1] - a_[1]) * j_ / k_
                    trave_z(arredi[METALLO], (x_, y_, z + SOLETTA), (x_, y_, z + SOLETTA + 1.0), 0.04)
        sc.mesh(csip + "_Soletta", gp, slab(shell.difference(foro), z, z + SOLETTA, COL["soletta"]))
        for hex_, polys in by_type.items():
            sc.mesh(f"{csip}_Locali_{hex_.lstrip('#')}", locali, slab(togli(unary_union(polys).difference(foro), orma), z + SOLETTA, z + SOLETTA + 0.04, hex_))
        for P_ in patii:
            # il pavimento del patio, toccabile come un'aula, col nome del locale che ne
            # copre di più; i piedi dei pilastri, tagliati come i muri
            csiv = max(f["vani"], key=lambda v: shape_of(v).intersection(P_).area)["csiv"]
            el_ = [e_ for e_ in eliche if P_.contains(e_.centroid)]
            sc.mesh(csiv, locali, slab(P_.difference(vano_scale), z + SOLETTA, z + SOLETTA + 0.05, PATIO))
            for x_ in griglia[0]:
                for y_ in griglia[1]:
                    if P_.buffer(-0.5).contains(Point(x_, y_)):
                        arredi[STEEL].extend(cruciforme(x_, y_, z + SOLETTA, z + SOLETTA + MURO))
            arredi.setdefault(ARANCIO, [])
            tavoli_patio(lin.get("arredi", []), P_, z + SOLETTA + 0.05, arredi)
            z_s = zs[sopra_csip]
            z_t = min((zz for zz in zs.values() if zz > z_s), default=z_s + PIANO)
            parti, occhio, guarda = interno_patio(P_, unary_union([ring(r).buffer(0) for r in geo[sopra_csip]["contorno"]]),
                                                  z + SOLETTA, z_s, z_t, *griglia)
            for e_ in el_:
                elica(e_, P_, z + SOLETTA, z_s + SOLETTA, arredi, parti)
            gi = sc.gruppo(csiv + "_Interno", gp)
            for hex_, ms in parti.items():
                if ms:
                    m = trimesh.util.concatenate(ms)
                    m.apply_transform(YUP)
                    sc.mesh(f"{csiv}_Interno_{hex_.lstrip('#')}", gi, colour(m, hex_))
            c = P_.representative_point()
            stanze.append({"csiv": csiv, "sigla": "Patio", "posti": None, "centro": [round(c.x, 2), round(z + 1, 2), round(c.y, 2)],
                           "interno": {"occhio": occhio, "guarda": guarda}})
        atrio = unary_union([shape_of(v) for v in f["vani"] if v.get("tipo") in ("corridoio", "locale") and shape_of(v).area > 100
                             and v["csiv"] not in aule])
        magna = aula_magna(fronti, atrio, colonne, z, arredi) if fronti else Polygon()
        if fronti:
            palladiana_aule.append((atrio.intersection(unary_union([g for g, _ in fronti]).convex_hull), max(zz for _, zz in fronti)))
        # I cubetti di pietra chiara delle foto: nei corridoi e nell'atrio, e davanti alla prima
        # fila delle aule. Una pellicola di 1 cm sopra il pavimento, fuori da _Locali: il tocco e la luce
        # gialla restano sull'aula.
        P = Solidi()
        for g_, zf in [(togli(unary_union(palladiana).difference(foro), orma), z + SOLETTA + 0.04)] + palladiana_aule:
            for q_ in clean(g_):
                P.solid("cubetti", trimesh.creation.extrude_polygon(q_, 0.01, engine="earcut").apply_translation([0, 0, zf]))
        for m in P.meshes().values():
            sc.mesh(f"{csip}_Pavimento", gp, m)
        # Gli ascensori dalle croci della pianta: al terra e al primo il vano non è un locale e
        # starebbe dentro i muri pieni, quindi lo si toglie dai muri.
        vani_asc = ascensori(lin.get("ascensori", []), unary_union([shape_of(v) for v in f["vani"] if v.get("tipo") in ("corridoio", "locale")]),
                             z + SOLETTA, arredi)
        muri = shell.difference(unary_union(rooms + colonne + [g_.buffer(0.12, join_style=2) for g_ in vani_asc]).buffer(0.0)).difference(aperture(f))
        muri = muri.difference(vuoti.buffer(0.05)) if not vuoti.is_empty else muri
        # nel patio la pianta divide il cortile in locali e chiude i pilastri in quadrati
        # pieni: nelle foto è un'aula unica, coi pilastri neri
        muri = muri.difference(orma.buffer(-0.3, join_style=2)) if not orma.is_empty else muri
        # Le finestre della pianta nei muri. Al terra e al primo sono gli esagoni di Ponti del
        # guscio, nelle stesse campate (plan_windows): davanzale pieno fino a 1,2 m dal solaio,
        # poi la metà bassa dell'esagono, che si allarga fino al taglio dei muri, con i
        # montanti grigi. Nel seminterrato finestre rettangolari, davanzale a 0,9 m.
        if z >= BASE_H - 0.01 and dettagliato(b):
            pts_g = ring_ccw(ring(b["pianta"]).buffer(0))
            es = edges(pts_g)
            pezzi = []
            for i_, spans in plan_windows(b, csip, pts_g).items():
                a_, _, u_, n_, _, _ = es[i_]
                a_, u_ = np.array(a_), np.array(u_)
                for t0, t1 in spans:
                    foot = LineString([tuple(a_ + u_ * t0), tuple(a_ + u_ * t1)]).buffer(0.6, cap_style=2).intersection(muri)
                    foot = max(getattr(foot, "geoms", [foot]), key=lambda g_: g_.area) if not foot.is_empty else foot
                    if foot.geom_type == "Polygon" and foot.area > 0.1:
                        pezzi.append((foot, a_, u_, t0, t1))
            vetri = unary_union([p_[0] for p_ in pezzi]) if pezzi else Polygon()
            pieni = muri.difference(vetri)
            sc.mesh(csip + "_Muri", gp, slab(pieni, z + SOLETTA, z + SOLETTA + MURO, COL["muri"]))
            if pezzi:
                sc.mesh(csip + "_Davanzali", gp, slab(vetri, z + SOLETTA, z + 1.2, COL["muri"]))
                taglio, k = z + SOLETTA + MURO, 0.3
                for foot, a_, u_, t0, t1 in pezzi:
                    nn = np.array([-u_[1], u_[0]])
                    ns = [float(np.dot(np.array(q), nn)) for q in foot.exterior.coords]
                    n0, n1 = min(ns), max(ns)
                    base = a_ - nn * float(np.dot(a_, nn))          # il lato, riportato a n = 0
                    P = lambda t, nv: tuple(base + u_ * t + nn * nv)
                    nm = (n0 + n1) / 2
                    vetro = hexa([(*P(t0 + k, nm - 0.05), z + 1.2), (*P(t1 - k, nm - 0.05), z + 1.2), (*P(t1 - k, nm + 0.05), z + 1.2), (*P(t0 + k, nm + 0.05), z + 1.2)],
                                 [(*P(t0, nm - 0.05), taglio), (*P(t1, nm - 0.05), taglio), (*P(t1, nm + 0.05), taglio), (*P(t0, nm + 0.05), taglio)])
                    arredi[VETRO].append(vetro)
                    for e0, e1 in ((t0, t0 + k), (t1 - k, t1)):     # gli spigoli smussati, pieni
                        lo = e0 if e0 == t0 else e1
                        arredi[COL["muri"]].append(hexa(
                            [(*P(e0, n0), z + 1.2), (*P(e1, n0), z + 1.2), (*P(e1, n1), z + 1.2), (*P(e0, n1), z + 1.2)],
                            [(*P(lo - 0.005, n0), taglio), (*P(lo + 0.005, n0), taglio), (*P(lo + 0.005, n1), taglio), (*P(lo - 0.005, n1), taglio)]))
                    bars = max(1, round((t1 - t0) / 0.8))
                    for j_ in range(1, bars):
                        t = t0 + (t1 - t0) * j_ / bars
                        arredi[FRAME_GREY].append(hexa([(*P(t - 0.03, nm - 0.04), z + 1.2), (*P(t + 0.03, nm - 0.04), z + 1.2), (*P(t + 0.03, nm + 0.04), z + 1.2), (*P(t - 0.03, nm + 0.04), z + 1.2)],
                                                       [(*P(t - 0.03, nm - 0.04), taglio), (*P(t + 0.03, nm - 0.04), taglio), (*P(t + 0.03, nm + 0.04), taglio), (*P(t - 0.03, nm + 0.04), taglio)]))
        else:
            vetri = unary_union([LineString([s_[:2], s_[2:4]]).buffer(0.3, cap_style=2) for s_ in lin.get("finestre", [])
                                 if math.dist(s_[:2], s_[2:4]) > 0.2]).intersection(muri) if lin.get("finestre") else Polygon()
            pieni = muri.difference(vetri)
            sc.mesh(csip + "_Muri", gp, slab(pieni, z + SOLETTA, z + SOLETTA + MURO, COL["muri"]))
            if not vetri.is_empty:
                sc.mesh(csip + "_Davanzali", gp, slab(vetri, z + SOLETTA, z + SOLETTA + 0.9, COL["muri"]))
                sc.mesh(csip + "_Finestre", gp, slab(vetri, z + SOLETTA + 0.9, z + SOLETTA + MURO, VETRO))
        # Le scale, le porte aperte come le disegna la pianta, i parapetti.
        for d in f.get("porte", []):
            h, o = np.array(d["cardine"]), np.array(d["aperta"])
            if np.linalg.norm(o - h) < 0.3 or magna.buffer(0.5).contains(Point(h)):
                continue      # nell'Aula Magna le pareti mobili fra le aule sono aperte
            nrm = np.array([-(o - h)[1], (o - h)[0]]) / np.linalg.norm(o - h) * 0.025
            q = [tuple(h - nrm), tuple(o - nrm), tuple(o + nrm), tuple(h + nrm)]
            arredi[LEAF].append(hexa([(*p, z + SOLETTA) for p in q], [(*p, z + SOLETTA + MURO) for p in q]))
        for x0, y0, x1, y1 in (s_[:4] for s_ in lin.get("ringhiere", [])):
            if math.dist((x0, y0), (x1, y1)) < 0.3 or not shell.buffer(0.3).contains(Polygon([(x0, y0), (x1, y1), (x1 + 1e-3, y1)]).centroid):
                continue
            if vano_scale.contains(LineString([(x0, y0), (x1, y1)]).centroid):
                continue      # i corrimano delle scale seguono i gradini
            a, c = np.array([x0, y0]), np.array([x1, y1])
            nrm = np.array([-(c - a)[1], (c - a)[0]]) / np.linalg.norm(c - a) * 0.025
            q = [tuple(a - nrm), tuple(c - nrm), tuple(c + nrm), tuple(a + nrm)]
            arredi[METALLO].append(hexa([(*p, z + SOLETTA + 0.95) for p in q], [(*p, z + SOLETTA + 1.0) for p in q]))
        # Dentro le aule: muri interi, soffitto, luci. Nascosto finché non si entra.
        sopra_csip = min(((zz, cc) for cc, zz in zs.items() if zz > z), default=(None, None))[1]
        z_tetto = min(nxt) if nxt else BASE_H + MOSAICO_H - 0.35
        porte = aperture(f)
        for csiv, poly, height in dentro_aule:
            r_ = interno(poly, height, gradonate.get(sopra_csip, []), z + SOLETTA, z_tetto, porte, vetri, travi=profilato(b))
            if not r_ and hasattr(guscio_proprio(b), "interno"):       # un interno disegnato a mano
                r_ = guscio_proprio(b).interno(b, sys.modules[__name__], csiv, poly, z + SOLETTA, porte)
            if not r_:
                continue
            parti, occhio, guarda = r_
            gi = sc.gruppo(csiv + "_Interno", gp)
            for hex_, ms in parti.items():
                if ms:
                    m = trimesh.util.concatenate(ms)
                    m.apply_transform(YUP)
                    sc.mesh(f"{csiv}_Interno_{hex_.lstrip('#')}", gi, colour(m, hex_))
            for st in stanze:
                if st["csiv"] == csiv:
                    st["interno"] = {"occhio": occhio, "guarda": guarda}
        if len(magna_aule) == 2 and not magna.is_empty:
            sala = unary_union(magna_aule + [magna]).buffer(0.3).buffer(-0.3)
            parti, occhio, guarda = interno_magna(sala, magna, z + SOLETTA, z_tetto, porte, vetri)
            gi = sc.gruppo("Aula_Magna_Interno", gp)
            for hex_, ms in parti.items():
                if ms:
                    m = trimesh.util.concatenate(ms)
                    m.apply_transform(YUP)
                    sc.mesh(f"Aula_Magna_Interno_{hex_.lstrip('#')}", gi, colour(m, hex_))
            for st in stanze:
                if st["csiv"] in AULA_MAGNA:
                    st["interno"] = {"occhio": occhio, "guarda": guarda, "nodo": "Aula_Magna_Interno"}
        if hasattr(guscio_proprio(b), "arredi"):                         # arredi disegnati a mano
            for hex_, ms in guscio_proprio(b).arredi(b, sys.modules[__name__], csip, z + SOLETTA, f).items():
                arredi.setdefault(hex_, []).extend(ms)
        ga = sc.gruppo(csip + "_Arredi", gp)
        for hex_, parts in arredi.items():
            if parts:
                m = trimesh.util.concatenate(parts)
                m.apply_transform(YUP)
                m.invert() if m.volume < 0 else None
                sc.mesh(f"{csip}_Arredi_{hex_.lstrip('#')}", ga, colour(m, hex_))
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
            if hex_ == LUCE:          # le luci delle aule: accese
                sh.CreateInput("emissiveColor", Sdf.ValueTypeNames.Color3f).Set(Gf.Vec3f(1.0, 0.98, 0.92))
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
        meta["altezza"] = round(esterno(b)[1] if esterno(b) else max(h for _, h, _ in volumi(b)), 2)
        usdz(sc, OUT / f"{csie}.usdz")
        if ARGS.glb:
            sc.s.export(OUT / f"{csie}.glb")
        (OUT / f"{csie}.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n")
        print(csie, b.get("nome", ""), len(meta["piani"]), "piani",
              sum(len(p["aule"]) for p in meta["piani"]), "aule")


if __name__ == "__main__":
    main()
