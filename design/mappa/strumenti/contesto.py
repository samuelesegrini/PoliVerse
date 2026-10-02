#!/usr/bin/env python3
"""Adds what OpenStreetMap shows around the buildings to the campus file, for a map
frame that reaches past what is already there.

    python3 strumenti/contesto.py leonardo 28 -44 162 92

The box is in the campus frame (metres, x east, y south). Only what lies outside the
frames of the buildings already drawn is added, so what is in the file, often
simplified by hand, is never doubled: trees, lawns, paths, outdoor steps, streets,
bike racks, lamps, defibrillators, fountains, entrances (not the ones closed to the
public) and the buildings around, as outlines. Positions are © OpenStreetMap
contributors (ODbL).
"""
import json
import math
import pathlib
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET

HERE = pathlib.Path(__file__).resolve().parent.parent
OSM = "https://api.openstreetmap.org/api/0.6/map"
STREET_WIDTH = {"primary": 12, "secondary": 10, "tertiary": 9, "residential": 7, "unclassified": 7}
PATHS = {"footway", "path", "pedestrian", "cycleway"}


def area(pts):
    return sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1])) / 2


def centre(pts):
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def simplify(pts, tol):
    if len(pts) < 3:
        return pts
    a, b = pts[0], pts[-1]
    dx, dy = b[0] - a[0], b[1] - a[1]
    n = math.hypot(dx, dy) or 1e-9
    far, idx = max((abs(dy * p[0] - dx * p[1] + b[0] * a[1] - b[1] * a[0]) / n, i) for i, p in enumerate(pts[1:-1], 1))
    if far <= tol:
        return [a, b]
    return simplify(pts[:idx + 1], tol)[:-1] + simplify(pts[idx:], tol)


def simplify_ring(pts, tol):
    """A closed outline: split at the point farthest from the first, simplify both halves."""
    i = max(range(len(pts)), key=lambda j: math.dist(pts[0], pts[j]))
    ring = simplify(pts[:i + 1], tol)[:-1] + simplify(pts[i:] + [pts[0]], tol)[:-1]
    return ring if len(ring) >= 3 else pts


def r1(p):
    return [round(p[0], 1), round(p[1], 1)]


