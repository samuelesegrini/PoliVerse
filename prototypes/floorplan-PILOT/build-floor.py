#!/usr/bin/env python3
"""Turn one Polimi floor's public DWG into a vector floor plan.

PILOT — one floor, to judge the data before designing the real pipeline.

    python3 build-floor.py MIA0203001        # building MIA0203, floor 001

Needs `dwg2dxf` (LibreDWG) on PATH and `pip install ezdxf`.

Writes out/<floor>.json (rooms as polygons in metres, keyed by the same
room id the maps API uses) and out/<floor>.svg (a styled render). `out/` is
gitignored: the plans are Polimi's, fetched live, never committed.
"""
import json, math, os, subprocess, sys, urllib.request

from ezdxf import path as dxfpath, recover

BASE = "https://onlineservices.polimi.it/maps_rest/rest"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")

# DWG layer -> role in our map. Everything else (furniture, plumbing,
# network sockets, CAD bookkeeping text) is dropped.
LINE_LAYERS = {
    "MURI": "wall",
    "MURI_VISTA": "wall",
    "M_PANNELLI": "partition",
    "FINESTRE": "window",
    "PORTE": "door",
    "SCALE": "stair",
    "EST_SCALE": "stair",
    "ASCENSORI": "lift",
    "RINGHIERA": "railing",
    "EST_RINGHIERA": "railing",
    "ESTERNI": "outdoor",
}
ROOM_LAYER = "SUPNETTAVANO"      # one closed polyline per room (net area)
HOLE_LAYER = "SUPNETTAVANO_FORI" # shafts/holes cut out of rooms
FLOOR_LAYER = "SUPLORDAPIANO"    # gross outline of the floor
NUMBER_LAYER = "NUMERAZIONE"     # block with attribute CODICE_VANO
NAME_LAYER = "TESTO_AULA"        # "AULA T.2.1" style labels


def fetch_dwg(floor):
    path = os.path.join(OUT, f"{floor}.dwg")
    if not os.path.exists(path):
        with urllib.request.urlopen(f"{BASE}/download/dwg/piano/{floor}", timeout=60) as r:
            open(path, "wb").write(r.read())
    return path


def to_dxf(dwg):
    dxf = dwg[:-4] + ".dxf"
    subprocess.run(["dwg2dxf", "-y", "-o", dxf, dwg], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return dxf


def r(v):
    return round(v, 3)


def poly_points(e):
    """LWPOLYLINE -> [[x, y], ...]; bulges (arcs) are flattened."""
    return [[r(p.x), r(p.y)] for p in dxfpath.make_path(e).flattening(0.05)]


def segments(e):
    t = e.dxftype()
    if t == "LINE":
        return [[[r(e.dxf.start.x), r(e.dxf.start.y)], [r(e.dxf.end.x), r(e.dxf.end.y)]]]
    if t in ("ARC", "CIRCLE", "LWPOLYLINE", "POLYLINE"):
        pts = [[r(p.x), r(p.y)] for p in dxfpath.make_path(e).flattening(0.05)]
        return [pts] if len(pts) > 1 else []
    return []


def inside(pt, poly):
    x, y = pt
    hit = False
    for (x1, y1), (x2, y2) in zip(poly, poly[1:] + poly[:1]):
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            hit = not hit
    return hit


def area(poly):
    return abs(sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(poly, poly[1:] + poly[:1]))) / 2


def centroid(poly):
    a = cx = cy = 0
    for (x1, y1), (x2, y2) in zip(poly, poly[1:] + poly[:1]):
        k = x1 * y2 - x2 * y1
        a += k; cx += (x1 + x2) * k; cy += (y1 + y2) * k
    if abs(a) < 1e-9:
        return [r(sum(p[0] for p in poly) / len(poly)), r(sum(p[1] for p in poly) / len(poly))]
    return [r(cx / (3 * a)), r(cy / (3 * a))]


