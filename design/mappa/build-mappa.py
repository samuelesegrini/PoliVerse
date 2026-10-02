#!/usr/bin/env python3
"""Draws the campus buildings as illustrations in the Mappa / Edificio style.

Run `python3 build-mappa.py` to regenerate every `<campus>/<csie>-*.svg`.

Each building is described by hand in `<campus>.json`: a simplified outline
in metres (a few chosen corners, not a survey), its floor count, rooftop
plant, and entrance. This file turns that description into two drawings that
share one look, so building fifty reads as the same hand as building one:

- `<csie>-mappa.svg` — top-down, the building with its surroundings, as in
  the "Mappa delle aule libere" illustration;
- `<csie>-isometrico.svg` — the building alone in isometric, one group per
  floor (`piano-0`, `piano-1`, …) so a single floor can be highlighted, as in
  the "Edificio con l'aula" illustration.

Coordinates are metres in a per-campus frame: x grows east, y grows south,
origin at the campus `origine` (lat, lon). Every building of a campus lives
in the same frame, so the top-down drawings line up into one campus map.

No transforms are written: offsets are baked into the path data, so the SVGs
survive any importer.
"""
import json
import math
import pathlib

HERE = pathlib.Path(__file__).parent

# Palette — taken from the illustrations, not invented here.
GROUND = "#EEF0EA"
GREEN = "#D5E8CC"
ROAD_EDGE, ROAD = "#DADDD5", "#FFFFFF"
ROAD_DASH = "#E6E8E1"
TREE, TREE_SHADE, TREE_LIGHT = "#A9CF95", "#8DBE78", "#BCDBA9"
ROOF_TOP, ROOF_BOTTOM = "#FFFFFF", "#F2F3F6"
WALL_TOP, WALL_BOTTOM = "#D3D7DF", "#BFC4CE"
SHADOW = "#4E5566"
PLANT, PLANT_LIP = "#E6E8EC", "#D3D7DF"
BADGE, BADGE_FOCUS = "#8E8E93", "#1C6BAD"

ISO_SLAB_LEFT, ISO_SLAB_RIGHT, ISO_SLAB_TOP = "#F2F3F6", "#D4D8DF", "#FFFFFF"
ISO_GLASS_LEFT = ("#B9D2EA", "#8FB1D4")
ISO_GLASS_RIGHT = ("#7F9FC2", "#617FA3")
ISO_FOCUS_LEFT = ("#3D86C9", "#1C6BAD")
ISO_FOCUS_RIGHT = ("#1B5E98", "#154C7C")
ISO_ROOF_INNER = "#EEF0F3"
ISO_PLANT = ("#E3E6EB", "#C7CCD5", "#FFFFFF")
ISO_LOT = ("#C8D4E1", "#AFBFD0", "#E3ECF5")
ISO_BASE = ("#C9CED6", "#AEB4BE", "#E9EBEF")
ISO_PATH = "#F4F7FA"
ISO_DOOR = "#2D3B4F"
ISO_SHADOW = "#1D2B40"
TRUNK = "#8A6A48"

# Proportions.
CORNER = 2.5               # m, rounding of every footprint corner on the map
WALL_PER_FLOOR = 1.1       # m of visible wall per floor on the map
ISO_SCALE = 2.0            # drawing units per metre in plan
ISO_FLOOR = 18.0           # units per floor (exaggerated, as in the reference)
ISO_SLAB = 4.0             # units of slab at the foot of each floor
ISO_MULLION = 5.0          # m between glazing mullions
COS30, SIN30 = math.cos(math.radians(30)), 0.5


# ---------------------------------------------------------------- geometry

def fmt(v):
    return f"{v:.1f}".rstrip("0").rstrip(".")


def signed_area(pts):
    return sum(x1 * y2 - x2 * y1 for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1])) / 2


def ccw(pts):
    """Clockwise on screen (y down) — one fixed winding for every outline."""
    return pts if signed_area(pts) > 0 else pts[::-1]


