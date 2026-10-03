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
import tempfile
import sys
import urllib.request
import xml.etree.ElementTree as ET

HERE = pathlib.Path(__file__).parent
MAPS = "https://onlineservices.polimi.it/maps_rest/rest"
OSM = "https://api.openstreetmap.org/api/0.6/map"
TAGS = [str(i) for i in range(1, 19)] + ["POI"]       # every public point-of-interest tag
FOUNTAIN_TAG = 5                                      # BEVERINO
# The drawings come in two CAD standards: short layer names (PORTE) and long ones
# (ARC_Porte). Each entry lists the names, or name prefixes ending in "*", of one kind of line.
LINE_LAYERS = {"scale": ["SCALE", "ARC_Scale rampe e ringhiere"],
               "arredi": ["LAYOUT_ARREDI", "ARC_Arredi ON"],
               "sanitari": ["IDR_*"],
               "finestre": ["FINESTRE", "ARC_Finestre", "INFISSI"],
               "ringhiere": ["RINGHIERA"],
               "esterni": ["ESTERNI", "ARC_Contesto esterno"],
               "ascensori": ["ASCENSORI", "TOV_6.3.2.A*", "TOV_ASCENSORI", "VANO_ASCENSORE"]}
DOOR_LAYERS = ["PORTE", "ARC_Porte"]


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


def seg_dist(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / ((dx * dx + dy * dy) or 1)))
    return math.dist(p, (a[0] + dx * t, a[1] + dy * t))


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

    def layer(names):
        ids = "|".join(re.escape(n[:-1]) + '[^"]*' if n.endswith("*") else re.escape(n) for n in names)
        out = []
        for m in re.finditer(r'<g class="layer" id="(?:%s)">(.*?)</g>' % ids, svg, re.S):
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
    shell = chain(lines(layer(["SUPLORDAPIANO"])))
    arcs = [tuple(map(float, a)) for a in re.findall(
        r'd="M ([-\d.]+) ([-\d.]+) A ([-\d.]+) [-\d.]+ [-\d.]+ (\d) (\d) ([-\d.]+) ([-\d.]+)"', layer(DOOR_LAYERS))]
    # Each leaf is drawn open, as a thin rectangle out of its hinge.
    leaves = lines(layer(DOOR_LAYERS))
    route = []
    for g in re.findall(r'<line[^>]*class="impianto percorsoDisabili[^"]*"[^>]*>', svg):
        way = 1 if "marker-end" in g else (-1 if "marker-start" in g else 0)
        route.append(((num(g, "x1"), num(g, "y1")), (num(g, "x2"), num(g, "y2")), way))
    fountains = [(float(x), float(y)) for x, y in re.findall(
        r'<use[^>]*transform="translate\(([-\d.]+),([-\d.]+)\)[^"]*"[^>]*class="poi tag_0*%d"' % FOUNTAIN_TAG, svg)]
    return {"rooms": rooms, "labels": labels, "shell": shell, "arcs": arcs, "leaves": leaves, "route": route,
            "fountains": fountains, "lines": {k: lines(layer(v)) for k, v in LINE_LAYERS.items()}}


