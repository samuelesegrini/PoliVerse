#!/usr/bin/env python3
"""I dettagli dell'arredo urbano di tutta la zona, per esterni/arredo.py: quello che zona.json
non tiene (scritto da importa.py), letto dalla stessa copia di OpenStreetMap su Overture.

    python3 importa_arredo.py arredo.json --zona zona.json

- lampioni con il tipo di sostegno (`lamp_mount`, `support`) e la direzione;
- panchine con schienale, braccioli, materiale, posti e direzione;
- cestini, rastrelliere (con la capienza), dissuasori, fontanelle (le "vedovelle"),
  pensiline e paline delle fermate, idranti, cancelli.

Stesso frame di zona.json (metri, x verso est, y verso sud, origine 45.48, 9.22803).
Dipendenze: pyarrow, shapely. Posizioni © OpenStreetMap contributors (ODbL).
"""
import argparse, importlib.util, json, pathlib, re

QUI = pathlib.Path(__file__).resolve().parent
# esterni/importa.py, caricato per percorso: giuriati/ ha un altro importa.py
_spec = importlib.util.spec_from_file_location("importa_zona", QUI / "importa.py")
Z = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(Z)

BUSSOLA = {"N": 0, "NNE": 22.5, "NE": 45, "ENE": 67.5, "E": 90, "ESE": 112.5, "SE": 135, "SSE": 157.5,
           "S": 180, "SSW": 202.5, "SW": 225, "WSW": 247.5, "W": 270, "WNW": 292.5, "NW": 315, "NNW": 337.5}


def direzione(s):
    """`direction` di OSM in gradi dalla bussola (0 = nord, 90 = est), o None. Un intervallo
    "270-90" è il suo punto di mezzo."""
    if not s:
        return None
    s = s.strip().upper()
    if s in BUSSOLA:
        return BUSSOLA[s]
    m = re.fullmatch(r"(\d+(?:\.\d+)?)(?:-(\d+(?:\.\d+)?))?", s)
    if not m:
        return None
    a = float(m.group(1))
    if m.group(2) is None:
        return a % 360
    b = float(m.group(2))
    if (b - a) % 360 == 0:          # "0-360": tutte le direzioni
        return None
    return (a + ((b - a) % 360) / 2) % 360


def sì(v):
    return v in ("yes", "true", "1")


def main():
    a = argparse.ArgumentParser()
    a.add_argument("uscita", type=pathlib.Path)
    a.add_argument("--zona", type=pathlib.Path, default=QUI / "zona.json")
    a = a.parse_args()
    x0, y0, x1, y1 = json.loads(a.zona.read_text())["zona"]
    area = (x0, y0, x1, y1)
    dentro = lambda p: x0 <= p.x <= x1 and y0 <= p.y <= y1

    out = {"zona": [x0, y0, x1, y1], "fonte": "OpenStreetMap via Overture Maps 2026-09-23.1 (ODbL)",
           "lampioni": [], "panchine": [], "cestini": [], "bici": [], "dissuasori": [], "fontanelle": [],
           "fermate": [], "idranti": []}
    visti = set()
    for r in Z.leggi("base", "infrastructure", area):
        g, c, t = r["g"], r["class"], r["tags"]
        if g.is_empty:
            continue
        p = g.centroid
        if not dentro(p) or t.get("level", "0") not in ("0", ""):
            continue
        chiave = (c, round(p.x), round(p.y))
        if chiave in visti:
            continue
        visti.add(chiave)
        xy = Z.r1((p.x, p.y))
        if c == "street_lamp":
            out["lampioni"].append({"punto": xy, "tipo": t.get("lamp_mount") or t.get("support") or "",
                                    **({"dir": direzione(t["direction"])} if direzione(t.get("direction")) is not None else {})})
        elif c == "bench":
            v = {"punto": xy, "schienale": not t.get("backrest") == "no",
                 "braccioli": t.get("armrest") not in ("no", None), "materiale": t.get("material", "wood")}
            if t.get("seats", "").isdigit():
                v["posti"] = int(t["seats"])
            if direzione(t.get("direction")) is not None:
                v["dir"] = direzione(t["direction"])
            out["panchine"].append(v)
        elif c == "waste_basket":
            out["cestini"].append(xy)
        elif c == "bicycle_parking":
            cap = t.get("capacity", "")
            v = {"punto": xy, "posti": int(cap) if cap.isdigit() else 8, "tipo": t.get("bicycle_parking", "stands"),
                 "coperta": sì(t.get("covered"))}
            if g.geom_type == "Polygon":               # la rastrelliera disegnata: il suo lato lungo
                v["linea"] = Z.linea(g.minimum_rotated_rectangle.exterior)[:2]
            out["bici"].append(v)
        elif c == "bollard":
            if g.geom_type == "LineString":            # una fila di dissuasori: uno ogni 1,5 m
                n = max(1, int(g.length // 1.5))
                out["dissuasori"] += [Z.r1((q.x, q.y)) for q in (g.interpolate(k / n, normalized=True) for k in range(n + 1))]
            else:
                out["dissuasori"].append(xy)
        elif c == "drinking_water" and g.geom_type == "Point":
            out["fontanelle"].append(xy)
        elif c == "bus_stop":
            out["fermate"].append({"punto": xy, "pensilina": sì(t.get("shelter")), "panchina": sì(t.get("bench"))})
        elif c == "fire_hydrant":
            out["idranti"].append(xy)

    a.uscita.write_text(Z.dump(out) + "\n")
    print({k: len(v) for k, v in out.items() if isinstance(v, list)})


if __name__ == "__main__":
    main()
