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
LIGHT_DIM = "#B87A24"
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
    "esterni": ("Spazi esterni", True, False),
    "muri": ("Muri", True, True),
    "locali": ("Locali", True, True),
    "arredi": ("Banchi e gradoni", True, False),
    "gradini": ("Scale e ringhiere", True, False),
    "ascensori": ("Ascensori", True, False),
    "finestre": ("Finestre", True, False),
    "porte": ("Porte", True, False),
    "ingressi": ("Ingressi", True, False),
    "accessibilita": ("Accessibilità", True, False),
    "percorso-accessibile": ("Percorso accessibile", False, False),
    "dotazioni": ("Dotazioni delle aule", True, False),
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
    "iso-lit-glow": ('<linearGradient id="iso-lit-glow" x1="0" y1="0" x2="0" y2="1">'
                     '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.75"/>'
                     '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>'),
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


def simplify_ring(pts, tol):
    """Douglas–Peucker on a closed outline, split at the point farthest from the first."""
    def rdp(seq):
        a, b = seq[0], seq[-1]
        dx, dy = b[0] - a[0], b[1] - a[1]
        n = math.hypot(dx, dy) or 1e-9
        far, idx = max(((abs(dy * p[0] - dx * p[1] + b[0] * a[1] - b[1] * a[0]) / n, i)
                        for i, p in enumerate(seq[1:-1], 1)), default=(0.0, 0))
        return [a, b] if far <= tol else rdp(seq[:idx + 1])[:-1] + rdp(seq[idx:])
    i = max(range(len(pts)), key=lambda j: math.dist(pts[0], pts[j]))
    ring = rdp(pts[:i + 1])[:-1] + rdp(pts[i:] + [pts[0]])[:-1]
    return ring if len(ring) >= 3 else pts


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
        q = (p1[0] + t * (p2[0] - p1[0]), p1[1] + t * (p2[1] - p1[1]))
        # A sharp corner would throw the mitre far out: bevel it instead.
        out.append(q if math.dist(q, p3) < 4 * abs(d) + 0.5 else p3)
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
    """Storeys above ground, as the map and 3D view draw them."""
    return b.get("piani") or len(b.get("livelli", [])) or 2


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


def glyph_drop(x, y, s=1.0):
    p = lambda dx, dy: f"{fmt(x + dx * s)} {fmt(y + dy * s)}"
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


def glyph_projector(x, y, s):
    p = lambda dx, dy: f"{fmt(x + dx * s)} {fmt(y + dy * s)}"
    return (f'<rect x="{fmt(x - 0.8 * s)}" y="{fmt(y - 0.42 * s)}" width="{fmt(1.6 * s)}" height="{fmt(0.9 * s)}" '
            f'rx="{fmt(0.18 * s)}" fill="{BADGE_FOCUS}"/>'
            f'<circle cx="{fmt(x + 0.32 * s)}" cy="{fmt(y + 0.03 * s)}" r="{fmt(0.26 * s)}" fill="#FFFFFF"/>'
            f'<path d="M{p(-0.5, 0.48)}V{fmt(y + 0.78 * s)}M{p(0.5, 0.48)}V{fmt(y + 0.78 * s)}" '
            f'stroke="{BADGE_FOCUS}" stroke-width="{fmt(0.16 * s)}" stroke-linecap="round"/>')


def glyph_microphone(x, y, s):
    p = lambda dx, dy: f"{fmt(x + dx * s)} {fmt(y + dy * s)}"
    return (f'<rect x="{fmt(x - 0.26 * s)}" y="{fmt(y - 0.9 * s)}" width="{fmt(0.52 * s)}" height="{fmt(1.0 * s)}" '
            f'rx="{fmt(0.26 * s)}" fill="{BADGE_FOCUS}"/>'
            f'<path d="M{p(-0.52, -0.15)}A{fmt(0.52 * s)} {fmt(0.52 * s)} 0 0 0 {p(0.52, -0.15)}M{p(0, 0.37)}V{fmt(y + 0.82 * s)}'
            f'M{p(-0.32, 0.82)}H{fmt(x + 0.32 * s)}" fill="none" stroke="{BADGE_FOCUS}" stroke-width="{fmt(0.16 * s)}" '
            f'stroke-linecap="round"/>')


def glyph_bolt(x, y, s):
    p = lambda dx, dy: f"{fmt(x + dx * s)} {fmt(y + dy * s)}"
    return (f'<path d="M{p(0.18, -0.92)}L{p(-0.48, 0.12)}L{p(-0.02, 0.12)}L{p(-0.18, 0.92)}L{p(0.48, -0.16)}'
            f'L{p(0.02, -0.16)}Z" fill="{LIGHT_DESK}"/>')


