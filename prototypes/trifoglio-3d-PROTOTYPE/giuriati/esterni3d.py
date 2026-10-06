#!/usr/bin/env python3
"""PROTOTIPO — il Centro Sportivo Giuriati e il suo isolato in 3D: solo l'esterno, cioè
suolo, verde, campi, pista, percorsi, alberi, recinzioni e arredi. Gli edifici sono
soltanto la loro impronta (`Edifici/<csie>_Impronta`), da sostituire con i volumi quando
si modellano.

    python3 esterni3d.py giuriati.json <cartella di uscita> [--png] [--leonardo <design/mappa>/leonardo.json]

Scrive giuriati.usdz nello stesso frame e con gli stessi assi di campus.usdz (X est, Y su,
Z sud, metri, origine del campus Leonardo), quindi si sovrappone al campus senza
spostamenti; con --png anche giuriati.png, la vista dall'alto.
Usa la palette, le estrusioni e l'esportazione USD di ../esporta3d.py.
"""
import argparse, json, math, pathlib, sys, tempfile
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union
from shapely import affinity

A = argparse.ArgumentParser()
A.add_argument("dati", type=pathlib.Path)
A.add_argument("uscita", type=pathlib.Path)
A.add_argument("--png", action="store_true")
A.add_argument("--leonardo", type=pathlib.Path, help="leonardo.json: il suolo non copre quello di campus.usdz")
A = A.parse_args()

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
sys.argv = [sys.argv[0], ".", tempfile.mkdtemp()]       # esporta3d legge i suoi argomenti all'import
import esporta3d as E                                    # noqa: E402

COL = dict(E.COL)
COL.update({
    "erba": "#9CCB86", "erba_chiara": "#AAD495", "sintetico": "#5FAE6A", "tartan": "#C2584A",
    "padel": "#3D6FB6", "gioco": "#E8D9B5", "calistenica": "#B8564A", "basket": "#D08A4E",
    "righe": "#FFFFFF", "bosco": "#B9D9A8", "pavimentato": "#E4E1DA", "parcheggio": "#D9DCE0",
    "recinzione": "#5B6168", "muro": "#C9C4BA", "impronta": "#D7DAE0", "palo": "#6E747C",
    "panchina": "#8A6A48",
})
SUPERFICIE = {"grass": "erba", "artificial_turf": "sintetico", "tartan": "tartan"}


def P(pts):
    return Polygon([tuple(p) for p in pts]).buffer(0)


def lastra(g, z0, z1, chiave):
    return E.slab(g, z0, z1, COL[chiave])


def righe(linee, z, largo=0.12):
    g = unary_union([l.buffer(largo / 2, cap_style=2) for l in linee if not l.is_empty])
    return lastra(g, z, z + 0.01, "righe")


def rettangolo(poly):
    """Il rettangolo orientato del campo: centro, asse lungo (versore), lunghezza, larghezza."""
    r = poly.minimum_rotated_rectangle
    c = list(r.exterior.coords)[:4]
    e = [np.subtract(c[(i + 1) % 4], c[i]) for i in range(2)]
    lung, larg = (e[0], e[1]) if np.linalg.norm(e[0]) >= np.linalg.norm(e[1]) else (e[1], e[0])
    L, W = np.linalg.norm(lung), np.linalg.norm(larg)
    return np.array(r.centroid.coords[0]), lung / L, larg / W, L, W


def segnatura(poly, sport):
    """Le righe del campo: perimetro, metà campo e, per il rugby, le linee dei 22 e di meta."""
    c, u, v, L, W = rettangolo(poly)
    pt = lambda s, t: tuple(c + u * s + v * t)
    lin = [LineString([pt(-L / 2 + .3, -W / 2 + .3), pt(L / 2 - .3, -W / 2 + .3), pt(L / 2 - .3, W / 2 - .3),
                       pt(-L / 2 + .3, W / 2 - .3), pt(-L / 2 + .3, -W / 2 + .3)]),
           LineString([pt(0, -W / 2), pt(0, W / 2)])]
    if sport == "rugby_union":
        meta = L / 2 - min(10, L * 0.08)                       # area di meta di 10 m dove c'è spazio
        for s in (-meta, meta, -meta + 22, meta - 22):
            lin.append(LineString([pt(s, -W / 2 + .3), pt(s, W / 2 - .3)]))
        lin += [LineString([pt(-meta, 0), pt(-meta - 0.1, 0)])]
    elif sport in ("basketball", "padel", "tennis"):
        lin.append(LineString([pt(-L / 2, 0), pt(L / 2, 0)]) if sport == "padel" else LineString())
    return lin


