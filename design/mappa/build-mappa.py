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
    "panchine": ("Panchine", True, False),
    "tavoli": ("Tavoli da picnic", True, False),
    "cestini": ("Cestini", False, False),
    "riciclo": ("Raccolta differenziata", False, False),
    "bagni": ("Bagni", True, False),
    "ristoro": ("Bar e ristoro", True, False),
    "distributori": ("Distributori automatici", True, False),
    "opere": ("Opere d'arte", True, False),
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

WOOD, WOOD_EDGE = "#C9A57A", "#A9865C"
COURTYARD = "#E4E6E1"


def glyph_text(label, size=0.95):
    return lambda x, y: (f'<text x="{fmt(x)}" y="{fmt(y + size * 0.36)}" font-size="{fmt(size)}" font-weight="700" '
                         f'text-anchor="middle" fill="{BADGE_FOCUS}" {FONT}>{label}</text>')


def glyph_cup(x, y):
    p = lambda dx, dy: f"{fmt(x + dx)} {fmt(y + dy)}"
    return (f'<path d="M{p(-0.55, -0.45)}H{fmt(x + 0.4)}V{fmt(y + 0.25)}A0.4 0.4 0 0 1 {p(0, 0.65)}H{fmt(x - 0.15)}'
            f'A0.4 0.4 0 0 1 {p(-0.55, 0.25)}Z" fill="{BADGE_FOCUS}"/>'
            f'<path d="M{p(0.4, -0.25)}H{fmt(x + 0.6)}A0.22 0.22 0 0 1 {p(0.6, 0.2)}H{fmt(x + 0.4)}" fill="none" '
            f'stroke="{BADGE_FOCUS}" stroke-width="0.16"/>')


def glyph_vending(x, y):
    return (f'<rect x="{fmt(x - 0.5)}" y="{fmt(y - 0.8)}" width="1" height="1.6" rx="0.15" fill="{BADGE_FOCUS}"/>'
            f'<rect x="{fmt(x - 0.32)}" y="{fmt(y - 0.6)}" width="0.42" height="0.8" fill="#FFFFFF"/>'
            f'<rect x="{fmt(x + 0.18)}" y="{fmt(y - 0.6)}" width="0.16" height="0.3" fill="#FFFFFF"/>')


def glyph_art(x, y):
    p = lambda dx, dy: f"{fmt(x + dx)} {fmt(y + dy)}"
    return f'<path d="M{p(0, -0.85)}L{p(0.8, 0)}L{p(0, 0.85)}L{p(-0.8, 0)}Z" fill="#9B6BC9"/>'


def map_bench(x, y):
    return (f'<rect x="{fmt(x - 0.9)}" y="{fmt(y - 0.3)}" width="1.8" height="0.6" rx="0.2" fill="{WOOD}" '
            f'stroke="{WOOD_EDGE}" stroke-width="0.12"/>')


def map_picnic(x, y):
    return (f'<rect x="{fmt(x - 0.9)}" y="{fmt(y - 1.0)}" width="1.8" height="0.35" rx="0.12" fill="{WOOD_EDGE}"/>'
            f'<rect x="{fmt(x - 0.9)}" y="{fmt(y + 0.65)}" width="1.8" height="0.35" rx="0.12" fill="{WOOD_EDGE}"/>'
            f'<rect x="{fmt(x - 0.9)}" y="{fmt(y - 0.45)}" width="1.8" height="0.9" rx="0.15" fill="{WOOD}"/>')


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
    # A courtyard is open ground inside the building: paved, the walls round it shading it.
    for b, _ in buildings:
        for yard in b.get("cortili", []):
            ring = ccw([tuple(p) for p in yard])
            body.append(f'<path d="{rounded(ring, 0.8)}" fill="{COURTYARD}"/>'
                        f'<path d="{rounded(ring, 0.8)}" fill="none" stroke="{SHADOW}" stroke-opacity="0.12" stroke-width="1.6"/>')
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
    strati.append(Strato("panchine", "panchine", [map_bench(x, y) for x, y in ctx.get("panchine", [])]))
    strati.append(Strato("tavoli", "tavoli", [map_picnic(x, y) for x, y in ctx.get("tavoli", [])]))
    strati.append(Strato("cestini", "cestini", [f'<circle cx="{fmt(x)}" cy="{fmt(y)}" r="0.4" fill="#8E959E" '
                                                f'stroke="#FFFFFF" stroke-width="0.12"/>' for x, y in ctx.get("cestini", [])]))
    strati.append(Strato("riciclo", "riciclo", [f'<rect x="{fmt(x - 0.5)}" y="{fmt(y - 0.5)}" width="1" height="1" rx="0.2" '
                                                f'fill="#6FA86A" stroke="#FFFFFF" stroke-width="0.12"/>' for x, y in ctx.get("riciclo", [])]))
    strati.append(Strato("bagni", "bagni", [marker(x, y, glyph_text("WC")) for x, y in ctx.get("bagni", [])]))
    strati.append(Strato("ristoro", "ristoro", [marker(*r["punto"], glyph_cup) for r in ctx.get("ristoro", [])]))
    strati.append(Strato("distributori", "distributori", [marker(x, y, glyph_vending) for x, y in ctx.get("distributori", [])]))
    strati.append(Strato("opere", "opere", [marker(*o["punto"], glyph_art) for o in ctx.get("opere", [])]))

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
            "fessura": ("#4D5D72", "#36465B", "#5B6B80"),
            "bianco": ("#F6F7F9", "#DDE0E5", "#FFFFFF"),
            "cemento": ("#DCD8D0", "#C4BFB5", "#E8E5DF"),     # the Trifoglio's concrete base
            "mosaico": ("#6B6E75", "#565960", "#7A7D84"),
            "stucco": ("#E4DFD3", "#CAC4B5", "#EEEAE1"),      # the Rettorato's grey-beige stone
            "pietra": ("#B4B2AA", "#9C9A92", "#C6C4BC"),
            "intonaco": ("#ECE7DC", "#D4CEC0", "#F2EFE8"),
            "ocra": ("#DDCCA6", "#C5B38B", "#E8DCC0")}         # the side blocks' warmer stone    # the courtyard wings' pale render     # and its grey glass mosaic
WINDOW_FRAME = "#F4F5F7"
STEEL = "#23272E"             # Viganò's black steel
STEEL_RED = "#C0503B"         # and his red
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


