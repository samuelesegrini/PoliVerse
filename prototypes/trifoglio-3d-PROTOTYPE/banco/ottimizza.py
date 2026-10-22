#!/usr/bin/env python3
"""PROTOTIPO — alleggerisce i .usdz che l'app carica, senza cambiare cosa si vede.

    python3 banco/ottimizza.py <file.usdz> [<file.usdz> ...] [--tessera 60]

Due passi, ciascuno misurato con banco/misura.py (vedi banco/README.md):

  salda    unisce i vertici doppi che stanno sulla stessa faccia piana (stessa posizione,
           stessa normale, stessa uv). Un vertice che tocca facce con normali diverse resta
           com'è, quindi le normali che RealityKit ricava sono le stesse di prima.
  tessere  spezza le mesh grandi che coprono tutta la zona (chiome, prati, strade, la città)
           in tessere di N metri, come le tile di una mappa: il frustum culling di RealityKit
           scarta allora le tessere fuori schermo invece di disegnare tutta la mesh. Il nodo
           resta con il suo nome (diventa un Xform con le tessere sotto), così l'app lo trova
           e lo dissolve come prima.

Riscrive i file al loro posto. esporta3d.py lo chiama su ogni .usdz che scrive.

Dipendenze: usd-core, numpy.
"""
import argparse, pathlib, tempfile, zipfile
import numpy as np
from pxr import Usd, UsdGeom, UsdShade, UsdUtils, Sdf, Vt

TESSERA = 60.0          # m, lato minimo di una tessera
TRI_PER_TESSERA = 3000  # una tessera ne tiene almeno tanti in media: ogni tessera è una draw call
INTERI = ("/Campus/Edifici/",)  # gli edifici sono già piccoli: restano come sono


def salda(points, faces, uv=None):
    """Toglie i triangoli senza area e unisce i vertici doppi sulle facce piane.

    Restituisce (points, faces, uv) con i soli vertici usati.
    """
    P = np.asarray(points, np.float64)
    F = np.asarray(faces, np.int64).reshape(-1, 3)
    n = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
    area = np.linalg.norm(n, axis=1)
    tieni = area > 1e-8                       # un triangolo degenere non disegna nulla
    if not tieni.any():
        return points, faces, uv
    F, n = F[tieni], n[tieni] / area[tieni, None]
    V = len(P)
    first = np.full((V, 3), np.nan)
    for k in range(3):                        # la normale della prima faccia di ogni vertice
        idx = F[:, k]
        nuovi = np.isnan(first[idx, 0])
        first[idx[nuovi]] = n[nuovi]
    piatto = np.ones(V, bool)                 # tutte le facce del vertice hanno quella normale
    for k in range(3):
        idx = F[:, k]
        piatto[idx[np.abs(first[idx] - n).max(axis=1) > 1e-3]] = False
    usati = np.unique(F)
    cols = [np.round(P * 1e4).astype(np.int64),
            np.where(piatto[:, None], np.round(np.nan_to_num(first) * 1e3).astype(np.int64), 0),
            # Un vertice non piatto resta solo: una chiave che nessun altro ha.
            np.where(piatto, -1, np.arange(V))[:, None]]
    if uv is not None:
        cols.append(np.round(np.asarray(uv, np.float64) * 1e5).astype(np.int64))
    key = np.concatenate(cols, axis=1)[usati]
    _, keep, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    # L'ordine dei vertici segue la prima comparsa, così il file resta stabile tra un export e l'altro.
    order = np.argsort(keep)
    rank = np.empty_like(order); rank[order] = np.arange(len(order))
    nuovo = np.full(V, -1, np.int64)
    nuovo[usati] = rank[inv.reshape(-1)]
    sorgente = usati[keep[order]]
    newUV = None if uv is None else np.asarray(uv)[sorgente]
    return np.asarray(points)[sorgente], nuovo[F].reshape(-1), newUV


def _array(mesh, name):
    a = mesh.GetPrim().GetAttribute(name)
    return a.Get() if a and a.HasAuthoredValue() else None


