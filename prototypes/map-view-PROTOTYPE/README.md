# Map view — PROTOTYPE (throwaway)

**Question:** what should a map of facilities, buildings and rooms look like in PoliVerse?

Open `index.html` (or `python3 -m http.server` in this folder and visit it).
No build, no dependencies, no network — `data.js` embeds everything, floor
plan JPEGs included.

## The finding that decided the design

The public geojson has **no real building footprints**. Of 465 building
features, 142 "detailed" polygons are *generated ellipses* and 155 are
axis-aligned bounding boxes. Only the coordinates are true.

So a vector campus map is out: it would look wrong because it *is* wrong.
Toggle **Geometria** to see it drawn. The map uses pins at real coordinates
instead, with MapKit supplying the city underneath — nothing invented.

## What the prototype shows

One screen, toggles rather than separate variants:

- **Mappa / Elenco** — same data, two presentations
- **Libere ora** — colours pins by free-room ratio
- **Geometria** — overlays the raw polygons, i.e. the rejected option
- **Sede chips** — campus switch

Drill: campus → building → room. The room pane shows everything available,
each block labelled with the endpoint that produced it: the official floor
plan with the room highlighted, the occupancy timeline with derived free
gaps, equipment, software, and the full `csi*` identity.

## Data

All public, no token. Built by `build-data.py`.

| Endpoint | Gives |
| --- | --- |
| `/spazi/aula`, `/spazi/edificio`, `/spazi/campus` | catalogue |
| `/spazi/{campus,edificio}/geojson?filter=` | coordinates (and the fake outlines) |
| `/ricerca/aula/occupazione/{idaula}/{date}` | busy bands |
| `/ricerca/aula/dotazioni/{idaula}`, `/software/{idaula}` | equipment, software |
| `/download/img/piano/{csip}/{csiv}` | floor plan, room highlighted |

`?filter=` must be present and **empty** — omitting it returns 500.

Occupancy, equipment and software were fetched for real for one building
(the largest); elsewhere the free counts are simulated and the UI says so.

## Cost, if this ships

Occupancy is one request per room. A campus view with real numbers
everywhere is ~150 requests for Milano Leonardo. The app already batches
eight at a time and caches per room and day; a map that colours every pin
would want a coarser signal or a visible "sto calcolando".