def glyph_network(x, y, s):
    p = lambda dx, dy: f"{fmt(x + dx * s)} {fmt(y + dy * s)}"
    box = lambda cx, cy: (f'<rect x="{fmt(x + (cx - 0.24) * s)}" y="{fmt(y + (cy - 0.24) * s)}" width="{fmt(0.48 * s)}" '
                          f'height="{fmt(0.48 * s)}" rx="{fmt(0.08 * s)}" fill="{BADGE_FOCUS}"/>')
    return (f'<path d="M{p(0, -0.4)}V{fmt(y + 0.08 * s)}M{p(-0.6, 0.4)}V{fmt(y + 0.08 * s)}H{fmt(x + 0.6 * s)}V{fmt(y + 0.4 * s)}" '
            f'fill="none" stroke="{BADGE_FOCUS}" stroke-width="{fmt(0.14 * s)}"/>'
            + box(0, -0.62) + box(-0.6, 0.62) + box(0.6, 0.62))


# What a room offers, in the order the icons sit under its label. Only these
# tell rooms apart; every lecture hall here is dimmable and has a wired desk.
EQUIPMENT = [("proiettore", glyph_projector), ("microfono", glyph_microphone),
             ("prese", glyph_bolt), ("rete", glyph_network)]


def entrance_arrow(q, n, main=False):
    """A triangle outside the wall, pointing in through the door."""
    nx, ny = n
    tx, ty = -ny, nx
    # Taller than wide, so which way it points reads at a glance.
    length, half = (3.4, 1.45) if main else (2.2, 0.68)
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
        turn = f' transform="rotate({n["angolo"]} {fmt(x)} {fmt(y)})"' if n.get("angolo") else ""
        names.append(f'<text x="{fmt(x)}" y="{fmt(y + 1.1)}" font-size="3.2" font-weight="600" text-anchor="middle" '
                     f'letter-spacing="0.3" fill="{STREET_INK}" {FONT}{turn}>{n["testo"]}</text>')
    strati.append(Strato("nomi", "nomi", names))

    badges = [f'<g font-size="4" font-weight="700" text-anchor="middle" {FONT}>']
    for b in campus["edifici"]:
        if "badge" not in b:
            continue
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


# Claddings for a building drawn by its profile: (left face, right face, top).
CLADDING = {"ceramica": ("#E6E0D4", "#CDC5B6", "#F1EDE5"),
            "mattone": ("#ECE7DE", "#D3CBBD", "#F4F1EB"),
            "fessura": ("#4D5D72", "#36465B", "#5B6B80")}
SKYLIGHT, SKYLIGHT_LIT = "#C9D6E4", "#FFD98A"


def floor_outline(b, csip, turn):
    """A floor's own gross outline, simplified, in the view's frame."""
    geo = json.loads((HERE / "piante" / f"{b['csie']}-geometria.json").read_text())["piani"][csip]
    ring = max(geo["contorno"], key=lambda r: abs(signed_area([tuple(p) for p in r])))
    return ccw([turn(p) for p in simplify_ring([tuple(p) for p in ring], 0.6)])


def floor_rooms(b, csip, turn, kinds=("aula",)):
    """The bounding boxes of a floor's rooms of the given kinds (classrooms by default)."""
    geo = json.loads((HERE / "piante" / f"{b['csie']}-geometria.json").read_text())["piani"][csip]
    plans = HERE / "piante" / f"{b['csie']}.json"
    aule = set()
    if plans.exists():
        aule = {k for f in json.loads(plans.read_text())["piani"] if f["csip"] == csip for k in f["aule"]}
    out = []
    for v in geo["vani"]:
        if v["csiv"] in aule or v["tipo"] in kinds:
            r = [turn(tuple(p)) for p in v["forma"][0]]
            out.append((min(p[0] for p in r), min(p[1] for p in r), max(p[0] for p in r), max(p[1] for p in r)))
    return out


