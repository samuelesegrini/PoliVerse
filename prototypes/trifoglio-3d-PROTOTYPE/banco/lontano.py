#!/usr/bin/env python3
"""PROTOTIPO — gli edifici del campus visti da lontano: involucri semplificati (LOD).

    python3 banco/lontano.py <campus.usdz> [--quota 0.15] [--minimo 2]

Scrive accanto a campus.usdz il file campus_lontano.usdz: per ogni `Campus/Edifici/<csie>` una
sola mesh, con un solo materiale per tutti. Le mesh di un edificio si uniscono e si saldano,
perdono i pezzi più piccoli di `minimo` metri e si semplificano per errore quadrico a circa
`quota` dei triangoli (fast-simplification). Ogni triangolo rimasto prende il colore del
materiale del triangolo originale più vicino (la media della texture, se ne ha una), letto da
una tavolozza: una texture con un quadretto per colore. Le facce restano piatte.

Perché: sull'iPhone 12 Pro il campus fermo sta a cavallo dei 16,7 ms per frame e scivola a
30 fps; la scena vuota sta a 60, senza edifici quasi, e dimezzare i triangoli degli involucri
non cambia nulla (banco/README.md). Quello che costa sono le 540 mesh con 404 materiali degli
involucri: qui diventano 36 mesh e 1 materiale. Con 2 m e 0,15 restano 500 k triangoli e da
400 m l'aspetto quasi non cambia; con 4 m i muri fatti di pezzi piccoli si bucano.
Trifoglio3DScene mostra questi involucri dalla vista campus e quelli veri quando la camera
scende su un edificio. esporta3d.py lo chiama su campus.usdz e poi salda il risultato con
ottimizza.py (30 → 21 MB).

Dipendenze: usd-core, numpy, pillow, fast-simplification.
"""
import argparse, pathlib, tempfile, zipfile
import fast_simplification
import numpy as np
from PIL import Image
from pxr import Sdf, Usd, UsdGeom, UsdShade, UsdUtils, Vt
from ottimizza import componenti

QUOTA = 0.15
CASELLA = 8       # pixel per lato del quadretto di ogni colore nella tavolozza
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


def colore(st, cartella, percorso):
    """Il colore sRGB 0–1 di un materiale: il suo diffuseColor, o la media della sua texture."""
    pbr = st.GetPrimAtPath(percorso).GetChild("PBR") if percorso else None
    if not pbr:
        return np.array([0.8, 0.8, 0.8])
    ingresso = UsdShade.Shader(pbr).GetInput("diffuseColor")
    fonti = ingresso.GetConnectedSources()[0] if ingresso else []
    if fonti:
        file = UsdShade.Shader(fonti[0].source.GetPrim()).GetInput("file").Get()
        with Image.open(cartella / file.path) as img:
            return np.asarray(img.convert("RGB"), np.float64).reshape(-1, 3).mean(axis=0) / 255
    lineare = np.array(ingresso.Get() if ingresso and ingresso.Get() is not None else (0.6, 0.6, 0.6))
    return np.where(lineare <= 0.0031308, lineare * 12.92, 1.055 * lineare ** (1 / 2.4) - 0.055)


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
        cartella = (d / radice).parent
        for child in st.GetPrimAtPath("/Campus").GetChildren():
            if child.GetName() != "Edifici":
                st.RemovePrim(child.GetPath())
        tavolozza = {}              # colore sRGB a 8 bit -> casella
        pezzi = []                  # (edificio, vertici dei triangoli, casella di ogni triangolo)
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
                mats.append(rel if rel else None)
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
            # Il materiale del triangolo originale più vicino al centro di ogni triangolo nuovo,
            # ridotto al suo colore: una casella della tavolozza.
            m2 = mat[vicini(V[G].mean(axis=1), V2[G2].mean(axis=1))]
            caselle = np.empty(len(m2), np.int64)
            for k in np.unique(m2):
                rgb = tuple(np.round(colore(st, cartella, mats[k]) * 255).astype(int))
                caselle[m2 == k] = tavolozza.setdefault(rgb, len(tavolozza))
            pezzi.append((edificio, V2[G2].reshape(-1, 3).astype(np.float32), caselle))
            dopo += len(G2)

        # Una sola texture con un quadretto per colore, e un solo materiale per tutti: una
        # mesh e una draw call per edificio invece di una per materiale.
        lato = CASELLA * int(np.ceil(np.sqrt(len(tavolozza))))
        lato = 1 << int(np.ceil(np.log2(lato)))
        per_riga = lato // CASELLA
        img = Image.new("RGB", (lato, lato))
        for rgb, i in tavolozza.items():
            x, y = i % per_riga * CASELLA, i // per_riga * CASELLA
            img.paste(rgb, (x, y, x + CASELLA, y + CASELLA))
        img.save(cartella / "lontano.png")
        st.RemovePrim("/Materiali")
        materiale = UsdShade.Material.Define(st, "/Materiali/Lontano")
        pbr = UsdShade.Shader.Define(st, "/Materiali/Lontano/PBR")
        pbr.CreateIdAttr("UsdPreviewSurface")
        pbr.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.9)
        lettore = UsdShade.Shader.Define(st, "/Materiali/Lontano/st")
        lettore.CreateIdAttr("UsdPrimvarReader_float2")
        lettore.CreateInput("varname", Sdf.ValueTypeNames.String).Set("st")
        tex = UsdShade.Shader.Define(st, "/Materiali/Lontano/tex")
        tex.CreateIdAttr("UsdUVTexture")
        tex.CreateInput("file", Sdf.ValueTypeNames.Asset).Set("lontano.png")
        tex.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(lettore.ConnectableAPI(), "result")
        pbr.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).ConnectToSource(tex.ConnectableAPI(), "rgb")
        materiale.CreateSurfaceOutput().ConnectToSource(pbr.ConnectableAPI(), "surface")
        for edificio, tris, caselle in pezzi:
            # Il centro del quadretto: con le tre uv uguali la texture non sfuma mai nel vicino.
            u = (caselle % per_riga * CASELLA + CASELLA / 2) / lato
            v = 1 - (caselle // per_riga * CASELLA + CASELLA / 2) / lato
            uv = np.repeat(np.stack([u, v], axis=1), 3, axis=0).astype(np.float32)
            mesh = UsdGeom.Mesh.Define(st, edificio.GetPath().AppendChild(f"{edificio.GetName()}_Lontano"))
            mesh.CreatePointsAttr(Vt.Vec3fArray.FromNumpy(tris))
            mesh.CreateFaceVertexCountsAttr(Vt.IntArray([3] * (len(tris) // 3)))
            mesh.CreateFaceVertexIndicesAttr(Vt.IntArray.FromNumpy(np.arange(len(tris), dtype=np.int32)))
            mesh.CreateSubdivisionSchemeAttr("none")
            UsdGeom.PrimvarsAPI(mesh).CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray,
                                                    UsdGeom.Tokens.vertex).Set(Vt.Vec2fArray.FromNumpy(uv))
            UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(materiale)
        layer = cartella / "campus_lontano.usdc"
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
