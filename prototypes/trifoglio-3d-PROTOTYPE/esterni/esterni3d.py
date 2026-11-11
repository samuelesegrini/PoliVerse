#!/usr/bin/env python3
"""PROTOTIPO — il suolo di tutta la zona del Politecnico in 3D, da `zona.json`
(scritto da importa.py): strade in asfalto con le strisce pedonali e la mezzeria, i binari
del tram, i marciapiedi rialzati, le piazze, i percorsi, il verde con le aiuole e le siepi,
gli alberi (latifoglie, conifere, palme, filari), i lampioni, le panchine, i semafori e i
volumi degli edifici della città intorno.

esporta3d.py lo chiama da campus() quando `esterni/zona.json` c'è:

    terreno(E, sc, "Campus", zona, escludi=<riquadro di giuriati.json>)

E è il modulo esporta3d (slab, colour, YUP, Solidi), sc la sua Scena. Dentro `escludi` i
campi e la pista li disegna giuriati/esterni3d.py, qui restano solo tolti dal verde.

Per provarlo da solo, senza gli edifici del campus:

    python3 esterni3d.py zona.json <cartella> [--glb]
"""
import json, math, pathlib, sys, zlib
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union

COL = {
    "suolo": "#E4E2DC", "asfalto": "#8F949B", "parcheggio": "#A4A8AE", "segnaletica": "#F5F5F1",
    "binari": "#5E636B", "marciapiede": "#DCD8CF", "piazza": "#E6E1D7", "ghiaia": "#E6DCC5",
    "prato": "#B2D59A", "parco": "#ABD193", "giardino": "#A3CC8C", "cani": "#BCD7A2", "bosco": "#98C283",
    "arbusti": "#8FBA79", "terra": "#8C7258", "acqua": "#93C3DE", "bordo": "#D3CEC4", "siepe": "#6E9E5B",
    "tronco": "#7A5C40", "chioma": ["#8EBF73", "#9CC981", "#7FB167"], "conifera": "#5F915B",
    "palma": "#82B064", "fiori": ["#E58FA6", "#F2C75C", "#B58BD6", "#F4F1EA"],
    "quartiere": "#DFE2E7", "tetto": "#F2F3F5", "palo": "#5B6168", "panchina": "#8A6A48", "luce": "#F6EBC8",
    "tartan": "#C2584A", "sintetico": "#5FAE6A", "erba": "#9CCB86", "campo": "#C9A27A", "gioco": "#E8D9B5",
    "cemento": "#C9C6BF",
}
SUPERFICIE = {"tartan": "tartan", "artificial_turf": "sintetico", "grass": "erba", "rubbercrumb": "gioco",
              "concrete": "cemento"}
MARCIAPIEDE = {"primary": 4, "secondary": 3.5, "tertiary": 3, "residential": 2.5, "unclassified": 2.5,
               "living_street": 2, "unknown": 2}
MEZZERIA = {"primary", "secondary", "tertiary"}


def P(pts, buchi=()):
    return Polygon([tuple(p) for p in pts], [[tuple(p) for p in h] for h in buchi]).buffer(0)


def L(pts):
    return LineString([tuple(p) for p in pts])


def caso(x, y, k=0):
    """Un numero fra 0 e 1 fisso per ogni posizione: gli alberi non cambiano a ogni esportazione."""
    return (zlib.crc32(f"{x:.1f},{y:.1f},{k}".encode()) % 10007) / 10007


def unisci(E, parti, hex_):
    if not parti:
        return None
    m = trimesh.util.concatenate(parti)
    m.apply_transform(E.YUP)
    m.invert() if m.volume < 0 else None
    return E.colour(m, hex_)


def lastra(E, g, z0, z1, chiave, tex=None):
    """Una lastra piana; con tex, la texture ripetuta in metri vista dall'alto."""
    if tex is None:
        return E.slab(g, z0, z1, COL[chiave])
    S = E.Solidi()
    for p in E.clean(g):
        m = trimesh.creation.extrude_polygon(p, z1 - z0, engine="earcut")
        m.apply_translation([0, 0, z0])
        S.solid(tex, m)
    return S.meshes().get(tex)


