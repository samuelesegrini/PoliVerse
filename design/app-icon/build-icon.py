#!/usr/bin/env python3
"""Builds the PoliVerse app icon as layered SVGs for Apple's Icon Composer.

Run `python3 build-icon.py` to regenerate `layers/` and `preview.svg`.

The subject is a ringed planet: the *-Verse* of PoliVerse, with one amber moon
for the thing coming up next. Every shape is an original drawing — no Apple
artwork is used, because the SF Symbols licence does not allow system symbols
in app icons.

What Icon Composer needs, and what this file therefore guarantees:

- one 1024x1024 document per layer, all sharing the same coordinate space, so
  the layers stack exactly as composed here;
- flat fills and plain linear gradients only — no CSS, no filters, no masks;
- `gradientUnits="userSpaceOnUse"`, so a gradient that spans two layers (the
  ring, split into a near and a far half) keeps one continuous field instead of
  restarting inside each layer's own bounding box;
- no `transform` attributes: every rotated coordinate is baked into the path
  data, so nothing depends on the importer honouring a transform stack;
- strokes converted to filled outlines, so weights cannot shift on import.
"""
import math
import pathlib

HERE = pathlib.Path(__file__).parent
LAYERS = HERE / "layers"

SIZE = 1024.0
C = SIZE / 2

# The ring, the planet, and the moon riding on the ring.
RING_RX, RING_RY = 448.0, 154.0
RING_TILT = -22.0          # degrees, anticlockwise
RING_THICKNESS = 54.0
PLANET_R = 288.0
MOON_ANGLE = 34.0          # where the moon sits, in the ring's own parameter space
MOON_R = 66.0
MOON_GAP = 20.0            # clear space punched through the ring around the moon

# Gradients, in user space so they are continuous across layers.
GRADIENTS = {
    "bg": ((154, 0), (819, 1024), [("0", "#14477E"), ("1", "#04182F")]),
    "orb": ((356, 300), (740, 770), [("0", "#FFFFFF"), ("1", "#9CCBF0")]),
    "ring": ((93, 330), (931, 700),
             [("0", "#3E7FBF"), ("0.5", "#CFE2F5"), ("1", "#3E7FBF")]),
    "moon": ((796, 380), (928, 510), [("0", "#FFC24D"), ("1", "#F08A1E")]),
}

KAPPA = 0.5522847498307936


def fmt(value):
    """A coordinate, trimmed so the path data stays readable."""
    return f"{value:.2f}".rstrip("0").rstrip(".")


def rotate(x, y, degrees):
    """A point about the canvas centre."""
    t = math.radians(degrees)
    return (C + x * math.cos(t) - y * math.sin(t),
            C + x * math.sin(t) + y * math.cos(t))


def on_ring(angle, rx, ry):
    """A point at `angle` on the tilted ring."""
    a = math.radians(angle)
    return rotate(rx * math.cos(a), ry * math.sin(a), RING_TILT)


def arc(rx, ry, start, end, steps=110):
    """A run of points along the tilted ellipse, start to end in degrees."""
    return [on_ring(start + (end - start) * i / steps, rx, ry)
            for i in range(steps + 1)]


def polygon(points):
    return "M" + " L".join(f"{fmt(x)},{fmt(y)}" for x, y in points) + "Z"


def circle_path(cx, cy, r):
    """A circle as four cubics, so it can be a subpath of a larger path."""
    k = KAPPA * r
    return (f"M{fmt(cx + r)},{fmt(cy)}"
            f"C{fmt(cx + r)},{fmt(cy + k)} {fmt(cx + k)},{fmt(cy + r)} {fmt(cx)},{fmt(cy + r)}"
            f"C{fmt(cx - k)},{fmt(cy + r)} {fmt(cx - r)},{fmt(cy + k)} {fmt(cx - r)},{fmt(cy)}"
            f"C{fmt(cx - r)},{fmt(cy - k)} {fmt(cx - k)},{fmt(cy - r)} {fmt(cx)},{fmt(cy - r)}"
            f"C{fmt(cx + k)},{fmt(cy - r)} {fmt(cx + r)},{fmt(cy - k)} {fmt(cx + r)},{fmt(cy)}Z")