def draw_profile(b, pts, turn, z, storey, door, strati, zmid):
    """Draws the bands of `profilo`, bottom up, from height z; returns the top.

    A band is a floor (`piano`) drawn as `vetro` (a glazed storey), `pieno` (a
    blind volume in `rivestimento` ceramica or mattone), `fessura` (a thin dark
    glazed slot) or `sporto` (a blind volume overhanging the one below by
    `sporto` metres, casting its shadow on it; lit, its skylights glow over the
    classrooms). `h` is its height in drawing units, `sagoma: propria` sets it on
    the floor's own outline, set back on the roof of what is below."""
    below, roofed, skylights = pts, False, []
    for band in b["profilo"]:
        csip, kind, h = band.get("piano"), band["tipo"], band["h"]
        own = pts
        if band.get("sagoma") == "propria":
            # Kept within the building: a floor's drawing may reach past it (a gallery, a
            # bridge); those points go onto the building's edge.
            near = offset(pts, 1.0)
            own = [p if inside(p, near) else nearest_edge(p, [pts])[0] for p in floor_outline(b, csip, turn)]
            own = [p for i, p in enumerate(own) if math.dist(p, own[i - 1]) > 0.1]
            own = ccw(simplify_ring(own, 0.6))
        if own is not pts and not roofed:
            roof = prism(below, z, z + ISO_SLAB, (ISO_SLAB_LEFT, ISO_SLAB_RIGHT), ISO_SLAB_TOP)
            roof.append(f'<polygon points="{iso_poly([(x, y, z + ISO_SLAB) for x, y in offset(below, -1.6)])}" fill="{ISO_ROOF_INNER}"/>')
            # The parapet railing along the roof's edge.
            rail = "".join(f"M{fmt(iso(*a, z + ISO_SLAB + 3)[0])} {fmt(iso(*a, z + ISO_SLAB + 3)[1])}"
                           f"L{fmt(iso(*c, z + ISO_SLAB + 3)[0])} {fmt(iso(*c, z + ISO_SLAB + 3)[1])}"
                           for a, c, _, _ in faces(below, 0, 1))
            roof.append(f'<path d="{rail}" stroke="#AEB4BE" stroke-width="0.8" fill="none"/>')
            strati.append(Strato("tetto", "edifici", roof))
            for c, lights in skylights:
                strati.append(Strato(f"{c}-lucernari", "piani", lights(False), piano=c, lit=lights(True)))
            skylights.clear()
            z, roofed = z + ISO_SLAB, True
        def body(lit):
            if kind == "vetro":
                return storey(z, lit, h, own)
            if kind == "sporto":
                out = []
                # Its shadow on the band below, deepest under the overhang.
                for a, c, _, _ in faces(below, 0, 1):
                    q = [(a[0], a[1], z - h * 0.45), (c[0], c[1], z - h * 0.45), (c[0], c[1], z), (a[0], a[1], z)]
                    out.append(f'<polygon points="{iso_poly(q)}" fill="{SHADOW}" opacity="0.22"/>')
                shape = offset(own, band.get("sporto", 2.0))
                out += prism(shape, z, z + h, *(lambda c: (c[:2], c[2]))(CLADDING[band.get("rivestimento", "mattone")]))
                return out
            colors = CLADDING["fessura" if kind == "fessura" else band.get("rivestimento", "ceramica")]
            if kind == "fessura" and lit:
                colors = (ISO_LIT_LEFT[1], ISO_LIT_RIGHT[1], colors[2])
            out = prism(own, z, z + h, colors[:2], colors[2])
            if kind == "pieno":
                # The cladding's courses, faint.
                courses = []
                for a, c, _, _ in faces(own, 0, 1):
                    for k in range(1, int(h / 3)):
                        (x0, y0), (x1, y1) = iso(*a, z + k * 3), iso(*c, z + k * 3)
                        courses.append(f"M{fmt(x0)} {fmt(y0)}L{fmt(x1)} {fmt(y1)}")
                out.append(f'<path d="{"".join(courses)}" stroke="#FFFFFF" stroke-width="0.5" opacity="0.35"/>')
            return out
        zmid[csip] = z + h / 2
        strati.append(Strato(csip, "piani", body(False), ["iso-glass-l", "iso-glass-r"], piano=csip,
                             lit=body(True), lit_defs=["iso-lit-l", "iso-lit-r", "iso-lit-glow"]))
        if band.get("ingresso"):
            strati.append(Strato("ingresso", "ingressi", door))
        if kind == "sporto":
            # Its classrooms are lit from above: skylights over each, on the roof drawn next.
            def lights(lit, zt=z + h + ISO_SLAB, csip=csip):
                out = []
                for x0, y0, x1, y1 in floor_rooms(b, csip, turn):
                    cx, cy, w, d = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) * 0.6, (y1 - y0) * 0.6
                    sky = [(cx - w / 2, cy - d / 2), (cx + w / 2, cy - d / 2), (cx + w / 2, cy + d / 2), (cx - w / 2, cy + d / 2)]
                    out.append(f'<polygon points="{iso_poly([(x, y, zt) for x, y in sky])}" '
                               f'fill="{SKYLIGHT_LIT if lit else SKYLIGHT}" opacity="{0.95 if lit else 0.8}"/>')
                return out
            skylights.append((csip, lights))
            own = offset(own, band.get("sporto", 2.0))
        z += h
        below = own
    roof = prism(below, z, z + ISO_SLAB, (ISO_SLAB_LEFT, ISO_SLAB_RIGHT), ISO_SLAB_TOP)
    roof.append(f'<polygon points="{iso_poly([(x, y, z + ISO_SLAB) for x, y in offset(below, -1.6)])}" fill="{ISO_ROOF_INNER}"/>')
    strati.append(Strato("tetto", "edifici", roof))
    for c, lights in skylights:
        strati.append(Strato(f"{c}-lucernari", "piani", lights(False), piano=c, lit=lights(True)))
    return z


