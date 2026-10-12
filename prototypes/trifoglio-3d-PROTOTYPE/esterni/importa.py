#!/usr/bin/env python3
"""Strade, marciapiedi, verde e alberi di tutta la zona del Politecnico (campus Leonardo,
via Bassini e via Golgi, Città Studi) da OpenStreetMap, letti dalla copia di Overture Maps.

    python3 importa.py zona.json --mappa ../../../design/mappa

La zona è il riquadro degli edifici di tutti i file del campus in `design/mappa`
(leonardo.json, bassini.json, citta-studi.json), allargato di 80 m. Scrive nel frame del
campus (metri, x verso est, y verso sud, origine 45.48, 9.22803), come giuriati/importa.py.
Dal contesto di leonardo.json aggiunge il verde, i percorsi e gli alberi che OSM non ha.

Dipendenze: pyarrow, shapely. Posizioni © OpenStreetMap contributors (ODbL).
"""
import argparse, json, math, os, pathlib, re, sys
import pyarrow.compute as pc
import pyarrow.dataset as ds
import pyarrow.fs as pafs
import shapely
from shapely.geometry import box, Point, Polygon, LineString
from shapely.ops import transform

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "giuriati"))
from importa import dump, r1, anello, linea   # noqa: E402  (stesso formato del JSON)

RELEASE = "overturemaps-us-west-2/release/2026-09-23.1"
LAT0, LON0 = 45.48, 9.22803
K = 111320 * math.cos(math.radians(LAT0))
MARGINE = 80
# carreggiata (m) per classe di OSM, senza i marciapiedi
CARREGGIATA = {"primary": 14, "secondary": 12, "tertiary": 9, "residential": 7, "unclassified": 7,
               "living_street": 6, "service": 4.5, "unknown": 6}
# marciapiede (m) per lato, dove OSM non lo disegna a parte
MARCIAPIEDE = {"primary": 4, "secondary": 3.5, "tertiary": 3, "residential": 2.5, "unclassified": 2.5,
               "living_street": 2}
VERDE = {"grass": "prato", "park": "parco", "garden": "giardino", "dog_park": "cani", "flowerbed": "aiuola",
         "village_green": "prato", "recreation_ground": "prato"}
SPORT = {"pitch", "track", "playground"}


def xy(x, y):
    return (x - LON0) * K, -(y - LAT0) * 110540


def leggi(theme, typ, area):
    s3 = pafs.S3FileSystem(anonymous=True, region="us-west-2",
                           proxy_options=os.environ.get("HTTPS_PROXY") or None)
    x0, y0, x1, y1 = area
    w, e = LON0 + x0 / K, LON0 + x1 / K
    n, s = LAT0 - y0 / 110540, LAT0 - y1 / 110540
    d = ds.dataset(f"{RELEASE}/theme={theme}/type={typ}/", filesystem=s3, format="parquet")
    f = ((pc.field("bbox", "xmin") < e) & (pc.field("bbox", "xmax") > w)
         & (pc.field("bbox", "ymin") < n) & (pc.field("bbox", "ymax") > s))
    for r in d.to_table(filter=f).to_pylist():
        r["g"] = transform(xy, shapely.from_wkb(r["geometry"]))
        r["tags"] = dict(r.get("source_tags") or {})
        r["nome"] = (r.get("names") or {}).get("primary")
        r["osm"] = next((x["record_id"].split("@")[0] for x in r.get("sources") or []
                         if x.get("dataset") == "OpenStreetMap" and x.get("record_id")), None)
        yield r


def a_terra(r):
    """Le strade al piano della città: niente gallerie, interni, ponti e passerelle."""
    flags = {v for f in r.get("road_flags") or [] for v in f["values"]}
    livelli = {l["value"] for l in r.get("level_rules") or []}
    return not (flags & {"is_tunnel", "is_indoor", "is_bridge", "is_covered"} or livelli - {0})


def numero(s, default):
    m = re.match(r"[\d.]+", s or "")
    return float(m.group()) if m else default


