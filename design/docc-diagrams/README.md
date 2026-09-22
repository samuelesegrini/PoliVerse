# DocC diagrams

The figures in `PoliVerse/PoliVerse.docc/Resources/`, built from one definition
so the light and dark variants cannot drift apart.

```bash
python3 build-diagrams.py
```

Each diagram is written twice — `name.svg` and `name~dark.svg`. DocC picks the
dark one by that filename suffix; nothing in the articles refers to it.

## Sizing

An SVG needs `width` and `height` on its root element, not just a `viewBox`.
Without them it has no intrinsic size, and DocC falls back to a default far
smaller than the column the figure sits in.

With them, a figure fills the column up to its intrinsic width and stops.
`RENDER_SCALE` in `build-diagrams.py` raises that ceiling without redrawing
anything — the `viewBox` is untouched, so the artwork just scales.

`check-width.html` renders three of the diagrams in mock columns at 680, 820,
1000 and 1180 points, styled the way DocC styles images. Serve the repository
root and open
`http://localhost:PORT/design/docc-diagrams/check-width.html`:

```bash
python3 -m http.server 8000
```

## Adding one

Write a function taking a palette dict and returning SVG body markup, add it to
`DIAGRAMS`, and reference it from an article as `![alt text](name)`. Use the
`box`, `label`, `chip`, `line` and `arrow_defs` helpers so a new figure inherits
the same type sizes, corner radii and arrowheads as the others, and give every
figure alt text that says what it shows.