def draw_iso(campus, b):
    turn = view(b)
    pts = ccw([turn(p) for p in b["pianta"]])
    # The storeys the view stacks: all of `livelli` unless `piani_3d` leaves out a
    # basement or a rooftop plant floor, which are no glass storey.
    levels = b.get("piani_3d") or b.get("livelli") or [f"piano-{i}" for i in range(floor_count(b))]
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

    def storey(z0, lit, h=ISO_FLOOR, shape=None):
        """One floor. Lit, it is the same floor at dusk with its lights on:
        warm rooms behind the glass, brightest under the ceiling where the
        light comes from, each bay a little different as rooms are, desks
        catching the light, frames dark against it, and a glow on the slab."""
        gl, gr = ("url(#iso-lit-l)", "url(#iso-lit-r)") if lit else ("url(#iso-glass-l)", "url(#iso-glass-r)")
        g0, g1 = z0 + ISO_SLAB, z0 + h
        own = shape or pts
        glass = offset(own, -0.4)
        out = prism(own, z0, g0, (ISO_SLAB_LEFT, ISO_SLAB_RIGHT), ISO_SLAB_TOP)
        mullions, desks = [], []
        for k, (a, c, is_left, q) in enumerate(faces(glass, g0, g1)):
            if lit:
                spill = [(a[0], a[1], z0), (c[0], c[1], z0), (c[0], c[1], g0), (a[0], a[1], g0)]
                out.append(f'<polygon points="{iso_poly(spill)}" fill="{LIGHT_SPILL}" opacity="0.55"/>')
            out.append(f'<polygon points="{iso_poly(q)}" fill="{gl if is_left else gr}"/>')
            n = max(1, round(math.dist(a, c) / ISO_MULLION))
            at = lambda t: (a[0] + (c[0] - a[0]) * t, a[1] + (c[1] - a[1]) * t)
            if lit:
                # No two rooms glow the same: a fixed, irregular rhythm of dimmer and brighter bays.
                for j in range(n):
                    tone = (k * 5 + j * 3) % 7
                    if tone in (0, 4):
                        fill, alpha = LIGHT_DIM, 0.14
                    elif tone == 2:
                        fill, alpha = "#FFFFFF", 0.18
                    else:
                        continue
                    (x0, y0), (x1, y1) = at(j / n), at((j + 1) / n)
                    bay = [(x0, y0, g0), (x1, y1, g0), (x1, y1, g1), (x0, y0, g1)]
                    out.append(f'<polygon points="{iso_poly(bay)}" fill="{fill}" opacity="{alpha}"/>')
                ceiling = [(a[0], a[1], g1 - 7), (c[0], c[1], g1 - 7), (c[0], c[1], g1), (a[0], a[1], g1)]
                out.append(f'<polygon points="{iso_poly(ceiling)}" fill="url(#iso-lit-glow)"/>')
                (dx0, dy0), (dx1, dy1) = iso(a[0], a[1], g0 + 3.2), iso(c[0], c[1], g0 + 3.2)
                desks.append(f"M{fmt(dx0)} {fmt(dy0)}L{fmt(dx1)} {fmt(dy1)}")
            for i in range(1, n):
                (px, py0), (_, py1) = iso(*at(i / n), g0), iso(*at(i / n), g1)
                mullions.append(f"M{fmt(px)} {fmt(py0)}V{fmt(py1)}")
        if lit:
            out.append(f'<path d="{"".join(desks)}" stroke="{LIGHT_DESK}" stroke-width="1.1" opacity="0.4"/>')
            out.append(f'<path d="{"".join(mullions)}" stroke="{LIGHT_FRAME}" stroke-width="1.2" opacity="0.55"/>')
        else:
            out.append(f'<path d="{"".join(mullions)}" stroke="#FFFFFF" stroke-width="1.2" opacity="0.75"/>')
        return out

    zmid = {}
    if b.get("profilo"):
        # A building that is not a stack of like storeys: its bands, bottom up, as drawn.
        top = draw_profile(b, pts, turn, base_h, storey, door, strati, zmid)
    else:
        for f, csip in enumerate(levels):
            z0 = base_h + f * ISO_FLOOR
            zmid[csip] = z0 + (ISO_SLAB + ISO_FLOOR) / 2
            strati.append(Strato(csip, "piani", storey(z0, False), ["iso-glass-l", "iso-glass-r"], piano=csip,
                                 lit=storey(z0, True), lit_defs=["iso-lit-l", "iso-lit-r", "iso-lit-glow"]))
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
    for f, csip in enumerate(c for c in (list(zmid) if b.get("profilo") else levels)):
        px, py = iso(*right, zmid[csip])
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

PLAN_FILL = {"aula": "#E3ECF5", "corridoio": "#FFFFFF", "wc": "#EEF0F3", "scale": "#E9EBEF",
             "ascensore": "#E9EBEF", "locale": "#F3F4F7", "tecnico": "#E4E7EC"}
PLAN_OUTSIDE = "#F8F9F6"       # landings, ramps and links outside the gross outline
PLAN_WALL = "#B9BFC9"          # the walls: what is left of the floor between the rooms
PLAN_TREAD = "#C3C8D1"         # stair treads and railings
PLAN_SEAT = "#C9D9EC"          # rows of seats and desks
PLAN_GLASS = "#8FC3E8"         # windows
PLAN_DOOR = "#A3AAB6"          # door leaves and their swing
PLAN_MUTED = "#8E8E93"


