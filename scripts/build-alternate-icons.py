#!/usr/bin/env python3
"""Builds the alternate app icons Personalizza offers under App ▸ Icona.

Run `python3 scripts/build-alternate-icons.py` from the repository root after
changing the layers in `design/app-icon/orbita` or the lists below. It writes,
next to the primary `PoliVerse/AppIcons/AppIcon.icon`:

- `AppIcon-Dial[-<Swatch>].icon` and `AppIcon-CloseUp[-<Swatch>].icon`, the
  Giorno and Vicino shapes in their own ground and in every swatch;
- `AppIcon-<Name>.icon`, one per special icon.

The names must match `AppIconChoice.alternateIconName(in:)`,
`SpecialIcon.alternateIconName` and the target's
`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`; the colours match
`Flavor.swatches`.

The small `AppIconPreview-*` images the picker draws are not written here: an
Icon Composer file cannot be loaded as an image, so render them into
`Assets.xcassets/AlternateIcons` when the icons change.
"""
import json
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
FOLDER = ROOT / "PoliVerse" / "AppIcons"
SOURCE = FOLDER / "AppIcon.icon"

# Asset name, and the swatch the ground is built on.
CHOICES = [
    ("Lavender", None, "#7A6FE0"),
    ("Indigo", None, "#3B4BC8"),
    ("Sky", None, "#2E9BD6"),
    ("Mint", None, "#2FA88A"),
    ("Sage", None, "#5E8C61"),
    ("Mandarin", None, "#E8751A"),
    ("Coral", None, "#E0584F"),
    ("Raspberry", None, "#C2386F"),
    ("Coffee", None, "#8A5A3C"),
    ("Slate", None, "#5B6472"),
    ("Graphite", None, "#1F2328"),
]

def rgb(hex_string):
    """A `#RRGGBB` string as a tuple of 0-255 channels."""
    value = hex_string.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    """`a` moved toward `b` by `t`."""
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def colour(channels):
    """A colour the way Icon Composer writes it in `icon.json`."""
    return "srgb:" + ",".join(f"{c / 255:.5f}" for c in channels) + ",1.00000"


def gradient(top, bottom):
    return {"linear-gradient": [colour(top), colour(bottom)]}


def fills(top, bottom):
    """The ground for every appearance, and a deeper one for dark."""
    return [
        {"value": gradient(top, bottom)},
        {"appearance": "dark", "value": gradient(mix(bottom, (0, 0, 0), 0.4), (0, 0, 0))},
    ]


# The other two shapes: the day as a dial (Giorno) and the planet close up
# (Vicino), built from their layers in design/app-icon/orbita, each in its own
# ground and in every swatch. Names match `AppIconChoice.alternateIconName(in:)`.
ORBITA = ROOT / "design" / "app-icon" / "orbita"
SHAPES = [
    # Asset name, layer folder, layers top to bottom, own ground top and bottom.
    ("Dial", "layers-giorno", ["4-luna", "3-pianeta", "2-quadrante"], "#15406A", "#040C18"),
    ("CloseUp", "layers-vicino", ["4-luna", "3-anello", "2-pianeta"], "#1B4F80", "#061322"),
]


def group(layer):
    """One layer on glass, as the primary icon draws its own."""
    return {
        "layers": [{"glass": True, "image-name": f"{layer}.svg", "name": layer}],
        "shadow": {"kind": "neutral", "opacity": 0.5},
        "translucency": {"enabled": True, "value": 0.3},
    }


def shapes():
    for shape, folder, layers, top, bottom in SHAPES:
        grounds = [("", rgb(top), rgb(bottom))]
        for name, _, swatch in CHOICES:
            base = rgb(swatch)
            grounds.append((f"-{name}", mix(base, (255, 255, 255), 0.12), mix(base, (0, 0, 0), 0.55)))
        for suffix, top_colour, bottom_colour in grounds:
            target = FOLDER / f"AppIcon-{shape}{suffix}.icon"
            if target.exists():
                shutil.rmtree(target)
            (target / "Assets").mkdir(parents=True)
            for layer in layers:
                shutil.copyfile(ORBITA / folder / f"{layer}.svg", target / "Assets" / f"{layer}.svg")
            icon = {
                "fill-specializations": fills(top_colour, bottom_colour),
                "groups": [group(layer) for layer in layers],
                "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
            }
            (target / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")
            print("wrote", target.relative_to(ROOT))


# The special icons: each a finished picture, drawn full-bleed on one layer
# with no glass, as its own light and depth are painted in. Three carry a grain
# over it, since Icon Composer draws no SVG noise. Names match `SpecialIcon`.
SPECIALS = [
    # Asset name, SVG in premium/, grain opacity or None.
    ("Neon", "01-neon", None),
    ("Spectrum", "02-spettro", None),
    ("Leather", "03-pelle", 0.5),
    ("Holographic", "04-olografico", None),
    ("Hyperspace", "05-iperspazio", None),
    ("Blueprint", "06-blueprint", None),
    ("Circuit", "07-circuito", 0.25),
    ("Heavens", "08-cielo", None),
    ("Observatory", "09-osservatorio", 0.2),
    ("Soft", "10-morbido", None),
    ("Paper", "11-carta", None),
]


def specials():
    for name, svg, grain in SPECIALS:
        target = FOLDER / f"AppIcon-{name}.icon"
        if target.exists():
            shutil.rmtree(target)
        (target / "Assets").mkdir(parents=True)
        shutil.copyfile(ORBITA / "premium" / f"{svg}.svg", target / "Assets" / "picture.svg")
        layers = []
        if grain:
            shutil.copyfile(ORBITA / "grain.png", target / "Assets" / "grain.png")
            layers.append({"blend-mode": "overlay", "glass": False, "image-name": "grain.png",
                           "name": "grain", "opacity": grain})
        layers.append({"glass": False, "image-name": "picture.svg", "name": "picture"})
        icon = {
            "groups": [{"layers": layers, "shadow": {"kind": "none", "opacity": 0},
                        "translucency": {"enabled": False, "value": 0}}],
            "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
        }
        (target / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")
        print("wrote", target.relative_to(ROOT))


if __name__ == "__main__":
    shapes()
    specials()
