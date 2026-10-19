#!/usr/bin/env python3
"""PROTOTIPO — gli edifici del campus visti da lontano: involucri semplificati (LOD).

    python3 banco/lontano.py <campus.usdz> [--quota 0.15] [--minimo 2]

Scrive accanto a campus.usdz il file campus_lontano.usdz: per ogni `Campus/Edifici/<csie>` il
suo involucro con circa `quota` dei triangoli. Le mesh di un edificio si uniscono in una sola,
saldata, senza i pezzi più piccoli di `minimo` metri, che si semplifica per errore quadrico (fast-simplification); ogni triangolo rimasto
riprende il materiale del triangolo originale più vicino, e si torna a una mesh per materiale.
Le facce restano piatte: alla fine ogni triangolo ha i suoi vertici.

Perché: sull'iPhone 12 Pro il campus fermo sta a cavallo dei 16,7 ms per frame e scivola a
30 fps (banco/README.md); gli involucri sono 1,24 M triangoli, inutili da lontano. Con 2 m e
0,15 restano 500 k triangoli e da 400 m l'aspetto quasi non cambia; con 4 m i muri fatti di
pezzi piccoli si bucano. Trifoglio3DScene mostra questi involucri dalla vista campus e quelli
veri quando la camera scende su un edificio. esporta3d.py lo chiama su campus.usdz e poi
salda il risultato con ottimizza.py (20 → 14 MB).

Dipendenze: usd-core, numpy, fast-simplification.
"""
import argparse, pathlib, tempfile, zipfile
import fast_simplification
import numpy as np
from pxr import Usd, UsdGeom, UsdShade, UsdUtils, Vt
from ottimizza import componenti

QUOTA = 0.15
MINIMO = 2.0      # metri: i pezzi più piccoli (cornici, davanzali, ringhiere) da lontano non si vedono


def vicini(src, dst, cella=0.5):
    """Per ogni punto di dst, l'indice del punto di src più vicino (griglia, poi forza bruta locale)."""
    from collections import defaultdict
    grid = defaultdict(list)
    keys = np.floor(src / cella).astype(np.int64)
    for i, k in enumerate(map(tuple, keys)):
        grid[k].append(i)
    out = np.zeros(len(dst), np.int64)
    for j, p in enumerate(dst):
        k = np.floor(p / cella).astype(np.int64)
        for r in range(1, 6):
            cand = [i for dx in range(-r, r + 1) for dy in range(-r, r + 1) for dz in range(-r, r + 1)
                    for i in grid.get((k[0] + dx, k[1] + dy, k[2] + dz), ())]
            if cand:
                c = np.array(cand)
                out[j] = c[np.argmin(np.linalg.norm(src[c] - p, axis=1))]
                break
    return out


def lontano(campus, quota=QUOTA, minimo=MINIMO):
    campus = pathlib.Path(campus)
    dest = campus.with_name("campus_lontano.usdz")
    prima = dopo = 0
    with tempfile.TemporaryDirectory() as d:
        d = pathlib.Path(d)
        with zipfile.ZipFile(campus) as z:
            z.extractall(d)
            radice = next(n for n in z.namelist() if n.endswith((".usdc", ".usda")))
        st = Usd.Stage.Open(str(d / radice))
        for child in st.GetPrimAtPath("/Campus").GetChildren():
            if child.GetName() != "Edifici":
                st.RemovePrim(child.GetPath())
        for edificio in list(st.GetPrimAtPath("/Campus/Edifici").GetChildren()):
            Ps, Fs, mats, uso = [], [], [], []
            off = 0
            for prim in Usd.PrimRange(edificio):
                if not prim.IsA(UsdGeom.Mesh):
                    continue
                m = UsdGeom.Mesh(prim)
                P = np.array(m.GetPointsAttr().Get(), np.float64)
                F = np.array(m.GetFaceVertexIndicesAttr().Get()).reshape(-1, 3)
                if not len(F):
                    continue
                rel = UsdShade.MaterialBindingAPI(prim).GetDirectBinding().GetMaterialPath()
                mats.append(str(rel) if rel else "")
                Ps.append(P); Fs.append(F + off); uso.append(np.full(len(F), len(mats) - 1))
                off += len(P)
            for child in list(edificio.GetChildren()):
                st.RemovePrim(child.GetPath())
            if not Ps:
                continue
            P, F, mat = np.concatenate(Ps), np.concatenate(Fs), np.concatenate(uso)
            prima += len(F)
            q = np.round(P * 1e3).astype(np.int64)
            _, first, inv = np.unique(q, axis=0, return_index=True, return_inverse=True)
            V, G = P[first], inv.reshape(-1)[F]
            ok = (G[:, 0] != G[:, 1]) & (G[:, 1] != G[:, 2]) & (G[:, 0] != G[:, 2])
            G, mat = G[ok], mat[ok]
            # Via i pezzi connessi più piccoli di `minimo` metri in ogni direzione.
            lab = componenti(G, len(V))[G[:, 0]]
            _, pezzo = np.unique(lab, return_inverse=True)
            lo = np.full((pezzo.max() + 1, 3), np.inf); hi = np.full_like(lo, -np.inf)
            C = V[G]
            np.minimum.at(lo, pezzo, C.min(axis=1)); np.maximum.at(hi, pezzo, C.max(axis=1))
            grande = (hi - lo).max(axis=1) >= minimo
            G, mat = G[grande[pezzo]], mat[grande[pezzo]]
            if len(G) > 200:
                V2, G2 = fast_simplification.simplify(V.astype(np.float32), G.astype(np.int32), target_reduction=1 - quota)
                V2, G2 = np.asarray(V2, np.float64), np.asarray(G2)
            else:
                V2, G2 = V, G
            # Il materiale del triangolo originale più vicino al centro di ogni triangolo nuovo.
            m2 = mat[vicini(V[G].mean(axis=1), V2[G2].mean(axis=1))]
            dopo += len(G2)
            for k in np.unique(m2):
                tris = V2[G2[m2 == k]].reshape(-1, 3).astype(np.float32)
                mesh = UsdGeom.Mesh.Define(st, edificio.GetPath().AppendChild(f"{edificio.GetName()}_Lontano_{k}"))
                mesh.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(tris))
                mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3] * (len(tris) // 3)))
                mesh.CreateFaceVertexIndicesAttr(Vt.IntArray.FromNumpy(np.arange(len(tris), dtype=np.int32)))
                mesh.CreateSubdivisionSchemeAttr("none")
                if mats[k]:
                    UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(UsdShade.Material(st.GetPrimAtPath(mats[k])))
        layer = d / "campus_lontano.usdc"
        st.GetRootLayer().Export(str(layer))
        tmp = dest.with_suffix(".tmp.usdz")
        UsdUtils.CreateNewUsdzPackage(str(layer), str(tmp))
        tmp.replace(dest)
    return dest, prima, dopo


if __name__ == "__main__":
    a = argparse.ArgumentParser()
    a.add_argument("campus", type=pathlib.Path)
    a.add_argument("--quota", type=float, default=QUOTA)
    a.add_argument("--minimo", type=float, default=MINIMO)
    a = a.parse_args()
    dest, prima, dopo = lontano(a.campus, a.quota, a.minimo)
    print(f"{dest.name}: {prima:,} → {dopo:,} triangoli, {dest.stat().st_size / 1e6:.2f} MB")