def segs_path(segs):
    return "".join(f"M{fmt(a)} {fmt(b)}L{fmt(c)} {fmt(d)}" for a, b, c, d, *_ in segs)


def rings_path(rings):
    return "".join(poly([tuple(p) for p in r]) for r in rings)


def clusters(items, near):
    """Groups items that touch, by union–find on the pairs `near` accepts."""
    parent = list(range(len(items)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(items)):
        for j in range(i + 1, len(items)):
            if near(items[i], items[j]):
                parent[root(i)] = root(j)
    groups = {}
    for i in range(len(items)):
        groups.setdefault(root(i), []).append(items[i])
    return list(groups.values())


def hull(points):
    pts = sorted(set(points))
    if len(pts) < 3:
        return pts
    cross = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def bbox_gap(a, b):
    (ax0, ay0, ax1, ay1), (bx0, by0, bx1, by1) = a, b
    return max(bx0 - ax1, ax0 - bx1, by0 - ay1, ay0 - by1, 0)


def ring_box(ring):
    xs, ys = [p[0] for p in ring], [p[1] for p in ring]
    return (min(xs), min(ys), max(xs), max(ys))


def visual_centre(rings, step=0.4):
    """The point deepest inside a room: where its label sits clear of every wall."""
    outer = rings[0]
    x0, y0, x1, y1 = ring_box(outer)
    edges = [(a, b) for r in rings for a, b in zip(r, r[1:] + r[:1])]

    def clearance(p):
        best = 1e9
        for a, b in edges:
            dx, dy = b[0] - a[0], b[1] - a[1]
            t = max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / ((dx * dx + dy * dy) or 1)))
            best = min(best, math.dist(p, (a[0] + dx * t, a[1] + dy * t)))
        return best

    best, at = -1.0, area_centroid(outer)
    y = y0 + step / 2
    while y < y1:
        x = x0 + step / 2
        while x < x1:
            if inside((x, y), outer) and not any(inside((x, y), h) for h in rings[1:]):
                c = clearance((x, y))
                if c > best:
                    best, at = c, (x, y)
            x += step
        y += step
    return at


def aula_label(x, y, sigla, seats, csiv):
    w = max(len(sigla) * 1.3, len(seats) * 0.72) + 1.6
    h = 5.2 if seats else 3.6
    out = (f'<g id="{csiv}-etichetta">'
           f'<rect x="{fmt(x - w / 2)}" y="{fmt(y - h / 2)}" width="{fmt(w)}" height="{fmt(h)}" rx="{fmt(min(h, 3.6) / 2)}" '
           f'fill="#FFFFFF" stroke="{MARKER_EDGE}" stroke-width="0.2"/>'
           f'<text x="{fmt(x)}" y="{fmt(y - h / 2 + 2.6)}" font-size="2.2" font-weight="700" text-anchor="middle" fill="{BADGE_FOCUS}" {FONT}>{sigla}</text>')
    if seats:
        out += (f'<text x="{fmt(x)}" y="{fmt(y + h / 2 - 0.9)}" font-size="1.3" font-weight="600" '
                f'text-anchor="middle" fill="#6E6E73" {FONT}>{seats}</text>')
    return out + "</g>", h


