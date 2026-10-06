#!/usr/bin/env python3
"""Il Centro Sportivo Giuriati e il suo isolato (via Ponzio, via Bassini, via Golgi, via
Celoria) dagli stessi dati di OpenStreetMap, letti dalla copia di Overture Maps.

    python3 importa.py giuriati.json [--leonardo <design/mappa>/leonardo.json]

api.openstreetmap.org e Overpass non sono raggiungibili da tutti gli ambienti; la release
di Overture (s3://overturemaps-us-west-2, lettura anonima) porta gli stessi oggetti OSM
con i loro tag (`source_tags`) e l'id OSM. Scrive nel frame del campus Leonardo (metri,
x verso est, y verso sud, origine 45.48, 9.22803), con le chiavi di `contesto` di
leonardo.json (verde, alberi, percorsi, strade, scale, lampioni, panchine…) più quelle
dello sport: `campi`, `piste`, `recinzioni`, `pavimentate`, `parcheggi`, e l'elenco degli
`edifici` da modellare dopo, con il codice del catalogo dove si riconosce.

Con --leonardo salta alberi, verde e percorsi già nel file del campus.

Dipendenze: pyarrow, shapely. Posizioni © OpenStreetMap contributors (ODbL).
"""
import argparse, json, math, os, pathlib, re
import pyarrow.compute as pc
import pyarrow.dataset as ds
import pyarrow.fs as pafs
import shapely
from shapely.geometry import box, Point
from shapely.ops import transform

RELEASE = "overturemaps-us-west-2/release/2026-09-23.1"
LAT0, LON0 = 45.48, 9.22803
K = 111320 * math.cos(math.radians(LAT0))
# l'isolato: via Ponzio a ovest, via Bassini a nord, via Golgi (con il campus di via Golgi 40) a est,
# via Celoria a sud
ISOLATO = (150.0, 60.0, 580.0, 345.0)
LARGHEZZA = {"primary": 12, "secondary": 10, "tertiary": 9, "residential": 7, "unclassified": 7, "service": 5}

# I codici del catalogo (prototypes/map-view-PROTOTYPE/data.js) nel frame del campus: il centro
# del riquadro di ogni edificio. Servono a dare il csie agli edifici di OSM.
CATALOGO = {
    "MIA0301": ("Edificio 20", 353, 131), "MIA0302": ("Edificio 19", 246, 124),
    "MIA0306": ("Edificio 21", 453, 96), "MIA0307": ("Edificio CT2", 436, 140),
    "MIA0309": ("Edificio 36", 380, 178), "MIA0310": ("Edificio 36A", 432, 177),
    "MIA0311": ("Edificio 37", 452, 178), "MIA0314": ("Edificio 41", 372, 94),
    "MIA0315": ("Edificio 42", 263, 303), "MIA0316": ("Edificio 43", 265, 267),
    "MIA0317": ("Isola Ecologica", 469, 140), "MIA0319": ("Edificio 20A", 298, 116),
    "MIA0320": ("Edificio 45", 466, 301), "MIA0401": ("Edificio 24", 520, 276),
    "MIA0402": ("Edificio 23", 543, 253), "MIA0403": ("Edificio 25", 556, 276),
    "MIA0404": ("Edificio 22", 537, 222),
}

# Quello che OSM non dice ancora (settembre 2026), dalle notizie:
# - il "Cantiere nuovo dipartimento chimica" è finito: il campus di via Bassini (DCMIC, Edificio 41,
#   e il nuovo DEIB, 20A) è stato inaugurato a dicembre 2025 (Urbanfile, 13 gennaio 2026);
# - il cantiere lungo il lato sud del Giuriati è la Giuriati Gym, inaugurata l'8 settembre 2026
#   (1700 m² coperti, due campi polivalenti sul tetto; Cronaca Milano, Il Giorno, MilanoToday).
CANTIERI = {"Cantiere nuovo dipartimento chimica": "piazzale del campus di via Bassini (finito, dic. 2025)"}
GYM = "Giuriati Gym"
NOTE = {"MIA0320": "nel catalogo, non in OSM: sta sui campi da padel coperti, probabilmente la loro copertura"}


def xy(x, y):
    return (x - LON0) * K, -(y - LAT0) * 110540


def r1(p):
    return [round(p[0], 1), round(p[1], 1)]


def leggi(theme, typ):
    s3 = pafs.S3FileSystem(anonymous=True, region="us-west-2",
                           proxy_options=os.environ.get("HTTPS_PROXY") or None)
    w, s = LON0 + (ISOLATO[0] - 40) / K, LAT0 - (ISOLATO[3] + 40) / 110540
    e, n = LON0 + (ISOLATO[2] + 40) / K, LAT0 - (ISOLATO[1] - 40) / 110540
    d = ds.dataset(f"{RELEASE}/theme={theme}/type={typ}/", filesystem=s3, format="parquet")
    f = ((pc.field("bbox", "xmin") < e) & (pc.field("bbox", "xmax") > w)
         & (pc.field("bbox", "ymin") < n) & (pc.field("bbox", "ymax") > s))
    for r in d.to_table(filter=f).to_pylist():
        r["g"] = transform(xy, shapely.from_wkb(r["geometry"]))
        st = r.get("source_tags") or {}
        r["tags"] = dict(st)
        r["nome"] = (r.get("names") or {}).get("primary")
        r["osm"] = next((x["record_id"].split("@")[0] for x in r.get("sources") or []
                         if x.get("dataset") == "OpenStreetMap" and x.get("record_id")), None)
        yield r