def parse_dwg(path):
    """The same floor from the service's CAD download (`download/dwg/piano/<csip>`), for
    when its drawing is not served: converted with LibreDWG's dwg2dxf and read with ezdxf,
    giving what `parse_floor` gives. Rooms are the net-area outlines, each named by the
    room-number block inside it; arcs and lines come from the same layers. It carries no
    room labels, step-free route or fountains: those come only with the drawing."""
    import fnmatch
    import subprocess
    import ezdxf
    dxf = path.with_suffix(".dxf")
    subprocess.run(["dwg2dxf", "-y", "-o", str(dxf), str(path)], check=True, capture_output=True)
    msp = ezdxf.readfile(str(dxf)).modelspace()
    csip = path.stem
    match = lambda layer, names: any(fnmatch.fnmatch(layer, n) for n in names)
    xy = lambda p: (float(p[0]), float(p[1]))

    def flat(entity):
        # Blocks (fixtures, lifts) are opened up; polylines become their segments.
        if entity.dxftype() == "INSERT":
            for sub in entity.virtual_entities():
                yield from flat(sub)
        elif entity.dxftype() == "LINE":
            yield entity
        elif entity.dxftype() in ("LWPOLYLINE", "POLYLINE"):
            yield from entity.virtual_entities()
        elif entity.dxftype() == "ARC":
            yield entity

    def lines(names):
        seen, out = set(), []
        for e in msp:
            if not match(e.dxf.layer, names):
                continue
            for s in flat(e):
                if s.dxftype() != "LINE":
                    continue
                a, b = xy(s.dxf.start), xy(s.dxf.end)
                key = tuple(sorted(((round(a[0], 3), round(a[1], 3)), (round(b[0], 3), round(b[1], 3)))))
                if key not in seen and math.dist(a, b) > 1e-6:
                    seen.add(key)
                    out.append((a, b))
        return out

    def arcs(names):
        out = []
        for e in msp:
            if not match(e.dxf.layer, names):
                continue
            for s in flat(e):
                if s.dxftype() != "ARC":
                    continue
                c, r = xy(s.dxf.center), s.dxf.radius
                a0, a1 = math.radians(s.dxf.start_angle), math.radians(s.dxf.end_angle)
                span = (a1 - a0) % (2 * math.pi)
                # DXF arcs run counter-clockwise, y up: the drawing's sweep flag 1.
                out.append((c[0] + r * math.cos(a0), c[1] + r * math.sin(a0), r, int(span > math.pi), 1,
                            c[0] + r * math.cos(a1), c[1] + r * math.sin(a1)))
        return out

    names = [(xy(e.dxf.insert), next((a.dxf.text for a in e.attribs if a.dxf.tag == "CODICE_VANO"), None))
             for e in msp if e.dxftype() == "INSERT" and e.dxf.name == "ID_VANI"]
    rooms = {}
    for e in msp:
        if e.dxf.layer != "SUPNETTAVANO" or e.dxftype() != "LWPOLYLINE":
            continue
        ring = [xy(p) for p in e.get_points("xy")]
        code = next((n for p, n in names if n and inside(p, ring)), None)
        if code:
            rooms[csip + code] = [ring]
    shells = [[xy(p) for p in e.get_points("xy")] for e in msp
              if e.dxf.layer == "SUPLORDAPIANO" and e.dxftype() == "LWPOLYLINE"]
    shell = shells or chain(lines(["SUPLORDAPIANO"]))
    return {"rooms": rooms, "labels": {}, "shell": shell, "arcs": arcs(DOOR_LAYERS), "leaves": lines(DOOR_LAYERS),
            "route": [], "fountains": [], "lines": {k: lines(v) for k, v in LINE_LAYERS.items()}}


def load_floor(csip, cache):
    """A floor's drawing from the service, or its CAD download when the drawing fails."""
    try:
        return parse_floor(get(f"{MAPS}/piano/{csip}/svg/pub", json.dumps(TAGS).encode()))
    except Exception as error:
        print(f"{csip}: drawing not served ({error}), reading the CAD download")
        path = cache / f"{csip}.dwg"
        with urllib.request.urlopen(f"{MAPS}/download/dwg/piano/{csip}", timeout=120) as r:
            path.write_bytes(r.read())
        return parse_dwg(path)


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