def strisce_pedonali(attr, carreggiata):
    """Le zebre: rettangoli da 50 cm ogni metro lungo l'attraversamento, lunghi 3 m nel senso
    della strada, tagliati sull'asfalto."""
    out = []
    for pts in attr:
        l = L(pts).intersection(carreggiata)
        for seg in getattr(l, "geoms", [l]):
            if seg.geom_type != "LineString" or seg.length < 2:
                continue
            a, b = np.array(seg.coords[0]), np.array(seg.coords[-1])
            u = (b - a) / np.linalg.norm(b - a)
            v = np.array([-u[1], u[0]])
            n = int(seg.length // 1.0)
            off = (seg.length - n) / 2
            for k in range(n):
                c = a + u * (off + 0.5 + k)
                out.append(Polygon([tuple(c - u * .25 - v * 1.5), tuple(c + u * .25 - v * 1.5),
                                    tuple(c + u * .25 + v * 1.5), tuple(c - u * .25 + v * 1.5)]))
    return unary_union(out).intersection(carreggiata) if out else Polygon()


def mezzeria(strade, zebre):
    """La linea tratteggiata in mezzo alle strade principali: 3 m sì, 4,5 m no, lontano 8 m
    dagli incroci (le estremità dei tratti di OSM) e dalle strisce."""
    out = []
    for s in strade:
        if s["classe"] not in MEZZERIA or s.get("tipo") == "link" or s["larghezza"] < 8:
            continue
        l = L(s["punti"])
        d = 8.0
        while d + 3 < l.length - 8:
            out.append(LineString([l.interpolate(d), l.interpolate(d + 3)]).buffer(0.08, cap_style=2))
            d += 7.5
    return unary_union(out).difference(zebre.buffer(1.5)) if out else Polygon()


def binari(tram):
    """Ogni linea del tram di OSM è un binario: due rotaie a 1,445 m."""
    out = []
    for pts in tram:
        l = L(pts)
        for lato in (-0.7225, 0.7225):
            r = l.offset_curve(lato)
            if not r.is_empty:
                out.append(r.buffer(0.05, cap_style=2))
    return unary_union(out) if out else Polygon()


def albero(x, y, chioma, alto, tipo):
    """Le parti (chioma, tronco) di un albero, nel frame Z-su. Le dimensioni vengono da OSM
    dove ci sono (diametro della chioma, altezza), se no da un albero di città, 9-12 m."""
    k = caso(x, y)
    if tipo == "conifera":
        h = alto or 10 + 4 * k
        r = chioma or h * 0.22
        coni = []
        for i, (f, s) in enumerate(((0.25, 1.0), (0.5, 0.75), (0.72, 0.5))):
            c = trimesh.creation.cone(radius=r * s, height=h * 0.45, sections=8)
            c.apply_translation([x, y, h * f])
            coni.append(c)
        t = trimesh.creation.cylinder(radius=0.2, height=h * 0.3, sections=6)
        t.apply_translation([x, y, h * 0.15])
        return "conifera", coni, [t]
    if tipo == "palma":
        h = alto or 6 + 3 * k
        t = trimesh.creation.cylinder(radius=0.17, height=h, sections=6)
        t.apply_translation([x, y, h / 2])
        c = trimesh.creation.icosphere(subdivisions=1, radius=1.0)
        c.apply_scale([chioma or 2.2, chioma or 2.2, 0.8])
        c.apply_translation([x, y, h])
        return "palma", [c], [t]
    r = chioma or 2.8 + 1.2 * k
    h = alto or max(8.0, r * 2.6 + 2 * caso(x, y, 1))
    base = max(2.5, h - 1.7 * r)                 # dove comincia la chioma
    sfere = []
    for i in range(3):                           # tre sfere un po' spostate: una chioma irregolare
        a = 2 * math.pi * (caso(x, y, 2 + i) + i / 3)
        rr = r * (0.62 + 0.18 * caso(x, y, 5 + i))
        s = trimesh.creation.icosphere(subdivisions=1, radius=rr)
        s.apply_scale([1, 1, 0.9])
        s.apply_translation([x + math.cos(a) * r * 0.38, y + math.sin(a) * r * 0.38,
                             base + r * (0.75 + 0.35 * (i == 0))])
        sfere.append(s)
    t = trimesh.creation.cylinder(radius=0.12 + 0.03 * r, height=base + r * 0.5, sections=6)
    t.apply_translation([x, y, (base + r * 0.5) / 2])
    return f"latifoglia{int(caso(x, y, 9) * 3)}", sfere, [t]


def terreno(E, sc, radice, d, escludi=None, ingombri=()):
    """Aggiunge a sc i gruppi Terreno (suolo, strade, verde…), Alberi (Chiome, Tronchi),
    Arredi e Quartiere sotto `radice`. `escludi`: dove i campi li disegna giuriati.usdz;
    `ingombri`: le piante degli edifici del campus, dove non va nessun albero."""
    zona = box(*d["zona"])
    pieni = unary_union([P(e["pianta"]) for e in d["edifici"]] + [g.buffer(0) for g in ingombri])
    escludi = escludi if escludi is not None else Polygon()
    terr = sc.gruppo("Terreno", radice)

    sc.mesh("Suolo", terr, lastra(E, zona, -0.4, 0.0, "suolo"))

    # ---- le strade: asfalto, poi i marciapiedi intorno dove OSM non li disegna a parte
    car = unary_union([L(s["punti"]).buffer(s["larghezza"] / 2, quad_segs=4) for s in d["strade"]]).intersection(zona)
    # gli alberi che OSM mette in mezzo alla strada stanno su uno spartitraffico verde
    spart = unary_union([Point(t[0], t[1]).buffer(1.4, quad_segs=3) for t in d["alberi"]]
                        + [L(f).buffer(1.4, cap_style=2) for f in d["filari"]]).intersection(car)
    spart = unary_union([g for g in getattr(spart, "geoms", [spart]) if g.area > 3]).buffer(0)
    car = car.difference(spart)
    park = unary_union([P(p["pianta"]) for p in d["parcheggi"]]).intersection(zona).difference(car)
    marc = unary_union([L(s["punti"]).buffer(s["larghezza"] / 2 + MARCIAPIEDE[s["classe"]], quad_segs=4)
                        for s in d["strade"] if s["classe"] in MARCIAPIEDE and not s.get("tipo")]
                       + [L(p).buffer(1.25, quad_segs=2) for p in d["marciapiedi"]])
    marc = marc.intersection(zona).difference(car).difference(park).difference(spart)
    tram = binari(d["tram"]).intersection(zona)
    zebre = strisce_pedonali(d["attraversamenti"], car)
    linee = mezzeria(d["strade"], zebre).intersection(car).difference(tram.buffer(0.5))

    # ---- piazze, percorsi, campi, acqua, verde: ognuno toglie il posto a quelli dopo
    piazze = unary_union([P(p["pianta"], p.get("buchi", ())) for p in d["pavimentate"]]).intersection(zona)
    piazze = piazze.difference(car).difference(marc)
    sport = unary_union([P(s["pianta"], s.get("buchi", ())) for s in d["sport"]]).intersection(zona)
    acqua = unary_union([P(a["pianta"]) for a in d["acqua"]]).intersection(zona)
    verde_tutto = unary_union([P(v["pianta"], v.get("buchi", ())) for v in d["verde"] + d["boschi"]])
    perc = unary_union([L(p["punti"]).buffer(1.1 if p["tipo"] != "pedestrian" else 2.0, quad_segs=2)
                        for p in d["percorsi"]] + [L(p).buffer(0.9, cap_style=2) for p in d["scale"]])
    perc = perc.intersection(zona).difference(car).difference(marc).difference(sport)
    ghiaia = perc.intersection(verde_tutto.buffer(-0.5))          # i vialetti dentro i parchi
    perc = perc.difference(ghiaia)
    pieno = unary_union([car, spart, park, marc, piazze, perc, ghiaia, sport, acqua])

    tex = getattr(E, "TEX", {})
    sc.mesh("Strade", terr, lastra(E, car, 0.0, 0.02, "asfalto", "asfalto" if "asfalto" in tex else None))
    sc.mesh("Parcheggi", terr, lastra(E, park, 0.0, 0.025, "parcheggio"))
    sc.mesh("Strisce", terr, lastra(E, unary_union([zebre, linee]), 0.02, 0.03, "segnaletica"))
    sc.mesh("Binari", terr, lastra(E, tram, 0.02, 0.04, "binari"))
    sc.mesh("Marciapiedi", terr, lastra(E, marc, 0.0, 0.15, "marciapiede"))
    sc.mesh("Spartitraffico", terr, lastra(E, spart, 0.0, 0.15, "prato", "erba" if "erba" in tex else None))
    sc.mesh("Piazze", terr, lastra(E, piazze, 0.0, 0.12, "piazza"))
    sc.mesh("Percorsi", terr, lastra(E, perc, 0.0, 0.12, "marciapiede"))
    sc.mesh("Vialetti", terr, lastra(E, ghiaia, 0.0, 0.1, "ghiaia"))
    fuori = sport.difference(escludi)
    for s in d["sport"]:
        g = P(s["pianta"], s.get("buchi", ())).intersection(fuori)
        if g.is_empty:
            continue
        chiave = SUPERFICIE.get(s.get("superficie")) or {"playground": "gioco", "track": "tartan"}.get(s["tipo"], "sintetico")
        fuori = fuori.difference(g)
        sc.mesh(f"Sport_{s['tipo']}_{abs(hash(s['pianta'][0][0])) % 10000}", terr, lastra(E, g, 0.0, 0.07, chiave))
    sc.mesh("Acqua_Bordo", terr, lastra(E, acqua.buffer(0.6).difference(acqua).difference(car), 0.0, 0.35, "bordo"))
    sc.mesh("Acqua", terr, lastra(E, acqua, 0.0, 0.2, "acqua"))

    # il verde, per tipo: prati, parchi, giardini, boschetti; le aiuole con i fiori
    verde_g = sc.gruppo("Prati", terr)
    preso = pieno
    for tipo in ("bosco", "arbusti", "giardino", "parco", "cani", "prato"):
        g = unary_union([P(v["pianta"], v.get("buchi", ())) for v in d["verde"] + d["boschi"]
                         if v["tipo"] == tipo]).intersection(zona).difference(preso)
        if not g.is_empty:
            sc.mesh(f"Verde_{tipo}", verde_g, lastra(E, g, 0.0, 0.13, tipo, "erba" if "erba" in tex else None))
            preso = preso.union(g)
    aiuole = unary_union([P(a["pianta"], a.get("buchi", ())) for a in d["aiuole"]]).intersection(zona).difference(pieno)
    sc.mesh("Aiuole", verde_g, lastra(E, aiuole, 0.0, 0.3, "terra"))
    fiori = {c: [] for c in COL["fiori"]}
    for p in getattr(aiuole, "geoms", [aiuole]):
        if p.is_empty:
            continue
        x0, y0, x1, y1 = p.bounds
        for x in np.arange(x0 + 0.3, x1, 0.7):
            for y in np.arange(y0 + 0.3, y1, 0.7):
                if p.contains(Point(x, y)):
                    s = trimesh.creation.icosphere(subdivisions=0, radius=0.28)
                    s.apply_translation([x, y, 0.42])
                    fiori[COL["fiori"][int(caso(x, y) * 4)]].append(s)
    for i, (c, parti) in enumerate(fiori.items()):
        sc.mesh(f"Fiori_{i}", verde_g, unisci(E, parti, c))
    siepi = unary_union([L(s).buffer(0.45, cap_style=2) for s in d["siepi"] if len(s) > 1]).intersection(zona).difference(car)
    sc.mesh("Siepi", verde_g, lastra(E, siepi, 0.0, 1.2, "siepe"))

    # ---- gli alberi: quelli di OSM e i filari (uno ogni 8 m, dove non c'è già un albero)
    tutti = [(x, y, r, h, t) for x, y, r, h, t in d["alberi"]
             if zona.contains(Point(x, y)) and not pieni.contains(Point(x, y))]
    vicini = [Point(t[0], t[1]) for t in tutti]
    from shapely import STRtree
    albi = STRtree(vicini)
    for f in d["filari"]:
        l = L(f)
        n = max(1, round(l.length / 8))
        for k in range(n + 1):
            p = l.interpolate(k / n, normalized=True)
            if zona.contains(p) and not albi.query(p.buffer(3.5)).size and not car.contains(p) \
                    and not pieni.buffer(1.5).contains(p):
                tutti.append((p.x, p.y, 0, 0, "latifoglia"))
    chiome, tronchi = {}, []
    for x, y, r, h, t in tutti:
        tipo, c, tr = albero(x, y, r, h, t)
        chiome.setdefault(tipo, []).extend(c)
        tronchi.extend(tr)
    verde = sc.gruppo("Alberi", radice)
    cg = sc.gruppo("Chiome", verde)                  # i nomi che Trifoglio3DView spegne dentro i piani
    for tipo, parti in sorted(chiome.items()):
        hex_ = COL["chioma"][int(tipo[-1])] if tipo.startswith("latifoglia") else COL[tipo]
        sc.mesh(f"Chiome_{tipo}", cg, unisci(E, parti, hex_))
    tg = sc.gruppo("Tronchi", verde)
    sc.mesh("Tronchi_tutti", tg, unisci(E, tronchi, COL["tronco"]))

    # ---- arredi della strada
    arr = sc.gruppo("Arredi", radice)
    pali, luci = [], []
    for x, y in d["lampioni"]:
        t = trimesh.creation.cylinder(radius=0.08, height=6.0, sections=6)
        t.apply_translation([x, y, 3.0])
        pali.append(t)
        b = trimesh.creation.box([0.7, 0.28, 0.14])
        b.apply_translation([x, y, 6.0])
        luci.append(b)
    for x, y in d["semafori"]:
        t = trimesh.creation.cylinder(radius=0.07, height=3.2, sections=6)
        t.apply_translation([x, y, 1.6])
        pali.append(t)
        b = trimesh.creation.box([0.3, 0.3, 0.9])
        b.apply_translation([x, y, 3.0])
        pali.append(b)
    sc.mesh("Pali", arr, unisci(E, pali, COL["palo"]))
    sc.mesh("Lampade", arr, unisci(E, luci, COL["luce"]))
    pan = []
    for x, y in d["panchine"]:
        b = trimesh.creation.box([1.8, 0.5, 0.45])
        b.apply_translation([x, y, 0.37])
        pan.append(b)
    sc.mesh("Panchine", arr, unisci(E, pan, COL["panchina"]))

    # ---- la città intorno: volumi chiari, senza dettagli, sotto Quartiere (non si toccano)
    q = sc.gruppo("Quartiere", radice)
    corpi, tetti = [], []
    for e in d["edifici"]:
        g, h = P(e["pianta"]), max(e["altezza"], 3.0)
        if g.is_empty or not zona.contains(g.centroid):
            continue
        for p in E.clean(g):
            m = trimesh.creation.extrude_polygon(p, h, engine="earcut")
            corpi.append(m)
            t = p.buffer(-0.5)
            if not t.is_empty and t.geom_type == "Polygon":
                m = trimesh.creation.extrude_polygon(t, 0.3, engine="earcut")
                m.apply_translation([0, 0, h])
                tetti.append(m)
    sc.mesh("Quartiere_Volumi", q, unisci(E, corpi, COL["quartiere"]))
    sc.mesh("Quartiere_Tetti", q, unisci(E, tetti, COL["tetto"]))
    return sc


def main():
    import argparse, tempfile
    a = argparse.ArgumentParser()
    a.add_argument("dati", type=pathlib.Path)
    a.add_argument("uscita", type=pathlib.Path)
    a.add_argument("--glb", action="store_true")
    a = a.parse_args()
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
    sys.argv = [sys.argv[0], ".", tempfile.mkdtemp()]
    import esporta3d as E
    d = json.loads(a.dati.read_text())
    gj = pathlib.Path(__file__).resolve().parent.parent / "giuriati" / "giuriati.json"
    escludi = box(*json.loads(gj.read_text())["isolato"]) if gj.exists() else None
    sc = E.Scena("Zona")
    terreno(E, sc, "Zona", d, escludi)
    a.uscita.mkdir(parents=True, exist_ok=True)
    if a.glb:
        sc.s.export(a.uscita / "zona.glb")
    else:
        E.usdz(sc, a.uscita / "zona.usdz")
    print(len(sc.s.geometry), "mesh")


if __name__ == "__main__":
    main()
