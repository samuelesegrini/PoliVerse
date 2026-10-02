#!/usr/bin/env python3
"""Imports a building's floor geometry from the Politecnico's public maps service.

    python3 importa-scheda.py MIA0203

Writes `piante/<csie>-geometria.json`, which `build-mappa.py` draws the floor
plans from. Run it again only when the Politecnico's plans change.

For each floor in the building's `livelli`, the service's public floor drawing
(`piano/<csip>/svg/pub`, the one its room pages show) gives the exact geometry:
the gross floor outline, every room as a polygon with its `csiv`, the doors as
swing arcs, stairs, lifts, windows, railings, outdoor parts, the furniture,
the step-free route and the drinking fountains. Nothing is drawn from it as
is: this keeps the geometry, `build-mappa.py` gives it the illustrations' look.

The service draws in the building's own CAD frame. OpenStreetMap's indoor map
of the same building is traced from the same plans and tags its rooms with the
same numbers, so one similarity transform fitted on the rooms both share brings
everything into the campus frame (metres, x east, y south). OpenStreetMap also
says what each room is — toilet, stairs, lecture hall, corridor — where the
service does not.

Needs network access; no other dependencies.
"""
import json
import math
import pathlib
import re
import statistics
import sys
import urllib.request
import xml.etree.ElementTree as ET

HERE = pathlib.Path(__file__).parent
MAPS = "https://onlineservices.polimi.it/maps_rest/rest"
OSM = "https://api.openstreetmap.org/api/0.6/map"
TAGS = [str(i) for i in range(1, 19)] + ["POI"]       # every public point-of-interest tag
FOUNTAIN_TAG = 5                                      # BEVERINO
LINE_LAYERS = {"SCALE": "scale", "LAYOUT_ARREDI": "arredi", "FINESTRE": "finestre",
               "RINGHIERA": "ringhiere", "ESTERNI": "esterni", "ASCENSORI": "ascensori"}


def get(url, data=None):
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"} if data else {})
    with urllib.request.urlopen(req, timeout=90) as r:
        return r.read().decode()


def r2(v):
    return round(v, 2)


# ---------------------------------------------------------------- geometry

def area(pts):
    return sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1])) / 2


def area_centroid(pts):
    a = cx = cy = 0.0
    for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
        k = x1 * y2 - x2 * y1
        a += k
        cx += (x1 + x2) * k
        cy += (y1 + y2) * k
    if abs(a) < 1e-9:
        return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
    return (cx / (3 * a), cy / (3 * a))


def inside(p, pts):
    x, y = p
    hit = False
    for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            hit = not hit
    return hit


def simplify(pts, tol):
    """Douglas–Peucker on a closed ring: drops the CAD's sub-centimetre jitter."""
    if len(pts) < 4:
        return pts

    def rdp(seq):
        a, b = seq[0], seq[-1]
        dx, dy = b[0] - a[0], b[1] - a[1]
        n = math.hypot(dx, dy) or 1e-9
        far, idx = 0.0, 0
        for i, p in enumerate(seq[1:-1], 1):
            d = abs(dy * p[0] - dx * p[1] + b[0] * a[1] - b[1] * a[0]) / n
            if d > far:
                far, idx = d, i
        if far <= tol:
            return [a, b]
        return rdp(seq[:idx + 1])[:-1] + rdp(seq[idx:])

    i = max(range(len(pts)), key=lambda k: math.dist(pts[0], pts[k]))
    ring = rdp(pts[:i + 1])[:-1] + rdp(pts[i:] + [pts[0]])[:-1]
    return ring if len(ring) >= 3 else pts


def chain(segments, snap=0.02):
    """Exploded outline segments → closed rings."""
    key = lambda p: (round(p[0] / snap), round(p[1] / snap))
    ends = {}
    for i, (a, b) in enumerate(segments):
        ends.setdefault(key(a), []).append((i, 0))
        ends.setdefault(key(b), []).append((i, 1))
    used, rings = set(), []
    for start in range(len(segments)):
        if start in used:
            continue
        used.add(start)
        ring = [segments[start][0], segments[start][1]]
        while True:
            nxt = [(i, e) for i, e in ends.get(key(ring[-1]), []) if i not in used]
            if not nxt:
                break
            i, e = nxt[0]
            used.add(i)
            ring.append(segments[i][1 - e])
        if len(ring) > 3 and math.dist(ring[0], ring[-1]) < 0.05:
            rings.append(ring[:-1])
    return rings


# ---------------------------------------------------------------- the service's drawing

