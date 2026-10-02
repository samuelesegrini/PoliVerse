# Mappa — building illustrations

Every Politecnico building redrawn by hand, one at a time, in the style of the
*Mappa delle aule libere* and *Edificio con l'aula* illustrations, so the
whole campus reads as one clean, uniform drawing.

## Files

| File | What it is |
|---|---|
| `build-mappa.py` | the source of truth for the look; regenerates every SVG below |
| `<campus>.json` | the hand-drawn description of each building on that campus |
| `piante/<csie>.json` | the hand-drawn rooms of each floor of one building |
| `<campus>/<csie>-mappa.svg` | top-down: the building and its surroundings |
| `<campus>/<csie>-isometrico.svg` | isometric: the building alone, one group per floor |
| `<campus>/<csip>-pianta.svg` | floor plan: one floor, its rooms, doors and entrances |

Run `python3 build-mappa.py` after any change. It has no dependencies.

Files are named by Politecnico codes, the same ones the rooms and occupancy
data use: `csie` for a building (`MIA0203` = Edificio 13, Trifoglio), `csip`
for a floor (`MIA0203000` = its ground floor), `csiv` for a room. The app can
go from a room straight to its floor plan and its building.

## Coordinates

Metres, one frame per campus: x grows east, y grows south, origin at the
campus `origine` (latitude, longitude). Every building of a campus shares that
frame, so the top-down drawings line up into one campus map, and a building's
floor plans sit exactly inside its outline.

## Adding a building

1. Add an entry to `edifici` in the campus file:
   - `pianta` — the outline as a handful of chosen corners, in order. Simplify:
     drop the jogs and notches a walker would not notice. Corners are rounded
     on the map by the script.
   - `livelli` — the `csip` of each floor shown in the isometric view, lowest
     first. (`piani`, a bare count, is enough for a neighbour.)
   - `badge` — where the building number sits (top-left of the roof).
   - `impianti` — rooftop plant as `[x, y, width, depth]`.
   - `ingresso` — the main door: which edge of `pianta` (`lato`, counting from
     0) and how far along it (`t`, 0–1).
   - `vista` — `"sud-ovest"` when the main door faces west or north-west; the
     isometric view then looks from the south-west so the door shows. Leave it
     out to look from the south-east.
   - `riquadro` — the area of the top-down drawing, `[x0, y0, x1, y1]`.
2. Add the paths, green areas, and trees around it to `contesto`.
3. Run the script and look at both SVGs before committing.

An entry without `riquadro` is a neighbour that has only a rough outline so
far: it shows up around other buildings but gets no drawings of its own until
it is redrawn properly.

## Adding floor plans

`piante/<csie>.json` lists the building's floors, each with:

- `csip` and `nome` — the floor's code and name, as the maps service gives them.
- `locali` — the rooms, each a `forma` (corners in campus metres) and a `tipo`:
  `aula`, `wc`, `scale`, `ascensore`, or `locale` for anything else. A room
  that is not listed is corridor.
  - an `aula` also takes `sigla`, `csiv`, `posti`, `gradoni` (the edge its
    rows of seats run parallel to) and, where the centre is crowded,
    `etichetta` (where its label goes);
  - `scale` take `gradini`, the edge their treads run parallel to.
- `porte` — a point near each door; it is snapped to the nearest wall.
- `ingressi` — a point on the outer wall for each way in, with
  `"principale": true` on the main one.
- `pilastri` — free-standing columns, where they help a reader find their way.

Draw a floor over its reference image: one point per corner, walls straight,
no detail a student would not use to find a room.

## Highlighting

In `-isometrico.svg` each floor is a group named by its `csip`, lowest first,
with the roof in `tetto`. Glazing uses `url(#iso-glass-l)` / `url(#iso-glass-r)`.
To highlight a floor, switch that group's glazing to `url(#iso-focus-l)` /
`url(#iso-focus-r)`. Both pairs are already defined in every file.

In `-pianta.svg` each classroom is a group with its `csiv` as id and
`data-sigla`; its label is the group `<csiv>-etichetta`. To highlight a room,
recolour that group's first path.

## Sources

Outlines and surroundings are traced by eye from OpenStreetMap, so the
drawings carry its attribution: © OpenStreetMap contributors (ODbL). Room
layouts are redrawn by eye from the floor plan images on the Politecnico's
public maps service; nothing is converted from them automatically.
