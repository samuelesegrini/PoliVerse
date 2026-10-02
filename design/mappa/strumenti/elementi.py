#!/usr/bin/env python3
"""Prints a building's map as one absolutely placed element per object (lawns, roads,
paths, trees, buildings, number badges), for a design canvas board.

    python3 strumenti/elementi.py > elementi.html

Uses the same data and palette as build-mappa.py; the first building in leonardo.json
is the one in focus. The last line says the board's size in pixels.
"""
import importlib.util, json, math, pathlib
HERE = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("bm", HERE / "build-mappa.py")
bm = importlib.util.module_from_spec(spec); spec.loader.exec_module(bm)
c = json.load(open(HERE / "leonardo.json"))
focus = c["edifici"][0]
X0, Y0, X1, Y1 = focus["riquadro"]
K = 6  # px per metre
f = bm.fmt

def box(x0, y0, x1, y1, label, inner, extra=""):
    return (f'<div data-label="{label}" style="position: absolute; left: {f((x0 - X0) * K)}px; top: {f((y0 - Y0) * K)}px; '
            f'width: {f((x1 - x0) * K)}px; height: {f((y1 - y0) * K)}px{extra}">'
            f'<svg width="100%" height="100%" viewBox="{f(x0)} {f(y0)} {f(x1 - x0)} {f(y1 - y0)}" aria-hidden="true" style="display: block; overflow: visible">{inner}</svg></div>')

def bounds(pts, pad):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    return min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad

line = lambda pts: "M" + "L".join(f"{f(x)} {f(y)}" for x, y in pts)
out = []
ctx = c["contesto"]

out.append('<div data-label="Verde">')
for i, v in enumerate(ctx["verde"]):
    pts = [tuple(p) for p in v]
    out.append(box(*bounds(pts, 0.2), "Verde — spartitraffico della piazza" if i == 0 else f"Verde — prato {i}",
                   f'<path d="{bm.rounded(pts, 2)}" fill="{bm.GREEN}"></path>'))
out.append("</div>")

out.append('<div data-label="Strade">')
for i, s in enumerate(ctx["strade"]):
    pts = [tuple(p) for p in s["punti"]]; w = s["larghezza"]
    d = line(pts)
    out.append(box(*bounds(pts, w / 2 + 0.7), f'{s["nome"]} — carreggiata {"nord" if i == 0 else "sud"}',
                   f'<path d="{d}" fill="none" stroke="{bm.ROAD_EDGE}" stroke-width="{f(w + 1.2)}"></path>'
                   f'<path d="{d}" fill="none" stroke="{bm.ROAD}" stroke-width="{f(w)}"></path>'
                   f'<path d="{d}" fill="none" stroke="{bm.ROAD_DASH}" stroke-width="0.3" stroke-dasharray="2.4 2.4"></path>'))
out.append("</div>")

# Paths: a path that ends on another one stops its border at the other's edge,
# so with the later one painted above, every junction joins cleanly.
pnames = ["Percorso ovest — verso l'ingresso", "Percorso nord", "Percorso sud", "Accesso sud",
          "Percorso lungo il 16A", "Passaggio a est del 16A", "Passaggio a ovest del 12", "Marciapiede della piazza"]
paths = [[tuple(p) for p in q] for q in ctx["percorsi"]]
order = [7, 0, 1, 4, 2, 3, 5, 6]
def dist_to(p, poly):
    best = 1e9
    for a, b in zip(poly, poly[1:]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        t = max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.dist(p, (a[0] + dx * t, a[1] + dy * t)))
    return best
def trim(pts, at_start, at_end, d=1.7):
    pts = list(pts)
    if at_start:
        a, b = pts[0], pts[1]; n = math.dist(a, b)
        pts[0] = (a[0] + (b[0] - a[0]) * d / n, a[1] + (b[1] - a[1]) * d / n)
    if at_end:
        a, b = pts[-1], pts[-2]; n = math.dist(a, b)
        pts[-1] = (a[0] + (b[0] - a[0]) * d / n, a[1] + (b[1] - a[1]) * d / n)
    return pts
