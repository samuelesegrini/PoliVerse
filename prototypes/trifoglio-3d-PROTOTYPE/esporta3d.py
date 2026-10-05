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
import argparse, json, pathlib
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
        for i, (poly, h, hex_) in enumerate(volumi(b)):
            sc.mesh(f"{b['csie']}_Esterno_{i}", g, slab(poly, 0, h, hex_))
            sc.mesh(f"{b['csie']}_Tetto_{i}", g, slab(poly.buffer(-0.6), h, h + 0.35, COL["tetto"]))
    return sc


# ---------------------------------------------------------------- piani

def quote(b):
    """Quota (m) del pavimento di ogni piano: il terra (…000) a zero."""
    liv = b.get("livelli", [])
    g = next((i for i, c in enumerate(liv) if c.endswith("000")), 0)
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
        meta["altezza"] = round(max(h for _, h, _ in volumi(b)), 2)
        usdz(sc, OUT / f"{csie}.usdz")
        if ARGS.glb:
            sc.s.export(OUT / f"{csie}.glb")
        (OUT / f"{csie}.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n")
        print(csie, b.get("nome", ""), len(meta["piani"]), "piani",
              sum(len(p["aule"]) for p in meta["piani"]), "aule")


if __name__ == "__main__":
    main()