def outward(a, b, pts):
    """Unit normal of edge a→b that points out of the polygon."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    n = math.hypot(dx, dy)
    nx, ny = -dy / n, dx / n
    mx, my = (a[0] + b[0]) / 2 + nx * 0.05, (a[1] + b[1]) / 2 + ny * 0.05
    return (-nx, -ny) if inside((mx, my), pts) else (nx, ny)


def inside(p, pts):
    x, y = p
    hit = False
    for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            hit = not hit
    return hit


def offset(pts, d):
    """Mitred offset; positive grows the outline. Fine for the small d used here."""
    lines = []
    for a, b in zip(pts, pts[1:] + pts[:1]):
        nx, ny = outward(a, b, pts)
        lines.append(((a[0] + nx * d, a[1] + ny * d), (b[0] + nx * d, b[1] + ny * d)))
    out = []
    for (p1, p2), (p3, p4) in zip(lines[-1:] + lines[:-1], lines):
        den = (p1[0] - p2[0]) * (p3[1] - p4[1]) - (p1[1] - p2[1]) * (p3[0] - p4[0])
        if abs(den) < 1e-9:
            out.append(p3)
            continue
        t = ((p1[0] - p3[0]) * (p3[1] - p4[1]) - (p1[1] - p3[1]) * (p3[0] - p4[0])) / den
        out.append((p1[0] + t * (p2[0] - p1[0]), p1[1] + t * (p2[1] - p1[1])))
    return out


def rounded(pts, r, dx=0.0, dy=0.0):
    """Closed path with every corner filleted by up to r."""
    n = len(pts)
    cut = []
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        l1 = math.dist(p0, p1)
        l2 = math.dist(p1, p2)
        d1, d2 = min(r, l1 / 2), min(r, l2 / 2)
        a = (p1[0] + (p0[0] - p1[0]) * d1 / l1, p1[1] + (p0[1] - p1[1]) * d1 / l1)
        b = (p1[0] + (p2[0] - p1[0]) * d2 / l2, p1[1] + (p2[1] - p1[1]) * d2 / l2)
        cut.append((a, p1, b))
    s = lambda p: f"{fmt(p[0] + dx)} {fmt(p[1] + dy)}"
    d = f"M{s(cut[0][2])}"
    for a, c, b in cut[1:] + cut[:1]:
        d += f"L{s(a)}Q{s(c)} {s(b)}"
    return d + "Z"


def poly(pts, dx=0.0, dy=0.0):
    return "M" + "L".join(f"{fmt(x + dx)} {fmt(y + dy)}" for x, y in pts) + "Z"


def centroid(pts):
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


# ---------------------------------------------------------------- top-down

def map_defs():
    return f"""<defs>
