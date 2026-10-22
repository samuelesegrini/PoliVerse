#!/usr/bin/env python3
"""PROTOTIPO — banco di prova del caricamento 3D: misura i modelli che l'app carica.

    python3 banco/misura.py "PoliVerse/Preview Content/Trifoglio3D" [--json out.json] [--md out.md]

Gira dove non c'è Xcode: legge gli stessi .usdz che Trifoglio3DView carica e ne ricava le
metriche che sul telefono diventano tempo, memoria, CPU e batteria (vedi banco/README.md):

  peso        byte nel bundle, byte scaricati (deflate, come l'App Store), byte delle texture
  geometria   mesh (≈ draw call), triangoli, vertici, vertici per triangolo, materiali
  memoria     stima della memoria GPU: vertici × (posizione + normale [+ uv + tangente])
              + indici a 32 bit + texture RGBA con mipmap
  parsing     ms per aprire lo stage e leggere tutti gli array (USD in Python: un indice,
              non il tempo di RealityKit, ma cresce con gli stessi byte)
  collisioni  mesh e triangoli che diventano forme di collisione (generateStaticMesh)
  primo frame cosa va letto prima che il campus compaia, con il caricamento di prima (tutto
              prima del primo frame) e con quello progressivo (solo il campus)
  a regime    la memoria GPU con tutto caricato, e con il campus più i 4 edifici più grandi
              (al più 4 restano caricati)
  fermate     triangoli e draw call che passano il frustum culling a ogni fermata della
              camera (campus, ogni edificio, il suo piano terra), con la stessa
              inquadratura di Trifoglio3DScene.frame(_:polar:margin:)

Dipendenze: usd-core, numpy, pillow.
"""
import argparse, io, json, math, pathlib, statistics, sys, time, zipfile, zlib
import numpy as np
from pxr import Usd, UsdGeom, Gf

# L'inquadratura di Trifoglio3DScene: fov verticale 35°, da sud-ovest; schermo di un iPhone
# in verticale meno le barre sopra e sotto (393 × 600 punti).
FOV = math.radians(35)
ASPECT = 393 / 600
AZIMUTH = -math.pi / 4
NEAR, FAR = 1.0, 4000.0
TENUTI = 4   # Trifoglio3DScene.keptBuildings


def bounds_world(cache, prim):
    r = cache.ComputeWorldBound(prim).ComputeAlignedRange()
    if r.IsEmpty():
        return None
    return np.array(r.GetMin()), np.array(r.GetMax())


class Modello:
    """Un .usdz: le sue mesh con i numeri che contano e il riquadro nel mondo."""

    def __init__(self, path):
        self.path = path
        self.bytes = path.stat().st_size
        raw = path.read_bytes()
        self.download = len(zlib.compress(raw, 6))
        self.tex_bytes = 0
        self.tex_gpu = 0
        with zipfile.ZipFile(path) as z:
            for info in z.infolist():
                if info.filename.lower().endswith((".png", ".jpg", ".jpeg")):
                    self.tex_bytes += info.file_size
                    from PIL import Image
                    w, h = Image.open(io.BytesIO(z.read(info))).size
                    self.tex_gpu += w * h * 4 * 4 / 3
        self.parse_ms = statistics.median(self._parse() for _ in range(3))
        st = Usd.Stage.Open(str(path))
        cache = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_, UsdGeom.Tokens.render])
        self.meshes = []
        mats = set()
        for prim in st.Traverse():
            if not prim.IsA(UsdGeom.Mesh):
                continue
            m = UsdGeom.Mesh(prim)
            tris = sum(c - 2 for c in (m.GetFaceVertexCountsAttr().Get() or []))
            verts = len(m.GetPointsAttr().Get() or [])
            uv = UsdGeom.PrimvarsAPI(prim).HasPrimvar("st")
            rel = prim.GetRelationship("material:binding")
            if rel and rel.GetTargets():
                mats.add(str(rel.GetTargets()[0]))
            b = bounds_world(cache, prim)
            if b is None or tris == 0:
                continue
            self.meshes.append(dict(path=str(prim.GetPath()), tris=tris, verts=verts, uv=uv, lo=b[0], hi=b[1]))
        self.materials = len(mats)
        self.tris = sum(m["tris"] for m in self.meshes)
        self.verts = sum(m["verts"] for m in self.meshes)
        geo = sum(m["verts"] * (24 + (24 if m["uv"] else 0)) + m["tris"] * 12 for m in self.meshes)
        self.gpu = geo + self.tex_gpu
        loc = [m for m in self.meshes if "_Locali/" in m["path"]]
        self.coll_meshes, self.coll_tris = len(loc), sum(m["tris"] for m in loc)

    def _parse(self):
        t = time.perf_counter()
        st = Usd.Stage.Open(str(self.path))
        for prim in st.Traverse():
            if prim.IsA(UsdGeom.Mesh):
                m = UsdGeom.Mesh(prim)
                m.GetPointsAttr().Get(); m.GetFaceVertexIndicesAttr().Get(); m.GetFaceVertexCountsAttr().Get()
                pv = UsdGeom.PrimvarsAPI(prim)
                if pv.HasPrimvar("st"):
                    pv.GetPrimvar("st").Get()
        return (time.perf_counter() - t) * 1000

    def sotto(self, prefix):
        return [m for m in self.meshes if m["path"].startswith(prefix)]

    def riquadro(self, prefix):
        ms = self.sotto(prefix)
        if not ms:
            return None
        return np.min([m["lo"] for m in ms], axis=0), np.max([m["hi"] for m in ms], axis=0)