def parse_floor(svg):
    """Everything in the CAD frame, y up, as the service stores it."""
    flip = float(re.search(r'class="layerDisegno"[^>]*translate\(0\.0,([-\d.]+)\)', svg).group(1))
    rooms = {}
    for m in re.finditer(r'<path data-csiv="([^"]+)"[^>]*class="vano"[^>]*d="([^"]+)"', svg):
        rings, cur = [], []
        for cmd, x, y in re.findall(r'([MLZ])\s*(?:(-?[\d.]+),(-?[\d.]+))?', m.group(2)):
            if cmd == "M" and cur:
                rings.append(cur)
                cur = []
            if x:
                cur.append((float(x), float(y)))
        if cur:
            rings.append(cur)
        rooms[m.group(1)] = rings
    labels = {}
    for m in re.finditer(r'<text class="testoVano(?:Small)?" x="([-\d.]+)" y="([-\d.]+)">([^<]+)</text>', svg):
        labels[m.group(3).strip().upper()] = (float(m.group(1)), flip - float(m.group(2)))

    def layer(lid):
        out = []
        for m in re.finditer(r'<g class="layer" id="%s">(.*?)</g>' % re.escape(lid), svg, re.S):
            out.append(m.group(1))
        return "".join(out)

    num = lambda g, k: float(re.search(k + r'="([-\d.]+)"', g).group(1))

    def lines(body):
        # Some layers come twice in the file: keep each segment once, whichever way it runs.
        seen, out = set(), []
        for g in re.findall(r"<line[^>]*>", body):
            a, b = (num(g, "x1"), num(g, "y1")), (num(g, "x2"), num(g, "y2"))
            key = tuple(sorted(((round(a[0], 3), round(a[1], 3)), (round(b[0], 3), round(b[1], 3)))))
            if key not in seen:
                seen.add(key)
                out.append((a, b))
        return out
    shell = chain(lines(layer("SUPLORDAPIANO")))
    arcs = [tuple(map(float, a)) for a in re.findall(
        r'd="M ([-\d.]+) ([-\d.]+) A ([-\d.]+) [-\d.]+ [-\d.]+ (\d) (\d) ([-\d.]+) ([-\d.]+)"', layer("PORTE"))]
    route = []
    for g in re.findall(r'<line[^>]*class="impianto percorsoDisabili[^"]*"[^>]*>', svg):
        way = 1 if "marker-end" in g else (-1 if "marker-start" in g else 0)
        route.append(((num(g, "x1"), num(g, "y1")), (num(g, "x2"), num(g, "y2")), way))
    fountains = [(float(x), float(y)) for x, y in re.findall(
        r'<use[^>]*transform="translate\(([-\d.]+),([-\d.]+)\)[^"]*"[^>]*class="poi tag_0*%d"' % FOUNTAIN_TAG, svg)]
    return {"rooms": rooms, "labels": labels, "shell": shell, "arcs": arcs, "route": route,
            "fountains": fountains, "lines": {v: lines(layer(k)) for k, v in LINE_LAYERS.items()}}


def door_from_arc(arc):
    """A swing arc → hinge, the leaf's tip when closed and when open (CAD frame)."""
    x1, y1, r, large, sweep, x2, y2 = arc
    mx, my = (x1 + x2) / 2, (y1 + y2) / 2
    d = math.dist((x1, y1), (x2, y2))
    h = math.sqrt(max(r * r - (d / 2) ** 2, 0))
    ux, uy = (x2 - x1) / (d or 1), (y2 - y1) / (d or 1)
    for cx, cy in ((mx - uy * h, my + ux * h), (mx + uy * h, my - ux * h)):
        a1 = math.atan2(y1 - cy, x1 - cx)
        a2 = math.atan2(y2 - cy, x2 - cx)
        # The angle the arc sweeps from its start to its end, in the direction its flag says.
        swept = ((a2 - a1) if sweep else (a1 - a2)) % (2 * math.pi)
        if (swept > math.pi) == bool(large):
            return (cx, cy), (x1, y1), (x2, y2), r
    return (mx - uy * h, my + ux * h), (x1, y1), (x2, y2), r


# ---------------------------------------------------------------- OpenStreetMap

