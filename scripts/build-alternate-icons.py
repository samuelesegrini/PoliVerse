#!/usr/bin/env python3
"""Builds the alternate app icons Personalizza offers under App ▸ Icona.

Run `python3 scripts/build-alternate-icons.py` from the repository root after
changing `AppIcon.png` or the list below. It writes, into the asset catalog:

- `AlternateIcons/AppIcon-<Name>.appiconset`, one per choice, which the build
  includes through `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS`;
- `AlternateIcons/AppIconPreview-<id>.imageset`, the same icon small, because
  an app icon set cannot be loaded as an image to draw in the app.

The mark is lifted off the shipped icon once, by unmixing it from its navy
gradient, and laid over a new gradient per colour. The ids match
`AppIconChoice`'s raw values, and the colours `Flavor.swatches`.
"""
import json
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "PoliVerse" / "Assets.xcassets"
SOURCE = ASSETS / "AppIcon.appiconset" / "AppIcon.png"
OUT = ASSETS / "AlternateIcons"

# id, asset name, top and bottom of the gradient. Classic is the shipped icon.
CHOICES = [
    ("classic", None, None, None),
    ("dark", "Dark", "#2C2C2E", "#000000"),
    ("light", "Light", "#FFFFFF", "#DCE4EE"),
    ("lavender", "Lavender", None, "#7A6FE0"),
    ("indigo", "Indigo", None, "#3B4BC8"),
    ("sky", "Sky", None, "#2E9BD6"),
    ("mint", "Mint", None, "#2FA88A"),
    ("sage", "Sage", None, "#5E8C61"),
    ("mandarin", "Mandarin", None, "#E8751A"),
    ("coral", "Coral", None, "#E0584F"),
    ("raspberry", "Raspberry", None, "#C2386F"),
    ("coffee", "Coffee", None, "#8A5A3C"),
    ("slate", "Slate", None, "#5B6472"),
    ("graphite", "Graphite", None, "#1F2328"),
]

NAVY = (15, 61, 110)
PREVIEW_SIDE = 180


def rgb(hex_string):
    """A `#RRGGBB` string as a tuple of 0-255 channels."""
    value = hex_string.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    """`a` moved toward `b` by `t`."""
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def lift_mark(source):
    """The mark alone on transparency: each pixel unmixed from the gradient behind it."""
    width, height = source.size
    pixels = source.load()
    mark = Image.new("RGBA", source.size)
    out = mark.load()
    for y in range(height):
        # The ground at this row, read at both edges, where the mark never is.
        left, right = pixels[24, y][:3], pixels[width - 25, y][:3]
        for x in range(width):
            ground = mix(left, right, x / (width - 1))
            pixel = pixels[x, y][:3]
            lift = max(pixel) - max(ground)
            # The ground is not quite linear across a row: a small lift is gradient, not mark.
            alpha = min(max((lift - 24) / (230 - max(ground) - 24), 0), 1)
            if alpha < 0.02:
                continue
            colour = tuple(min(max(round((p - (1 - alpha) * g) / alpha), 0), 255) for p, g in zip(pixel, ground))
            out[x, y] = (*colour, round(alpha * 255))
    return mark


def for_light_ground(mark):
    """The mark with its whites turned navy, so it shows on a white ground."""
    recoloured = mark.copy()
    pixels = recoloured.load()
    for y in range(recoloured.height):
        for x in range(recoloured.width):
            r, g, b, a = pixels[x, y]
            if a == 0 or max(r, g, b) - min(r, g, b) > 70:
                continue  # the amber tassel stays amber
            t = min(max((255 - min(r, g, b)) / 70, 0), 1)
            pixels[x, y] = (*mix(NAVY, (127, 155, 184), t), a)
    return recoloured


def gradient(size, top, bottom):
    """A vertical gradient from `top` to `bottom`."""
    column = Image.new("RGB", (1, size))
    for y in range(size):
        column.putpixel((0, y), mix(top, bottom, y / (size - 1)))
    return column.resize((size, size)).convert("RGBA")


def write_json(folder, contents):
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main():
    source = Image.open(SOURCE).convert("RGBA")
    mark = lift_mark(source)
    light_mark = for_light_ground(mark)
    write_json(OUT, {"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}})

    for choice, name, top, bottom in CHOICES:
        if name is None:
            icon = source
        else:
            if top is None:
                # A swatch: a little lighter at the top, much deeper at the foot.
                base = rgb(bottom)
                top_colour, bottom_colour = mix(base, (255, 255, 255), 0.12), mix(base, (0, 0, 0), 0.55)
            else:
                top_colour, bottom_colour = rgb(top), rgb(bottom)
            ground = gradient(source.width, top_colour, bottom_colour)
            icon = Image.alpha_composite(ground, light_mark if choice == "light" else mark)
            folder = OUT / f"AppIcon-{name}.appiconset"
            _mkdir(folder)
            icon.convert("RGB").save(folder / "icon.png")
            write_json(folder, {
                "images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                "info": {"author": "xcode", "version": 1},
            })

        preview = OUT / f"AppIconPreview-{choice}.imageset"
        _mkdir(preview)
        icon.convert("RGB").resize((PREVIEW_SIDE, PREVIEW_SIDE), Image.LANCZOS).save(preview / "preview.png")
        write_json(preview, {
            "images": [{"filename": "preview.png", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
        })
        print("wrote", choice)


def _mkdir(folder):
    folder.mkdir(parents=True, exist_ok=True)
    return folder


if __name__ == "__main__":
    main()