<linearGradient id="mp-roof" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{ROOF_TOP}"/><stop offset="1" stop-color="{ROOF_BOTTOM}"/></linearGradient>
<linearGradient id="mp-wall" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{WALL_TOP}"/><stop offset="1" stop-color="{WALL_BOTTOM}"/></linearGradient>
</defs>"""


def map_building(b):
    pts = ccw([tuple(p) for p in b["pianta"]])
    wall = WALL_PER_FLOOR * b.get("piani", 2)
    out = [f'<g id="{b["csie"]}">',
           f'<path d="{rounded(pts, CORNER, wall * 0.86, wall * 1.57)}" fill="{SHADOW}" opacity="0.10"/>',
           f'<path d="{rounded(pts, CORNER, 0, wall)}" fill="url(#mp-wall)"/>',
           f'<path d="{rounded(pts, CORNER)}" fill="url(#mp-roof)"/>']
    for x, y, w, h in b.get("impianti", []):
        out.append(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" rx="0.8" fill="{PLANT}"/>'
                   f'<rect x="{fmt(x)}" y="{fmt(y + h - 0.6)}" width="{fmt(w)}" height="1" fill="{PLANT_LIP}"/>')
    out.append("</g>")
    return out


def map_badge(b, focus):
    x, y = b["badge"]
    label = b["numero"]
    w = 7.0 + 2.4 * max(0, len(label) - 1)
    fill = BADGE_FOCUS if focus else BADGE
    return (f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="6" rx="3" fill="{fill}"/>'
            f'<text x="{fmt(x + w / 2)}" y="{fmt(y + 4.4)}" fill="#FFFFFF">{label}</text>')


def map_tree(x, y, r):
    return (f'<circle cx="{fmt(x)}" cy="{fmt(y)}" r="{fmt(r)}" fill="{TREE}"/>'
            f'<circle cx="{fmt(x + r * 0.3)}" cy="{fmt(y + r * 0.3)}" r="{fmt(r)}" fill="{TREE_SHADE}" opacity="0.5"/>'
            f'<circle cx="{fmt(x)}" cy="{fmt(y)}" r="{fmt(r * 0.69)}" fill="{TREE_LIGHT}"/>')


def draw_map(campus, focus):
    x0, y0, x1, y1 = focus["riquadro"]
    ctx = campus["contesto"]
    line = lambda pts: "M" + "L".join(f"{fmt(x)} {fmt(y)}" for x, y in pts)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0} {y0} {x1 - x0} {y1 - y0}" '
           f'width="{(x1 - x0) * 4}" height="{(y1 - y0) * 4}">', map_defs(),
           f'<clipPath id="mp-tile"><rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}"/></clipPath>',
           '<g clip-path="url(#mp-tile)">',
           '<g id="terreno">', f'<rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}" fill="{GROUND}"/>']
    out += [f'<path d="{rounded([tuple(p) for p in v], 2)}" fill="{GREEN}"/>' for v in ctx["verde"]]
    out += ["</g>", '<g id="strade" fill="none" stroke-linecap="round" stroke-linejoin="round">']
    for s in ctx["strade"]:
        w = s["larghezza"]
        out.append(f'<path d="{line(s["punti"])}" stroke="{ROAD_EDGE}" stroke-width="{fmt(w + 1.2)}"/>'
                   f'<path d="{line(s["punti"])}" stroke="{ROAD}" stroke-width="{fmt(w)}"/>'
                   f'<path d="{line(s["punti"])}" stroke="{ROAD_DASH}" stroke-width="0.3" stroke-dasharray="2.4 2.4"/>')
    for p in ctx["percorsi"]:
        out.append(f'<path d="{line(p)}" stroke="{ROAD_EDGE}" stroke-width="3.4"/>')
    for p in ctx["percorsi"]:
        out.append(f'<path d="{line(p)}" stroke="{ROAD}" stroke-width="2.6"/>')
    out += ["</g>", '<g id="alberi">'] + [map_tree(*t) for t in ctx["alberi"]] + ["</g>"]
    out.append('<g id="edifici">')
    for b in campus["edifici"]:
        out += map_building(b)
    out.append("</g>")
    out.append('<g id="numeri" font-size="4" font-weight="700" text-anchor="middle" '
               'font-family="-apple-system, system-ui, sans-serif">')
    out += [map_badge(b, b is focus) for b in campus["edifici"]]
    out += ["</g>", "</g>", "</svg>"]
    return "\n".join(out)


# ---------------------------------------------------------------- isometric

def iso(x, y, z=0.0):
    return ((x - y) * COS30 * ISO_SCALE, (x + y) * SIN30 * ISO_SCALE - z)


def iso_poly(pts3):
    return " ".join(f"{fmt(px)},{fmt(py)}" for px, py in (iso(*p) for p in pts3))


def faces(pts, z0, z1):
    """Side faces seen by the viewer (south-east), far ones first."""
    seen = []
    for a, b in zip(pts, pts[1:] + pts[:1]):
        nx, ny = outward(a, b, pts)
        if nx + ny <= 0.02:
            continue
        left = ny > nx
        seen.append(((a[0] + b[0] + a[1] + b[1]) / 2, a, b, left))
    seen.sort(key=lambda f: f[0])
    return [(a, b, left, [(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)])
            for _, a, b, left in seen]


def prism(pts, z0, z1, side_colors, top_color):
    left, right = side_colors
    out = [f'<polygon points="{iso_poly(q)}" fill="{left if is_left else right}"/>'
           for _, _, is_left, q in faces(pts, z0, z1)]
    out.append(f'<polygon points="{iso_poly([(x, y, z1) for x, y in pts])}" fill="{top_color}"/>')
    return out


def box(x, y, w, h, z0, height, colors):
    pts = ccw([(x, y), (x + w, y), (x + w, y + h), (x, y + h)])
    return prism(pts, z0, z0 + height, colors[:2], colors[2])


def iso_defs():
    grad = lambda gid, c: (f'<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
                           f'<stop offset="0" stop-color="{c[0]}"/><stop offset="1" stop-color="{c[1]}"/></linearGradient>')
    return ("<defs>" + grad("iso-glass-l", ISO_GLASS_LEFT) + grad("iso-glass-r", ISO_GLASS_RIGHT)
            + grad("iso-focus-l", ISO_FOCUS_LEFT) + grad("iso-focus-r", ISO_FOCUS_RIGHT)
            + f'<radialGradient id="iso-shadow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{ISO_SHADOW}" stop-opacity="0.22"/>'
              f'<stop offset="1" stop-color="{ISO_SHADOW}" stop-opacity="0"/></radialGradient>'
            + '<radialGradient id="iso-tree" cx="0.35" cy="0.3" r="0.75"><stop offset="0" stop-color="#9FD08A"/>'
              '<stop offset="1" stop-color="#4F9A5E"/></radialGradient>'
            + "</defs>")


def iso_tree(x, y, r):
    px, py = iso(x, y)
    s = ISO_SCALE * r * 1.3
    return (f'<ellipse cx="{fmt(px)}" cy="{fmt(py)}" rx="{fmt(s * 1.1)}" ry="{fmt(s * 0.5)}" fill="{ISO_SHADOW}" opacity="0.16"/>'
            f'<rect x="{fmt(px - 1.5)}" y="{fmt(py - 20)}" width="3" height="20" rx="1.5" fill="{TRUNK}"/>'
            f'<circle cx="{fmt(px)}" cy="{fmt(py - 16 - s * 0.6)}" r="{fmt(s)}" fill="url(#iso-tree)"/>')


def draw_iso(campus, b, focus_floor=None):
    pts = ccw([tuple(p) for p in b["pianta"]])
    floors = b.get("piani", 2)
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    lot = ccw([(min(xs) - 7, min(ys) - 7), (max(xs) + 7, min(ys) - 7),
               (max(xs) + 7, max(ys) + 7), (min(xs) - 7, max(ys) + 7)])
    base = offset(pts, 2.0)
    base_h = 6.0
    top = base_h + floors * ISO_FLOOR

    # Trees sit on the lot; the ones in front of the building are drawn after it.
    lx0, ly0, lx1, ly1 = lot[0][0], lot[0][1], lot[2][0], lot[2][1]
    trees = [t for t in campus["contesto"]["alberi"]
             if lx0 + 3 < t[0] < lx1 - 3 and ly0 + 3 < t[1] < ly1 - 3 and not inside(t[:2], offset(pts, 3))]
    cx, cy = centroid(pts)
    behind = [t for t in trees if t[0] + t[1] < cx + cy]
    front = [t for t in trees if t[0] + t[1] >= cx + cy]

    out = [iso_defs()]
    sx, sy = iso(cx, cy)
    span = (max(xs) - min(xs) + max(ys) - min(ys)) * COS30 * ISO_SCALE / 2
    out.append(f'<g id="ombra"><ellipse cx="{fmt(sx)}" cy="{fmt(sy)}" rx="{fmt(span * 1.15)}" ry="{fmt(span * 0.66)}" fill="url(#iso-shadow)"/></g>')
    out.append('<g id="lotto">')
    out += prism(lot, -5, 0, ISO_LOT[:2], ISO_LOT[2])
    ent = b.get("ingresso")
    if ent:
        raw = [tuple(p) for p in b["pianta"]]   # "lato" counts edges in the file's own order
        a, c = raw[ent["lato"]], raw[(ent["lato"] + 1) % len(raw)]
        ex, ey = a[0] + (c[0] - a[0]) * ent["t"], a[1] + (c[1] - a[1]) * ent["t"]
        nx, ny = outward(a, c, pts)
        # Walk from the door straight out to the edge of the lot.
        far = max(0.0, min((lx1 - ex) / nx if nx > 0 else (lx0 - ex) / nx if nx < 0 else 1e9,
                           (ly1 - ey) / ny if ny > 0 else (ly0 - ey) / ny if ny < 0 else 1e9))
        tx, ty = -ny, nx
        walk = [(ex + tx * 1.6, ey + ty * 1.6), (ex - tx * 1.6, ey - ty * 1.6),
                (ex - tx * 1.6 + nx * far, ey - ty * 1.6 + ny * far), (ex + tx * 1.6 + nx * far, ey + ty * 1.6 + ny * far)]
        out.append(f'<polygon points="{iso_poly([(x, y, 0) for x, y in walk])}" fill="{ISO_PATH}"/>')
    out.append("</g>")
    out.append('<g id="alberi-dietro">')
    out += [iso_tree(*t) for t in behind]
    out.append("</g>")
    out.append('<g id="basamento">')
    out += prism(base, 0, base_h, ISO_BASE[:2], ISO_BASE[2])
    out.append("</g>")

    glass = offset(pts, -0.4)
    for f in range(floors):
        z0 = base_h + f * ISO_FLOOR
        lit = f == focus_floor
        gl, gr = ("url(#iso-focus-l)", "url(#iso-focus-r)") if lit else ("url(#iso-glass-l)", "url(#iso-glass-r)")
        out.append(f'<g id="piano-{f}">')
        out += prism(pts, z0, z0 + ISO_SLAB, (ISO_SLAB_LEFT, ISO_SLAB_RIGHT), ISO_SLAB_TOP)
        mullions = []
        for a, c, is_left, q in faces(glass, z0 + ISO_SLAB, z0 + ISO_FLOOR):
            out.append(f'<polygon points="{iso_poly(q)}" fill="{gl if is_left else gr}"/>')
            n = max(1, round(math.dist(a, c) / ISO_MULLION))
            for i in range(1, n):
                t = i / n
                x, y = a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t
                (px, py0), (_, py1) = iso(x, y, z0 + ISO_SLAB), iso(x, y, z0 + ISO_FLOOR)
                mullions.append(f"M{fmt(px)} {fmt(py0)}V{fmt(py1)}")
        stroke = "#CFE2F5" if lit else "#FFFFFF"
        out.append(f'<path d="{"".join(mullions)}" stroke="{stroke}" stroke-width="1.2" opacity="0.75"/>')
        if f == 0 and ent:
            door = [(ex + tx * 1.5, ey + ty * 1.5), (ex - tx * 1.5, ey - ty * 1.5)]
            dz0, dz1 = z0 + ISO_SLAB, z0 + ISO_FLOOR * 0.78
            q = [(*door[0], dz0), (*door[1], dz0), (*door[1], dz1), (*door[0], dz1)]
            out.append(f'<polygon points="{iso_poly(q)}" fill="{ISO_DOOR}"/>')
            canopy = ccw([(ex + tx * 3, ey + ty * 3), (ex - tx * 3, ey - ty * 3),
                          (ex - tx * 3 + nx * 3, ey - ty * 3 + ny * 3), (ex + tx * 3 + nx * 3, ey + ty * 3 + ny * 3)])
            out += prism(canopy, dz1, dz1 + 3, ("#E8EAEE", "#C9CED6"), "#FFFFFF")
        out.append("</g>")

    out.append('<g id="tetto">')
    out += prism(pts, top, top + ISO_SLAB, (ISO_SLAB_LEFT, ISO_SLAB_RIGHT), ISO_SLAB_TOP)
    out.append(f'<polygon points="{iso_poly([(x, y, top + ISO_SLAB) for x, y in offset(pts, -1.6)])}" fill="{ISO_ROOF_INNER}"/>')
    for x, y, w, h in sorted(b.get("impianti", []), key=lambda u: u[0] + u[1]):
        out += box(x, y, w, h, top + ISO_SLAB, 7, ISO_PLANT)
    out.append("</g>")
    out.append('<g id="alberi">')
    out += [iso_tree(*t) for t in front]
    out.append("</g>")

    corners = [iso(x, y, z) for x, y in lot for z in (-5, 0)] + [iso(x, y, top + 12) for x, y in pts]
    vx0, vy0 = min(p[0] for p in corners) - 6, min(p[1] for p in corners) - 30
    vx1, vy1 = max(p[0] for p in corners) + 6, max(p[1] for p in corners) + 6
    head = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{fmt(vx0)} {fmt(vy0)} {fmt(vx1 - vx0)} {fmt(vy1 - vy0)}" '
            f'width="{fmt((vx1 - vx0) * 2)}" height="{fmt((vy1 - vy0) * 2)}">')
    return "\n".join([head] + out + ["</svg>"])


# ---------------------------------------------------------------- main

def main():
    for src in sorted(HERE.glob("*.json")):
        campus = json.loads(src.read_text())
        dest = HERE / src.stem
        dest.mkdir(exist_ok=True)
        for b in campus["edifici"]:
            if "riquadro" not in b:      # outline only, drawn as a neighbour so far
                continue
            (dest / f"{b['csie']}-mappa.svg").write_text(draw_map(campus, b) + "\n")
            (dest / f"{b['csie']}-isometrico.svg").write_text(draw_iso(campus, b) + "\n")
            print(f"{src.stem}/{b['csie']}  {b.get('nome', b['numero'])}")


if __name__ == "__main__":
    main()