def build(floor):
    os.makedirs(OUT, exist_ok=True)
    doc, _ = recover.readfile(to_dxf(fetch_dwg(floor)))
    msp = doc.modelspace()

    lines = {}
    for e in msp:
        role = LINE_LAYERS.get(e.dxf.layer)
        if role:
            lines.setdefault(role, []).extend(segments(e))

    outline = [poly_points(e) for e in msp.query(f'LWPOLYLINE[layer=="{FLOOR_LAYER}"]')]
    holes = [poly_points(e) for e in msp.query(f'LWPOLYLINE[layer=="{HOLE_LAYER}"]')]

    numbers = []
    for ins in msp.query(f'INSERT[layer=="{NUMBER_LAYER}"]'):
        code = next((a.dxf.text.strip() for a in ins.attribs if a.dxf.tag == "CODICE_VANO"), None)
        if code:
            numbers.append((code, [ins.dxf.insert.x, ins.dxf.insert.y]))
    names = [(t.plain_text().strip(), [t.dxf.insert.x, t.dxf.insert.y])
             for t in msp.query(f'MTEXT[layer=="{NAME_LAYER}"]')]

    rooms, unmatched = [], 0
    for e in msp.query(f'LWPOLYLINE[layer=="{ROOM_LAYER}"]'):
        poly = poly_points(e)
        code = next((c for c, p in numbers if inside(p, poly)), None)
        name = next((n for n, p in names if inside(p, poly)), None)
        unmatched += code is None
        rooms.append({
            "id": f"{floor}{code}" if code else None,
            "code": code,
            "name": name,
            "area": round(area(poly), 1),
            "center": centroid(poly),
            "polygon": poly,
        })
    rooms.sort(key=lambda x: x["code"] or "~")

    xs = [p[0] for ring in outline + [x["polygon"] for x in rooms] for p in ring]
    ys = [p[1] for ring in outline + [x["polygon"] for x in rooms] for p in ring]
    for segs in lines.values():
        for s in segs:
            xs += [p[0] for p in s]; ys += [p[1] for p in s]
    data = {
        "floor": floor,
        "building": floor[:7],
        "units": "m",
        "bounds": [r(min(xs)), r(min(ys)), r(max(xs)), r(max(ys))],
        "outline": outline,
        "holes": holes,
        "rooms": rooms,
        "lines": lines,
    }
    json.dump(data, open(os.path.join(OUT, f"{floor}.json"), "w"), separators=(",", ":"))
    open(os.path.join(OUT, f"{floor}.svg"), "w").write(svg(data))
    print(f"{floor}: {len(rooms)} rooms ({unmatched} without a number), "
          f"{sum(len(v) for v in lines.values())} line strokes, "
          f"{data['bounds'][2] - data['bounds'][0]:.1f} x {data['bounds'][3] - data['bounds'][1]:.1f} m")
    return data


def svg(d, scale=12, pad=2):
    x0, y0, x1, y1 = d["bounds"]
    w, h = (x1 - x0 + 2 * pad) * scale, (y1 - y0 + 2 * pad) * scale

    def pt(p):  # DWG y grows up, SVG y grows down
        return f"{(p[0] - x0 + pad) * scale:.1f},{(y1 - p[1] + pad) * scale:.1f}"

    def path(ring, close=True):
        return "M" + "L".join(pt(p) for p in ring) + ("Z" if close else "")

    style = {
        "outdoor": "stroke:#9aa79a;stroke-width:1",
        "railing": "stroke:#b8b2a7;stroke-width:1",
        "stair": "stroke:#a39e93;stroke-width:0.8",
        "lift": "stroke:#a39e93;stroke-width:0.8",
        "window": "stroke:#7fb2d6;stroke-width:1.6",
        "partition": "stroke:#6d675e;stroke-width:1.4",
        "door": "stroke:#c4703f;stroke-width:1",
        "wall": "stroke:#2f2b26;stroke-width:2.4;stroke-linecap:square",
    }
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:.0f} {h:.0f}" '
           f'width="{w:.0f}" height="{h:.0f}" font-family="-apple-system,Helvetica,sans-serif">',
           f'<rect width="100%" height="100%" fill="#f4f1ea"/>']
    for ring in d["outline"]:
        out.append(f'<path d="{path(ring)}" fill="#fffdf8" stroke="#d9d3c6" stroke-width="1"/>')
    for room in d["rooms"]:
        fill = "#e3ecf7" if room["name"] else "#f6efe2"
        out.append(f'<path d="{path(room["polygon"])}" fill="{fill}" data-id="{room["id"] or ""}"/>')
    for ring in d["holes"]:
        out.append(f'<path d="{path(ring)}" fill="#ddd6c8"/>')
    for role, st in style.items():
        segs = d["lines"].get(role, [])
        if segs:
            out.append(f'<path d="{"".join(path(s, False) for s in segs)}" fill="none" style="{st}"/>')
    for room in d["rooms"]:
        x, y = pt(room["center"]).split(",")
        if room["name"]:
            out.append(f'<text x="{x}" y="{y}" text-anchor="middle" font-size="13" font-weight="600" fill="#1f3b63">{room["name"]}</text>')
        elif room["code"] and room["area"] > 6:
            out.append(f'<text x="{x}" y="{y}" text-anchor="middle" font-size="9" fill="#8a8274">{room["code"]}</text>')
    out.append("</svg>")
    return "\n".join(out)


if __name__ == "__main__":
    build(sys.argv[1] if len(sys.argv) > 1 else "MIA0203001")