def osm_rooms(bbox, origin):
    lat0, lon0 = origin
    k = 111320 * math.cos(math.radians(lat0))
    xy = lambda la, lo: ((lo - lon0) * k, -(la - lat0) * 110540)
    root = ET.fromstring(get(f"{OSM}?bbox={bbox[0]},{bbox[1]},{bbox[2]},{bbox[3]}"))
    nodes = {n.get("id"): xy(float(n.get("lat")), float(n.get("lon"))) for n in root.findall("node")}
    out = []
    for w in root.findall("way"):
        tags = {t.get("k"): t.get("v") for t in w.findall("tag")}
        if "ref" not in tags or "level" not in tags:
            continue
        pts = [nodes[n.get("ref")] for n in w.findall("nd") if n.get("ref") in nodes]
        if len(pts) > 3 and pts[0] == pts[-1]:
            out.append({"level": tags["level"], "ref": tags["ref"].upper(), "tags": tags,
                        "centre": area_centroid(pts[:-1])})
    return out


KIND_ORDER = ["aula", "wc", "ascensore", "corridoio", "scale", "tecnico"]


def kind_from_osm_all(records):
    """Several features can share a room's number (a hall and its aisle steps): the room wins."""
    kinds = [kind_from_osm(r["tags"]) for r in records]
    for k in KIND_ORDER:
        if k in kinds:
            return k
    return None


def kind_from_osm(tags):
    room, indoor = tags.get("room"), tags.get("indoor")
    if room == "toilet" or tags.get("amenity") == "toilets":
        return "wc"
    if room == "stairs" or tags.get("stairs") == "yes" or tags.get("area:highway") == "steps":
        return "scale"
    if room == "elevator" or tags.get("highway") == "elevator":
        return "ascensore"
    if room in ("lecture_hall", "classroom"):
        return "aula"
    if indoor in ("corridor", "area") or room == "corridor" or tags.get("area:highway") == "footway":
        return "corridoio"
    if room == "technical":
        return "tecnico"
    return None


# ---------------------------------------------------------------- the fit

def fit(pairs):
    P = [p for p, _ in pairs]
    Q = [q for _, q in pairs]
    mx, my = sum(p[0] for p in P) / len(P), sum(p[1] for p in P) / len(P)
    nx, ny = sum(q[0] for q in Q) / len(Q), sum(q[1] for q in Q) / len(Q)
    a = b = var = 0.0
    for (px, py), (qx, qy) in zip(P, Q):
        px, py, qx, qy = px - mx, py - my, qx - nx, qy - ny
        a += px * qx + py * qy
        b += px * qy - py * qx
        var += px * px + py * py
    return {"mx": mx, "my": my, "nx": nx, "ny": ny, "s": math.hypot(a, b) / var, "th": math.atan2(b, a)}


def flipped(p):
    """CAD points have y up; the campus frame has y south."""
    return (p[0], -p[1])


def apply(t, q):
    """A flipped CAD point → campus."""
    x, y = q[0] - t["mx"], q[1] - t["my"]
    c, s = math.cos(t["th"]), math.sin(t["th"])
    return (t["s"] * (c * x - s * y) + t["nx"], t["s"] * (s * x + c * y) + t["ny"])


def robust_fit(pairs):
    cur = pairs
    for _ in range(6):
        t = fit(cur)
        errs = [(math.dist(apply(t, p), q), p, q) for p, q in pairs]
        med = statistics.median(e for e, _, _ in errs)
        cur = [(p, q) for e, p, q in errs if e < max(0.5, 2.5 * med)]
    t = fit(cur)
    errs = sorted(math.dist(apply(t, p), q) for p, q in cur)
    return t, len(cur), statistics.median(errs)


# ---------------------------------------------------------------- main