def voids(shell, rooms, step=0.5, wall=0.6):
    """Parts of the floor that are no room and too wide to be a wall: double-height
    spaces and voids over the floor below. Found on a grid, traced, and simplified."""
    if not shell:
        return []
    xs, ys = [p[0] for p in shell], [p[1] for p in shell]
    boxes = [(min(p[0] for p in r), min(p[1] for p in r), max(p[0] for p in r), max(p[1] for p in r)) for r in rooms]
    edges = [(a, b) for r in rooms + [shell] for a, b in zip(r, r[1:] + r[:1])]
    # Edges bucketed by grid cell, so each point only looks at the walls near it.
    buckets = {}
    for a, b in edges:
        for gx in range(int((min(a[0], b[0]) - wall) // 2), int((max(a[0], b[0]) + wall) // 2) + 1):
            for gy in range(int((min(a[1], b[1]) - wall) // 2), int((max(a[1], b[1]) + wall) // 2) + 1):
                buckets.setdefault((gx, gy), []).append((a, b))
    cells = set()
    for i in range(int((max(xs) - min(xs)) / step) + 1):
        for j in range(int((max(ys) - min(ys)) / step) + 1):
            p = (min(xs) + (i + 0.5) * step, min(ys) + (j + 0.5) * step)
            if not inside(p, shell):
                continue
            if any(x0 <= p[0] <= x1 and y0 <= p[1] <= y1 and inside(p, r) for (x0, y0, x1, y1), r in zip(boxes, rooms)):
                continue
            near = buckets.get((int(p[0] // 2), int(p[1] // 2)), [])
            if all(seg_dist(p, a, b) > wall for a, b in near):
                cells.add((i, j))
    # The cells' outer edges, chained into rings: a cell edge shared by two cells is inside.
    count = {}
    for i, j in cells:
        for e in (((i, j), (i + 1, j)), ((i + 1, j), (i + 1, j + 1)), ((i, j + 1), (i + 1, j + 1)), ((i, j), (i, j + 1))):
            count[e] = count.get(e, 0) + 1
    to_xy = lambda c: (min(xs) + c[0] * step, min(ys) + c[1] * step)
    rings = chain([(to_xy(a), to_xy(b)) for e, n in count.items() if n == 1 for a, b in [e]], snap=step / 4)
    return [simplify(r, step * 0.75) for r in rings if abs(area(r)) >= 6]


def outline_fit(P, Q, prior=None):
    """A similarity taking outline P onto outline Q. With a prior (rotation, scale) from
    the campus's other drawings only the shift is sought; without, the four quarter turns
    of the outlines' main wall directions are tried. Each is refined by nearest points,
    trimmed so a floor larger than the footprint (a basement) does not pull it; the
    closest kept."""
    def along(ring, step=0.5):
        out = []
        for a, b in zip(ring, ring[1:] + ring[:1]):
            n = max(1, int(math.dist(a, b) / step))
            out += [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n)]
        return out

    def heading(ring):
        sx = sy = 0.0
        for a, b in zip(ring, ring[1:] + ring[:1]):
            ang, w = math.atan2(b[1] - a[1], b[0] - a[0]) * 4, math.dist(a, b)
            sx, sy = sx + w * math.cos(ang), sy + w * math.sin(ang)
        return math.atan2(sy, sx) / 4

    def nearest(p):
        best = (1e9, p)
        for a, b in zip(Q, Q[1:] + Q[:1]):
            dx, dy = b[0] - a[0], b[1] - a[1]
            u = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / ((dx * dx + dy * dy) or 1)))
            q = (a[0] + dx * u, a[1] + dy * u)
            best = min(best, (math.dist(p, q), q))
        return best

    pts = along(P)[::3]
    cp, cq = area_centroid(P), area_centroid(Q)
    best = None
    starts = [prior[0]] if prior else [heading(Q) - heading(P) + k * math.pi / 2 for k in range(4)]
    for th in starts:
        t = {"mx": cp[0], "my": cp[1], "nx": cq[0], "ny": cq[1], "s": prior[1] if prior else 1.0, "th": th}
        for _ in range(30):
            near = sorted((nearest(apply(t, p)) + (p,) for p in pts), key=lambda x: x[0])
            pairs = [(p, q) for _, q, p in near[:int(len(near) * 0.6)]]
            if prior:
                # Only the shift: the mean gap of the closest pairs.
                dx = statistics.mean(q[0] - apply(t, p)[0] for p, q in pairs)
                dy = statistics.mean(q[1] - apply(t, p)[1] for p, q in pairs)
                t = {**t, "nx": t["nx"] + dx, "ny": t["ny"] + dy}
            else:
                t = fit(pairs)
                t["s"] = min(1.05, max(0.95, t["s"]))
        err = statistics.median(nearest(apply(t, p))[0] for p in pts)
        if best is None or err < best[1]:
            best = (t, err)
    return best


def lift_centres(segs):
    """Lift cars: the lines of the lift layer that touch each other, as one point each."""
    groups = []
    for a, b in segs:
        hit = [g for g in groups if any(min(math.dist(p, q) for p in (a, b) for q in s) < 0.3 for s in g)]
        merged = [(a, b)] + [s for g in hit for s in g]
        groups = [g for g in groups if g not in hit] + [merged]
    return [(sum(p[0] for s in g for p in s) / (2 * len(g)), sum(p[1] for s in g for p in s) / (2 * len(g)))
            for g in groups if len(g) >= 4]


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

    cache = pathlib.Path(tempfile.mkdtemp(prefix="dwg-"))
    drawn = {c: load_floor(c, cache) for c in floors}
    # A floor drawn without its outline (some basements) takes the largest one of the others:
    # every floor is in the same CAD frame.
    widest = max((f["shell"] for f in drawn.values() if f["shell"]),
                 key=lambda s: max(abs(area(r)) for r in s), default=[])
    for c, f in drawn.items():
        if not f["shell"] and f["rooms"]:
            print(f"{c}: no outline drawn, the widest floor's is used")
            f["shell"] = widest
    rooms = osm_rooms(bbox, (lat0, lon0))

    # Which OpenStreetMap level is which floor: room numbers repeat on every floor, so
    # each level goes to the one floor it shares the most numbers with, and only when
    # that is enough to tell. Every floor is in the same CAD frame, so floors that
    # OpenStreetMap does not map are placed by the fit on the others.
    shared = []
    for c, f in drawn.items():
        refs = {csiv[len(c):].upper() for csiv in f["rooms"]}
        counts = {}
        for r in rooms:
            if r["ref"] in refs:
                counts[r["level"]] = counts.get(r["level"], 0) + 1
        shared += [(n, c, lvl) for lvl, n in counts.items()]
    level_of, taken = {c: None for c in drawn}, set()
    for n, c, lvl in sorted(shared, reverse=True):
        if n >= 8 and level_of[c] is None and lvl not in taken:
            level_of[c] = lvl
            taken.add(lvl)
    print("OpenStreetMap levels:", {c: lvl for c, lvl in level_of.items() if lvl})

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
    ref = None
    fitted = None
    if len(pairs) >= 4:
        t, used, err = robust_fit(pairs)
        print(f"fit on {used}/{len(pairs)} rooms, median error {err * 100:.0f} cm, "
              f"scale {t['s']:.4f}, rotation {math.degrees(t['th']):.2f}°")
        # Room numbers repeat across buildings too: a fit this loose matched the wrong rooms.
        fitted = t if err < 1.0 else None
        if not fitted:
            print("  too loose: those rooms are not the same, the outline is used instead")
            level_of = {c: None for c in drawn}
    if fitted:
        t = fitted
    else:
        # OpenStreetMap maps no room inside: match the floor's outline to the building's.
        # The floor whose outline sits best on the footprint places the building: often the
        # ground floor, but a basement may reach under a courtyard and a ground floor be partial.
        known = [json.loads(g.read_text())["trasformazione"] for g in (HERE / "piante").glob("*-geometria.json")
                 if not g.name.startswith(csie)]
        known = [k for k in known if k.get("da") != "contorno"]
        prior = (statistics.median(k["th"] for k in known), statistics.median(k["s"] for k in known)) if known else None
        tries = []
        for c in drawn:
            if drawn[c]["shell"]:
                shell = max(drawn[c]["shell"], key=lambda r: abs(area(r)))
                # Most drawings share one orientation, but some are drawn a quarter turn round:
                # each quarter is tried.
                for k in range(4) if prior else [0]:
                    turned = (prior[0] + k * math.pi / 2, prior[1]) if prior else None
                    tries.append(outline_fit([flipped(p) for p in shell], [tuple(p) for p in building["pianta"]], turned) + (c,))
        t, err, ref = min(tries, key=lambda x: x[1])
        print(f"no rooms in OpenStreetMap: {ref}'s outline fitted to the building's, "
              f"median gap {err * 100:.0f} cm, scale {t['s']:.4f}, rotation {math.degrees(t['th']):.2f}°")
        t["da"] = "contorno"

    # Some floors are drawn with their own origin. Lift shafts stand in the same place on
    # every floor, so a floor OpenStreetMap does not place is moved until its lifts sit on
    # those of a floor it does.
    lifts = {c: lift_centres([(apply(t, flipped(a)), apply(t, flipped(b))) for a, b in f["lines"]["ascensori"]])
             for c, f in drawn.items()}
    anchors = [c for c in drawn if level_of[c]] or [ref]
    anchor = next((c for c in anchors if drawn[c]["shell"]), None)
    # Placed by its outline, every floor goes onto the building's footprint; placed by its rooms,
    # onto the floor OpenStreetMap placed.
    # Every other floor goes onto the anchor floor's own outline, wherever that was placed:
    # the building's footprint is only a rough sketch of it.
    anchor_shell = ([apply(t, flipped(p)) for p in max(drawn[anchor]["shell"], key=lambda r: abs(area(r)))]
                    if anchor else [tuple(p) for p in building["pianta"]])
    placed = [p for c in anchors for p in lifts[c]]
    shift = {}
    for c in drawn:
        shift[c] = (0.0, 0.0)
        if c in anchors or not placed:
            continue
        best = (0, 0.0)
        for p in lifts[c]:
            for q in placed:
                dx, dy = q[0] - p[0], q[1] - p[1]
                n = sum(1 for a in lifts[c] if any(math.dist((a[0] + dx, a[1] + dy), b) < 0.6 for b in placed))
                if n > best[0] or (n == best[0] and math.hypot(dx, dy) < math.hypot(*best[1:] or (0, 0))):
                    best = (n, dx, dy)
        # Floors drawn apart sit a few metres off at most: a bigger jump means the lifts paired
        # up wrongly (two shafts the same distance apart elsewhere), so the outline decides.
        if best[0] >= 2 and math.hypot(*best[1:]) < 8:
            shift[c] = best[1:]
        elif drawn[c]["shell"] and anchor_shell:
            # No lifts: the floor's outline onto the anchor's, by a shift only.
            own = [apply(t, flipped(p)) for p in max(drawn[c]["shell"], key=lambda r: abs(area(r)))]
            moved, gap = outline_fit(own, anchor_shell, (0.0, 1.0))
            dx, dy = apply(moved, own[0])[0] - own[0][0], apply(moved, own[0])[1] - own[0][1]
            if gap < 1.0:
                shift[c] = (dx, dy)
            else:
                print(f"{c}: no lifts, and its outline matches nothing: left where its drawing puts it")
    print("moved:", {c: (r2(dx), r2(dy)) for c, (dx, dy) in shift.items() if math.hypot(dx, dy) > 0.05})

    out = {"csie": csie, "fonte": "onlineservices.polimi.it/maps_rest, piano/<csip>/svg/pub",
           "trasformazione": {k2: round(v, 6) if isinstance(v, float) else v for k2, v in t.items()}, "piani": {}}
    for c, f in drawn.items():
        T = lambda p, c=c: [r2(v + d) for v, d in zip(apply(t, flipped(p)), shift[c])]
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
                if count("sanitari") >= 6 and abs(area(ring)) < 60:
                    kind = "wc"
                elif count("ascensori") >= 2:
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
        doors, unread = [], 0
        for arc in f["arcs"]:
            hinge, p1, p2, radius = door_from_arc(arc)
            # The arc ends where the drawn (open) leaf ends; its other end is the closed leaf, in the wall.
            near_leaf = lambda p: min((seg_dist(p, a, b) for a, b in f["leaves"]), default=1e9)
            d1, d2 = near_leaf(p1), near_leaf(p2)
            # The open tip touches its leaf; the closed one is clear of every leaf, its neighbours' included.
            if min(d1, d2) < 0.03 and max(d1, d2) > 0.12:
                closed, open_ = (p1, p2) if d2 < d1 else (p2, p1)
            else:
                # No leaf drawn: the open one swings into a room.
                in_room = lambda p: any(inside(((hinge[0] + p[0]) / 2, (hinge[1] + p[1]) / 2), ring) for ring in all_rooms)
                closed, open_ = (p1, p2) if in_room(p2) and not in_room(p1) else (p2, p1)
                unread += 1
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
            "vuoti": [[T(p) for p in ring] for ring in voids(shell, all_rooms)],
        }
        print(f"{c}: {len(vani)} rooms, {len(doors)} doors ({sum(d['esterna'] for d in doors)} outside, "
              f"{unread} without a drawn leaf), "
              f"{len(f['route'])} route segments, {len(f['fountains'])} fountains")
    dest = HERE / "piante" / f"{csie}-geometria.json"
    dest.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"wrote {dest.relative_to(HERE)}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "MIA0203")
