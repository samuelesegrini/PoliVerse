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

# Altezze reali (m) delle fasce del profilo, al posto delle unità esagerate del disegno.
FESSURA = 1.2        # il seminterrato che affiora: il piano terra è rialzato di tanto
GLASS, FRAME = "#9DB4CC", "#F4F5F7"
PLANT, ROOF, ROOF_EDGE = "#E3E6EB", "#E3E5E8", "#B9BDC4"
PALE, DOOR, ENTRY = "#E9E6E0", "#2D3B4F", "#2B3644"
BASE = "#C9CED6"


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


def faces_of(poly):
    """Ogni lato del contorno con la sua normale verso l'esterno."""
    pts = list(poly.exterior.coords)[:-1]
    out = []
    for a, c in zip(pts, pts[1:] + pts[:1]):
        L = math.dist(a, c)
        if L < 0.3:
            continue
        n = ((c[1] - a[1]) / L, -(c[0] - a[0]) / L)
        mid = ((a[0] + c[0]) / 2 + n[0] * 0.2, (a[1] + c[1]) / 2 + n[1] * 0.2)
        if poly.contains(Polygon([mid, (mid[0] + 1e-3, mid[1]), (mid[0], mid[1] + 1e-3)]).centroid):
            n = (-n[0], -n[1])
        out.append((a, c, n, L))
    return out


def windows(poly, z, h, rows, big, parts):
    """Le finestre di una fascia piena, con lo stesso schema di punched() in build-mappa.py:
    una campata ogni 4,2 m; al terra una finestra grande per campata, sopra `rows` file
    di finestrelle e ogni tanto una striscia alta di vetrocemento."""
    for a, c, n, L in faces_of(poly):
        step = 4.2
        k = int((L - 2) / step)
        if k < 1:
            continue
        pad = (L - k * step) / 2
        def pane(t0, t1, z0, z1):
            parts[FRAME].append(box3(a, c, n, t0 - 0.12, t1 + 0.12, z0 - 0.12, z1 + 0.12, -0.02, 0.08))
            parts[GLASS].append(box3(a, c, n, t0, t1, z0, z1, 0.0, 0.1))
        for i in range(k):
            t = pad + i * step
            if big:
                pane(t + 0.6, t + step - 0.6, z + h * 0.18, z + h * 0.78)
                continue
            seed = (i * 7 + int(L)) % 9
            if seed == 4:
                pane(t + 1.8, t + 2.4, z + h * 0.12, z + h * 0.88)          # vetrocemento
                continue
            for r in range(rows):
                if (seed + r * 3) % 5 == 0:
                    continue                                                # cieca qui
                zr = z + h * (r + 0.42) / rows
                w = 2.6 if (seed + r) % 3 else 1.4
                pane(t + 0.8, t + 0.8 + w, zr, zr + h / rows * 0.32)


def ingresso(b, poly, zg, parts):
    """Il terra rialzato: pianerottolo davanti alla porta, due rampe lungo i muri, sotto il
    pianerottolo l'ingresso vetrato del seminterrato, e la porta scura sopra."""
    ent = b.get("ingresso") or {}
    r = ent.get("rampa")
    if not r or "lato" not in ent:
        return
    raw = [tuple(p) for p in b["pianta"]]
    a, c = raw[ent["lato"]], raw[(ent["lato"] + 1) % len(raw)]
    n = next(f[2] for f in faces_of(poly) if math.dist(f[0], a) < 0.5 or math.dist(f[1], c) < 0.5)
    L = math.dist(a, c)
    mid = ent["t"] * L
    land = Polygon(r["pianerottolo"]).buffer(0)
    parts[PALE].append(trimesh.creation.extrude_polygon(land, 0.3).apply_translation([0, 0, zg - 0.3]))
    for q in r["rampe"]:
        # I primi due vertici toccano il pianerottolo, gli ultimi due il suolo.
        top = [(*q[0], zg), (*q[1], zg), (*q[2], 0.02), (*q[3], 0.02)]
        parts[PALE].append(hexa([(x, y, zz - 0.3) for x, y, zz in top], top))
        for p0, p1 in ((q[0], q[3]), (q[1], q[2])):        # corrimano
            dx, dy = p1[0] - p0[0], p1[1] - p0[1]
            k = math.hypot(dx, dy)
            w = (-dy / k * 0.04, dx / k * 0.04)
            q4 = [(p0[0] - w[0], p0[1] - w[1], zg), (p1[0] - w[0], p1[1] - w[1], 0.0),
                  (p1[0] + w[0], p1[1] + w[1], 0.0), (p0[0] + w[0], p0[1] + w[1], zg)]
            parts[FRAME].append(hexa([(x, y, zz + 0.9) for x, y, zz in q4], [(x, y, zz + 0.97) for x, y, zz in q4]))
    half = r.get("sotto", 3.5)
    parts[ENTRY].append(box3(a, c, n, mid - half, mid + half, 0, zg - 0.35, 0, 0.06))
    parts[DOOR].append(box3(a, c, n, mid - 1.5, mid + 1.5, zg, zg + 2.6, 0, 0.08))
    # I pilastri sotto il bordo esterno del pianerottolo.
    ring_ = list(land.exterior.coords)[:-1]
    edge = max(zip(ring_, ring_[1:] + ring_[:1]), key=lambda e: math.dist(*e))
    for i in range(5):
        f = (i + 0.5) / 5
        x, y = edge[0][0] + (edge[1][0] - edge[0][0]) * f, edge[0][1] + (edge[1][1] - edge[0][1]) * f
        col = trimesh.creation.cylinder(radius=0.18, height=zg - 0.3, sections=8)
        parts[FRAME].append(col.apply_translation([x - n[0] * 0.5, y - n[1] * 0.5, (zg - 0.3) / 2]))