def camera(box, polar, margin):
    """La stessa camera di Trifoglio3DScene.frame: la sfera del riquadro nel campo più stretto."""
    lo, hi = box
    centre = (lo + hi) / 2
    radius = max(np.linalg.norm(hi - lo) / 2, 4) * margin
    horizontal = 2 * math.atan(math.tan(FOV / 2) * ASPECT)
    d = radius / math.sin(min(FOV, horizontal) / 2)
    offset = np.array([math.sin(polar) * math.sin(AZIMUTH), math.cos(polar), math.sin(polar) * math.cos(AZIMUTH)]) * d
    return centre + offset, centre


def piani_frustum(eye, target):
    """I sei piani del frustum, ciascuno come (normale verso l'interno, un suo punto)."""
    f = target - eye; f /= np.linalg.norm(f)
    r = np.cross(f, [0, 1, 0]); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    tv = math.tan(FOV / 2); th = tv * ASPECT
    planes = [(f, eye + f * NEAR), (-f, eye + f * FAR)]
    # Ogni lato passa per l'occhio, contiene il bordo dello schermo e l'asse perpendicolare.
    for edge, axis in ((f + r * th, u), (f - r * th, u), (f + u * tv, r), (f - u * tv, r)):
        n = np.cross(axis, edge); n /= np.linalg.norm(n)
        planes.append((n if np.dot(n, f) > 0 else -n, eye))
    return planes


def visibile(m, planes):
    for n, p in planes:
        # il vertice del riquadro più avanti lungo la normale
        v = np.where(n >= 0, m["hi"], m["lo"])
        if np.dot(n, v - p) < 0:
            return False
    return True


def conta(meshes, planes):
    vis = [m for m in meshes if visibile(m, planes)]
    return sum(m["tris"] for m in vis), len(vis)


def misura(cartella):
    cartella = pathlib.Path(cartella)
    files = sorted(cartella.glob("*.usdz"))
    modelli = {f.stem: Modello(f) for f in files}
    campus = modelli.get("campus")
    giuriati = modelli.get("giuriati")
    edifici = {k: v for k, v in modelli.items() if k.startswith("MIA")}
    sfondo = [m for m in [campus, giuriati] if m]

    out = {"file": {}, "totale": {}, "primo_frame": {}, "fermate": {}}
    for k, m in modelli.items():
        out["file"][k] = dict(mb=m.bytes / 1e6, download_mb=m.download / 1e6, texture_mb=m.tex_bytes / 1e6,
                              mesh=len(m.meshes), triangoli=m.tris, vertici=m.verts,
                              vertici_per_tri=round(m.verts / max(m.tris, 1), 2), materiali=m.materials,
                              gpu_mb=m.gpu / 1e6, parse_ms=m.parse_ms,
                              collisioni_mesh=m.coll_meshes, collisioni_tri=m.coll_tris)
    tutti = list(modelli.values())
    somma = lambda ms, a: sum(getattr(m, a) for m in ms)
    out["totale"] = dict(mb=somma(tutti, "bytes") / 1e6, download_mb=somma(tutti, "download") / 1e6,
                         triangoli=somma(tutti, "tris"), vertici=somma(tutti, "verts"),
                         gpu_mb=somma(tutti, "gpu") / 1e6, parse_ms=somma(tutti, "parse_ms"),
                         mesh=sum(len(m.meshes) for m in tutti))
    # Il primo frame: oggi RealityView aspetta tutta la closure make, cioè ogni file e ogni
    # collisione; con il caricamento progressivo solo il campus (o il suo primo strato).
    for nome, ms in (("tutto subito", tutti), ("progressivo", [m for m in [campus] if m])):
        out["primo_frame"][nome] = dict(file=len(ms), mb=somma(ms, "bytes") / 1e6, parse_ms=somma(ms, "parse_ms"),
                                        triangoli=somma(ms, "tris"), gpu_mb=somma(ms, "gpu") / 1e6,
                                        collisioni_mesh=somma(ms, "coll_meshes"))

    # La memoria a regime: oggi tutto; con il caricamento progressivo il campus, il Giuriati
    # e al più TENUTI edifici (Trifoglio3DScene.keptBuildings), nel caso peggiore i più grandi.
    grandi = sorted(edifici.values(), key=lambda m: -m.gpu)[:TENUTI]
    out["memoria_regime"] = {"tutto subito": somma(tutti, "gpu") / 1e6,
                                 "progressivo": somma([m for m in [campus, giuriati] if m] + grandi, "gpu") / 1e6}

    # Le fermate della camera
    fermate = {}
    base = [x for m in sfondo for x in m.meshes]
    eb = campus.riquadro("/Campus/Edifici") if campus else None
    if eb is not None:
        planes = piani_frustum(*camera(eb, 0.95, 0.9))
        fermate["campus"] = conta(base, planes)
    for csie, m in edifici.items():
        shell = campus.riquadro(f"/Campus/Edifici/{csie}") if campus else None
        if shell is None:
            continue
        planes = piani_frustum(*camera(shell, 1.0, 1.15))
        fermate[f"edificio {csie}"] = conta(base, planes)
        # Il piano terra: alberi e involucro spenti, i piani sopra spenti.
        piani = sorted({p["path"].split("/")[3] for p in m.meshes if p["path"].count("/") >= 3 and "/Piani/" in p["path"]})
        if not piani:
            continue
        terra = next((p for p in piani if p.endswith("000")), piani[0])
        idx = piani.index(terra)
        box = m.riquadro(f"/{csie}/Piani/{terra}")
        if box is None:
            continue
        planes = piani_frustum(*camera(box, 0.6, 1.0))
        fondo = [x for x in base if "/Alberi/" not in x["path"] and "/Chiome" not in x["path"]
                 and "/Tronchi" not in x["path"] and not x["path"].startswith(f"/Campus/Edifici/{csie}")]
        sotto = [x for x in m.meshes if any(x["path"].startswith(f"/{csie}/Piani/{p}/") or x["path"] == f"/{csie}/Piani/{p}"
                                            for p in piani[:idx + 1])]
        fermate[f"piano {terra}"] = conta(fondo + sotto, planes)
    out["fermate"] = {k: dict(triangoli=t, draw_call=d) for k, (t, d) in fermate.items()}
    tri = [v["triangoli"] for k, v in out["fermate"].items() if k != "campus"]
    dc = [v["draw_call"] for k, v in out["fermate"].items() if k != "campus"]
    out["fermate_riassunto"] = dict(campus=out["fermate"].get("campus"),
                                    tri_mediana=statistics.median(tri) if tri else 0, tri_max=max(tri) if tri else 0,
                                    dc_mediana=statistics.median(dc) if dc else 0, dc_max=max(dc) if dc else 0)
    return out