out.append('<div data-label="Percorsi">')
for i in order:
    pts = paths[i]
    others = [paths[j] for j in range(len(paths)) if j != i]
    s_on = any(dist_to(pts[0], o) < 0.5 for o in others)
    e_on = any(dist_to(pts[-1], o) < 0.5 for o in others)
    edge = trim(pts, s_on, e_on)
    cap_s = "butt" if s_on or e_on else "round"
    out.append(box(*bounds(pts, 1.8), pnames[i],
                   f'<path d="{line(edge)}" fill="none" stroke="{bm.ROAD_EDGE}" stroke-width="3.4" stroke-linecap="{cap_s}" stroke-linejoin="round"></path>'
                   f'<path d="{line(pts)}" fill="none" stroke="{bm.ROAD}" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"></path>'))
out.append("</div>")

out.append('<div data-label="Alberi">')
for i, (x, y, r) in enumerate(ctx["alberi"], 1):
    out.append(box(x - r, y - r, x + r * 1.3, y + r * 1.3, f"Albero {i}",
                   f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(r)}" fill="{bm.TREE}"></circle>'
                   f'<circle cx="{f(x + r * 0.3)}" cy="{f(y + r * 0.3)}" r="{f(r)}" fill="{bm.TREE_SHADE}" opacity="0.5"></circle>'
                   f'<circle cx="{f(x)}" cy="{f(y)}" r="{f(r * 0.69)}" fill="{bm.TREE_LIGHT}"></circle>'))
out.append("</div>")

out.append('<div data-label="Edifici">')
for b in c["edifici"]:
    pts = bm.ccw([tuple(p) for p in b["pianta"]])
    wall = bm.WALL_PER_FLOOR * bm.floor_count(b)
    x0, y0, x1, y1 = bounds(pts, 0)
    x1 += wall * 0.86; y1 += wall * 1.57
    cid = b["csie"]
    inner = (f'<defs><linearGradient id="roof-{cid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{bm.ROOF_TOP}"></stop><stop offset="1" stop-color="{bm.ROOF_BOTTOM}"></stop></linearGradient>'
             f'<linearGradient id="wall-{cid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{bm.WALL_TOP}"></stop><stop offset="1" stop-color="{bm.WALL_BOTTOM}"></stop></linearGradient></defs>'
             f'<path d="{bm.rounded(pts, bm.CORNER, wall * 0.86, wall * 1.57)}" fill="{bm.SHADOW}" opacity="0.10"></path>'
             f'<path d="{bm.rounded(pts, bm.CORNER, 0, wall)}" fill="url(#wall-{cid})"></path>'
             f'<path d="{bm.rounded(pts, bm.CORNER)}" fill="url(#roof-{cid})"></path>')
    for x, y, w, h in b.get("impianti", []):
        inner += (f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" rx="0.8" fill="{bm.PLANT}"></rect>'
                  f'<rect x="{f(x)}" y="{f(y + h - 0.6)}" width="{f(w)}" height="1" fill="{bm.PLANT_LIP}"></rect>')
    name = f'Edificio {b["numero"]}' + (f' — {b["nome"]}' if b.get("nome") else "")
    out.append(box(x0, y0, x1, y1, f"{name} ({cid})", inner))
out.append("</div>")

out.append('<div data-label="Numeri">')
for b in c["edifici"]:
    x, y = b["badge"]; label = b["numero"]
    w = 7.0 + 2.4 * max(0, len(label) - 1)
    fill = bm.BADGE_FOCUS if b is focus else bm.BADGE
    out.append(f'<div data-label="Numero {label}" style="position: absolute; left: {f((x - X0) * K)}px; top: {f((y - Y0) * K)}px; '
               f'width: {f(w * K)}px; height: {f(6 * K)}px; border-radius: {f(3 * K)}px; background: {fill}; color: #FFFFFF; '
               f'font-size: {f(4 * K)}px; font-weight: 700; display: flex; align-items: center; justify-content: center; line-height: 1">{label}</div>')
out.append("</div>")
print("\n".join(out))
print(f"<!-- size {(X1 - X0) * K} x {(Y1 - Y0) * K} -->")