def exoskeleton(pts, top, others):
    """Viganò's steel: cruciform columns standing out from the visible façades, rising past
    the roof to a crowning frame, braced in V, with beams reaching back over the roof.
    Façades against another part of the building get none."""
    lines, heavy = [], []
    zt = top + ISO_SLAB + 16
    seg = lambda p, za, q, zb: f"M{fmt(iso(*p, za)[0])} {fmt(iso(*p, za)[1])}L{fmt(iso(*q, zb)[0])} {fmt(iso(*q, zb)[1])}"
    for a, c, _, _ in faces(pts, 0, 1):
        mid = ((a[0] + c[0]) / 2, (a[1] + c[1]) / 2)
        if math.dist(a, c) < 6 or any(math.dist(mid, nearest_edge(mid, [o])[0]) < 1.0 for o in others):
            continue
        n = outward(a, c, pts)
        length = math.dist(a, c)
        ux, uy = (c[0] - a[0]) / length, (c[1] - a[1]) / length
        k = max(1, round(length / 7.2))
        heads = []
        for i in range(k + 1):
            t = i * length / k
            p = (a[0] + ux * t + n[0] * 1.8, a[1] + uy * t + n[1] * 1.8)
            heavy.append(seg(p, 0, p, zt))
            back = (p[0] - n[0] * 5.5, p[1] - n[1] * 5.5)
            lines.append(seg(p, zt, back, zt))                        # beam back over the roof
            lines.append(seg(p, zt, (p[0] - n[0] * 1.8, p[1] - n[1] * 1.8), top + ISO_SLAB))  # strut to the roof
            heads.append(p)
        for p, q in zip(heads, heads[1:]):
            lines.append(seg(p, zt, q, zt))                           # the crown
            m = ((p[0] + q[0]) / 2, (p[1] + q[1]) / 2)
            lines.append(seg(p, zt, m, zt - 10) + seg(m, zt - 10, q, zt))  # V bracing
            lines.append(seg(p, top - 4, q, top - 4))                 # the beam the floors hang from
    return [f'<path d="{"".join(lines)}" stroke="{STEEL}" stroke-width="1.1" fill="none" stroke-linejoin="round"/>',
            f'<path d="{"".join(heavy)}" stroke="{STEEL}" stroke-width="2.6" fill="none"/>']


def sculpture_a(pts, at, top):
    """The "A" of architecture over Viganò's main entrance: three steel sections in red
    and black, standing before the façade at `at`."""
    q, a, c, _ = nearest_edge(at, [pts])
    n = outward(a, c, pts)
    length = math.dist(a, c)
    ux, uy = (c[0] - a[0]) / length, (c[1] - a[1]) / length
    p = lambda t, out=3.2: (q[0] + ux * t + n[0] * out, q[1] + uy * t + n[1] * out)
    base = 6.0
    # As on Via Ampère: an equilateral A, a thick black leg running a little past the
    # apex, a thinner red one, and the red crossbar over the opening it frames.
    out = 4.5
    zx = top * 0.92
    h = zx - base
    # Metres along the façade that look as wide as h is tall over √3: the legs at 60° as
    # seen, however the façade turns from the viewer.
    seen = math.dist(iso(0, 0), iso(ux, uy))
    half = h / seen / math.sqrt(3)
    apex = 3.2
    xs = lambda t0, t1, f: t0 + (t1 - t0) * f
    leg = lambda t0, t1, z1, w: [(*p(t0, out), base), (*p(t0 + w, out), base), (*p(t1 + w, out), z1), (*p(t1, out), z1)]
    tb, tr = apex + half, apex - half          # the black and red feet
    wb, wr = 2.2, 1.4
    black_leg = leg(tb - wb / 2, xs(tb, apex, 1.12) - wb / 2, base + h * 1.12, wb)
    red_leg = leg(tr - wr / 2, apex - wr / 2, zx, wr)
    # The opening: the ground storey, open under the A into the building.
    zp = base + 23
    f0, f1 = (zp - base) / h, (zp - base) / h + 0.09
    z0, z1 = base + h * f0, base + h * f1
    bar = [(*p(xs(tr, apex, f0), out), z0), (*p(xs(tb, apex, f0), out), z0),
           (*p(xs(tb, apex, f1), out), z1), (*p(xs(tr, apex, f1), out), z1)]
    o0, o1 = tr + 1.5, tb - 1.5
    face = lambda t0, t1, za, zb, d=0.15: [(*p(t0, d), za), (*p(t1, d), za), (*p(t1, d), zb), (*p(t0, d), zb)]
    line = lambda t0, t1, z, d=0.2: f'M{fmt(iso(*p(t0, d), z)[0])} {fmt(iso(*p(t0, d), z)[1])}L{fmt(iso(*p(t1, d), z)[0])} {fmt(iso(*p(t1, d), z)[1])}'
    span = o1 - o0
    opening = [f'<polygon points="{iso_poly(face(o0, o1, base, zp))}" fill="#1B1F25" opacity="0.55"/>',
               # the sunken floor seen through the well, warm with its lights
               f'<polygon points="{iso_poly(face(o0 + span * 0.08, o1 - span * 0.3, base + 1, base + 6, 0.1))}" fill="#3A332B"/>',
               # the silver ducts along the ceiling
               f'<polygon points="{iso_poly(face(o0, o1, zp - 4.2, zp - 2.4, 0.18))}" fill="#A9B0B9"/>',
               f'<polygon points="{iso_poly(face(o0, o1, zp - 2.0, zp - 0.6, 0.18))}" fill="#C9CED5"/>',
               # the white stair rising inside, on the red leg's side
               f'<polygon points="{iso_poly([(*p(o0 + span * 0.04, 0.17), base + 6), (*p(o0 + span * 0.2, 0.17), base + 6), (*p(o0 + span * 0.42, 0.17), zp - 5), (*p(o0 + span * 0.3, 0.17), zp - 5)])}" fill="#E4E6E9"/>',
               # lit glazing at the back of the hall
               f'<polygon points="{iso_poly(face(o0 + span * 0.5, o1 - span * 0.12, base + 7, base + 14, 0.16))}" fill="#E8C989" opacity="0.75"/>',
               # the black columns holding the building over the opening
               f'<path d="' + "".join(f'M{fmt(iso(*p(t, 0.2), base)[0])} {fmt(iso(*p(t, 0.2), base)[1])}V{fmt(iso(*p(t, 0.2), zp)[1])}'
                                      for t in (o0 + span * 0.33, o0 + span * 0.66)) + f'" stroke="{STEEL}" stroke-width="2.2"/>',
               # the orange railings of the walkway and the well
               f'<path d="{line(o0, o1, base + 6.5)}{line(o0, o1, base + 4.5)}" stroke="#E2672A" stroke-width="1.1" fill="none"/>']
    return [*opening,
            f'<polygon points="{iso_poly(red_leg)}" fill="{STEEL_RED}"/>',
            f'<polygon points="{iso_poly(bar)}" fill="{STEEL_RED}"/>',
            f'<polygon points="{iso_poly(black_leg)}" fill="{STEEL}"/>']