def alberi(sc, gruppo, punti, nome):
    if not punti:
        return
    chiome, tronchi = [], []
    for x, y, r in punti:
        s = trimesh.creation.icosphere(subdivisions=1, radius=r)
        s.apply_translation([x, y, 2.2 + r * 0.8])
        chiome.append(s)
        t = trimesh.creation.cylinder(radius=0.18, height=2.4, sections=6)
        t.apply_translation([x, y, 1.2])
        tronchi.append(t)
    for parte, lista, hex_ in (("Chiome", chiome, COL["chioma"]), ("Tronchi", tronchi, COL["tronco"])):
        m = trimesh.util.concatenate(lista)
        m.apply_transform(E.YUP)
        m.invert() if m.volume < 0 else None
        sc.mesh(f"{nome}_{parte}", gruppo, E.colour(m, hex_))


def oggetti(sc, gruppo, nome, parti, hex_):
    if parti:
        m = trimesh.util.concatenate(parti)
        m.apply_transform(E.YUP)
        m.invert() if m.volume < 0 else None
        sc.mesh(nome, gruppo, E.colour(m, hex_))


def main():
    d = json.loads(A.dati.read_text())
    area = box(*d["isolato"])
    sc = E.Scena("Giuriati")
    terr = sc.gruppo("Terreno", "Giuriati")
    sport = sc.gruppo("Sport", "Giuriati")
    verde_g = sc.gruppo("Verde", "Giuriati")
    arredi = sc.gruppo("Arredi", "Giuriati")
    edifici = sc.gruppo("Edifici", "Giuriati")

    suolo = area
    if A.leonardo:                    # lo stesso riquadro che campus() in esporta3d.py dà al suo suolo
        c = json.loads(A.leonardo.read_text())
        xs = [p[0] for b in c["edifici"] for p in b["pianta"]]
        ys = [p[1] for b in c["edifici"] for p in b["pianta"]]
        suolo = area.difference(box(min(xs) - 80, min(ys) - 80, max(xs) + 80, max(ys) + 80))
    sc.mesh("Suolo", terr, lastra(suolo, -0.4, 0.0, "terreno"))
    strade = unary_union([LineString(s["punti"]).buffer(s["larghezza"] / 2, cap_style=2)
                          for s in d["strade"]]).intersection(area)
    sc.mesh("Strade", terr, lastra(strade, 0.0, 0.05, "strada"))
    pav = unary_union([P(p["pianta"]) for p in d["pavimentate"]]).intersection(area).difference(strade)
    sc.mesh("Pavimentate", terr, lastra(pav, 0.0, 0.03, "pavimentato"))
    park = unary_union([P(p) for p in d["parcheggi"]]).intersection(area).difference(strade)
    sc.mesh("Parcheggi", terr, lastra(park, 0.0, 0.035, "parcheggio"))

    # i campi e la pista stanno sopra il verde; il verde non ci passa sotto
    campi = [(c, P(c["pianta"])) for c in d["campi"]]
    piste = [(p, Polygon([tuple(q) for q in p["pianta"]], [[tuple(q) for q in h] for h in p.get("buchi", [])]).buffer(0))
             for p in d["piste"]]
    occupato = unary_union([g for _, g in campi] + [g for _, g in piste])

    verde = unary_union([P(v["pianta"]) for v in d["verde"]]).intersection(area)
    # il prato dentro l'anello della pista, fuori dal campo da rugby
    for p, g in piste:
        for h in p.get("buchi", []):
            verde = verde.union(P(h))
    sc.mesh("Prati", verde_g, lastra(verde.difference(occupato).difference(strade), 0.0, 0.04, "verde"))
    boschi = unary_union([P(b["pianta"]) for b in d["boschi"]]).intersection(area)
    sc.mesh("Boschi", verde_g, lastra(boschi.difference(strade), 0.0, 0.045, "bosco"))
    perc = unary_union([LineString(p if isinstance(p, list) else p["punti"]).buffer(1.2)
                        for p in d["percorsi"] if len(p if isinstance(p, list) else p["punti"]) > 1])
    sc.mesh("Percorsi", terr, lastra(perc.intersection(area).difference(strade).difference(occupato), 0.0, 0.06, "percorso"))

    for i, (p, g) in enumerate(piste):
        nome = f"Pista_{i}_{p.get('sport') or 'pista'}"
        sc.mesh(nome, sport, lastra(g, 0.0, 0.08, SUPERFICIE.get(p.get("superficie"), "tartan")))
        # le corsie: l'anello interno allargato di 1,22 m alla volta, tagliato sulla pista
        for h in p.get("buchi", []):
            inner = P(h)
            corsie = [inner.buffer(1.22 * k, join_style=1).exterior.intersection(g) for k in range(1, 9)]
            sc.mesh(nome + "_Corsie", sport, righe(corsie, 0.08, 0.05))
        if not p.get("buchi"):                        # il rettilineo: corsie lungo l'asse lungo
            c, u, v, L, W = rettangolo(g)
            n = max(1, int(W / 1.22))
            linee = [LineString([tuple(c - u * L / 2 + v * (k * W / n - W / 2)), tuple(c + u * L / 2 + v * (k * W / n - W / 2))])
                     for k in range(1, n)]
            sc.mesh(nome + "_Corsie", sport, righe(linee, 0.08, 0.05))
    contatori = {}
    for c, g in campi:
        s = c.get("sport") or "campo"
        contatori[s] = contatori.get(s, 0) + 1
        nome = f"Campo_{s}_{contatori[s]}"
        chiave = {"padel": "padel", "gioco": "gioco", "gymnastics": "calistenica", "basketball": "basket"}.get(
            s, SUPERFICIE.get(c.get("superficie"), "sintetico"))
        if s == "rugby_union":
            # il prato a strisce di falciatura, larghe 5 m lungo l'asse lungo
            cc, u, v, L, W = rettangolo(g)
            strisce = [Polygon([tuple(cc + u * (a - L / 2) + v * (-W)), tuple(cc + u * (a + 5 - L / 2) + v * (-W)),
                                tuple(cc + u * (a + 5 - L / 2) + v * W), tuple(cc + u * (a - L / 2) + v * W)])
                       for a in np.arange(0, L, 10)]
            chiare = unary_union(strisce).intersection(g)
            sc.mesh(nome, sport, lastra(g.difference(chiare), 0.0, 0.07, "erba"))
            sc.mesh(nome + "_Strisce", sport, lastra(chiare, 0.0, 0.07, "erba_chiara"))
        else:
            sc.mesh(nome, sport, lastra(g, 0.0, 0.07, chiave))
        if s not in ("gioco", "gymnastics"):
            sc.mesh(nome + "_Righe", sport, righe(segnatura(g, s), 0.07))
        if c.get("coperto"):                          # padel coperto: pilastri e tetto leggero a 7 m
            cc, u, v, L, W = rettangolo(g)
            pil = []
            for a in (-0.5, 0, 0.5):
                for b in (-0.5, 0.5):
                    t = trimesh.creation.box([0.3, 0.3, 7.0])
                    t.apply_translation([*(cc + u * a * L + v * b * W), 3.5])
                    pil.append(t)
            oggetti(sc, sport, nome + "_Pilastri", pil, COL["palo"])
            sc.mesh(nome + "_Copertura", sport, lastra(g.buffer(0.5), 7.0, 7.25, "tetto"))

    # alberi: quelli isolati e i filari, un albero ogni 7 m
    alberi(sc, verde_g, d["alberi"], "Alberi")
    fil = []
    for f in d["filari"]:
        l = LineString(f)
        n = max(1, int(l.length // 7))
        for k in range(n + 1):
            p = l.interpolate(k / n, normalized=True)
            if area.buffer(5).contains(p):
                fil.append([p.x, p.y, 2.6])
    alberi(sc, verde_g, fil, "Filari")

    # recinzioni (rete scura alta 2,5 m, sottile) e muri (pieni, 2 m)
    for chiave, h, s, col in (("recinzioni", 2.5, 0.05, "recinzione"), ("muri", 2.0, 0.25, "muro")):
        g = unary_union([LineString(r["punti"]).buffer(s / 2, cap_style=2) for r in d[chiave]])
        sc.mesh(chiave.capitalize(), arredi, lastra(g, 0.0, h, col))
    lamp = []
    for x, y in d["lampioni"]:
        t = trimesh.creation.cylinder(radius=0.08, height=5.0, sections=6)
        t.apply_translation([x, y, 2.5])
        lamp.append(t)
        t = trimesh.creation.box([0.6, 0.25, 0.15])
        t.apply_translation([x, y, 5.0])
        lamp.append(t)
    oggetti(sc, arredi, "Lampioni", lamp, COL["palo"])
    pan = []
    for x, y in d["panchine"]:
        t = trimesh.creation.box([1.8, 0.5, 0.45])
        t.apply_translation([x, y, 0.225])
        pan.append(t)
    oggetti(sc, arredi, "Panchine", pan, COL["panchina"])

    # gli edifici: per ora solo l'impronta, chiamata col csie quando si conosce; quelli con un
    # guscio proprio (gusci/<csie>.py) stanno in campus.usdz con il loro esterno
    gusci = pathlib.Path(__file__).resolve().parent.parent / "gusci"
    for i, e in enumerate(d["edifici"]):
        if "pianta" not in e or (e.get("csie") and (gusci / f"{e['csie']}.py").exists()):
            continue
        nome = (e.get("csie") or f"osm_{(e.get('osm') or str(i)).lstrip('wr')}").replace("-", "_")
        if e.get("nome") == "Giuriati Gym":
            nome = "Giuriati_Gym"
        sc.mesh(f"{nome}_Impronta", edifici, lastra(P(e["pianta"]), 0.0, 0.3, "impronta"))

    A.uscita.mkdir(parents=True, exist_ok=True)
    E.usdz(sc, A.uscita / "giuriati.usdz")
    print("giuriati.usdz", sum(1 for _ in sc.s.geometry), "mesh")
    if A.png:
        disegna(d, A.uscita / "giuriati.png")


def disegna(d, path):
    """La vista dall'alto, per controllare a colpo d'occhio cosa c'è (y verso sud = in basso)."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    x0, y0, x1, y1 = d["isolato"]
    fig, ax = plt.subplots(figsize=(14, 14 * (y1 - y0) / (x1 - x0)), dpi=110)
    ax.set_facecolor(COL["terreno"])

    def poly(pts, c, z=1, **kw):
        kw.setdefault("lw", 0)
        ax.fill(*zip(*pts), color=c, zorder=z, **kw)

    for s in d["strade"]:
        g = LineString(s["punti"]).buffer(s["larghezza"] / 2, cap_style=2)
        for p in getattr(g, "geoms", [g]):
            poly(p.exterior.coords, "#FFFFFF", 1)
    for p in d["pavimentate"]:
        poly(p["pianta"], COL["pavimentato"], 1)
    for p in d["parcheggi"]:
        poly(p, COL["parcheggio"], 1)
    for v in d["verde"]:
        poly(v["pianta"], COL["verde"], 2)
    for v in d["boschi"]:
        poly(v["pianta"], COL["bosco"], 2)
    for p in d["piste"]:
        poly(p["pianta"], COL["tartan"], 3)
        for h in p.get("buchi", []):
            poly(h, COL["verde"], 3)
    for c in d["campi"]:
        s = c.get("sport")
        col = {"padel": "padel", "gioco": "gioco", "gymnastics": "calistenica", "basketball": "basket"}.get(
            s, SUPERFICIE.get(c.get("superficie"), "sintetico"))
        poly(c["pianta"], COL[col], 4)
    for p in d["percorsi"]:
        pts = p if isinstance(p, list) else p["punti"]
        ax.plot(*zip(*pts), color="#B9C2CC", lw=1.2, zorder=3)
    for r in d["recinzioni"]:
        ax.plot(*zip(*r["punti"]), color=COL["recinzione"], lw=0.8, zorder=5)
    for r in d["muri"]:
        ax.plot(*zip(*r["punti"]), color="#9C968B", lw=1.6, zorder=5)
    for f in d["filari"]:
        ax.plot(*zip(*f), color=COL["chioma"], lw=5, alpha=0.8, zorder=6, solid_capstyle="round")
    for x, y, r in d["alberi"]:
        ax.add_patch(plt.Circle((x, y), r, color=COL["chioma"], alpha=0.85, zorder=6, lw=0))
    for e in d["edifici"]:
        if "pianta" in e:
            ax.fill(*zip(*e["pianta"]), fc="#C3C8D1", ec="#7D8591", lw=0.6, zorder=7)
            c = Polygon(e["pianta"]).centroid
            lab = e.get("nome") or ""
            if e.get("csie") or e.get("nome") == "Giuriati Gym":
                ax.text(c.x, c.y, lab.replace("Edificio ", "Ed. "), ha="center", va="center", fontsize=7, zorder=9)
        else:
            ax.plot(*e["punto"], marker="*", color="#D9534F", ms=10, zorder=9)
            ax.text(e["punto"][0] + 3, e["punto"][1], e["nome"].replace("Edificio ", "Ed. ") + " (catalogo)",
                    fontsize=7, color="#D9534F", zorder=9)
    for s in {s["nome"]: s for s in d["strade"]}.values():
        l = LineString(s["punti"]).intersection(box(x0 + 5, y0 + 5, x1 - 5, y1 - 5))
        if l.length > 60 and l.geom_type == "LineString":
            m = l.interpolate(0.5, normalized=True)
            (a, b), (c_, e_) = l.coords[0], l.coords[-1]
            ang = -math.degrees(math.atan2(e_ - b, c_ - a))
            ang = ang - 180 if ang > 90 else ang + 180 if ang < -90 else ang
            ax.text(m.x, m.y, s["nome"], rotation=ang, ha="center", va="center", fontsize=7, color="#6B7280", zorder=8)
    ax.set_xlim(x0, x1)
    ax.set_ylim(y1, y0)
    ax.set_aspect("equal")
    ax.set_title("Centro Sportivo Giuriati e isolato — esterni (metri, frame del campus Leonardo)", fontsize=10)
    fig.tight_layout()
    fig.savefig(path)


if __name__ == "__main__":
    main()