def draw_plan(b, floor, geo):
    """One floor, drawn from the imported geometry in the illustrations' look.

    The floor slab is filled with the wall colour and every room is laid on top
    of it, so the walls are exactly what is left between the rooms, at their
    real thickness. Each door cuts its opening out of the wall where its leaf
    closes, and draws its leaf and swing.
    """
    shell = [[tuple(p) for p in r] for r in geo["contorno"]]
    shell.sort(key=lambda r: -abs(signed_area(r)))
    outline = shell[0]
    kinds = floor.get("tipi", {})
    aule = floor.get("aule", {})
    accessible = set(floor.get("wc_accessibili", []))
    rooms = []
    for v in geo["vani"]:
        rings = [[tuple(p) for p in r] for r in v["forma"]]
        kind = "aula" if v["csiv"] in aule else kinds.get(v["csiv"], v["tipo"])
        out = not inside(area_centroid(rings[0]), outline)
        rooms.append({**v, "tipo": kind, "rings": rings, "fuori": out})
    lines = geo["linee"]
    # A room the step-free route runs through is somewhere people walk: draw it as one,
    # unless it is a hall the route crosses.
    for ax, ay, bx, by, _ in geo.get("percorso_accessibile", []):
        mid = ((ax + bx) / 2, (ay + by) / 2)
        for rm in rooms:
            if rm["tipo"] == "locale" and abs(signed_area(rm["rings"][0])) < 250 and inside(mid, rm["rings"][0]):
                rm["tipo"] = "corridoio"

    every = [p for r in shell for p in r] + [p for rm in rooms for p in rm["rings"][0]]
    every += [(s[0], s[1]) for segs in lines.values() for s in segs] + [(s[2], s[3]) for segs in lines.values() for s in segs]
    xs, ys = [p[0] for p in every], [p[1] for p in every]
    m = 12.0      # room for the entrance's name beside its arrow
    x0, y0, x1, y1 = min(xs) - m, min(ys) - m, max(xs) + m, max(ys) + m
    wall = WALL_PER_FLOOR * 1.4
    strati = []

    strati.append(Strato("fondo", "terreno", [
        f'<rect x="{fmt(x0)}" y="{fmt(y0)}" width="{fmt(x1 - x0)}" height="{fmt(y1 - y0)}" fill="{GROUND}"/>',
        f'<path d="{poly(outline, wall * 0.86, wall * 1.57)}" fill="{SHADOW}" opacity="0.10"/>']))

    strati.append(Strato("esterni", "esterni", [
        f'<path d="{rings_path(rm["rings"])}" fill="{PLAN_OUTSIDE}" fill-rule="evenodd" stroke="{PLAN_TREAD}" '
        f'stroke-width="0.08" stroke-linejoin="round"/>' for rm in rooms if rm["fuori"]] + [
        f'<path d="{segs_path(lines["esterni"])}" stroke="{PLAN_TREAD}" stroke-width="0.1" stroke-linecap="round"/>']))

    # Openings: where each leaf closes, through the wall, kept inside the outline.
    cuts = []
    for d in geo["porte"]:
        h, c = d["cardine"], d["chiusa"]
        ux, uy = c[0] - h[0], c[1] - h[1]
        n = math.hypot(ux, uy) or 1
        nx, ny = -uy / n * 0.45, ux / n * 0.45
        cuts.append(poly([(h[0] + nx, h[1] + ny), (c[0] + nx, c[1] + ny), (c[0] - nx, c[1] - ny), (h[0] - nx, h[1] - ny)]))
    strati.append(Strato("muri", "muri", [
        f'<defs><clipPath id="pl-guscio"><path d="{rings_path(shell)}"/></clipPath></defs>',
        f'<path d="{rings_path(shell)}" fill="{PLAN_WALL}" fill-rule="evenodd"/>',
        f'<path d="{"".join(cuts)}" fill="#FFFFFF" clip-path="url(#pl-guscio)"/>']))

    fills = []
    for rm in rooms:
        if rm["fuori"]:
            continue
        attrs = f' id="{rm["csiv"]}"' + (f' data-sigla="{aule[rm["csiv"]]["sigla"]}"' if rm["csiv"] in aule else "")
        fills.append(f'<path{attrs} data-tipo="{rm["tipo"]}" d="{rings_path(rm["rings"])}" fill="{PLAN_FILL[rm["tipo"]]}" '
                     f'fill-rule="evenodd"/>')
    # Voids: open to the floor below, edged like a railing.
    fills += [f'<path data-tipo="vuoto" d="{poly([tuple(p) for p in r])}" fill="{PLAN_OUTSIDE}" stroke="{PLAN_TREAD}" '
              f'stroke-width="0.12" stroke-dasharray="0.5 0.35"/>' for r in geo.get("vuoti", [])]
    strati.append(Strato("locali", "locali", fills))

    strati.append(Strato("arredi", "arredi", [
        f'<path d="{segs_path(lines["arredi"] + lines.get("sanitari", []))}" stroke="{PLAN_SEAT}" '
        f'stroke-width="0.09" stroke-linecap="round"/>']))
    strati.append(Strato("gradini", "gradini", [
        f'<path d="{segs_path(lines["scale"])}" stroke="{PLAN_TREAD}" stroke-width="0.06" stroke-linecap="round"/>',
        f'<path d="{segs_path(lines["ringhiere"])}" stroke="{PLAN_DOOR}" stroke-width="0.07" stroke-linecap="round"/>']))

    lift_groups = clusters(lines["ascensori"], lambda s, t: min(
        math.dist(p, q) for p in ((s[0], s[1]), (s[2], s[3])) for q in ((t[0], t[1]), (t[2], t[3]))) < 0.3)
    cars = []
    for g in lift_groups:
        h = hull([(s[0], s[1]) for s in g] + [(s[2], s[3]) for s in g])
        if len(h) >= 3:
            cars.append(f'<path d="{poly(h)}" fill="{PLAN_FILL["ascensore"]}"/>')
        cars.append(f'<path d="{segs_path(g)}" stroke="{PLAN_DOOR}" stroke-width="0.08" stroke-linecap="round"/>')
    strati.append(Strato("ascensori", "ascensori", cars))

    strati.append(Strato("finestre", "finestre", [
        f'<path d="{segs_path(lines["finestre"])}" stroke="{PLAN_GLASS}" stroke-width="0.12" stroke-linecap="round"/>']))

    leaves = []
    for d in geo["porte"]:
        h, c, o = d["cardine"], d["chiusa"], d["aperta"]
        r = math.dist(h, c)
        sweep = 1 if (c[0] - h[0]) * (o[1] - h[1]) - (c[1] - h[1]) * (o[0] - h[0]) > 0 else 0
        leaves.append(f"M{fmt(h[0])} {fmt(h[1])}L{fmt(o[0])} {fmt(o[1])}"
                      f"M{fmt(c[0])} {fmt(c[1])}A{fmt(r)} {fmt(r)} 0 0 {sweep} {fmt(o[0])} {fmt(o[1])}")
    strati.append(Strato("porte", "porte", [
        f'<path d="{"".join(leaves)}" fill="none" stroke="{PLAN_DOOR}" stroke-width="0.07" stroke-linecap="round"/>']))

    # The step-free route: the line stops at each arrowhead's base, so nothing shows past its tip.
    route, heads = [], []
    for ax, ay, bx, by, way in geo.get("percorso_accessibile", []):
        if math.dist((ax, ay), (bx, by)) < 0.2:
            continue
        if way:
            (fx, fy), (tx, ty) = ((ax, ay), (bx, by)) if way > 0 else ((bx, by), (ax, ay))
            n = math.dist((fx, fy), (tx, ty))
            ux, uy = (tx - fx) / n, (ty - fy) / n
            hx, hy = tx - ux * min(1.0, n * 0.6), ty - uy * min(1.0, n * 0.6)
            heads.append(poly([(tx, ty), (hx - uy * 0.55, hy + ux * 0.55), (hx + uy * 0.55, hy - ux * 0.55)]))
            ax, ay, bx, by = fx, fy, hx, hy
        route.append((ax, ay, bx, by))
    strati.append(Strato("percorso-accessibile", "percorso-accessibile", [
        f'<path d="{segs_path(route)}" fill="none" stroke="#FFFFFF" stroke-width="0.9" stroke-linecap="round" stroke-linejoin="round"/>',
        f'<path d="{"".join(heads)}" fill="#FFFFFF" stroke="#FFFFFF" stroke-width="0.5" stroke-linejoin="round"/>',
        f'<path d="{segs_path(route)}" fill="none" stroke="{BADGE_FOCUS}" stroke-width="0.38" stroke-linecap="round" stroke-linejoin="round"/>',
        f'<path d="{"".join(heads)}" fill="{BADGE_FOCUS}"/>',
    ] if route else []))

    # Ways in: every door that opens through the outline, one arrow per doorway,
    # and the main entrance larger, with its name.
    ways = []
    main = floor.get("principale")
    if main:
        q, a, c, _ = nearest_edge(tuple(main), [outline])
        n = outward(a, c, outline)
        ways.append(entrance_arrow(q, n, True))
        lx, ly = q[0] + n[0] * 4.0, q[1] + n[1] * 4.0
        anchor = ("end" if n[0] < 0 else "start") if abs(n[0]) > abs(n[1]) else "middle"
        if anchor == "middle":
            ly += 1.6 if n[1] > 0 else -0.6
        ways.append(f'<text x="{fmt(lx)}" y="{fmt(ly + 0.55)}" font-size="1.5" font-weight="700" '
                    f'text-anchor="{anchor}" fill="{BADGE_FOCUS}" {FONT}>Ingresso</text>')
    outside = []
    for d in geo["porte"]:
        if not d["esterna"]:
            continue
        h, c, o = d["cardine"], d["chiusa"], d["aperta"]
        mid = ((h[0] + c[0]) / 2, (h[1] + c[1]) / 2)
        n = math.dist(h, c) or 1
        nx, ny = -(c[1] - h[1]) / n, (c[0] - h[0]) / n
        # Which way is out is read from the door itself: its far side lies outside the outline.
        if inside((mid[0] + nx * 0.9, mid[1] + ny * 0.9), outline):
            nx, ny = -nx, -ny
        outside.append({"cardine": h, "chiusa": c, "aperta": o, "n": (nx, ny)})
    # A doorway is the leaves that close onto the same point (both halves of a double door).
    doorways = []
    for g in clusters(outside, lambda s, t: math.dist(s["chiusa"], t["chiusa"]) < 0.15):
        p = centroid([s["cardine"] for s in g] + ([g[0]["chiusa"]] if len(g) == 1 else []))
        n = g[0]["n"]
        # In the façade, the way in is square to the façade, whatever angle the leaves
        # are drawn at (a revolving door's are at several).
        q, a, c, _ = nearest_edge(p, [outline])
        if math.dist(p, q) < 1.5:
            n = outward(a, c, outline)
        t = 0.0
        while t < 3 and inside((p[0] + n[0] * t, p[1] + n[1] * t), outline):
            t += 0.05
        probe = (p[0] + n[0] * (t + 0.6), p[1] + n[1] * (t + 0.6))
        onto = next((rm for rm in rooms if rm["fuori"] and inside(probe, rm["rings"][0])), None)
        # A door onto a ledge or balcony is no way out; one onto an outdoor stair is.
        if onto and onto["tipo"] != "scale" and abs(signed_area(onto["rings"][0])) < 8:
            continue
        doorways.append({"p": p, "n": n, "leaves": g, "t": t, "onto": onto and onto["csiv"]})
    # Doorways side by side in one wall, onto the same outdoor space, are one way in.
    same_way = lambda a, b: (math.dist(a["p"], b["p"]) < 3.0 and a["onto"] == b["onto"]
                             and a["n"][0] * b["n"][0] + a["n"][1] * b["n"][1] > 0.7)
    # Entrances the drawing has no swinging door for (sliding or revolving), given by hand.
    extra = [tuple(e) for e in floor.get("ingressi", [])]
    for e in extra:
        q, a, c, _ = nearest_edge(e, [outline])
        ways.append(entrance_arrow(q, outward(a, c, outline)))
    for bank in clusters(doorways, same_way):
        p = centroid([d["p"] for d in bank])
        if (main and math.dist(p, main) < 4) or any(math.dist(p, e) < 3 for e in extra):
            continue
        n = bank[0]["n"]
        # Just past the wall's outer face, and clear of any leaf that swings out.
        swing = max((s["aperta"][0] - p[0]) * n[0] + (s["aperta"][1] - p[1]) * n[1]
                    for d in bank for s in d["leaves"])
        t = max(max(d["t"] for d in bank), swing + 0.1)
        ways.append(entrance_arrow((p[0] + n[0] * t, p[1] + n[1] * t), n))
    strati.append(Strato("ingressi", "ingressi", ways))

    wc = [rm for rm in rooms if rm["tipo"] == "wc" and not rm["fuori"]]
    wc_groups = clusters(wc, lambda s, t: bbox_gap(ring_box(s["rings"][0]), ring_box(t["rings"][0])) < 1.6)
    access, labels = [], []
    for car in lift_groups:
        pts = [(s[0], s[1]) for s in car] + [(s[2], s[3]) for s in car]
        if len(pts) >= 6:
            access.append(access_badge(*centroid(pts), size=1.5))
    for g in wc_groups:
        big = max(g, key=lambda rm: abs(signed_area(rm["rings"][0])))
        x, y = big["etichetta"]
        lit = any(rm["csiv"] in accessible for rm in g)
        labels.append(f'<text x="{fmt(x - (1.2 if lit else 0))}" y="{fmt(y + 0.55)}" font-size="1.5" font-weight="700" '
                      f'text-anchor="middle" fill="{PLAN_MUTED}" {FONT}>WC</text>')
        if lit:
            access.append(access_badge(x + 1.4, y, size=1.8))
    strati.append(Strato("accessibilita", "accessibilita", access))

    water = [tuple(p) for p in geo.get("acqua", [])]
    for p in floor.get("acqua", []):
        if all(math.dist(p, q) > 1.5 for q in water):
            water.append(tuple(p))
    strati.append(Strato("acqua", "acqua", [marker(x, y, lambda gx, gy: glyph_drop(gx, gy, 0.62), r=0.85)
                                            for x, y in water]))

    kit = []
    for rm in rooms:
        meta = aule.get(rm["csiv"])
        if not meta:
            continue
        x, y = meta.get("etichetta") or visual_centre(rm["rings"])
        seats = f'{meta["posti"]} posti' if meta.get("posti") else ""
        text, h = aula_label(x, y, meta["sigla"], seats, rm["csiv"])
        labels.append(text)
        have = [draw for name, draw in EQUIPMENT if name in meta.get("dotazioni", [])]
        cy = y + h / 2 + 1.5
        for i, draw in enumerate(have):
            cx = x + (i - (len(have) - 1) / 2) * 2.1
            kit.append(f'<circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="0.9" fill="#FFFFFF" stroke="{MARKER_EDGE}" stroke-width="0.15"/>'
                       + draw(cx, cy, 0.55))
    strati.append(Strato("etichette", "etichette", labels))
    strati.append(Strato("dotazioni", "dotazioni", kit))

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
            if "riquadro" in b:          # without one, an outline drawn as a neighbour so far
                name = f"{b['csie']}-mappa"
                disegni[f"{src.stem}/{name}"] = write_drawing(dest, name, *draw_map(campus, b))
                name = f"{b['csie']}-isometrico"
                disegni[f"{src.stem}/{name}"] = write_drawing(dest, name, *draw_iso(campus, b))
                print(f"{src.stem}/{b['csie']}  {b.get('nome', b['numero'])}")
            plans = HERE / "piante" / f"{b['csie']}.json"
            geometry = HERE / "piante" / f"{b['csie']}-geometria.json"
            if plans.exists() and geometry.exists():
                geo = json.loads(geometry.read_text())["piani"]
                for floor in json.loads(plans.read_text())["piani"]:
                    name = f"{floor['csip']}-pianta"
                    disegni[f"{src.stem}/{name}"] = write_drawing(dest, name, *draw_plan(b, floor, geo[floor["csip"]]))
                    print(f"{src.stem}/{floor['csip']}  piano {floor['nome']}")
    catalogue = {k: {"nome": n, "predefinito": on, "fisso": fixed} for k, (n, on, fixed) in LIVELLI.items()}
    (HERE / "livelli.json").write_text(json.dumps({"livelli": catalogue, "disegni": disegni},
                                                  indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