def ornaments(part, own, turn, top, z0):
    """A palazzo's crown and steps: curved pediments over the front (`frontone`, one or
    a list: a point on it, its width, how far below the top it starts), arched doorways
    (`portoni`), obelisks, a clock turret, and a flight of steps before the door
    (`scalinata`: a point on the front, width, depth, steps)."""
    out = []
    if part.get("frontone"):
        for f in part["frontone"] if isinstance(part["frontone"], list) else [part["frontone"]]:
            q, a, c, _ = nearest_edge(turn(tuple(f["punto"])), [own])
            n = outward(a, c, own)
            L = math.dist(a, c)
            u = ((c[0] - a[0]) / L, (c[1] - a[1]) / L)
            w, zb, rise = f.get("larghezza", 10) / 2, top - f.get("sotto", 0), f.get("freccia", 6)
            at = lambda t, zz, o=0.6: (q[0] + u[0] * t + n[0] * o, q[1] + u[1] * t + n[1] * o, zz)
            arc = [at(w * math.cos(th), zb + rise * math.sin(th)) for th in [math.pi * k / 16 for k in range(17)]]
            inner = [at(0.82 * w * math.cos(th), zb + rise * 0.72 * math.sin(th)) for th in [math.pi * k / 16 for k in range(16, -1, -1)]]
            out.append(f'<polygon points="{iso_poly([at(w, zb), *arc, at(-w, zb)])}" fill="#E4DFD3" stroke="#B9B2A2" stroke-width="0.4"/>')
            out.append(f'<polygon points="{iso_poly(arc[1:-1] + inner[1:-1])}" fill="#EFEBE2" stroke="#C7C0B0" stroke-width="0.25"/>')
            crest = [at(-1.3, zb - 4), at(1.3, zb - 4), at(1.5, zb + 1.5), at(0, zb + 4), at(-1.5, zb + 1.5)]
            out.append(f'<polygon points="{iso_poly(crest)}" fill="#CFC8B7" stroke="#A9A291" stroke-width="0.3"/>')
    if part.get("portoni"):
        # Arched doorways in the middle of the front, iron gates in them.
        d = part["portoni"]
        q, a, c, _ = nearest_edge(turn(tuple(d["punto"])), [own])
        n = outward(a, c, own)
        L = math.dist(a, c)
        u = ((c[0] - a[0]) / L, (c[1] - a[1]) / L)
        k, step, hz, zb = d.get("n", 3), d.get("passo", 4.9), d.get("h", 10), z0 + d.get("da", 4)
        for i in range(k):
            t = (i - (k - 1) / 2) * step
            at = lambda tt, zz: (q[0] + u[0] * tt + n[0] * 0.25, q[1] + u[1] * tt + n[1] * 0.25, zz)
            w = 1.3
            shape = [at(t - w, zb), at(t + w, zb), at(t + w, zb + hz)]
            shape += [at(t + w * math.cos(th), zb + hz + w * ISO_SCALE * math.sin(th)) for th in [math.pi * j / 8 for j in range(1, 8)]]
            shape += [at(t - w, zb + hz)]
            out.append(f'<polygon points="{iso_poly(shape)}" fill="#2C3138" stroke="#E9E4D8" stroke-width="0.6"/>')
            bars = "".join(f'M{fmt(iso(*at(t + dt, zb)[:2], zb)[0])} {fmt(iso(*at(t + dt, zb)[:2], zb)[1])}'
                           f'V{fmt(iso(*at(t + dt, zb)[:2], zb + hz)[1])}' for dt in (-0.65, 0, 0.65))
            out.append(f'<path d="{bars}" stroke="#5B636D" stroke-width="0.35"/>')
    def frame(p):
        q, a, c, _ = nearest_edge(turn(tuple(p)), [own])
        n = outward(a, c, own)
        L = math.dist(a, c)
        u = ((c[0] - a[0]) / L, (c[1] - a[1]) / L)
        if (u[0] - u[1]) < 0:
            u = (-u[0], -u[1])
        return q, u, n
    for b in part.get("balconi_extra", []):
        # A stone balcony over a door: a slab out from the wall, a balustrade on it.
        q, u, n = frame(b["punto"])
        w, zb, d = b.get("larghezza", 6) / 2, z0 + b["z"], b.get("sporto", 1.6)
        slab = [(q[0] + u[0] * t + n[0] * o, q[1] + u[1] * t + n[1] * o) for t, o in ((-w, 0), (w, 0), (w, d), (-w, d))]
        out += prism(ccw(slab), zb, zb + 0.8, ("#E7DECB", "#CDBF9F"), "#F1EADB")
        front = [(q[0] + u[0] * t + n[0] * d, q[1] + u[1] * t + n[1] * d) for t in (-w, w)]
        out.append(f'<polygon points="{iso_poly([(*front[0], zb + 0.8), (*front[1], zb + 0.8), (*front[1], zb + 3), (*front[0], zb + 3)])}" '
                   f'fill="#EDE5D3" stroke="#BFB297" stroke-width="0.3" stroke-dasharray="0.3 0.5"/>')
    if part.get("scritta"):
        # Lettering along the frieze, set on the wall's plane.
        t = part["scritta"]
        q, u, n = frame(t["punto"])
        px, py = iso(q[0] + n[0] * 0.3, q[1] + n[1] * 0.3, z0 + t["z"])
        ax, ay = (u[0] - u[1]) * COS30, (u[0] + u[1]) * SIN30
        out.append(f'<text transform="matrix({fmt(ax)} {fmt(ay)} 0 1 {fmt(px)} {fmt(py)})" font-family="Georgia, serif" '
                   f'font-size="{t.get("corpo", 2.6)}" letter-spacing="0.15" text-anchor="middle" fill="#6E6450">{t["testo"]}</text>')
    for f in part.get("bandiere", []):
        # Flagpoles slanting out from the balcony, the flags hanging from them.
        q, u, n = frame(f["punto"])
        zb = z0 + f["z"]
        for k, cols in enumerate(f["colori"]):
            dt = (k - (len(f["colori"]) - 1) / 2) * 2.4
            foot = (q[0] + u[0] * dt + n[0] * 0.4, q[1] + u[1] * dt + n[1] * 0.4, zb)
            tip = (foot[0] + n[0] * 4, foot[1] + n[1] * 4, zb + 6)
            (fx, fy), (tx, ty) = iso(*foot), iso(*tip)
            out.append(f'<path d="M{fmt(fx)} {fmt(fy)}L{fmt(tx)} {fmt(ty)}" stroke="#4A4A48" stroke-width="0.35"/>')
            stripes = len(cols)
            for i, col in enumerate(cols):
                s0, s1 = i / stripes, (i + 1) / stripes
                pt = lambda s, dz: iso(tip[0] - n[0] * 0.2 + u[0] * 4.5 * s, tip[1] - n[1] * 0.2 + u[1] * 4.5 * s, tip[2] - dz * 1.4 - s * 0.8)
                quad = [pt(s0, 0), pt(s1, 0), pt(s1, 2.4), pt(s0, 2.4)]
                out.append(f'<polygon points="{" ".join(f"{fmt(a)},{fmt(b)}" for a, b in quad)}" fill="{col}" stroke="#8A8A86" stroke-width="0.12"/>')
    out += pinnacles(part, turn, top)
    if part.get("scalinata"):
        s = part["scalinata"]
        q, a, c, _ = nearest_edge(turn(tuple(s["punto"])), [own])
        n = outward(a, c, own)
        L = math.dist(a, c)
        u = ((c[0] - a[0]) / L, (c[1] - a[1]) / L)
        w, deep, k = s.get("larghezza", 14) / 2, s.get("profondita", 4), s.get("gradini", 4)
        for i in range(k):
            o0, o1 = deep * i / k, deep
            zz = z0 * (k - i) / k
            step = [(q[0] + u[0] * t + n[0] * o, q[1] + u[1] * t + n[1] * o) for t, o in ((-w, o0), (w, o0), (w, o1), (-w, o1))]
            out += prism(ccw(step), 0, zz, ("#C9C7BF", "#B1AFA7"), "#D8D6CF")
    return out