def half_ring(start, end):
    """One half of the ring as a closed outline: out along the outer edge,
    back along the inner one."""
    outer = arc(RING_RX, RING_RY, start, end)
    inner = arc(RING_RX - RING_THICKNESS, RING_RY - RING_THICKNESS, end, start)
    return polygon(outer + inner)


def defs(*names):
    out = "<defs>"
    for name in names:
        (x1, y1), (x2, y2), stops = GRADIENTS[name]
        out += (f'<linearGradient id="{name}" gradientUnits="userSpaceOnUse" '
                f'x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">')
        out += "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
        out += "</linearGradient>"
    return out + "</defs>"


def document(body, *gradient_names):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            f'viewBox="0 0 1024 1024">{defs(*gradient_names)}{body}</svg>')


# ------------------------------------------------------------------ the layers

MOON_X, MOON_Y = on_ring(MOON_ANGLE,
                         RING_RX - RING_THICKNESS / 2,
                         RING_RY - RING_THICKNESS / 2)


def background():
    return '<rect x="0" y="0" width="1024" height="1024" fill="url(#bg)"/>'


def ring_back():
    """The far half, dimmed so it reads as being behind the planet."""
    return f'<path d="{half_ring(180, 360)}" fill="url(#ring)" fill-opacity="0.85"/>'


def planet():
    return f'<circle cx="{fmt(C)}" cy="{fmt(C)}" r="{fmt(PLANET_R)}" fill="url(#orb)"/>'


def ring_front():
    """The near half, with a hole punched where the moon crosses it: the gap is
    transparent, so whatever is behind shows through rather than a painted disc
    that would have to match the background exactly."""
    d = half_ring(0, 180) + circle_path(MOON_X, MOON_Y, MOON_R + MOON_GAP)
    return f'<path d="{d}" fill="url(#ring)" fill-rule="evenodd"/>'


def moon():
    return f'<circle cx="{fmt(MOON_X)}" cy="{fmt(MOON_Y)}" r="{fmt(MOON_R)}" fill="url(#moon)"/>'


LAYER_ORDER = [
    ("1-background", background, ("bg",)),
    ("2-ring-back", ring_back, ("ring",)),
    ("3-planet", planet, ("orb",)),
    ("4-ring-front", ring_front, ("ring",)),
    ("5-moon", moon, ("moon",)),
]


def main():
    LAYERS.mkdir(exist_ok=True)
    for name, build, gradients in LAYER_ORDER:
        path = LAYERS / f"{name}.svg"
        path.write_text(document(build(), *gradients), encoding="utf-8")
        print(f"layers/{path.name}")

    combined = "".join(build() for _, build, _ in LAYER_ORDER)
    names = tuple(dict.fromkeys(g for _, _, gs in LAYER_ORDER for g in gs))
    (HERE / "preview.svg").write_text(document(combined, *names), encoding="utf-8")
    print("preview.svg")

    # Where the artwork actually sits, so the safe area can be checked by eye.
    half_w = math.hypot(RING_RX * math.cos(math.radians(RING_TILT)),
                        RING_RY * math.sin(math.radians(RING_TILT)))
    half_h = math.hypot(RING_RX * math.sin(math.radians(RING_TILT)),
                        RING_RY * math.cos(math.radians(RING_TILT)))
    print(f"\nring bounds   x {C - half_w:.0f}–{C + half_w:.0f}   "
          f"y {C - half_h:.0f}–{C + half_h:.0f}")
    print(f"planet bounds x {C - PLANET_R:.0f}–{C + PLANET_R:.0f}   "
          f"y {C - PLANET_R:.0f}–{C + PLANET_R:.0f}")
    print(f"moon centre   ({MOON_X:.0f}, {MOON_Y:.0f})  r {MOON_R:.0f}")


if __name__ == "__main__":
    main()