def main(csie):
    campus_file = next(f for f in HERE.glob("*.json") if f.name != "livelli.json"
                       and csie in f.read_text())
    campus = json.loads(campus_file.read_text())
    building = next(b for b in campus["edifici"] if b["csie"] == csie)
    floors = building["livelli"]
    lat0, lon0 = campus["origine"]
    xs = [p[0] for p in building["pianta"]]
    ys = [p[1] for p in building["pianta"]]
    k = 111320 * math.cos(math.radians(lat0))
    bbox = (lon0 + (min(xs) - 15) / k, lat0 - (max(ys) + 15) / 110540,
            lon0 + (max(xs) + 15) / k, lat0 - (min(ys) - 15) / 110540)

    drawn = {c: parse_floor(get(f"{MAPS}/piano/{c}/svg/pub", json.dumps(TAGS).encode())) for c in floors}
    rooms = osm_rooms(bbox, (lat0, lon0))

    # Which OpenStreetMap level is which floor: the one sharing the most room numbers.
    level_of = {}
    for c, f in drawn.items():
        refs = {csiv[len(c):].upper() for csiv in f["rooms"]}
        counts = {}
        for r in rooms:
            if r["ref"] in refs:
                counts[r["level"]] = counts.get(r["level"], 0) + 1
        level_of[c] = max(counts, key=counts.get) if counts else None

    pairs = []
    by_floor = {}
    for c in drawn:
        by_floor[c] = {}
        for r in rooms:
            if r["level"] == level_of[c]:
                by_floor[c].setdefault(r["ref"], []).append(r)
    for c, f in drawn.items():
        for csiv, rings in f["rooms"].items():
            same = by_floor[c].get(csiv[len(c):].upper(), [])
            # Only the room itself, not steps or areas inside it, says where its centre is.
            room = [r for r in same if r["tags"].get("indoor") in ("room", "corridor", "area")]
            if room:
                pairs.append((flipped(area_centroid(rings[0])), room[0]["centre"]))
    t, used, err = robust_fit(pairs)
    print(f"fit on {used}/{len(pairs)} rooms, median error {err * 100:.0f} cm, "
          f"scale {t['s']:.4f}, rotation {math.degrees(t['th']):.2f}°")

    T = lambda p: [r2(v) for v in apply(t, flipped(p))]
    out = {"csie": csie, "fonte": "onlineservices.polimi.it/maps_rest, piano/<csip>/svg/pub",
           "trasformazione": {k2: round(v, 6) for k2, v in t.items()}, "piani": {}}
    for c, f in drawn.items():
        osm = by_floor[c]
        shell = max(f["shell"], key=lambda ring: abs(area(ring))) if f["shell"] else []
        all_rooms = [ring for rings in f["rooms"].values() for ring in rings[:1]]
        vani = []
        for csiv, rings in f["rooms"].items():
            ref = csiv[len(c):].upper()
            kind = kind_from_osm_all(osm[ref]) if ref in osm else None
            ring = rings[0]
            if kind is None:
                count = lambda name: sum(1 for a, b in f["lines"][name]
                                         if inside(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2), ring))
                if count("ascensori") >= 2:
                    kind = "ascensore"
                elif count("scale") >= 6 and abs(area(ring)) < 60:
                    kind = "scale"
                elif abs(area(ring)) < 2.0:
                    kind = "tecnico"
                else:
                    kind = "locale"
            label = f["labels"].get(ref) or area_centroid(ring)
            vani.append({"csiv": csiv, "tipo": kind, "etichetta": T(label),
                         "forma": [[T(p) for p in simplify(r, 0.03)] for r in rings]})
        doors = []
        for arc in f["arcs"]:
            hinge, p1, p2, radius = door_from_arc(arc)
            # The closed leaf lies in the wall; the open one swings into a room.
            in_room = lambda p: any(inside(((hinge[0] + p[0]) / 2, (hinge[1] + p[1]) / 2), ring) for ring in all_rooms)
            closed, open_ = (p1, p2) if in_room(p2) and not in_room(p1) else (p2, p1)
            ux, uy = closed[0] - hinge[0], closed[1] - hinge[1]
            n = math.hypot(ux, uy) or 1
            nx, ny = -uy / n, ux / n
            mid = ((hinge[0] + closed[0]) / 2, (hinge[1] + closed[1]) / 2)
            out_a = shell and not inside((mid[0] + nx * 0.9, mid[1] + ny * 0.9), shell)
            out_b = shell and not inside((mid[0] - nx * 0.9, mid[1] - ny * 0.9), shell)
            doors.append({"cardine": T(hinge), "chiusa": T(closed), "aperta": T(open_),
                          "esterna": bool(out_a or out_b)})
        out["piani"][c] = {
            "livello_osm": level_of[c],
            "contorno": [[T(p) for p in simplify(ring, 0.03)] for ring in f["shell"]],
            "vani": vani,
            "porte": doors,
            "linee": {name: [T(a) + T(b) for a, b in segs] for name, segs in f["lines"].items()},
            "percorso_accessibile": [T(a) + T(b) + [way] for a, b, way in f["route"]],
            "acqua": [T(p) for p in f["fountains"]],
        }
        print(f"{c}: {len(vani)} rooms, {len(doors)} doors ({sum(d['esterna'] for d in doors)} outside), "
              f"{len(f['route'])} route segments, {len(f['fountains'])} fountains")
    dest = HERE / "piante" / f"{csie}-geometria.json"
    dest.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"wrote {dest.relative_to(HERE)}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "MIA0203")
