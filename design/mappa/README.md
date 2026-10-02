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
| `<campus>/<csie>-isometrico.svg` | isometric: the building alone, one layer per floor |
| `<campus>/<csip>-pianta.svg` | floor plan: one floor, its rooms, doors and entrances |
| `<campus>/<drawing>/NN-<layer>.svg` | the same drawing split into one file per layer |
| `livelli.json` | every layer, and every drawing's layers in stacking order |

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
2. Add what surrounds it to `contesto`: `percorsi`, `verde`, `alberi`
   (`[x, y, radius]`), `scale` (outdoor steps, as lines), `ingressi`, `bici`
   (`[x, y, capacity]`), `lampioni`, `dae`, `acqua`, and street `nomi`.
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
- `acqua` — drinking fountains on this floor.
- a `wc` with `"accessibile": true` gets the accessibility symbol; lifts always do.

Draw a floor over its reference image: one point per corner, walls straight,
no detail a student would not use to find a room.

## Layers

Every drawing is a stack of layers the app can switch on and off. `livelli.json`
holds the catalogue — each layer's Italian name, whether it is on by default,
and whether it is fixed (the drawing makes no sense without it) — and, for
each drawing, its layers in stacking order, back to front.

| Layer | Map | 3D | Plan | Default |
|---|---|---|---|---|
| `terreno` | ✓ | ✓ | ✓ | fixed |
| `edifici` | ✓ | ✓ | | fixed |
| `piani` | | ✓ | | fixed |
| `locali`, `muri` | | | ✓ | fixed |
| `verde`, `strade`, `percorsi`, `scale-esterne` | ✓ | path | | on |
| `alberi`, `ombre`, `impianti` | ✓ | ✓ | | on |
| `ingressi` | ✓ | ✓ | ✓ | on |
| `bici`, `dae`, `nomi`, `numeri` | ✓ | | | on |
| `acqua` | ✓ | | ✓ | on |
| `lampioni` | ✓ | | | off |
| `gradoni`, `gradini`, `ascensori`, `pilastri`, `porte`, `accessibilita`, `etichette` | | | ✓ | on |
| `etichette-piani` | | ✓ | | off |

The same layer can appear more than once in a stack: the 3D trees are split
into `alberi-dietro` and `alberi-davanti` around the building, both under the
`alberi` switch. Two ways to use them:

- **One file per drawing.** In `<drawing>.svg` each layer is a group
  `id="livello-<name>" data-livello="<layer>"`; a layer that is off by default
  carries `style="display: none"`. Show or hide groups by `data-livello`.
- **One image per layer.** Stack the files in `<drawing>/` in the order
  `livelli.json` gives. They share one frame, so they register with no
  offsets; hide an image to switch its layer off.

## Highlighting

In the 3D view each floor is a layer named by its `csip`, lowest first, and
a floor is highlighted by switching its lights on: warm rooms behind the
glass, a row of ceiling spotlights, desks catching the light, frames dark
against it, and light spilling onto the slab. The rest of the building stays
in daylight, so the lit floor is the one the eye lands on.

- **One image per layer:** the floor's entry in `livelli.json` names an
  `acceso` file. Swap the floor's image for it.
- **One file:** each floor group `livello-<csip>` has a hidden twin
  `livello-<csip>-acceso` (`data-acceso="true"`) right after it. Hide the
  first and show the twin.

In `-pianta.svg` each classroom is a group with its `csiv` as id and
`data-sigla`; its label is the group `<csiv>-etichetta`. To highlight a room,
recolour that group's path.

## Sources

Outlines and surroundings are traced by eye from OpenStreetMap, and the
positions of trees, lawns, outdoor steps, entrances, bike racks, lamps,
defibrillators, fountains and the Trifoglio's columns come from it too, so the
drawings carry its attribution: © OpenStreetMap contributors (ODbL). Room
layouts are redrawn by eye from the floor plan images on the Politecnico's
public maps service, checked against OpenStreetMap's indoor mapping; nothing
is converted from either automatically.