def pinnacles(b, turn, top):
    """Stone obelisks on the roof's corners and a clock turret, farthest first."""
    out = []
    # A pinnacle is [x, y] or [x, y, height above the roof].
    items = [("obelisco", turn(tuple(p[:2])), p[2] if len(p) > 2 else 16) for p in b.get("pinnacoli", [])]
    if b.get("orologio"):
        items.append(("orologio", turn(tuple(b["orologio"])), 0))
    for kind, (x, y), tall in sorted(items, key=lambda it: it[1][0] + it[1][1]):
        if kind == "obelisco":
            out += prism([(x - 0.7, y - 0.7), (x + 0.7, y - 0.7), (x + 0.7, y + 0.7), (x - 0.7, y + 0.7)],
                         top, top + 3, ("#EFE7D5", "#D3C7AB"), "#F3EDDF")
            tip = iso(x, y, top + tall)
            l, r, f = iso(x - 0.5, y + 0.5, top + 3), iso(x + 0.5, y - 0.5, top + 3), iso(x + 0.5, y + 0.5, top + 3)
            out.append(f'<polygon points="{fmt(l[0])},{fmt(l[1])} {fmt(f[0])},{fmt(f[1])} {fmt(tip[0])},{fmt(tip[1])}" fill="#E9E0CB"/>')
            out.append(f'<polygon points="{fmt(f[0])},{fmt(f[1])} {fmt(r[0])},{fmt(r[1])} {fmt(tip[0])},{fmt(tip[1])}" fill="#CFC2A4"/>')
        else:
            box = [(x - 2, y - 2), (x + 2, y - 2), (x + 2, y + 2), (x - 2, y + 2)]
            out += prism(box, top, top + 9, ("#EFE7D5", "#D3C7AB"), "#F3EDDF")
            cx, cy = iso(x - 2.05, y, top + 5)
            out.append(f'<ellipse cx="{fmt(cx)}" cy="{fmt(cy)}" rx="1.6" ry="2.6" fill="#FFFFFF" stroke="#8C7F64" stroke-width="0.4"/>'
                       f'<path d="M{fmt(cx)} {fmt(cy)}V{fmt(cy - 1.8)}M{fmt(cx)} {fmt(cy)}L{fmt(cx + 0.9)} {fmt(cy + 0.5)}" stroke="#3B3A36" stroke-width="0.35"/>')
            out += prism([(x - 2.4, y - 2.4), (x + 2.4, y - 2.4), (x + 2.4, y + 2.4), (x - 2.4, y + 2.4)],
                         top + 9, top + 10.5, ("#E7DDC6", "#CDBF9F"), "#F3EDDF")
    return out


def lamellae(b, pts, turn, z0, top):
    """Renzo Piano's screen for 16B: a dense row of thin white steel blades standing
    `distanza` metres out from the glass, from the first floor to `sopra` above the
    roof, tied at the top; along `ciechi` (edges of `pianta`) a blind white wall
    instead, out to the same line and from the ground."""
    cfg = b["lamelle"]
    d, step, above = cfg.get("distanza", 2.0), cfg.get("passo", 0.6), cfg.get("sopra", 8)
    z1 = z0 + cfg.get("da", 18)
    shell = offset(pts, d)
    raw = [turn(p) for p in b["pianta"]]
    blind = []
    for i in cfg.get("ciechi", []):
        a, c = raw[i], raw[(i + 1) % len(raw)]
        blind.append(((a[0] + c[0]) / 2, (a[1] + c[1]) / 2, (c[0] - a[0], c[1] - a[1])))
    def is_blind(a, c):
        m = ((a[0] + c[0]) / 2, (a[1] + c[1]) / 2)
        for bx, by, (vx, vy) in blind:
            cross = abs(vx * (c[1] - a[1]) - vy * (c[0] - a[0])) / (math.hypot(vx, vy) * math.dist(a, c))
            if cross < 0.05 and math.dist(m, (bx, by)) < d + 3:
                return True
        return False
    out = []
    for a, c, left, _ in faces(shell, 0, 1):
        if is_blind(a, c):
            q = [(*a, 0), (*c, 0), (*c, top + 2.2), (*a, top + 2.2)]
            out.append(f'<polygon points="{iso_poly(q)}" fill="{"#EEF0F3" if left else "#DADEE3"}"/>')
            k = max(1, int(math.dist(a, c) / 3.0))
            joints = "".join(f"M{fmt(iso(a[0] + (c[0] - a[0]) * i / k, a[1] + (c[1] - a[1]) * i / k, 0)[0])} "
                             f"{fmt(iso(a[0] + (c[0] - a[0]) * i / k, a[1] + (c[1] - a[1]) * i / k, 0)[1])}"
                             f"V{fmt(iso(a[0] + (c[0] - a[0]) * i / k, a[1] + (c[1] - a[1]) * i / k, top + 2.2)[1])}"
                             for i in range(1, k))
            out.append(f'<path d="{joints}" stroke="#C3C8CF" stroke-width="0.35"/>')
            continue
        k = max(1, int(math.dist(a, c) / step))
        blades, ties = [], []
        for i in range(k + 1):
            x, y = a[0] + (c[0] - a[0]) * i / k, a[1] + (c[1] - a[1]) * i / k
            (px, py0), (_, py1) = iso(x, y, z1), iso(x, y, top + above)
            blades.append(f"M{fmt(px)} {fmt(py0)}V{fmt(py1)}")
        for zz in (top + above, top + 3):
            (x0, y0), (x1, y1) = iso(*a, zz), iso(*c, zz)
            ties.append(f"M{fmt(x0)} {fmt(y0)}L{fmt(x1)} {fmt(y1)}")
        out.append(f'<path d="{"".join(blades)}" stroke="#F7F8FA" stroke-width="0.45" opacity="0.95"/>')
        out.append(f'<path d="{"".join(ties)}" stroke="#E6E9ED" stroke-width="0.9"/>')
    return out