def main():
    a = argparse.ArgumentParser()
    a.add_argument("uscita", type=pathlib.Path)
    a.add_argument("--mappa", type=pathlib.Path, required=True)
    a = a.parse_args()

    campus = {f.name: json.loads(f.read_text()) for f in sorted(a.mappa.glob("*.json"))}
    campus = {k: v for k, v in campus.items() if isinstance(v, dict) and "edifici" in v}
    pts = [p for c in campus.values() for b in c["edifici"] for p in b.get("pianta", [])]
    area = (math.floor(min(p[0] for p in pts) - MARGINE), math.floor(min(p[1] for p in pts) - MARGINE),
            math.ceil(max(p[0] for p in pts) + MARGINE), math.ceil(max(p[1] for p in pts) + MARGINE))
    zona = box(*area)
    dentro = lambda g: g.intersects(zona)
    taglia = lambda g: g.intersection(zona.buffer(10))

    out = {"zona": list(area), "origine": [LAT0, LON0],
           "fonte": f"OpenStreetMap via Overture Maps {RELEASE.rsplit('/', 1)[1]} (ODbL)",
           "strade": [], "tram": [], "marciapiedi": [], "attraversamenti": [], "percorsi": [], "scale": [],
           "verde": [], "boschi": [], "aiuole": [], "pavimentate": [], "parcheggi": [], "sport": [],
           "acqua": [], "alberi": [], "filari": [], "siepi": [], "lampioni": [], "panchine": [],
           "semafori": [], "edifici": []}

    # ---- strade, tram, marciapiedi, attraversamenti, percorsi
    for r in leggi("transportation", "segment", area):
        g, c, sub = r["g"], r["class"], r.get("subclass")
        if not dentro(g) or not a_terra(r):
            continue
        g = taglia(g)
        for part in getattr(g, "geoms", [g]):
            if part.geom_type != "LineString" or part.length < 1:
                continue
            if r["subtype"] == "rail":
                if c == "tram":
                    out["tram"].append(linea(part, 0.3))
                continue
            if c in CARREGGIATA:
                w = next((x["value"] for x in r.get("width_rules") or [] if not x.get("between")), None)
                s = {"classe": c, "punti": linea(part, 0.3), "larghezza": w or CARREGGIATA[c]}
                if sub:
                    s["tipo"] = sub                         # driveway, parking_aisle, alley, link
                if r["nome"]:
                    s["nome"] = r["nome"]
                out["strade"].append(s)
            elif c == "footway" and sub == "sidewalk":
                out["marciapiedi"].append(linea(part, 0.3))
            elif c in ("footway", "cycleway") and sub in ("crosswalk", "cycle_crossing"):
                out["attraversamenti"].append(linea(part, 0.2))
            elif c in ("footway", "path", "pedestrian", "cycleway", "bridleway", "track"):
                out["percorsi"].append({"tipo": c, "punti": linea(part, 0.3)})
            elif c == "steps":
                out["scale"].append(linea(part, 0.2))

    # ---- suolo: verde, aiuole, piazze, parcheggi, campi
    for r in leggi("base", "land_use", area):
        g, c, t = r["g"], r["class"], r["tags"]
        if not dentro(g) or g.geom_type not in ("Polygon", "MultiPolygon") or g.area > 60000:
            continue
        g = taglia(g)
        for part in getattr(g, "geoms", [g]):
            if part.geom_type != "Polygon" or part.area < 4:
                continue
            v = {"pianta": anello(part, 0.3)}
            if part.interiors:
                v["buchi"] = [[r1(p) for p in list(i.simplify(0.3).coords)[:-1]] for i in part.interiors]
            if c in VERDE:
                v["tipo"] = VERDE[c]
                if r["nome"]:
                    v["nome"] = r["nome"]
                out["aiuole" if c == "flowerbed" else "verde"].append(v)
            elif c in ("pedestrian", "plaza"):
                out["pavimentate"].append(v)
            elif c in SPORT:
                v["tipo"] = c if c != "pitch" else t.get("sport") or "campo"
                v["superficie"] = t.get("surface")
                out["sport"].append(v)
    for r in leggi("base", "land", area):
        g, c, t = r["g"], r["class"], r["tags"]
        if not dentro(g):
            continue
        if c == "tree" and g.geom_type == "Point":
            foglia = {"needleleaved": "conifera", "palm": "palma"}.get(t.get("leaf_type"), "latifoglia")
            chioma = numero(t.get("diameter_crown"), 0) / 2
            alto = numero(t.get("height"), 0)
            out["alberi"].append([*r1((g.x, g.y)), round(chioma, 1), round(alto, 1), foglia])
        elif c == "tree_row":
            for part in getattr(taglia(g), "geoms", [taglia(g)]):
                if part.geom_type == "LineString" and part.length > 3:
                    out["filari"].append(linea(part, 0.3))
        elif c in ("forest", "wood", "scrub", "grass", "shrub") and g.geom_type == "Polygon" and g.area < 60000:
            out["boschi" if c in ("forest", "wood") else "verde"].append(
                {"pianta": anello(taglia(g), 0.3), "tipo": {"scrub": "arbusti", "shrub": "arbusti"}.get(c, "prato" if c == "grass" else "bosco")})
    for r in leggi("base", "water", area):
        g = r["g"]
        if dentro(g) and g.geom_type == "Polygon":
            out["acqua"].append({"tipo": r["class"], "pianta": anello(taglia(g), 0.2)})

    # ---- siepi, parcheggi, arredi della strada
    for r in leggi("base", "infrastructure", area):
        g, c, t = r["g"], r["class"], r["tags"]
        if not dentro(g):
            continue
        if c == "hedge" and g.geom_type == "LineString":
            out["siepi"].append(linea(taglia(g), 0.3))
        elif c == "hedge" and g.geom_type == "Polygon":
            out["siepi"].append(linea(taglia(g.exterior), 0.3))
        elif c == "parking" and g.geom_type == "Polygon" and t.get("parking", "surface") == "surface":
            out["parcheggi"].append({"pianta": anello(taglia(g), 0.3)})
        elif c == "street_lamp" and g.geom_type == "Point" and zona.contains(g):
            out["lampioni"].append(r1((g.x, g.y)))
        elif c == "bench" and g.geom_type == "Point" and zona.contains(g):
            out["panchine"].append(r1((g.x, g.y)))
        elif c == "traffic_signals" and g.geom_type == "Point" and zona.contains(g):
            out["semafori"].append(r1((g.x, g.y)))

    # ---- gli edifici di OSM che non sono del Politecnico: solo volumi di contesto
    nostri = [Polygon(b["pianta"]).buffer(2) for c in campus.values() for b in c["edifici"] if len(b.get("pianta", [])) > 2]
    nostri = shapely.union_all(nostri)
    for r in leggi("buildings", "building", area):
        g = r["g"]
        if g.geom_type == "MultiPolygon":
            g = max(g.geoms, key=lambda p: p.area)
        if g.geom_type != "Polygon" or not zona.contains(g.centroid) or g.area < 12:
            continue
        if g.intersection(nostri).area > 0.3 * g.area:
            continue
        h = r.get("height")
        piani = r.get("num_floors")
        out["edifici"].append({"altezza": round(h or (piani or 4) * 3.2, 1), "pianta": anello(g, 0.3),
                               **({"nome": r["nome"]} if r["nome"] else {}), "osm": r["osm"]})

    # ---- quello che leonardo.json ha in più (disegnato a mano o da un OSM più vecchio)
    k = campus["leonardo.json"]["contesto"]
    verde = shapely.union_all([Polygon(v["pianta"]).buffer(0) for v in out["verde"]])
    for v in k["verde"]:
        p = Polygon(v).buffer(0)
        if p.difference(verde).area > 0.3 * p.area:
            out["verde"].append({"pianta": [r1(q) for q in v], "tipo": "prato", "fonte": "leonardo.json"})
    perc = shapely.union_all([LineString(p["punti"]).buffer(1.0) for p in out["percorsi"]]
                             + [LineString(p).buffer(1.0) for p in out["marciapiedi"]])
    for p in k["percorsi"]:
        if len(p) > 1 and LineString(p).difference(perc).length > 0.3 * LineString(p).length:
            out["percorsi"].append({"tipo": "footway", "punti": [r1(q) for q in p], "fonte": "leonardo.json"})
    alberi = shapely.STRtree([Point(t[0], t[1]) for t in out["alberi"]])
    for x, y, rr in k["alberi"]:
        if not alberi.query(Point(x, y).buffer(1.5)).size:
            out["alberi"].append([x, y, rr, 0, "latifoglia"])

    a.uscita.write_text(dump(out) + "\n")
    print(area, {k: len(v) for k, v in out.items() if isinstance(v, list)})


if __name__ == "__main__":
    main()