def tabella(out):
    t, p = out["totale"], out["primo_frame"]
    r = out["fermate_riassunto"]
    righe = [
        "| Metrica | Valore |", "|---|---|",
        f"| Bundle (tutti i .usdz) | {t['mb']:.1f} MB |",
        f"| Download (deflate) | {t['download_mb']:.1f} MB |",
        f"| Triangoli totali | {t['triangoli']:,} |",
        f"| Vertici totali | {t['vertici']:,} |",
        f"| Mesh totali | {t['mesh']:,} |",
        f"| Memoria GPU stimata, tutto caricato | {t['gpu_mb']:.0f} MB |",
        f"| Parsing, tutti i file | {t['parse_ms']:.0f} ms |",
    ]
    for k, v in p.items():
        righe.append(f"| Primo frame, {k}: file / MB / parsing / collisioni | {v['file']} / {v['mb']:.1f} MB / "
                     f"{v['parse_ms']:.0f} ms / {v['collisioni_mesh']} mesh |")
    m = out["memoria_regime"]
    righe.append(f"| Memoria GPU stimata a regime, tutto subito / progressivo | {m['tutto subito']:.0f} / {m['progressivo']:.0f} MB |")
    if r["campus"]:
        righe.append(f"| Fermata campus: triangoli / draw call | {r['campus']['triangoli']:,} / {r['campus']['draw_call']} |")
    righe.append(f"| Altre fermate: triangoli mediana / max | {r['tri_mediana']:,.0f} / {r['tri_max']:,} |")
    righe.append(f"| Altre fermate: draw call mediana / max | {r['dc_mediana']:.0f} / {r['dc_max']} |")
    righe += ["", "| File | MB | Download MB | Mesh | Triangoli | Vertici | V/T | Materiali | GPU MB | Parsing ms | Collisioni |",
              "|---|---|---|---|---|---|---|---|---|---|---|"]
    for k, v in sorted(out["file"].items(), key=lambda kv: -kv[1]["mb"]):
        righe.append(f"| {k} | {v['mb']:.2f} | {v['download_mb']:.2f} | {v['mesh']} | {v['triangoli']:,} | {v['vertici']:,} | "
                     f"{v['vertici_per_tri']} | {v['materiali']} | {v['gpu_mb']:.1f} | {v['parse_ms']:.0f} | {v['collisioni_mesh']} |")
    return "\n".join(righe) + "\n"


if __name__ == "__main__":
    a = argparse.ArgumentParser()
    a.add_argument("cartella")
    a.add_argument("--json", type=pathlib.Path)
    a.add_argument("--md", type=pathlib.Path)
    a = a.parse_args()
    out = misura(a.cartella)
    md = tabella(out)
    print(md)
    if a.json:
        a.json.write_text(json.dumps(out, indent=1, default=float) + "\n")
    if a.md:
        a.md.write_text(md)