def guscio(b):
    """L'esterno come nell'isometrico, ad altezze reali: {colore: [mesh Z-up]}.

    Per gli edifici con profilo fessura + pieni + gronda (il Trifoglio): zoccolo, la
    fessura vetrata del seminterrato, una fascia per piano nel suo rivestimento con le
    sue finestre, il tetto che sporge di `gronda` m con gli impianti, e l'ingresso."""
    poly = ring(b["pianta"]).buffer(0)
    parts = {k: [] for k in (BASE, GLASS, FRAME, PLANT, ROOF, ROOF_EDGE, PALE, DOOR, ENTRY, CLADDING["fessura"])}
    ext = lambda g, z0, z1: trimesh.creation.extrude_polygon(g, z1 - z0).apply_translation([0, 0, z0])
    parts[BASE].append(ext(poly.buffer(0.6, join_style=2), 0, 0.25))
    z = 0.0
    for band in b["profilo"]:
        if band["tipo"] == "fessura":
            parts[CLADDING["fessura"]].append(ext(poly.buffer(-0.25, join_style=2), z, z + FESSURA))
            z += FESSURA
            continue
        colore = CLADDING.get(band.get("rivestimento"), COL["edificio"])
        parts.setdefault(colore, []).append(ext(poly, z, z + PIANO))
        if band.get("finestre"):
            windows(poly, z, PIANO, band.get("file", 1), band["finestre"] == "grandi", parts)
        z += PIANO
    g = b.get("gronda", 0.6)
    eave = poly.buffer(g, join_style=2)
    parts[ROOF_EDGE].append(ext(eave, z, z + 0.45))
    parts[ROOF].append(ext(eave.buffer(-0.05, join_style=2), z + 0.45, z + 0.5))
    for x, y, w, d in b.get("impianti", []):
        parts[PLANT].append(trimesh.creation.box(extents=[w, d, 1.6]).apply_translation([x + w / 2, y + d / 2, z + 0.5 + 0.8]))
    ingresso(b, poly, FESSURA, parts)
    out = {}
    for hex_, ms in parts.items():
        if ms:
            m = trimesh.util.concatenate(ms)
            m.apply_transform(YUP)
            m.invert() if m.volume < 0 else None
            out[hex_] = colour(m, hex_)
    return out, z + 0.5


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
            for hex_, m in guscio(b)[0].items():
                sc.mesh(f"{b['csie']}_Esterno_{hex_.lstrip('#')}", g, m)
            continue
        for i, (poly, h, hex_) in enumerate(volumi(b)):
            sc.mesh(f"{b['csie']}_Esterno_{i}", g, slab(poly, 0, h, hex_))
            sc.mesh(f"{b['csie']}_Tetto_{i}", g, slab(poly.buffer(-0.6), h, h + 0.35, COL["tetto"]))
    return sc


# ---------------------------------------------------------------- piani

def quote(b):
    """Quota (m) del pavimento di ogni piano: il terra (…000) a zero, o rialzato sulla
    fessura del seminterrato dove il guscio la disegna."""
    liv = b.get("livelli", [])
    g = next((i for i, c in enumerate(liv) if c.endswith("000")), 0)
    terra = FESSURA if dettagliato(b) else 0.0
    return {c: terra + (i - g) * PIANO for i, c in enumerate(liv)}


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
        UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(material(m.metadata.get("colore", "#CCCCCC")))
    st.SetDefaultPrim(st.GetPrimAtPath(path_of(next(n for n in g.nodes if g.transforms.parents.get(n) == g.base_frame))))
    st.GetRootLayer().Save()
    UsdUtils.CreateNewUsdzPackage(str(usda), str(path))
    usda.unlink()


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