def anello(g, tol=0.4):
    g = g.simplify(tol)
    if g.geom_type == "MultiPolygon":
        g = max(g.geoms, key=lambda p: p.area)
    return [r1(p) for p in list(g.exterior.coords)[:-1]]


def linea(g, tol=0.4):
    return [r1(p) for p in g.simplify(tol).coords]


def main():
    a = argparse.ArgumentParser()
    a.add_argument("uscita", type=pathlib.Path)
    a.add_argument("--leonardo", type=pathlib.Path)
    a = a.parse_args()
    area = box(*ISOLATO)
    dentro = lambda g: g.intersects(area)

    gia = {"alberi": [], "verde": None, "percorsi": None}
    if a.leonardo:
        k = json.loads(a.leonardo.read_text())["contesto"]
        gia["alberi"] = [Point(x, y) for x, y, _ in k["alberi"]]
        gia["verde"] = shapely.union_all([shapely.Polygon(v).buffer(0) for v in k["verde"]])
        gia["percorsi"] = shapely.union_all([shapely.LineString(p).buffer(1.0) for p in k["percorsi"] if len(p) > 1])
    nuovo_albero = lambda p: not any(p.distance(q) < 1.5 for q in gia["alberi"])

    out = {"campus": "Leonardo", "origine": [LAT0, LON0], "isolato": list(ISOLATO),
           "fonte": f"OpenStreetMap via Overture Maps {RELEASE.rsplit('/', 1)[1]} (ODbL)",
           "strade": [], "percorsi": [], "scale": [], "verde": [], "boschi": [], "alberi": [], "filari": [],
           "campi": [], "piste": [], "pavimentate": [], "parcheggi": [], "recinzioni": [], "muri": [],
           "lampioni": [], "panchine": [], "bici": [], "cestini": [], "riciclo": [], "acqua": [],
           "bagni": [], "distributori": [], "edifici": []}

    # ---- suolo: verde, campi, piste, piazzali
    gym = None
    for r in leggi("base", "land_use"):
        g, t, c = r["g"], r["tags"], r["class"]
        if not dentro(g) or g.area > 40000 or g.geom_type not in ("Polygon", "MultiPolygon"):
            continue
        if c in ("grass", "park", "garden", "dog_park"):
            if gia["verde"] is not None and g.difference(gia["verde"]).area < 0.2 * g.area:
                continue
            out["verde"].append({"pianta": anello(g), "tipo": c, **({"nome": r["nome"]} if r["nome"] else {}), "osm": r["osm"]})
        elif c == "pitch":
            out["campi"].append({"sport": t.get("sport"), "superficie": t.get("surface"), "pianta": anello(g, 0.2),
                                 **({"coperto": True} if t.get("covered") == "yes" else {}),
                                 **({"nome": r["nome"]} if r["nome"] else {}), "osm": r["osm"]})
        elif c == "track":
            out["piste"].append({"sport": t.get("sport"), "superficie": t.get("surface"),
                                 "pianta": anello(g, 0.2), "buchi": [[r1(p) for p in list(i.coords)[:-1]]
                                                                    for i in g.interiors], "osm": r["osm"]})
        elif c == "playground":
            out["campi"].append({"sport": "gioco", "pianta": anello(g, 0.2), "osm": r["osm"]})
        elif c == "pedestrian":
            out["pavimentate"].append({"pianta": anello(g), "superficie": t.get("surface"), "osm": r["osm"]})
        elif c == "construction":
            nome = CANTIERI.get(r["nome"], f"cantiere {GYM} (finito, set. 2026)" if g.centroid.y > 280 else "cantiere")
            out["pavimentate"].append({"pianta": anello(g), "nota": nome, "osm": r["osm"]})
            if GYM in nome:
                gym = {"csie": None, "nome": GYM, "uso": "sports_centre", "piani": 1, "area": round(g.area),
                       "pianta": anello(g, 0.3), "osm": r["osm"],
                       "nota": "nuova (set. 2026): 1700 m² coperti, due campi sul tetto; sagoma del cantiere in OSM"}
    for r in leggi("base", "land"):
        g, c = r["g"], r["class"]
        if not dentro(g):
            continue
        if c == "tree" and g.geom_type == "Point" and nuovo_albero(g):
            crown = re.match(r"[\d.]+", r["tags"].get("diameter_crown", ""))
            out["alberi"].append([*r1((g.x, g.y)), round(float(crown.group()) / 2, 1) if crown else 2.8])
        elif c == "tree_row":
            out["filari"].append(linea(g.intersection(area.buffer(20))))
        elif c in ("forest", "wood", "scrub", "grass") and g.area < 40000:
            out["boschi" if c in ("forest", "wood") else "verde"].append(
                {"pianta": anello(g), "tipo": c, **({"nome": r["nome"]} if r["nome"] else {}), "osm": r["osm"]})

    # ---- strade e percorsi
    for r in leggi("transportation", "segment"):
        g = r["g"]
        if r["subtype"] != "road" or not dentro(g):
            continue
        c = r["class"]
        if c in LARGHEZZA and r["nome"] and g.intersection(area).length < 15:
            continue
        g = g.intersection(area.buffer(15))
        if g.is_empty or g.geom_type != "LineString":
            continue
        if c in LARGHEZZA and r["nome"]:
            out["strade"].append({"nome": r["nome"], "punti": linea(g, 0.5), "larghezza": LARGHEZZA[c]})
        elif c in ("footway", "path", "pedestrian", "cycleway", "service"):
            if gia["percorsi"] is not None and g.difference(gia["percorsi"]).length < 0.2 * g.length:
                continue
            out["percorsi"].append(linea(g, 0.5) if not r["nome"] else {"nome": r["nome"], "punti": linea(g, 0.5)})
        elif c == "steps":
            out["scale"].append(linea(g, 0.3))

    # ---- recinzioni, arredi
    punti = {"street_lamp": "lampioni", "bench": "panchine", "waste_basket": "cestini", "recycling": "riciclo",
             "drinking_water": "acqua", "toilets": "bagni", "vending_machine": "distributori"}
    for r in leggi("base", "infrastructure"):
        g, c = r["g"], r["class"]
        if not g.intersects(area):
            continue
        if c in ("fence", "wall", "hedge") and g.geom_type == "LineString":
            g = g.intersection(area)
            for part in getattr(g, "geoms", [g]):
                if part.length > 1:
                    tipo = r["tags"].get("fence_type") or r["tags"].get("material") or c
                    out["muri" if c == "wall" else "recinzioni"].append({"tipo": tipo, "punti": linea(part, 0.3)})
        elif c == "parking" and g.geom_type == "Polygon":
            out["parcheggi"].append(anello(g))
        elif c == "bicycle_parking" and g.geom_type == "Point":
            cap = r["tags"].get("capacity", "")
            out["bici"].append([*r1((g.x, g.y)), int(cap) if cap.isdigit() else 10])
        elif c in punti:
            p = g.centroid
            if not any(math.dist(q, (p.x, p.y)) < 1 for q in out[punti[c]]):
                out[punti[c]].append(r1((p.x, p.y)))

    # ---- edifici: solo da riconoscere, si modellano dopo
    trovati = set()
    if gym:
        out["edifici"].append(gym)
    for r in leggi("buildings", "building"):
        g = r["g"]
        if not area.contains(g.centroid) or g.area < 15:
            continue
        c = g.centroid
        csie = min(CATALOGO, key=lambda k: math.dist(CATALOGO[k][1:], (c.x, c.y)))
        if math.dist(CATALOGO[csie][1:], (c.x, c.y)) > 12 or csie in trovati:
            csie = None
        trovati.add(csie)
        piani = r.get("num_floors")
        out["edifici"].append({
            "csie": csie, "nome": CATALOGO[csie][0] if csie else r["nome"],
            **({"osm_nome": r["nome"]} if r["nome"] and csie else {}),
            "uso": r.get("class") or r.get("subtype"),
            "piani": piani, "altezza": round(r["height"], 1) if r.get("height") else None,
            "area": round(g.area), "pianta": anello(g, 0.3), "osm": r["osm"]})
    for csie, (nome, x, y) in CATALOGO.items():
        if csie not in trovati:
            out["edifici"].append({"csie": csie, "nome": nome, "punto": [x, y], "nota": NOTE.get(csie, "nel catalogo, non ancora in OSM")})

    a.uscita.write_text(dump(out) + "\n")
    print({k: len(v) for k, v in out.items() if isinstance(v, list)})


def dump(v, pad=""):
    """JSON come i file del campus: un punto, o una lista di valori semplici, su una riga."""
    inner = pad + "  "
    flat = lambda x: x is None or isinstance(x, (int, float, str, bool)) or (
        isinstance(x, list) and all(isinstance(y, (int, float, str)) for y in x))
    if isinstance(v, dict) and len(v) <= 3 and all(flat(x) for x in v.values()):
        return "{" + ", ".join(f"{json.dumps(k)}: {json.dumps(x, ensure_ascii=False)}" for k, x in v.items()) + "}"
    if isinstance(v, dict):
        return "{\n" + ",\n".join(f"{inner}{json.dumps(k)}: {dump(x, inner)}" for k, x in v.items()) + f"\n{pad}}}"
    if isinstance(v, list) and v and not all(isinstance(x, (int, float, str)) for x in v):
        return "[\n" + ",\n".join(inner + dump(x, inner) for x in v) + f"\n{pad}]"
    return json.dumps(v, ensure_ascii=False)


if __name__ == "__main__":
    main()