def main(campus_name, x0, y0, x1, y1):
    path = HERE / f"{campus_name}.json"
    campus = json.loads(path.read_text())
    lat0, lon0 = campus["origine"]
    k = 111320 * math.cos(math.radians(lat0))
    to_xy = lambda lat, lon: ((lon - lon0) * k, -(lat - lat0) * 110540)
    bbox = (lon0 + x0 / k, lat0 - y1 / 110540, lon0 + x1 / k, lat0 - y0 / 110540)
    with urllib.request.urlopen(f"{OSM}?bbox={bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]}", timeout=120) as r:
        root = ET.fromstring(r.read())

    frames = [b["riquadro"] for b in campus["edifici"] if "riquadro" in b]
    new = lambda p: (x0 <= p[0] <= x1 and y0 <= p[1] <= y1
                     and not any(a <= p[0] <= c and b <= p[1] <= d for a, b, c, d in frames))
    tags = lambda e: {t.get("k"): t.get("v") for t in e.findall("tag")}
    nodes = {n.get("id"): to_xy(float(n.get("lat")), float(n.get("lon"))) for n in root.findall("node")}
    ctx = campus["contesto"]
    added = {}

    def add(key, item):
        ctx.setdefault(key, []).append(item)
        added[key] = added.get(key, 0) + 1

    for n in root.findall("node"):
        t, p = tags(n), nodes[n.get("id")]
        if not t or not new(p):
            continue
        if t.get("natural") == "tree":
            crown = re.match(r"[\d.]+", t.get("diameter_crown", ""))
            add("alberi", [*r1(p), round(float(crown.group()) / 2, 1) if crown else 2.8])
        elif t.get("highway") == "street_lamp":
            add("lampioni", r1(p))
        elif t.get("emergency") == "defibrillator":
            add("dae", r1(p))
        elif t.get("amenity") == "drinking_water":
            add("acqua", r1(p))
        elif t.get("amenity") == "bicycle_parking":
            add("bici", [*r1(p), int(t["capacity"]) if t.get("capacity", "").isdigit() else 10])
        elif "entrance" in t and t.get("access") != "no" and t["entrance"] != "emergency" and "level" not in t:
            add("ingressi", {"punto": r1(p), **({"principale": True} if t["entrance"] == "main" else {})})

    taken = {b.get("numero") for b in campus["edifici"]}
    shells = [[tuple(p) for p in b["pianta"]] for b in campus["edifici"]]
    for w in root.findall("way"):
        t = tags(w)
        pts = [nodes[n.get("ref")] for n in w.findall("nd") if n.get("ref") in nodes]
        if len(pts) < 2:
            continue
        closed = pts[0] == pts[-1] and len(pts) > 3
        if closed:
            pts = pts[:-1]
        mid = centre(pts)
        hw = t.get("highway")
        if hw in STREET_WIDTH and t.get("name"):
            # The street every metre, with its direction there, kept where it is in the box.
            seen = []
            for a, b in zip(pts, pts[1:]):
                n = max(1, int(math.dist(a, b)))
                for i in range(n):
                    p = (a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n)
                    if x0 <= p[0] <= x1 and y0 <= p[1] <= y1:
                        seen.append((p, math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))))
            if seen and not any(s["nome"] == t["name"] for s in ctx["strade"]):
                add("strade", {"nome": t["name"], "punti": [r1(p) for p in simplify(pts, 0.5)],
                               "larghezza": STREET_WIDTH[hw]})
                # The name in the middle of what shows, clear of the frame's edge, along the
                # street and reading left to right.
                clear = [(p, a) for p, a in seen if x0 + 8 <= p[0] <= x1 - 4 and y0 + 8 <= p[1] <= y1 - 8]
                if len(clear) >= 30:
                    p, angle = clear[len(clear) // 2]
                    angle = angle - 180 if angle > 90 else angle + 180 if angle <= -90 else angle
                    add("nomi", {"testo": t["name"], "punto": r1(p), "angolo": round(angle)})
        elif not new(mid):
            continue
        elif hw in PATHS and not closed:
            add("percorsi", [r1(p) for p in simplify(pts, 0.5)])
        elif hw == "steps" and not closed:
            add("scale", [r1(p) for p in simplify(pts, 0.3)])
        elif closed and (t.get("landuse") == "grass" or t.get("leisure") in ("garden", "park")):
            if abs(area(pts)) > 4:
                add("verde", [r1(p) for p in simplify_ring(pts, 0.5)])
        elif closed and t.get("building") and abs(area(pts)) > 30:
            # A building already drawn (its outline holds this one's centre) is not added again.
            if any(_inside(mid, s) for s in shells):
                continue
            ref = re.search(r"\d+[A-Z]?", t.get("ref", "") or t.get("name", ""))
            numero = ref.group() if ref and ("Edificio" in t.get("ref", "") + t.get("name", "")) else None
            if numero in taken:
                continue
            outline = [r1(p) for p in simplify_ring(pts, 0.5)]
            levels = re.match(r"\d+", t.get("building:levels", ""))
            b = {"csie": f"osm-{w.get('id')}", "piani": max(1, int(levels.group())) if levels else 3, "pianta": outline}
            if numero:
                xs, ys = [p[0] for p in outline], [p[1] for p in outline]
                b.update({"numero": numero, "badge": [round(min(xs) + 2, 1), round(min(ys) + 2, 1)]})
                taken.add(numero)
            campus["edifici"].append(b)
            added["edifici"] = added.get("edifici", 0) + 1
    path.write_text(dump(campus) + "\n")
    print("added:", added or "nothing")


def dump(v, pad=""):
    """JSON as the campus file is written: a point, or any list of plain values, on one line."""
    inner = pad + "  "
    flat = lambda x: isinstance(x, (int, float, str, bool)) or (
        isinstance(x, list) and all(isinstance(y, (int, float, str)) for y in x))
    if isinstance(v, dict) and len(v) <= 3 and all(flat(x) for x in v.values()):
        return "{" + ", ".join(f"{json.dumps(k)}: {json.dumps(x, ensure_ascii=False)}" for k, x in v.items()) + "}"
    if isinstance(v, dict):
        return "{\n" + ",\n".join(f"{inner}{json.dumps(k)}: {dump(x, inner)}" for k, x in v.items()) + f"\n{pad}}}"
    if isinstance(v, list) and v and not all(isinstance(x, (int, float, str)) for x in v):
        return "[\n" + ",\n".join(inner + dump(x, inner) for x in v) + f"\n{pad}]"
    return json.dumps(v, ensure_ascii=False)


def _inside(p, pts):
    x, y = p
    hit = False
    for (xa, ya), (xb, yb) in zip(pts, pts[1:] + pts[:1]):
        if (ya > y) != (yb > y) and x < (xb - xa) * (y - ya) / (yb - ya) + xa:
            hit = not hit
    return hit


if __name__ == "__main__":
    main(sys.argv[1], *map(float, sys.argv[2:6]))