def palazzo(pts, z, h, lit, colors, finestre, bugnato=False, bay=4.4, ordine=False):
    """An eclectic palazzo storey, face by face, far ones first: the wall, its rusticated
    joints, a lighter pilaster at each bay, and in each bay a window, `archi` (round
    arched), `balconi` (arched, over a little balustraded balcony) or `rette` (square)."""
    out = []
    glass = "#F2D492" if lit else "#3E4652"
    frame = "#F7F2E6"
    for a, c, left, q in faces(pts, z, z + h):
        out.append(f'<polygon points="{iso_poly(q)}" fill="{colors[0] if left else colors[1]}"/>')
        n = outward(a, c, pts)
        length = math.dist(a, c)
        u = ((c[0] - a[0]) / length, (c[1] - a[1]) / length)
        at = lambda t, zz, o=0.05: (a[0] + u[0] * t + n[0] * o, a[1] + u[1] * t + n[1] * o, zz)
        if bugnato:
            joints = "".join(f'M{fmt(iso(*at(0, zz)[:2], zz)[0])} {fmt(iso(*at(0, zz)[:2], zz)[1])}'
                             f'L{fmt(iso(*at(length, zz)[:2], zz)[0])} {fmt(iso(*at(length, zz)[:2], zz)[1])}'
                             for zz in [z + k * 2.4 for k in range(1, int(h / 2.4))])
            out.append(f'<path d="{joints}" stroke="#B9AD92" stroke-width="0.35"/>')
        k = int(length / bay)
        if k < 1:
            continue
        pad = (length - k * bay) / 2
        for i in range(k + 1):                          # pilasters
            t = pad + i * bay
            wp = 0.55 if ordine else 0.3           # a giant order: broad pilasters, a capital on top
            p = [at(t - wp, z, 0.2), at(t + wp, z, 0.2), at(t + wp, z + h, 0.2), at(t - wp, z + h, 0.2)]
            out.append(f'<polygon points="{iso_poly(p)}" fill="{colors[2]}" opacity="0.9"/>')
            if ordine:
                cap = [at(t - wp - 0.25, z + h - 1.6, 0.3), at(t + wp + 0.25, z + h - 1.6, 0.3), at(t + wp + 0.25, z + h, 0.3), at(t - wp - 0.25, z + h, 0.3)]
                out.append(f'<polygon points="{iso_poly(cap)}" fill="#D3CCBC"/>')
        for i in range(k):
            t = pad + i * bay + bay / 2
            w = 0.8 if finestre != "rette" else 0.7
            z0, z1 = z + h * (0.18 if finestre != "rette" else 0.25), z + h * (0.68 if finestre != "rette" else 0.8)
            shape = [at(t - w, z0), at(t + w, z0), at(t + w, z1)]
            if finestre != "rette":
                r = w * ISO_SCALE
                shape += [at(t + w * math.cos(th), z1 + r * math.sin(th)) for th in [math.pi * j / 8 for j in range(1, 8)]]
            shape += [at(t - w, z1)]
            out.append(f'<polygon points="{iso_poly(shape)}" fill="{glass}" stroke="{frame}" stroke-width="0.7"/>')
            if finestre == "balconi":
                sill = [at(t - w - 0.5, z0, 0.05), at(t + w + 0.5, z0, 0.05), at(t + w + 0.5, z0, 0.9), at(t - w - 0.5, z0, 0.9)]
                out.append(f'<polygon points="{iso_poly(sill)}" fill="{colors[2]}"/>')
                rail = [at(t - w - 0.5, z0, 0.9), at(t + w + 0.5, z0, 0.9), at(t + w + 0.5, z0 + 3, 0.9), at(t - w - 0.5, z0 + 3, 0.9)]
                out.append(f'<polygon points="{iso_poly(rail)}" fill="{colors[2]}" stroke="#C9BC9E" stroke-width="0.3"/>')
    out.append(f'<polygon points="{iso_poly([(x, y, z + h) for x, y in pts])}" fill="{colors[2]}"/>')
    return out


def punched(pts, z, h, rows, lit, colors, big=False):
    """Windows cut into a blind wall, face by face, far ones first so nearer faces
    cover them: `rows` rows of small horizontal windows in white frames, every
    so often a tall strip of glass block, as on the Trifoglio. `big` draws one
    row of large ground-floor windows instead."""
    out = []
    glass = "#F2D492" if lit else "#9DB4CC"
    for a, c, left, q in faces(pts, z, z + h):
        # The wall again, so a nearer face covers a farther one's windows.
        out.append(f'<polygon points="{iso_poly(q)}" fill="{colors[0] if left else colors[1]}"/>')
        n = outward(a, c, pts)
        length = math.dist(a, c)
        u = ((c[0] - a[0]) / length, (c[1] - a[1]) / length)
        at = lambda t, zz: (a[0] + u[0] * t + n[0] * 0.05, a[1] + u[1] * t + n[1] * 0.05, zz)
        step = 4.2
        k = int((length - 2) / step)
        if k < 1:
            continue
        pad = (length - k * step) / 2
        rect = lambda t0, t1, z0, z1: (f'<polygon points="{iso_poly([at(t0, z0), at(t1, z0), at(t1, z1), at(t0, z1)])}" '
                                       f'fill="{glass}" stroke="{WINDOW_FRAME}" stroke-width="0.9"/>')
        for i in range(k):
            t = pad + i * step
            if big:
                out.append(rect(t + 0.6, t + step - 0.6, z + h * 0.18, z + h * 0.78))
                continue
            seed = (i * 7 + int(length)) % 9
            if seed == 4:
                out.append(rect(t + 1.8, t + 2.4, z + h * 0.12, z + h * 0.88))      # glass block
                continue
            for r in range(rows):
                if (seed + r * 3) % 5 == 0:
                    continue                                                    # blind here
                zr = z + h * (r + 0.42) / rows
                w = 2.6 if (seed + r) % 3 else 1.4
                out.append(rect(t + 0.8, t + 0.8 + w, zr, zr + min(4.0, h / rows * 0.32)))
    out.append(f'<polygon points="{iso_poly([(x, y, z + h) for x, y in pts])}" fill="{colors[2]}"/>')
    return out