def salda_stage(st):
    for prim in list(st.Traverse()):
        if not prim.IsA(UsdGeom.Mesh):
            continue
        m = UsdGeom.Mesh(prim)
        counts = m.GetFaceVertexCountsAttr().Get()
        if not counts or any(c != 3 for c in counts):
            continue
        pv = UsdGeom.PrimvarsAPI(prim)
        st_pv = pv.GetPrimvar("st") if pv.HasPrimvar("st") else None
        if st_pv and st_pv.GetInterpolation() != UsdGeom.Tokens.vertex:
            continue
        uv = np.array(st_pv.Get()) if st_pv else None
        P, F, UV = salda(np.array(m.GetPointsAttr().Get()), np.array(m.GetFaceVertexIndicesAttr().Get()), uv)
        m.GetPointsAttr().Set(Vt.Vec3fArray.FromNumpy(np.asarray(P, np.float32)))
        m.GetFaceVertexIndicesAttr().Set(Vt.IntArray.FromNumpy(np.asarray(F, np.int32)))
        m.GetFaceVertexCountsAttr().Set(Vt.IntArray([3] * (len(F) // 3)))
        if st_pv:
            st_pv.Set(Vt.Vec2fArray.FromNumpy(np.asarray(UV, np.float32)))


def componenti(F, V):
    """L'etichetta del pezzo connesso di ogni vertice (facce che condividono vertici)."""
    lab = np.arange(V)
    while True:
        m = lab[F].min(axis=1)
        nuovo = lab.copy()
        for k in range(3):
            np.minimum.at(nuovo, F[:, k], m)
        nuovo = nuovo[nuovo]                     # salto dei puntatori
        while not np.array_equal(nuovo, nuovo[nuovo]):
            nuovo = nuovo[nuovo]
        if np.array_equal(nuovo, lab):
            return lab
        lab = nuovo


def tessere(st, lato=TESSERA, minimo=TRI_PER_TESSERA):
    """Spezza le mesh grandi in tessere di `lato` metri sul piano X-Z."""
    for prim in list(st.Traverse()):
        if not prim.IsA(UsdGeom.Mesh) or str(prim.GetPath()).startswith(INTERI):
            continue
        m = UsdGeom.Mesh(prim)
        P = np.array(m.GetPointsAttr().Get())
        F = np.array(m.GetFaceVertexIndicesAttr().Get()).reshape(-1, 3)
        if len(F) < 2 * minimo:
            continue
        # Un pezzo connesso (una chioma, un marciapiede) va tutto in una tessera, scelta dal
        # suo centro: tagliarlo staccherebbe i vertici condivisi e cambierebbe le normali.
        lab = componenti(F, len(P))[F[:, 0]]
        ids, inv = np.unique(lab, return_inverse=True)
        inv = inv.reshape(-1)
        cen = np.zeros((len(ids), 2)); cnt = np.zeros(len(ids))
        np.add.at(cen, inv, P[F].mean(axis=1)[:, [0, 2]]); np.add.at(cnt, inv, 1)
        c = (cen / cnt[:, None])[inv]
        lo, hi = c.min(axis=0), c.max(axis=0)
        w, h = np.maximum(hi - lo, 1)
        # Il lato cresce finché ogni tessera tiene in media `minimo` triangoli.
        lato_m = max(lato, float(np.sqrt(w * h * minimo / len(F))))
        if max(w, h) <= lato_m * 1.5:
            continue
        cell = np.floor((c - lo) / lato_m).astype(int)
        pv = UsdGeom.PrimvarsAPI(prim)
        uv = np.array(pv.GetPrimvar("st").Get()) if pv.HasPrimvar("st") else None
        binding = UsdShade.MaterialBindingAPI(prim).GetDirectBinding().GetMaterial()
        scheme = m.GetSubdivisionSchemeAttr().Get()
        path = Sdf.Path(str(prim.GetPath()))
        # Il nodo diventa un Xform con lo stesso nome; la mesh si sposta nelle tessere.
        for name in ("points", "faceVertexCounts", "faceVertexIndices", "subdivisionScheme", "primvars:st",
                     "extent", "normals"):
            if prim.HasAttribute(name):
                prim.RemoveProperty(name)
        prim.SetTypeName("Xform")
        for (i, j) in sorted({tuple(x) for x in cell}):
            sel = (cell[:, 0] == i) & (cell[:, 1] == j)
            sub = F[sel]
            used, inv = np.unique(sub, return_inverse=True)
            t = UsdGeom.Mesh.Define(st, path.AppendChild(f"{path.name}_t{i}_{j}"))
            t.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(np.asarray(P[used], np.float32)))
            t.CreateFaceVertexCountsAttr(Vt.IntArray([3] * len(sub)))
            t.CreateFaceVertexIndicesAttr(Vt.IntArray.FromNumpy(inv.reshape(-1).astype(np.int32)))
            t.CreateSubdivisionSchemeAttr(scheme or "none")
            if uv is not None:
                p = UsdGeom.PrimvarsAPI(t).CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex)
                p.Set(Vt.Vec2fArray.FromNumpy(np.asarray(uv[used], np.float32)))
            if binding:
                UsdShade.MaterialBindingAPI.Apply(t.GetPrim()).Bind(binding)


def _apri(path, tmp):
    """Estrae un .usdz in una cartella e ne apre il livello radice per modificarlo."""
    with zipfile.ZipFile(path) as z:
        z.extractall(tmp)
        radice = next(n for n in z.namelist() if n.endswith((".usdc", ".usda")))
    return Usd.Stage.Open(str(tmp / radice)), tmp / radice


def _impacchetta(st, layer, dest):
    # Export e non Save: un .usdc salvato sul posto accoda i dati nuovi e tiene i vecchi.
    fresco = layer.with_name("_" + layer.name)
    st.GetRootLayer().Export(str(fresco))
    fresco.replace(layer)
    tmp = dest.with_suffix(".tmp.usdz")
    UsdUtils.CreateNewUsdzPackage(str(layer), str(tmp))
    tmp.replace(dest)


def ottimizza(path, lato=TESSERA):
    path = pathlib.Path(path)
    with tempfile.TemporaryDirectory() as d:
        st, layer = _apri(path, pathlib.Path(d))
        salda_stage(st)
        if lato:
            tessere(st, lato)
        _impacchetta(st, layer, path)


if __name__ == "__main__":
    a = argparse.ArgumentParser()
    a.add_argument("file", nargs="+", type=pathlib.Path)
    a.add_argument("--tessera", type=float, default=TESSERA, help="lato delle tessere in metri; 0 per non tagliare")
    a = a.parse_args()
    for f in a.file:
        prima = f.stat().st_size
        ottimizza(f, a.tessera)
        print(f"{f.name}: {prima / 1e6:.2f} → {f.stat().st_size / 1e6:.2f} MB")
