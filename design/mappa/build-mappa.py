#!/usr/bin/env python3
"""Draws the campus buildings as illustrations in the Mappa / Edificio style.

Run `python3 build-mappa.py` to regenerate every drawing and `livelli.json`.

Each building is described by hand in `<campus>.json`: a simplified outline
in metres (a few chosen corners, not a survey), its floors, rooftop plant,
and entrance; the campus around it — paths, green, trees, bike racks, lamps —
lives in the same file. This file turns those descriptions into drawings that
share one look, so building fifty reads as the same hand as building one:

- `<csie>-mappa` — top-down, the building with its surroundings, as in the
  "Mappa delle aule libere" illustration;
- `<csie>-isometrico` — the building alone in isometric, one layer per floor
  so a single floor can be highlighted, as in the "Edificio con l'aula"
  illustration;
- `<csip>-pianta` — one floor plan per floor described in
  `piante/<csie>.json`, drawn inside the same outline.

Every drawing is a stack of layers (`LIVELLI`) the app can switch on and off.
Each is written three ways: `<name>.svg` with one `livello-*` group per
layer, `<name>/NN-<layer>.svg` with one file per layer on the same frame (for
stacking images), and an entry in `livelli.json` that lists them in order.

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
ALERT = "#C40F22"
LAMP, LAMP_GLOW = "#E8B931", "#F5D77A"
STEPS, STEPS_LINE = "#E6E8EC", "#C9CED6"
INK = "#3A3A3C"
STREET_INK = "#5E7A55"
MARKER_EDGE = "#E3E5EA"

ISO_SLAB_LEFT, ISO_SLAB_RIGHT, ISO_SLAB_TOP = "#F2F3F6", "#D4D8DF", "#FFFFFF"
ISO_GLASS_LEFT = ("#B9D2EA", "#8FB1D4")
ISO_GLASS_RIGHT = ("#7F9FC2", "#617FA3")
# A floor with its lights on: warm rooms seen through the glass.
ISO_LIT_LEFT = ("#FFF7DC", "#FFD47E")
ISO_LIT_RIGHT = ("#FBE2A2", "#ECB65A")
LIGHT_SPILL = "#FFD98A"
LIGHT_DESK = "#D9963A"
LIGHT_FRAME = "#9C7434"
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
FONT = 'font-family="-apple-system, system-ui, sans-serif"'

# Every layer any drawing can have: name shown in the app, on by default,
# and whether it is fixed (the drawing makes no sense without it).
LIVELLI = {
    "terreno": ("Terreno", True, True),
    "verde": ("Verde", True, False),
    "strade": ("Strade", True, False),
    "percorsi": ("Percorsi pedonali", True, False),
    "scale-esterne": ("Scale esterne", True, False),
    "alberi": ("Alberi", True, False),
    "ombre": ("Ombre", True, False),
    "edifici": ("Edifici", True, True),
    "impianti": ("Impianti sul tetto", True, False),
    "piani": ("Piani", True, True),
    "locali": ("Locali", True, True),
    "gradoni": ("Gradoni delle aule", True, False),
    "gradini": ("Gradini delle scale", True, False),
    "ascensori": ("Ascensori", True, False),
    "pilastri": ("Pilastri", True, False),
    "porte": ("Porte", True, False),
    "muri": ("Muri esterni", True, True),
    "ingressi": ("Ingressi", True, False),
    "accessibilita": ("Accessibilità", True, False),
    "bici": ("Rastrelliere per bici", True, False),
    "lampioni": ("Lampioni", False, False),
    "dae": ("Defibrillatori", True, False),
    "acqua": ("Fontanelle", True, False),
    "nomi": ("Nomi", True, False),
    "numeri": ("Numeri degli edifici", True, False),
    "etichette": ("Nomi delle aule", True, False),
    "etichette-piani": ("Nomi dei piani", False, False),
}

FLOOR_TAGS = {"Primo Interrato": "-1", "Seminterrato": "S", "Terra": "T", "Primo": "1",
              "Secondo": "2", "Terzo": "3", "Quarto": "4", "Quinto": "5"}


def grad(gid, top, bottom):
    return (f'<linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>')


DEFS = {
    "mp-roof": grad("mp-roof", ROOF_TOP, ROOF_BOTTOM),
    "mp-wall": grad("mp-wall", WALL_TOP, WALL_BOTTOM),
    "mp-glow": (f'<radialGradient id="mp-glow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{LAMP_GLOW}" stop-opacity="0.55"/>'
                f'<stop offset="1" stop-color="{LAMP_GLOW}" stop-opacity="0"/></radialGradient>'),
    "iso-glass-l": grad("iso-glass-l", *ISO_GLASS_LEFT),
    "iso-glass-r": grad("iso-glass-r", *ISO_GLASS_RIGHT),
    "iso-lit-l": grad("iso-lit-l", *ISO_LIT_LEFT),
    "iso-lit-r": grad("iso-lit-r", *ISO_LIT_RIGHT),
    "iso-shadow": (f'<radialGradient id="iso-shadow" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{ISO_SHADOW}" stop-opacity="0.22"/>'
                   f'<stop offset="1" stop-color="{ISO_SHADOW}" stop-opacity="0"/></radialGradient>'),
    "iso-tree": ('<radialGradient id="iso-tree" cx="0.35" cy="0.3" r="0.75"><stop offset="0" stop-color="#9FD08A"/>'
                 '<stop offset="1" stop-color="#4F9A5E"/></radialGradient>'),
}


class Strato:
    """One layer of one drawing: its markup, the defs it needs, and its layer id.

    `lit` is the same layer with the floor's lights on, for the isometric floors.
    """

    def __init__(self, nome, livello, parti, defs=(), piano=None, lit=None, lit_defs=()):
        self.nome, self.livello, self.parti, self.defs = nome, livello, parti, list(defs)
        self.piano, self.lit, self.lit_defs = piano, lit, list(lit_defs)


# ---------------------------------------------------------------- geometry

def fmt(v):
    s = f"{v:.1f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


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


def line(pts):
    return "M" + "L".join(f"{fmt(x)} {fmt(y)}" for x, y in pts)


def floor_count(b):
    return len(b["livelli"]) if b.get("livelli") else b.get("piani", 2)


def centroid(pts):
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def area_centroid(pts):
    a = cx = cy = 0.0
    for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
        k = x1 * y2 - x2 * y1
        a += k
        cx += (x1 + x2) * k
        cy += (y1 + y2) * k
    return (cx / (3 * a), cy / (3 * a)) if abs(a) > 1e-9 else centroid(pts)


def nearest_edge(p, polys):
    best = None
    for pts in polys:
        for a, b in zip(pts, pts[1:] + pts[:1]):
            dx, dy = b[0] - a[0], b[1] - a[1]
            t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy)))
            q = (a[0] + dx * t, a[1] + dy * t)
            d = math.dist(p, q)
            if best is None or d < best[0]:
                best = (d, q, a, b, pts)
    return best[1:]


# ---------------------------------------------------------------- symbols

def marker(x, y, glyph, fill="#FFFFFF", r=1.9):
    """A round map marker: a disc with a small glyph drawn in a ±1 m box."""
    edge = f' stroke="{MARKER_EDGE}" stroke-width="0.25"' if fill == "#FFFFFF" else ' stroke="#FFFFFF" stroke-width="0.3"'
    return f'<circle cx="{fmt(x)}" cy="{fmt(y)}" r="{fmt(r)}" fill="{fill}"{edge}/>' + glyph(x, y)


def glyph_bike(x, y):
    p = lambda dx, dy: f"{fmt(x + dx)} {fmt(y + dy)}"
    return (f'<circle cx="{fmt(x - 0.62)}" cy="{fmt(y + 0.3)}" r="0.5" fill="none" stroke="{BADGE_FOCUS}" stroke-width="0.2"/>'
            f'<circle cx="{fmt(x + 0.62)}" cy="{fmt(y + 0.3)}" r="0.5" fill="none" stroke="{BADGE_FOCUS}" stroke-width="0.2"/>'
            f'<path d="M{p(-0.62, 0.3)}L{p(-0.2, -0.35)}L{p(0.4, -0.35)}L{p(0.62, 0.3)}M{p(-0.2, -0.35)}L{p(0, 0.3)}L{p(0.4, -0.35)}'
            f'M{p(-0.42, -0.6)}L{p(-0.05, -0.6)}" fill="none" stroke="{BADGE_FOCUS}" stroke-width="0.2" '
            f'stroke-linecap="round" stroke-linejoin="round"/>')


def glyph_heart(x, y):
    p = lambda dx, dy: f"{fmt(x + dx)} {fmt(y + dy)}"
    return (f'<path d="M{p(0, 0.75)}C{p(-1, -0.05)} {p(-0.9, -0.85)} {p(-0.42, -0.85)}C{p(-0.18, -0.85)} {p(0, -0.68)} {p(0, -0.52)}'
            f'C{p(0, -0.68)} {p(0.18, -0.85)} {p(0.42, -0.85)}C{p(0.9, -0.85)} {p(1, -0.05)} {p(0, 0.75)}Z" fill="#FFFFFF"/>'
            f'<path d="M{p(0.12, -0.55)}L{p(-0.22, 0.02)}L{p(0.02, 0.02)}L{p(-0.12, 0.45)}L{p(0.24, -0.14)}L{p(0, -0.14)}Z" fill="{ALERT}"/>')


def glyph_drop(x, y):
    p = lambda dx, dy: f"{fmt(x + dx)} {fmt(y + dy)}"
    return (f'<path d="M{p(0, -0.9)}C{p(0.4, -0.35)} {p(0.62, -0.02)} {p(0.62, 0.28)}C{p(0.62, 0.66)} {p(0.33, 0.9)} {p(0, 0.9)}'
            f'C{p(-0.33, 0.9)} {p(-0.62, 0.66)} {p(-0.62, 0.28)}C{p(-0.62, -0.02)} {p(-0.4, -0.35)} {p(0, -0.9)}Z" fill="{BADGE_FOCUS}"/>')


def glyph_wheelchair(x, y, s=0.8):
    p = lambda dx, dy: f"{fmt(x + dx * s)} {fmt(y + dy * s)}"
    w = fmt(0.17 * s * 1.25)
    return (f'<circle cx="{fmt(x + 0.05 * s)}" cy="{fmt(y - 0.68 * s)}" r="{fmt(0.2 * s)}" fill="#FFFFFF"/>'
            f'<path d="M{p(-0.08, -0.38)}L{p(-0.08, 0.1)}L{p(0.4, 0.1)}L{p(0.6, 0.6)}M{p(-0.08, -0.14)}L{p(0.3, -0.14)}" '
            f'fill="none" stroke="#FFFFFF" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>'
            f'<path d="M{p(-0.3, -0.05)}A{fmt(0.48 * s)} {fmt(0.48 * s)} 0 1 0 {p(0.32, 0.62)}" fill="none" stroke="#FFFFFF" '
            f'stroke-width="{w}" stroke-linecap="round"/>')


def access_badge(x, y, size=2.2):
    h = size / 2
    return (f'<rect x="{fmt(x - h)}" y="{fmt(y - h)}" width="{fmt(size)}" height="{fmt(size)}" rx="{fmt(size * 0.22)}" '
            f'fill="{BADGE_FOCUS}"/>' + glyph_wheelchair(x, y + 0.08, size * 0.38))


def entrance_arrow(q, n, main=False):
    """A triangle outside the wall, pointing in through the door."""
    nx, ny = n
    tx, ty = -ny, nx
    length, half = (3.2, 1.7) if main else (2.5, 1.25)
    tip = (q[0] + nx * 0.35, q[1] + ny * 0.35)
    base = (q[0] + nx * length, q[1] + ny * length)
    tri = [tip, (base[0] + tx * half, base[1] + ty * half), (base[0] - tx * half, base[1] - ty * half)]
    edge = ' stroke="#FFFFFF" stroke-width="0.45"' if main else f' stroke="{BADGE_FOCUS}" stroke-width="0.3"'
    return f'<path d="{poly(tri)}" fill="{BADGE_FOCUS}"{edge} stroke-linejoin="round"/>'


# ---------------------------------------------------------------- writing

def svg_head(view, width, height):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}" '
            f'width="{fmt(width)}" height="{fmt(height)}">')


def defs_block(keys):
    keys = sorted(set(keys))
    return [f"<defs>{''.join(DEFS[k] for k in keys)}</defs>"] if keys else []


def write_drawing(dest, name, view, width, height, strati):
    """`name.svg` with every layer, `name/NN-layer.svg` one per layer, and the manifest entry."""
    folder = dest / name
    folder.mkdir(exist_ok=True)
    for old in folder.glob("*.svg"):
        old.unlink()
    head = svg_head(view, width, height)
    combined = [head] + defs_block(d for s in strati for d in s.defs + s.lit_defs)
    entries = []
    for i, s in enumerate(strati, 1):
        hidden = "" if LIVELLI[s.livello][1] else ' style="display: none"'
        extra = f' data-piano="{s.piano}"' if s.piano else ""
        combined += [f'<g id="livello-{s.nome}" data-livello="{s.livello}"{extra}{hidden}>'] + s.parti + ["</g>"]
        if s.lit is not None:
            # The lit floor sits right beside the plain one, hidden: show one, hide the other.
            combined += [f'<g id="livello-{s.nome}-acceso" data-livello="{s.livello}"{extra} data-acceso="true" '
                         f'style="display: none">'] + s.lit + ["</g>"]
        file = f"{i:02d}-{s.nome}.svg"
        (folder / file).write_text("\n".join([head] + defs_block(s.defs) + s.parti + ["</svg>"]) + "\n")
        entry = {"file": f"{dest.name}/{name}/{file}", "livello": s.livello}
        if s.piano:
            entry["piano"] = s.piano
        if s.lit is not None:
            lit = f"{i:02d}-{s.nome}-acceso.svg"
            (folder / lit).write_text("\n".join([head] + defs_block(s.lit_defs) + s.lit + ["</svg>"]) + "\n")
            entry["acceso"] = f"{dest.name}/{name}/{lit}"
        entries.append(entry)
    (dest / f"{name}.svg").write_text("\n".join(combined + ["</svg>"]) + "\n")
    return {"file": f"{dest.name}/{name}.svg", "viewBox": view, "strati": entries}


# ---------------------------------------------------------------- top-down

def map_tree(x, y, r):
    return (f'<circle cx="{fmt(x)}" cy="{fmt(y)}" r="{fmt(r)}" fill="{TREE}"/>'
            f'<circle cx="{fmt(x + r * 0.3)}" cy="{fmt(y + r * 0.3)}" r="{fmt(r)}" fill="{TREE_SHADE}" opacity="0.5"/>'
            f'<circle cx="{fmt(x)}" cy="{fmt(y)}" r="{fmt(r * 0.69)}" fill="{TREE_LIGHT}"/>')


def outdoor_steps(pts, width=2.4, step=0.6):
    """A band of treads along the line, the way steps read from above."""
    out = []
    for a, b in zip(pts, pts[1:]):
        n = math.dist(a, b)
        ux, uy = (b[0] - a[0]) / n, (b[1] - a[1]) / n
        tx, ty = -uy * width / 2, ux * width / 2
        band = [(a[0] + tx, a[1] + ty), (b[0] + tx, b[1] + ty), (b[0] - tx, b[1] - ty), (a[0] - tx, a[1] - ty)]
        out.append(f'<path d="{poly(band)}" fill="{STEPS}" stroke="{STEPS_LINE}" stroke-width="0.15"/>')
        treads, d = [], step
        while d < n - 0.1:
            cx, cy = a[0] + ux * d, a[1] + uy * d
            treads.append(f"M{fmt(cx + tx)} {fmt(cy + ty)}L{fmt(cx - tx)} {fmt(cy - ty)}")
            d += step
        out.append(f'<path d="{"".join(treads)}" stroke="{STEPS_LINE}" stroke-width="0.15"/>')
    return out


def draw_map(campus, focus):
    x0, y0, x1, y1 = focus["riquadro"]
    ctx = campus["contesto"]
    buildings = [(b, ccw([tuple(p) for p in b["pianta"]])) for b in campus["edifici"]]
    shells = [pts for _, pts in buildings]
    strati = []

    strati.append(Strato("terreno", "terreno",
                         [f'<rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}" fill="{GROUND}"/>']))
    strati.append(Strato("verde", "verde",
                         [f'<path d="{rounded([tuple(p) for p in v], 2)}" fill="{GREEN}"/>' for v in ctx["verde"]]))

    roads = []
    for s in ctx["strade"]:
        w, d = s["larghezza"], line(s["punti"])
        roads.append(f'<path d="{d}" fill="none" stroke="{ROAD_EDGE}" stroke-width="{fmt(w + 1.2)}"/>'
                     f'<path d="{d}" fill="none" stroke="{ROAD}" stroke-width="{fmt(w)}"/>'
                     f'<path d="{d}" fill="none" stroke="{ROAD_DASH}" stroke-width="0.3" stroke-dasharray="2.4 2.4"/>')
    strati.append(Strato("strade", "strade", roads))

    # All borders first, then all fills, so every junction joins cleanly.
    walk = ['<g fill="none" stroke-linecap="round" stroke-linejoin="round">']
    walk += [f'<path d="{line(p)}" stroke="{ROAD_EDGE}" stroke-width="3.4"/>' for p in ctx["percorsi"]]
    walk += [f'<path d="{line(p)}" stroke="{ROAD}" stroke-width="2.6"/>' for p in ctx["percorsi"]]
    strati.append(Strato("percorsi", "percorsi", walk + ["</g>"]))

    steps = []
    for p in ctx.get("scale", []):
        steps += outdoor_steps([tuple(q) for q in p])
    strati.append(Strato("scale-esterne", "scale-esterne", steps))

    strati.append(Strato("alberi", "alberi", [map_tree(*t) for t in ctx["alberi"]]))

    shade, body, plant = [], [], []
    for b, pts in buildings:
        wall = WALL_PER_FLOOR * floor_count(b)
        shade.append(f'<path d="{rounded(pts, CORNER, wall * 0.86, wall * 1.57)}" fill="{SHADOW}" opacity="0.10"/>')
        body.append(f'<g id="{b["csie"]}"><path d="{rounded(pts, CORNER, 0, wall)}" fill="url(#mp-wall)"/>'
                    f'<path d="{rounded(pts, CORNER)}" fill="url(#mp-roof)"/></g>')
        for x, y, w, h in b.get("impianti", []):
            plant.append(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" rx="0.8" fill="{PLANT}"/>'
                         f'<rect x="{fmt(x)}" y="{fmt(y + h - 0.6)}" width="{fmt(w)}" height="1" fill="{PLANT_LIP}"/>')
    strati.append(Strato("ombre", "ombre", shade))
    strati.append(Strato("edifici", "edifici", body, ["mp-roof", "mp-wall"]))
    strati.append(Strato("impianti", "impianti", plant))

    doors = []
    for e in ctx.get("ingressi", []):
        q, a, c, pts = nearest_edge(tuple(e["punto"]), shells)
        doors.append(entrance_arrow(q, outward(a, c, pts), e.get("principale", False)))
    strati.append(Strato("ingressi", "ingressi", doors))

    strati.append(Strato("bici", "bici", [marker(x, y, glyph_bike) for x, y, _ in ctx.get("bici", [])]))
    strati.append(Strato("lampioni", "lampioni",
                         [f'<circle cx="{fmt(x)}" cy="{fmt(y)}" r="4.5" fill="url(#mp-glow)"/>'
                          f'<circle cx="{fmt(x)}" cy="{fmt(y)}" r="0.6" fill="{LAMP}" stroke="#FFFFFF" stroke-width="0.25"/>'
                          for x, y in ctx.get("lampioni", [])], ["mp-glow"]))
    strati.append(Strato("dae", "dae", [marker(x, y, glyph_heart, ALERT) for x, y in ctx.get("dae", [])]))
    strati.append(Strato("acqua", "acqua", [marker(x, y, glyph_drop) for x, y in ctx.get("acqua", [])]))

    names = []
    for b in campus["edifici"]:
        if b.get("nome") and b.get("badge"):
            bx, by = b["badge"]
            # The halo is its own text underneath: `paint-order` is not read by every renderer.
            at = f'x="{fmt(bx + 0.4)}" y="{fmt(by + 10.0)}" font-size="3.4" font-weight="600" {FONT}'
            names.append(f'<text {at} fill="none" stroke="#FFFFFF" stroke-width="1" stroke-linejoin="round">{b["nome"]}</text>'
                         f'<text {at} fill="{INK}">{b["nome"]}</text>')
    for n in ctx.get("nomi", []):
        x, y = n["punto"]
        names.append(f'<text x="{fmt(x)}" y="{fmt(y + 1.1)}" font-size="3.2" font-weight="600" text-anchor="middle" '
                     f'letter-spacing="0.3" fill="{STREET_INK}" {FONT}>{n["testo"]}</text>')
    strati.append(Strato("nomi", "nomi", names))

    badges = [f'<g font-size="4" font-weight="700" text-anchor="middle" {FONT}>']
    for b in campus["edifici"]:
        x, y = b["badge"]
        label = b["numero"]
        w = 7.0 + 2.4 * max(0, len(label) - 1)
        fill = BADGE_FOCUS if b is focus else BADGE
        badges.append(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="6" rx="3" fill="{fill}"/>'
                      f'<text x="{fmt(x + w / 2)}" y="{fmt(y + 4.4)}" fill="#FFFFFF">{label}</text>')
    strati.append(Strato("numeri", "numeri", badges + ["</g>"]))

    return f"{x0} {y0} {x1 - x0} {y1 - y0}", (x1 - x0) * 4, (y1 - y0) * 4, strati


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


def iso_tree(x, y, r):
    px, py = iso(x, y)
    s = ISO_SCALE * r * 1.3
    return (f'<ellipse cx="{fmt(px)}" cy="{fmt(py)}" rx="{fmt(s * 1.1)}" ry="{fmt(s * 0.5)}" fill="{ISO_SHADOW}" opacity="0.16"/>'
            f'<rect x="{fmt(px - 1.5)}" y="{fmt(py - 20)}" width="3" height="20" rx="1.5" fill="{TRUNK}"/>'
            f'<circle cx="{fmt(px)}" cy="{fmt(py - 16 - s * 0.6)}" r="{fmt(s)}" fill="url(#iso-tree)"/>')


def view(b):
    """Turns the plan so the side holding the entrance faces the viewer.

    The isometric view always looks from the south-east. A building whose door
    is on its west side is drawn from the south-west instead: the plan is
    rotated a quarter turn, which keeps it a true view, not a mirror image.
    """
    if b.get("vista") == "sud-ovest":
        return lambda p: (p[1], -p[0])
    return lambda p: (p[0], p[1])


def floor_names(b):
    plans = HERE / "piante" / f"{b['csie']}.json"
    if not plans.exists():
        return {}
    return {f["csip"]: f["nome"] for f in json.loads(plans.read_text())["piani"]}


def draw_iso(campus, b):
    turn = view(b)
    pts = ccw([turn(p) for p in b["pianta"]])
    levels = b.get("livelli") or [f"piano-{i}" for i in range(floor_count(b))]
    floors = len(levels)
    names = floor_names(b)
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    lot = ccw([(min(xs) - 7, min(ys) - 7), (max(xs) + 7, min(ys) - 7),
               (max(xs) + 7, max(ys) + 7), (min(xs) - 7, max(ys) + 7)])
    base = offset(pts, 2.0)
    base_h = 6.0
    top = base_h + floors * ISO_FLOOR

    # Trees sit on the lot; the ones in front of the building are drawn after it.
    lx0, ly0, lx1, ly1 = lot[0][0], lot[0][1], lot[2][0], lot[2][1]
    trees = [(*turn(t[:2]), t[2]) for t in campus["contesto"]["alberi"]]
    # Trees hugging the walls would hide the facade and the door: the map keeps them, this view does not.
    clear = offset(pts, 7)
    trees = [t for t in trees
             if lx0 + 3 < t[0] < lx1 - 3 and ly0 + 3 < t[1] < ly1 - 3 and not inside(t[:2], clear)]
    cx, cy = centroid(pts)
    behind = sorted((t for t in trees if t[0] + t[1] < cx + cy), key=lambda t: t[0] + t[1])
    front = sorted((t for t in trees if t[0] + t[1] >= cx + cy), key=lambda t: t[0] + t[1])

    strati = []
    sx, sy = iso(cx, cy)
    span = (max(xs) - min(xs) + max(ys) - min(ys)) * COS30 * ISO_SCALE / 2
    strati.append(Strato("ombra", "ombre",
                         [f'<ellipse cx="{fmt(sx)}" cy="{fmt(sy)}" rx="{fmt(span * 1.15)}" ry="{fmt(span * 0.66)}" fill="url(#iso-shadow)"/>'],
                         ["iso-shadow"]))
    strati.append(Strato("lotto", "terreno", prism(lot, -5, 0, ISO_LOT[:2], ISO_LOT[2])))

    ent = b.get("ingresso")
    walk, door = [], []
    if ent:
        raw = [turn(p) for p in b["pianta"]]    # "lato" counts edges in the file's own order
        a, c = raw[ent["lato"]], raw[(ent["lato"] + 1) % len(raw)]
        ex, ey = a[0] + (c[0] - a[0]) * ent["t"], a[1] + (c[1] - a[1]) * ent["t"]
        nx, ny = outward(a, c, pts)
        # Walk from the door straight out to the edge of the lot.
        far = max(0.0, min((lx1 - ex) / nx if nx > 0 else (lx0 - ex) / nx if nx < 0 else 1e9,
                           (ly1 - ey) / ny if ny > 0 else (ly0 - ey) / ny if ny < 0 else 1e9))
        tx, ty = -ny, nx
        path = [(ex + tx * 1.6, ey + ty * 1.6), (ex - tx * 1.6, ey - ty * 1.6),
                (ex - tx * 1.6 + nx * far, ey - ty * 1.6 + ny * far), (ex + tx * 1.6 + nx * far, ey + ty * 1.6 + ny * far)]
        walk.append(f'<polygon points="{iso_poly([(x, y, 0) for x, y in path])}" fill="{ISO_PATH}"/>')
        z0 = base_h
        dz0, dz1 = z0 + ISO_SLAB, z0 + ISO_FLOOR * 0.78
        leaf = [(ex + tx * 1.5, ey + ty * 1.5), (ex - tx * 1.5, ey - ty * 1.5)]
        q = [(*leaf[0], dz0), (*leaf[1], dz0), (*leaf[1], dz1), (*leaf[0], dz1)]
        door.append(f'<polygon points="{iso_poly(q)}" fill="{ISO_DOOR}"/>')
        canopy = ccw([(ex + tx * 3, ey + ty * 3), (ex - tx * 3, ey - ty * 3),
                      (ex - tx * 3 + nx * 3, ey - ty * 3 + ny * 3), (ex + tx * 3 + nx * 3, ey + ty * 3 + ny * 3)])
        door += prism(canopy, dz1, dz1 + 3, ("#E8EAEE", "#C9CED6"), "#FFFFFF")
    strati.append(Strato("percorso", "percorsi", walk))
    strati.append(Strato("alberi-dietro", "alberi", [iso_tree(*t) for t in behind], ["iso-tree"]))
    strati.append(Strato("basamento", "edifici", prism(base, 0, base_h, ISO_BASE[:2], ISO_BASE[2])))

    glass = offset(pts, -0.4)

    def storey(z0, lit):
        """One floor. Lit, it is the same floor at dusk with its lights on:
        warm rooms behind the glass, a row of ceiling lights, desks catching
        the light, frames dark against it, and a glow spilling onto the slab."""
        gl, gr = ("url(#iso-lit-l)", "url(#iso-lit-r)") if lit else ("url(#iso-glass-l)", "url(#iso-glass-r)")
        g0, g1 = z0 + ISO_SLAB, z0 + ISO_FLOOR
        out = prism(pts, z0, g0, (ISO_SLAB_LEFT, ISO_SLAB_RIGHT), ISO_SLAB_TOP)
        mullions, lamps, desks = [], [], []
        for a, c, is_left, q in faces(glass, g0, g1):
            if lit:
                spill = [(a[0], a[1], z0), (c[0], c[1], z0), (c[0], c[1], g0), (a[0], a[1], g0)]
                out.append(f'<polygon points="{iso_poly(spill)}" fill="{LIGHT_SPILL}" opacity="0.55"/>')
            out.append(f'<polygon points="{iso_poly(q)}" fill="{gl if is_left else gr}"/>')
            if lit:
                ceiling = [(a[0], a[1], g1 - 3.2), (c[0], c[1], g1 - 3.2), (c[0], c[1], g1), (a[0], a[1], g1)]
                out.append(f'<polygon points="{iso_poly(ceiling)}" fill="#FFFFFF" opacity="0.5"/>')
                (lx0, ly0), (lx1, ly1) = iso(a[0], a[1], g1 - 4.6), iso(c[0], c[1], g1 - 4.6)
                lamps.append(f"M{fmt(lx0)} {fmt(ly0)}L{fmt(lx1)} {fmt(ly1)}")
                (dx0, dy0), (dx1, dy1) = iso(a[0], a[1], g0 + 3.2), iso(c[0], c[1], g0 + 3.2)
                desks.append(f"M{fmt(dx0)} {fmt(dy0)}L{fmt(dx1)} {fmt(dy1)}")
            n = max(1, round(math.dist(a, c) / ISO_MULLION))
            for i in range(1, n):
                t = i / n
                x, y = a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t
                (px, py0), (_, py1) = iso(x, y, g0), iso(x, y, g1)
                mullions.append(f"M{fmt(px)} {fmt(py0)}V{fmt(py1)}")
        if lit:
            out.append(f'<path d="{"".join(desks)}" stroke="{LIGHT_DESK}" stroke-width="1.1" opacity="0.6"/>')
            # Ceiling spotlights: round dots, each in a soft halo on the same rhythm.
            out.append(f'<path d="{"".join(lamps)}" stroke="#FFFFFF" stroke-width="4" stroke-dasharray="0.1 6" '
                       f'stroke-linecap="round" opacity="0.4"/>')
            out.append(f'<path d="{"".join(lamps)}" stroke="#FFFFFF" stroke-width="1.7" stroke-dasharray="0.1 6" '
                       f'stroke-linecap="round"/>')
            out.append(f'<path d="{"".join(mullions)}" stroke="{LIGHT_FRAME}" stroke-width="1.2" opacity="0.55"/>')
        else:
            out.append(f'<path d="{"".join(mullions)}" stroke="#FFFFFF" stroke-width="1.2" opacity="0.75"/>')
        return out

    for f, csip in enumerate(levels):
        z0 = base_h + f * ISO_FLOOR
        strati.append(Strato(csip, "piani", storey(z0, False), ["iso-glass-l", "iso-glass-r"], piano=csip,
                             lit=storey(z0, True), lit_defs=["iso-lit-l", "iso-lit-r"]))
        if f == 0:
            # The door sits on the ground floor; anything higher is drawn over it.
            strati.append(Strato("ingresso", "ingressi", door))

    roof = prism(pts, top, top + ISO_SLAB, (ISO_SLAB_LEFT, ISO_SLAB_RIGHT), ISO_SLAB_TOP)
    roof.append(f'<polygon points="{iso_poly([(x, y, top + ISO_SLAB) for x, y in offset(pts, -1.6)])}" fill="{ISO_ROOF_INNER}"/>')
    strati.append(Strato("tetto", "edifici", roof))
    plant = []
    for x, y, w, h in b.get("impianti", []):
        c = [turn(p) for p in ((x, y), (x + w, y + h))]
        plant.append((min(c[0][0], c[1][0]), min(c[0][1], c[1][1]), abs(c[1][0] - c[0][0]), abs(c[1][1] - c[0][1])))
    units = []
    for x, y, w, h in sorted(plant, key=lambda u: u[0] + u[1]):
        units += box(x, y, w, h, top + ISO_SLAB, 7, ISO_PLANT)
    strati.append(Strato("impianti", "impianti", units))
    strati.append(Strato("alberi-davanti", "alberi", [iso_tree(*t) for t in front], ["iso-tree"]))

    # Floor tags beside the right-most corner, one per storey.
    right = max(pts, key=lambda p: iso(*p)[0])
    tags = []
    for f, csip in enumerate(levels):
        zm = base_h + f * ISO_FLOOR + (ISO_SLAB + ISO_FLOOR) / 2
        px, py = iso(*right, zm)
        label = FLOOR_TAGS.get(names.get(csip, ""), str(f))
        w = 9 + 4 * max(0, len(label) - 1)
        tags.append(f'<path d="M{fmt(px + 2)} {fmt(py)}H{fmt(px + 10)}" stroke="#8E8E93" stroke-width="0.8" stroke-dasharray="1.5 1.5"/>'
                    f'<rect x="{fmt(px + 10)}" y="{fmt(py - 5)}" width="{fmt(w)}" height="10" rx="5" fill="#FFFFFF" stroke="{MARKER_EDGE}" stroke-width="0.8"/>'
                    f'<text x="{fmt(px + 10 + w / 2)}" y="{fmt(py + 2.6)}" font-size="7" font-weight="700" text-anchor="middle" '
                    f'fill="{BADGE_FOCUS}" {FONT}>{label}</text>')
    strati.append(Strato("etichette-piani", "etichette-piani", tags))

    corners = [iso(x, y, z) for x, y in lot for z in (-5, 0)] + [iso(x, y, top + 12) for x, y in pts]
    corners.append((iso(*right)[0] + 34, iso(*right)[1]))
    vx0, vy0 = min(p[0] for p in corners) - 6, min(p[1] for p in corners) - 30
    vx1, vy1 = max(p[0] for p in corners) + 6, max(p[1] for p in corners) + 6
    return f"{fmt(vx0)} {fmt(vy0)} {fmt(vx1 - vx0)} {fmt(vy1 - vy0)}", (vx1 - vx0) * 2, (vy1 - vy0) * 2, strati


# ---------------------------------------------------------------- floor plans

PLAN_FILL = {"aula": "#E3ECF5", "wc": "#EEF0F3", "scale": "#E9EBEF",
             "ascensore": "#E9EBEF", "locale": "#F2F3F6"}
PLAN_WALL = "#C9CED6"          # inner walls, between rooms
PLAN_SHELL = "#AEB4BE"         # the outer wall
PLAN_TIER = "#CBDCEE"          # amphitheatre rows
PLAN_TREAD = "#D3D7DF"         # stair treads
PLAN_MUTED = "#8E8E93"
INNER_WALL = 0.3               # m
SHELL_WALL = 0.6               # m
DOOR = 1.4                     # m of opening
ENTRANCE = 2.2                 # m of opening in the outer wall


def hatch(pts, edge, step, margin):
    """Lines parallel to edge `edge` of the polygon, `step` apart, across all of it."""
    a, b = pts[edge], pts[(edge + 1) % len(pts)]
    length = math.dist(a, b)
    ux, uy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
    vx, vy = outward(a, b, pts)
    vx, vy = -vx, -vy                                   # into the room
    depth = max((p[0] - a[0]) * vx + (p[1] - a[1]) * vy for p in pts)
    reach = max(math.dist(a, p) for p in pts) + 1
    lines, d = [], margin
    while d < depth - margin:
        ox, oy = a[0] + vx * d, a[1] + vy * d
        lines.append(f"M{fmt(ox - ux * reach)} {fmt(oy - uy * reach)}L{fmt(ox + ux * reach)} {fmt(oy + uy * reach)}")
        d += step
    return "".join(lines)


def opening(q, a, b, width):
    n = math.dist(a, b)
    ux, uy = (b[0] - a[0]) / n * width / 2, (b[1] - a[1]) / n * width / 2
    return f"M{fmt(q[0] - ux)} {fmt(q[1] - uy)}L{fmt(q[0] + ux)} {fmt(q[1] + uy)}"


def plan_label(room):
    x, y = room.get("etichetta") or area_centroid([tuple(p) for p in room["forma"]])
    if room["tipo"] == "wc":
        dx = -1.4 if room.get("accessibile") else 0
        return (f'<text x="{fmt(x + dx)}" y="{fmt(y + 0.6)}" font-size="1.7" font-weight="700" '
                f'text-anchor="middle" fill="{PLAN_MUTED}" {FONT}>WC</text>')
    if room["tipo"] != "aula":
        return ""
    sigla, seats = room["sigla"], f'{room["posti"]} posti' if room.get("posti") else ""
    w = max(len(sigla) * 1.3, len(seats) * 0.72) + 1.6
    h = 5.2 if seats else 3.6
    out = (f'<g id="{room["csiv"]}-etichetta">'
           f'<rect x="{fmt(x - w / 2)}" y="{fmt(y - h / 2)}" width="{fmt(w)}" height="{fmt(h)}" rx="{fmt(min(h, 3.6) / 2)}" '
           f'fill="#FFFFFF" stroke="{MARKER_EDGE}" stroke-width="0.2"/>'
           f'<text x="{fmt(x)}" y="{fmt(y - h / 2 + 2.6)}" font-size="2.2" font-weight="700" text-anchor="middle" fill="{BADGE_FOCUS}" {FONT}>{sigla}</text>')
    if seats:
        out += (f'<text x="{fmt(x)}" y="{fmt(y + h / 2 - 0.9)}" font-size="1.3" font-weight="600" '
                f'text-anchor="middle" fill="#6E6E73" {FONT}>{seats}</text>')
    return out + "</g>"


def draw_plan(b, floor):
    shell = [tuple(p) for p in b["pianta"]]
    xs, ys = [p[0] for p in shell], [p[1] for p in shell]
    m = 7.0
    x0, y0, x1, y1 = min(xs) - m, min(ys) - m, max(xs) + m, max(ys) + m
    wall = WALL_PER_FLOOR * 1.4
    rooms = floor["locali"]
    polys = [[tuple(p) for p in r["forma"]] for r in rooms]
    strati = []

    strati.append(Strato("fondo", "terreno", [
        f'<rect x="{fmt(x0)}" y="{fmt(y0)}" width="{fmt(x1 - x0)}" height="{fmt(y1 - y0)}" fill="{GROUND}"/>',
        f'<path d="{poly(shell, wall * 0.86, wall * 1.57)}" fill="{SHADOW}" opacity="0.10"/>',
        f'<path d="{poly(shell)}" fill="#FFFFFF"/>']))

    fills = []
    for r, pts in zip(rooms, polys):
        attrs = f' id="{r["csiv"]}" data-sigla="{r["sigla"]}"' if r.get("csiv") else ""
        fills.append(f'<g{attrs} data-tipo="{r["tipo"]}"><path d="{poly(pts)}" fill="{PLAN_FILL[r["tipo"]]}" '
                     f'stroke="{PLAN_WALL}" stroke-width="{INNER_WALL}" stroke-linejoin="round"/></g>')
    strati.append(Strato("locali", "locali", fills))

    def lines_in(kind, step, margin, color, width, key):
        clips, marks = [], []
        for i, (r, pts) in enumerate(zip(rooms, polys)):
            if r["tipo"] != kind:
                continue
            clips.append(f'<clipPath id="{key}-{i}"><path d="{poly(pts)}"/></clipPath>')
            edge = r.get("gradoni" if kind == "aula" else "gradini", 0)
            marks.append(f'<path d="{hatch(pts, edge, step, margin)}" clip-path="url(#{key}-{i})" '
                         f'stroke="{color}" stroke-width="{width}"/>')
        return ([f"<defs>{''.join(clips)}</defs>"] if clips else []) + marks

    strati.append(Strato("gradoni", "gradoni", lines_in("aula", 0.9, 1.4, PLAN_TIER, 0.18, "gr")))
    strati.append(Strato("gradini", "gradini", lines_in("scale", 0.45, 0.25, PLAN_TREAD, 0.12, "gd")))

    lifts = []
    for r, pts in zip(rooms, polys):
        if r["tipo"] == "ascensore" and len(pts) == 4:
            ctr = centroid(pts)
            p = [(q[0] + (ctr[0] - q[0]) * 0.18, q[1] + (ctr[1] - q[1]) * 0.18) for q in pts]
            lifts.append(f'<path d="M{fmt(p[0][0])} {fmt(p[0][1])}L{fmt(p[2][0])} {fmt(p[2][1])}'
                         f'M{fmt(p[1][0])} {fmt(p[1][1])}L{fmt(p[3][0])} {fmt(p[3][1])}" '
                         f'stroke="#C7CCD5" stroke-width="0.2" stroke-linecap="round"/>')
    strati.append(Strato("ascensori", "ascensori", lifts))

    strati.append(Strato("pilastri", "pilastri",
                         [f'<rect x="{fmt(x - 0.35)}" y="{fmt(y - 0.35)}" width="0.7" height="0.7" rx="0.12" fill="{PLAN_WALL}"/>'
                          for x, y in floor.get("pilastri", [])]))

    doors = [opening(*nearest_edge(tuple(p), polys)[:3], DOOR) for p in floor.get("porte", [])]
    strati.append(Strato("porte", "porte",
                         [f'<path d="{"".join(doors)}" stroke="#FFFFFF" stroke-width="{INNER_WALL + 0.25}"/>'] if doors else []))

    strati.append(Strato("muri", "muri", [f'<path d="{poly(shell)}" fill="none" stroke="{PLAN_SHELL}" '
                                          f'stroke-width="{SHELL_WALL}" stroke-linejoin="round"/>']))

    ways = []
    for e in floor.get("ingressi", []):
        q, a, c, _ = nearest_edge(tuple(e["punto"]), [shell])
        nx, ny = outward(a, c, shell)
        ways.append(f'<path d="{opening(q, a, c, ENTRANCE)}" stroke="#FFFFFF" stroke-width="{SHELL_WALL + 0.3}"/>')
        ways.append(entrance_arrow(q, (nx, ny), e.get("principale", False)))
        if e.get("principale"):
            # Beside the arrow, on its far side, whichever way the wall faces.
            lx, ly = q[0] + nx * 3.8, q[1] + ny * 3.8
            if abs(nx) > abs(ny):
                anchor = "end" if nx < 0 else "start"
            else:
                anchor, ly = "middle", ly + (1.6 if ny > 0 else -0.6)
            ways.append(f'<text x="{fmt(lx)}" y="{fmt(ly + 0.55)}" font-size="1.5" font-weight="700" '
                        f'text-anchor="{anchor}" fill="{BADGE_FOCUS}" {FONT}>Ingresso</text>')
    strati.append(Strato("ingressi", "ingressi", ways))

    access = []
    lift_pts = [p for r, pts in zip(rooms, polys) if r["tipo"] == "ascensore" for p in pts]
    if lift_pts:
        access.append(access_badge(*centroid(lift_pts)))
    for r, pts in zip(rooms, polys):
        if r["tipo"] == "wc" and r.get("accessibile"):
            x, y = r.get("etichetta") or area_centroid(pts)
            access.append(access_badge(x + 1.6, y))
    strati.append(Strato("accessibilita", "accessibilita", access))

    strati.append(Strato("acqua", "acqua", [marker(x, y, glyph_drop, r=1.4) for x, y in floor.get("acqua", [])]))
    strati.append(Strato("etichette", "etichette", [lbl for lbl in (plan_label(r) for r in rooms) if lbl]))

    return f"{fmt(x0)} {fmt(y0)} {fmt(x1 - x0)} {fmt(y1 - y0)}", (x1 - x0) * 10, (y1 - y0) * 10, strati


# ---------------------------------------------------------------- main

def main():
    disegni = {}
    for src in sorted(HERE.glob("*.json")):
        if src.name == "livelli.json":
            continue
        campus = json.loads(src.read_text())
        dest = HERE / src.stem
        dest.mkdir(exist_ok=True)
        for b in campus["edifici"]:
            if "riquadro" not in b:      # outline only, drawn as a neighbour so far
                continue
            name = f"{b['csie']}-mappa"
            disegni[f"{src.stem}/{name}"] = write_drawing(dest, name, *draw_map(campus, b))
            name = f"{b['csie']}-isometrico"
            disegni[f"{src.stem}/{name}"] = write_drawing(dest, name, *draw_iso(campus, b))
            print(f"{src.stem}/{b['csie']}  {b.get('nome', b['numero'])}")
            plans = HERE / "piante" / f"{b['csie']}.json"
            if plans.exists():
                for floor in json.loads(plans.read_text())["piani"]:
                    name = f"{floor['csip']}-pianta"
                    disegni[f"{src.stem}/{name}"] = write_drawing(dest, name, *draw_plan(b, floor))
                    print(f"{src.stem}/{floor['csip']}  piano {floor['nome']}")
    catalogue = {k: {"nome": n, "predefinito": on, "fisso": fixed} for k, (n, on, fixed) in LIVELLI.items()}
    (HERE / "livelli.json").write_text(json.dumps({"livelli": catalogue, "disegni": disegni},
                                                  indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
