# Mappa — building illustrations

Every Politecnico building redrawn by hand, one at a time, in the style of the
*Mappa delle aule libere* and *Edificio con l'aula* illustrations, so the
whole campus reads as one clean, uniform drawing.

## Files

| File | What it is |
|---|---|
| `build-mappa.py` | the source of truth for the look; regenerates every SVG below |
| `<campus>.json` | the hand-drawn description of each building on that campus |
| `<campus>/<csie>-mappa.svg` | top-down: the building and its surroundings |
| `<campus>/<csie>-isometrico.svg` | isometric: the building alone, one group per floor |

Run `python3 build-mappa.py` after any change. It has no dependencies.

Files are named by the building's `csie` code (`MIA0203` = Edificio 13,
Trifoglio), the same code the rooms and occupancy data use, so the app can go
from a room to its building's drawing directly.

## Coordinates

Metres, one frame per campus: x grows east, y grows south, origin at the
campus `origine` (latitude, longitude). Every building of a campus shares that
frame, so the top-down drawings line up into one campus map.

## Adding a building

1. Add an entry to `edifici` in the campus file:
   - `pianta` — the outline as a handful of chosen corners, in order. Simplify:
     drop the jogs and notches a walker would not notice. Corners are rounded
     by the script.
   - `piani` — floor count above ground.
   - `badge` — where the building number sits (top-left of the roof).
   - `impianti` — rooftop plant as `[x, y, width, depth]`.
   - `ingresso` — the main door: which edge of `pianta` (`lato`, counting from
     0) and how far along it (`t`, 0–1). It must face south or east, the two
     sides the isometric view shows.
   - `riquadro` — the area of the top-down drawing, `[x0, y0, x1, y1]`.
2. Add the paths, green areas, and trees around it to `contesto`.
3. Run the script and look at both SVGs before committing.

An entry without `riquadro` is a neighbour that has only a rough outline so
far: it shows up around other buildings but gets no drawings of its own until
it is redrawn properly.

The outlines are traced by eye from OpenStreetMap, so the drawings carry its
attribution: © OpenStreetMap contributors (ODbL).

## Highlighting a floor

In `-isometrico.svg` each floor is a group, `piano-0` (ground) upwards, with
the roof in `tetto`. Glazing uses `url(#iso-glass-l)` / `url(#iso-glass-r)`.
To highlight a floor, switch that group's glazing to `url(#iso-focus-l)` /
`url(#iso-focus-r)`. Both pairs are already defined in every file.