def draw_profile(b, pts, turn, z, storey, door, strati, zmid, profilo=None, parte=""):
    """Draws the bands of `profilo`, bottom up, from height z; returns the top.

    A band is a floor (`piano`) drawn as `vetro` (a glazed storey), `portico` (an open ground floor, its glass set back
    `arretrato` metres), `pieno` (a
    blind volume in `rivestimento` ceramica or mattone), `fessura` (a thin dark
    glazed slot) or `sporto` (a blind volume overhanging the one below by
    `sporto` metres, casting its shadow on it; lit, its skylights glow over the
    classrooms). `h` is its height in drawing units, `sagoma: propria` sets it on
    the floor's own outline, set back on the roof of what is below."""
    tag = f"-{parte}" if parte else ""
    below, roofed, skylights = pts, False, []
    bands = profilo or b["profilo"]
    tiles = next((x for x in bands if x["tipo"] == "coppi"), None)
    for band in [x for x in bands if x is not tiles]:
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
            strati.append(Strato("tetto" + tag, "edifici", roof))
            for c, lights in skylights:
                strati.append(Strato(f"{c}-lucernari{tag}", "piani", lights(False), piano=c, lit=lights(True)))
            skylights.clear()
            z, roofed = z + ISO_SLAB, True
        def body(lit):
            if kind == "vetro" and band.get("ballatoio"):
                # A glazed storey behind a walkway: the slab running out in front, a glass
                # balustrade along its edge.
                deck = offset(own, band["ballatoio"])
                out = prism(deck, z, z + 1.6, ("#D9DDE2", "#C3C8CF"), "#E9ECEF")
                out += storey(z + 1.6, lit, h - 1.6, own, band.get("telaio"))
                for a, c, _, q in faces(deck, z + 1.6, z + 5.5):
                    out.append(f'<polygon points="{iso_poly(q)}" fill="#DDE7EF" opacity="0.45" stroke="#B9C2CB" stroke-width="0.5"/>')
                return out
            if kind == "vetro":
                return storey(z, lit, h, own, band.get("telaio"))
            if kind == "palazzo":
                colors = CLADDING[band.get("rivestimento", "stucco")]
                return palazzo(own, z, h, lit, colors, band.get("finestre", "archi"), band.get("bugnato", False),
                               band.get("campata", 4.4), band.get("ordine", False))
            if kind == "cornicione":
                # A heavy cornice running out over the wall, its shadow beneath.
                out = []
                for a, c, _, _ in faces(below, 0, 1):
                    q = [(a[0], a[1], z - 3), (c[0], c[1], z - 3), (c[0], c[1], z), (a[0], a[1], z)]
                    out.append(f'<polygon points="{iso_poly(q)}" fill="{SHADOW}" opacity="0.25"/>')
                return out + prism(offset(own, band.get("sporto", 0.8)), z, z + h, ("#F1EADB", "#D9CDB2"), "#F5F0E4")
            if kind == "balaustra":
                # The parapet: a stone balustrade, its posts and balusters.
                out = prism(own, z, z + h, ("#EFE7D5", "#D8CCB0"), "#F3EDDF")
                # The flat terrace behind it, leaded and darker than the stone.
                out.append(f'<polygon points="{iso_poly([(x, y, z + h) for x, y in offset(own, -0.9)])}" fill="#A9A79F"/>')
                bars = []
                for a, c, _, _ in faces(own, 0, 1):
                    k = max(1, int(math.dist(a, c) / 0.7))
                    for i in range(1, k):
                        x, y = a[0] + (c[0] - a[0]) * i / k, a[1] + (c[1] - a[1]) * i / k
                        (px, py0), (_, py1) = iso(x, y, z + 0.8), iso(x, y, z + h - 1)
                        bars.append(f"M{fmt(px)} {fmt(py0)}V{fmt(py1)}")
                out.append(f'<path d="{"".join(bars)}" stroke="#BFB297" stroke-width="0.3"/>')
                # A stone ball on a post every few metres along the front.
                for a, c, _, _ in faces(own, 0, 1):
                    k = max(1, int(math.dist(a, c) / band.get("passo_sfere", 4.9)))
                    for i in range(k + 1):
                        x, y = a[0] + (c[0] - a[0]) * i / k, a[1] + (c[1] - a[1]) * i / k
                        px, py = iso(x, y, z + h)
                        out.append(f'<rect x="{fmt(px - 0.7)}" y="{fmt(py - 1.2)}" width="1.4" height="1.2" fill="#E2D8C2"/>'
                                   f'<circle cx="{fmt(px)}" cy="{fmt(py - 2.0)}" r="1.15" fill="#EFE8D8" stroke="#B9AC8E" stroke-width="0.35"/>')
                return out
            if kind == "opalino":
                # Milky white glass panels between thin mullions; lit, they glow.
                colors = ("#FBE6B4", "#EED39A", "#F6F7F9") if lit else ("#F1F3F6", "#DCE1E7", "#F6F7F9")
                out = prism(own, z, z + h, colors[:2], colors[2])
                bars = []
                for a, c, _, _ in faces(own, 0, 1):
                    k = max(1, int(math.dist(a, c) / 2.4))
                    for i in range(1, k):
                        x, y = a[0] + (c[0] - a[0]) * i / k, a[1] + (c[1] - a[1]) * i / k
                        (px, py0), (_, py1) = iso(x, y, z), iso(x, y, z + h)
                        bars.append(f"M{fmt(px)} {fmt(py0)}V{fmt(py1)}")
                out.append(f'<path d="{"".join(bars)}" stroke="#9AA3AD" stroke-width="0.6"/>')
                return out
            if kind == "portico":
                # An open ground floor: the glass set back under the floors above, in their
                # shadow, the paving running in to it, ducts along the ceiling and orange
                # railings at the edge.
                back = band.get("arretrato", 3.0)
                inner = offset(own, -back)
                outer = lambda q: nearest_edge(q, [own])[0]
                out = [f'<polygon points="{iso_poly([(x, y, z) for x, y in own])}" fill="#C3C8CF"/>']
                out += storey(z, lit, h, inner, band.get("telaio"))
                for a, c, _, _ in faces(inner, 0, 1):
                    q = [(*a, z), (*c, z), (*c, z + h), (*a, z + h)]
                    if lit:
                        # Lit, the hall throws its light out onto the paving under the floors above.
                        pool = [(*a, z), (*c, z), (*outer(c), z), (*outer(a), z)]
                        out.append(f'<polygon points="{iso_poly(pool)}" fill="#F3D9A0" opacity="0.55"/>')
                    else:
                        out.append(f'<polygon points="{iso_poly(q)}" fill="#14181E" opacity="0.5"/>')
                line = lambda a, c, zz: f"M{fmt(iso(*a, zz)[0])} {fmt(iso(*a, zz)[1])}L{fmt(iso(*c, zz)[0])} {fmt(iso(*c, zz)[1])}"
                mid = offset(own, -1.2)
                ducts = "".join(line(a, c, z + h - 2.2) for a, c, _, _ in faces(mid, 0, 1))
                ducts2 = "".join(line(a, c, z + h - 4.4) for a, c, _, _ in faces(mid, 0, 1))
                out.append(f'<path d="{ducts2}" stroke="#9AA2AC" stroke-width="1.8" fill="none"/>')
                out.append(f'<path d="{ducts}" stroke="#C9CED5" stroke-width="1.8" fill="none"/>')
                rail = "".join(line(a, c, zz) for a, c, _, _ in faces(own, 0, 1) for zz in (z + 2.2, z + 4.2))
                out.append(f'<path d="{rail}" stroke="#E2672A" stroke-width="0.9" fill="none"/>')
                return out
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
            if kind == "pieno" and band.get("finestre"):
                out += punched(own, z, h, band.get("file", 1), lit, colors, band["finestre"] == "grandi")
            elif kind == "pieno" and band.get("rivestimento") not in ("mosaico",):
                # The cladding's courses, faint.
                courses = []
                for a, c, _, _ in faces(own, 0, 1):
                    for k in range(1, int(h / 3)):
                        (x0, y0), (x1, y1) = iso(*a, z + k * 3), iso(*c, z + k * 3)
                        courses.append(f"M{fmt(x0)} {fmt(y0)}L{fmt(x1)} {fmt(y1)}")
                out.append(f'<path d="{"".join(courses)}" stroke="#FFFFFF" stroke-width="0.5" opacity="0.35"/>')
            return out
        if not band.get("decoro"):              # a cornice or a parapet is no floor of its own
            zmid.setdefault(csip, z + h / 2)
        strati.append(Strato(csip + tag, "piani", body(False), ["iso-glass-l", "iso-glass-r"], piano=csip,
                             lit=body(True), lit_defs=["iso-lit-l", "iso-lit-r", "iso-lit-glow"]))
        if band.get("ingresso"):
            strati.append(Strato("ingresso", "ingressi", door))
        if kind == "sporto":
            # Its classrooms are lit from above: skylights over each, on the roof drawn next.
            def lights(lit, zt=z + h + ISO_SLAB, csip=csip):
                out = []
                for x0, y0, x1, y1 in floor_rooms(b, csip, turn):
                    cx, cy, w, d = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) * 0.6, (y1 - y0) * 0.6
                    if not inside((cx, cy), pts):
                        continue                  # a classroom under another part's roof
                    sky = [(cx - w / 2, cy - d / 2), (cx + w / 2, cy - d / 2), (cx + w / 2, cy + d / 2), (cx - w / 2, cy + d / 2)]
                    out.append(f'<polygon points="{iso_poly([(x, y, zt) for x, y in sky])}" '
                               f'fill="{SKYLIGHT_LIT if lit else SKYLIGHT}" opacity="{0.95 if lit else 0.8}"/>')
                return out
            skylights.append((csip, lights))
            own = offset(own, band.get("sporto", 2.0))
        z += h
        below = own
    if tiles:
        # A hipped roof in red tiles: each side slopes up from the eaves to a ridge set in.
        eaves, ridge = offset(below, 0.6), offset(below, -tiles.get("rientro", 4.0))
        zr = z + tiles["h"]
        roof = []
        # Every slope shows from above, the far ones too: drawn far first, lit by their aspect.
        slopes = []
        for i in range(len(eaves)):
            j = (i + 1) % len(eaves)
            a, c = eaves[i], eaves[j]
            nx, ny = outward(a, c, eaves)
            fill = "#C2704A" if ny > nx and nx + ny > 0 else "#A85A38" if nx + ny > 0 else "#D58A63"
            slopes.append(((a[0] + c[0] + a[1] + c[1]) / 2, [(*a, z), (*c, z), (*ridge[j], zr), (*ridge[i], zr)], fill))
        for _, q, fill in sorted(slopes, key=lambda s: s[0]):
            roof.append(f'<polygon points="{iso_poly(q)}" fill="{fill}"/>')
        if tiles.get("lucernario"):
            # The middle of the roof is glass: a skylit hall below, ribbed in steel.
            roof.append(f'<polygon points="{iso_poly([(x, y, zr) for x, y in ridge])}" fill="#8EA3B7" stroke="#5E6B78" stroke-width="0.6"/>')
            xs, ys = [p[0] for p in ridge], [p[1] for p in ridge]
            ribs = []
            for k in range(1, 6):
                x = min(xs) + (max(xs) - min(xs)) * k / 6
                (a0, b0), (a1, b1) = iso(x, min(ys), zr), iso(x, max(ys), zr)
                ribs.append(f"M{fmt(a0)} {fmt(b0)}L{fmt(a1)} {fmt(b1)}")
            (a0, b0), (a1, b1) = iso(min(xs), (min(ys) + max(ys)) / 2, zr), iso(max(xs), (min(ys) + max(ys)) / 2, zr)
            ribs.append(f"M{fmt(a0)} {fmt(b0)}L{fmt(a1)} {fmt(b1)}")
            roof.append(f'<path d="{"".join(ribs)}" stroke="#E8ECEF" stroke-width="0.7"/>')
        else:
            roof.append(f'<polygon points="{iso_poly([(x, y, zr) for x, y in ridge])}" fill="#CF7E57"/>')
        z = zr
    elif b.get("gronda"):
        # A thin pale roof overhanging every side by `gronda` metres, its shadow on the wall.
        roof = []
        for a, c, _, _ in faces(below, 0, 1):
            q = [(a[0], a[1], z - 7), (c[0], c[1], z - 7), (c[0], c[1], z), (a[0], a[1], z)]
            roof.append(f'<polygon points="{iso_poly(q)}" fill="{SHADOW}" opacity="0.3"/>')
        roof += prism(offset(below, b["gronda"]), z, z + 2.2, ("#B9BDC4", "#A3A8B0"), "#E3E5E8")
    elif bands[-1]["tipo"] == "balaustra":
        roof = []  # a terrace behind the balustrade, drawn with it
    else:
        roof = prism(below, z, z + ISO_SLAB, (ISO_SLAB_LEFT, ISO_SLAB_RIGHT), ISO_SLAB_TOP)
        roof.append(f'<polygon points="{iso_poly([(x, y, z + ISO_SLAB) for x, y in offset(below, -1.6)])}" fill="{ISO_ROOF_INNER}"/>')
    strati.append(Strato("tetto" + tag, "edifici", roof))
    for c, lights in skylights:
        strati.append(Strato(f"{c}-lucernari{tag}", "piani", lights(False), piano=c, lit=lights(True)))
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
    if ent and "lato" in ent:
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
        if ent.get("rampa"):
            # A raised ground floor, as the plans draw it: a landing before the door, ramps
            # down from its ends along the walls, and under the landing, between its posts,
            # the glazed entrance to the floor below.
            r = ent["rampa"]
            zg = base_h + r.get("quota", 5)
            land = [turn(tuple(p)) for p in r["pianerottolo"]]
            ramps = [[turn(tuple(p)) for p in q] for q in r["rampe"]]
            P = lambda s, o, z: (ex + tx * s + nx * o, ey + ty * s + ny * o, z)
            pale, edge = "#E9E6E0", "#BDB7AC"
            half = r.get("sotto", 3.5)
            door.append(f'<polygon points="{iso_poly([P(half, 0.05, 0), P(-half, 0.05, 0), P(-half, 0.05, zg - 1.4), P(half, 0.05, zg - 1.4)])}" fill="#2B3644"/>')
            mull = "".join(f'M{fmt(iso(*P(s0, 0.06, 0)[:2])[0])} {fmt(iso(*P(s0, 0.06, 0)[:2])[1])}V{fmt(iso(*P(s0, 0.06, 0)[:2], zg - 1.4)[1])}'
                           for s0 in [-half + i * 2 * half / 4 for i in range(1, 4)])
            door.append(f'<path d="{mull}" stroke="#8C96A3" stroke-width="0.6"/>')
            door.append(f'<polygon points="{iso_poly([P(1.5, 0.05, zg), P(-1.5, 0.05, zg), P(-1.5, 0.05, zg + ISO_FLOOR * 0.6), P(1.5, 0.05, zg + ISO_FLOOR * 0.6)])}" fill="{ISO_DOOR}"/>')
            # The landing's posts, along its outer edge.
            outer = max(zip(land, land[1:] + land[:1]), key=lambda e: math.dist(*e) * (1 if outward(e[0], e[1], land)[0] + outward(e[0], e[1], land)[1] > 0 else 0))
            posts = []
            for i in range(5):
                x, y = outer[0][0] + (outer[1][0] - outer[0][0]) * (i + 0.5) / 5, outer[0][1] + (outer[1][1] - outer[0][1]) * (i + 0.5) / 5
                x, y = x - nx * 0.5, y - ny * 0.5
                posts.append(f'M{fmt(iso(x, y, 0)[0])} {fmt(iso(x, y, 0)[1])}V{fmt(iso(x, y, zg - 1.2)[1])}')
            door.append(f'<path d="{"".join(posts)}" stroke="#D2CEC6" stroke-width="2.2"/>')
            def slab(top3):
                out = []
                for i in range(len(top3)):
                    a3, c3 = top3[i], top3[(i + 1) % len(top3)]
                    out.append(f'<polygon points="{iso_poly([a3, c3, (c3[0], c3[1], c3[2] - 1.2), (a3[0], a3[1], a3[2] - 1.2)])}" fill="{edge}"/>')
                out.append(f'<polygon points="{iso_poly(top3)}" fill="{pale}"/>')
                return out
            line = lambda p3, q3: f'M{fmt(iso(*p3)[0])} {fmt(iso(*p3)[1])}L{fmt(iso(*q3)[0])} {fmt(iso(*q3)[1])}'
            pieces = [(sum(x + y for x, y in land) / len(land), slab([(x, y, zg) for x, y in land])
                       + [f'<path d="{line((*outer[0], zg + 3), (*outer[1], zg + 3))}" stroke="#FFFFFF" stroke-width="0.9"/>'])]
            for q in ramps:
                # The first two corners meet the landing, the last two the ground.
                top3 = [(*q[0], zg), (*q[1], zg), (*q[2], 0), (*q[3], 0)]
                rails = line((q[1][0], q[1][1], zg + 3), (q[2][0], q[2][1], 3)) + line((q[0][0], q[0][1], zg + 3), (q[3][0], q[3][1], 3))
                pieces.append((sum(x + y for x, y in q) / 4, slab(top3) + [f'<path d="{rails}" stroke="#FFFFFF" stroke-width="0.9"/>']))
            for _, piece in sorted(pieces, key=lambda p: p[0]):
                door += piece
        else:
            door.append(f'<polygon points="{iso_poly(q)}" fill="{ISO_DOOR}"/>')
        canopy = ccw([(ex + tx * 3, ey + ty * 3), (ex - tx * 3, ey - ty * 3),
                      (ex - tx * 3 + nx * 3, ey - ty * 3 + ny * 3), (ex + tx * 3 + nx * 3, ey + ty * 3 + ny * 3)])
        if not ent.get("rampa"):
            door += prism(canopy, dz1, dz1 + 3, ("#E8EAEE", "#C9CED6"), "#FFFFFF")
    strati.append(Strato("percorso", "percorsi", walk))
    strati.append(Strato("alberi-dietro", "alberi", [iso_tree(*t) for t in behind], ["iso-tree"]))
    strati.append(Strato("basamento", "edifici", prism(base, 0, base_h, ISO_BASE[:2], ISO_BASE[2])))

    def storey(z0, lit, h=ISO_FLOOR, shape=None, frame=None):
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
            if frame and not lit:
                out.append(f'<polygon points="{iso_poly(q)}" fill="#1E2A3A" opacity="0.38"/>')   # tinted glass
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
            out.append(f'<path d="{"".join(mullions)}" stroke="{frame or "#FFFFFF"}" stroke-width="1.2" '
                       f'opacity="{0.9 if frame else 0.75}"/>')
        return out

    zmid = {}
    if b.get("parti"):
        # A building of parts, each with its own outline and bands, the farthest drawn first.
        parts = [(p, ccw([turn(q) for q in p["pianta"]])) for p in b["parti"]]
        parts.sort(key=lambda pp: sum(x + y for x, y in pp[1]) / len(pp[1]))
        top = 0
        for part, own in parts:
            ztop = draw_profile(b, own, turn, base_h, storey, door, strati, zmid, part["profilo"], part["nome"])
            others = [o for p2, o in parts if p2 is not part]
            steel = exoskeleton(own, ztop, others) if part.get("esoscheletro") else []
            if ent and ent.get("scultura") == "A" and part.get("ingresso"):
                # The A hangs from the structure, in front of it: one layer, drawn after the columns.
                steel += sculpture_a(own, turn(tuple(ent["punto"])), ztop)
            if steel:
                strati.append(Strato(f"struttura-{part['nome']}", "edifici", steel))
            if part.get("pinnacoli") or part.get("orologio") or part.get("frontone") or part.get("scalinata") \
                    or part.get("scritta") or part.get("bandiere") or part.get("portoni") or part.get("balconi_extra"):
                strati.append(Strato(f"ornati-{part['nome']}", "edifici", ornaments(part, own, turn, ztop, base_h)))
            top = max(top, ztop)
    elif b.get("profilo"):
        # A building that is not a stack of like storeys: its bands, bottom up, as drawn.
        top = draw_profile(b, pts, turn, base_h, storey, door, strati, zmid)
        if b.get("pinnacoli") or b.get("orologio"):
            strati.append(Strato("pinnacoli", "edifici", pinnacles(b, turn, top)))
        if b.get("lamelle"):
            strati.append(Strato("lamelle", "edifici", lamellae(b, pts, turn, base_h, top)))
        if ent and ent.get("rampa"):
            strati.append(Strato("ingresso", "ingressi", door))
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
    for f, csip in enumerate(c for c in (list(zmid) if b.get("profilo") or b.get("parti") else levels)):
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
        for parco in campus.get("parchi", []):
            # A park drawn on its own: the map of its frame, with what it offers.
            name = f"parco-{parco['id']}-mappa"
            disegni[f"{src.stem}/{name}"] = write_drawing(dest, name, *draw_map(campus, parco))
            print(f"{src.stem}/{name}  {parco['nome']}")
    catalogue = {k: {"nome": n, "predefinito": on, "fisso": fixed} for k, (n, on, fixed) in LIVELLI.items()}
    (HERE / "livelli.json").write_text(json.dumps({"livelli": catalogue, "disegni": disegni},
                                                  indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
