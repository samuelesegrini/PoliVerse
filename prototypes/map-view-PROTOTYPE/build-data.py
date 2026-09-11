#!/usr/bin/env python3
"""Fetch and trim the public maps data into one embeddable file.

PROTOTYPE — throwaway. Run once: `python3 build-data.py`.

Everything here is public and unauthenticated. The output is embedded in
index.html's sibling data.js so the prototype opens from file:// with no
server and no CORS.
"""
import base64, json, urllib.request

BASE = "https://onlineservices.polimi.it/maps_rest/rest"


def get(path, binary=False):
    with urllib.request.urlopen(BASE + path, timeout=60) as r:
        raw = r.read()
    return raw if binary else json.loads(raw)


def ring_bounds(feature):
    """Everything carries a bbox in its properties; use it when geometry is a point."""
    p = feature.get("properties") or {}
    if p.get("SWLAT") is None:
        return None
    return [p["SWLNG"], p["SWLAT"], p["NELNG"], p["NELAT"]]


def simplify(features):
    out = []
    for f in features:
        props = f.get("properties") or {}
        csi = props.get("POLIMI_ID_SPAZIO")
        geom = f.get("geometry") or {}
        if not csi:
            continue
        entry = {"id": csi, "bbox": ring_bounds(f)}
        if geom.get("type") == "Polygon":
            # Outer ring only, rounded — this is a sketch, not a survey.
            entry["ring"] = [[round(x, 6), round(y, 6)] for x, y in geom["coordinates"][0]]
        out.append(entry)
    return out


print("campus…")
campus = simplify(get("/spazi/campus/geojson?filter=")["features"])
print("edifici…")
edifici = simplify(get("/spazi/edificio/geojson?filter=")["features"])
print("catalogo…")
aule = get("/spazi/aula")
edifici_meta = get("/spazi/edificio?mode=")
campus_meta = get("/spazi/campus?mode=")

names = {}
for e in edifici_meta if isinstance(edifici_meta, list) else []:
    if e.get("csie"):
        names[e["csie"]] = {
            "nome": e.get("nome"),
            "csic": e.get("csic"),
            "indirizzo": " ".join(filter(None, [
                e.get("prefissoToponomastico"), e.get("indirizzo"),
                e.get("numeroCivico")])),
            "citta": e.get("cittaEdificio"),
        }

campus_names = {}
for c in campus_meta if isinstance(campus_meta, list) else []:
    if c.get("csic"):
        campus_names[c["csic"]] = c.get("nome")

rooms = []
for a in aule:
    if not a.get("idaula") or not a.get("sigla"):
        continue
    rooms.append({
        "sigla": a["sigla"], "idaula": a["idaula"],
        "csie": a.get("csie"), "csip": a.get("csip"), "csiv": a.get("csiv"),
        "capienza": int(a.get("capienza") or 0),
        "disabili": int(a.get("posti_disabili") or 0),
    })

# Two real floor plans, embedded so the prototype needs no network at all.
plans = {}
for csip, csiv in [("MIA0102000", "MIA0102000077"), ("MIA0102000", None)]:
    path = f"/download/img/piano/{csip}" + (f"/{csiv}" if csiv else "")
    try:
        plans[csiv or csip] = "data:image/jpeg;base64," + base64.b64encode(
            get(path, binary=True)).decode()
        print("plan", csiv or csip, "ok")
    except Exception as exc:
        print("plan failed", path, exc)

payload = {"campus": campus, "edifici": edifici, "nomiEdifici": names,
           "nomiCampus": campus_names, "aule": rooms, "piante": plans}
with open("data.js", "w") as fh:
    fh.write("window.POLIMAP = ")
    json.dump(payload, fh, separators=(",", ":"))
    fh.write(";")
print(f"campus={len(campus)} edifici={len(edifici)} aule={len(rooms)} piante={len(plans)}")

# ---------------------------------------------------------------------------
# Detail pass: one real building, fully populated, so the prototype's detail
# panes show genuine data instead of placeholders.
DETAIL_CSIE = max(
    {r["csie"] for r in rooms if r.get("csie")},
    key=lambda c: sum(1 for r in rooms if r["csie"] == c),
)
detail_rooms = [r for r in rooms if r["csie"] == DETAIL_CSIE]
print(f"detail building {DETAIL_CSIE}: {len(detail_rooms)} rooms")

today = __import__("datetime").date.today().isoformat()
details = {}
for i, r in enumerate(detail_rooms):
    entry = {}
    for key, path in (("dotazioni", f"/ricerca/aula/dotazioni/{r['idaula']}"),
                      ("software", f"/ricerca/aula/software/{r['idaula']}"),
                      ("occupazione", f"/ricerca/aula/occupazione/{r['idaula']}/{today}")):
        try:
            entry[key] = get(path)
        except Exception:
            entry[key] = []
    # Floor plans are ~70 KB each; a handful keeps the file openable.
    if i < 8 and r.get("csip") and r.get("csiv"):
        try:
            entry["pianta"] = "data:image/jpeg;base64," + base64.b64encode(
                get(f"/download/img/piano/{r['csip']}/{r['csiv']}", binary=True)).decode()
        except Exception:
            pass
    details[r["idaula"]] = entry
    print(" ", r["sigla"], len(entry.get("dotazioni", [])), "dot",
          len(entry.get("occupazione", [])), "band", "pianta" if "pianta" in entry else "")

payload["dettagli"] = details
payload["dettaglioEdificio"] = DETAIL_CSIE
payload["dataOccupazione"] = today
with open("data.js", "w") as fh:
    fh.write("window.POLIMAP = ")
    json.dump(payload, fh, separators=(",", ":"))
    fh.write(";")
print("rewrote data.js with details")
