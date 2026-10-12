#!/usr/bin/env python3
"""Fills a building's classrooms into `piante/<csie>.json` from the Politecnico's maps
service: each floor's name, and every classroom's name, seats and equipment.

    python3 strumenti/aule.py MIA0205

Run it after adding the building's `livelli` to the campus file. What is already in
the file and not about classrooms (the main entrance, room types, accessible toilets,
fountains) is kept, so it can be run again whenever the classrooms change.
"""
import json
import pathlib
import sys
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent.parent
MAPS = "https://onlineservices.polimi.it/maps_rest/rest"
# The service's equipment ids → the names build-mappa.py draws icons for.
EQUIPMENT = {4: "proiettore", 5: "microfono", 6: "oscurabile", 7: "cattedra", 142: "prese", 143: "rete"}


def get(path):
    with urllib.request.urlopen(f"{MAPS}/{path}", timeout=90) as r:
        return json.loads(r.read().decode())


def main(csie):
    campus = next(json.loads(f.read_text()) for f in HERE.glob("*.json")
                  if f.name != "livelli.json" and csie in f.read_text())
    floors = next(b for b in campus["edifici"] if b["csie"] == csie)["livelli"]
    names = {p["csip"]: p["nome"] for p in get("spazi/piano") if p["csie"] == csie}
    rooms = [a for a in get("spazi/aula") if a["csie"] == csie]

    dest = HERE / "piante" / f"{csie}.json"
    old = {p["csip"]: p for p in json.loads(dest.read_text())["piani"]} if dest.exists() else {}
    piani = []
    for c in floors:
        aule = {}
        for a in sorted((a for a in rooms if a["csip"] == c), key=lambda a: a["sigla"]):
            kit = {d["id"] for d in get(f"ricerca/aula/dotazioni/{a['idaula']}")}
            seats = int(a["capienza"]) if int(a["capienza"]) > 0 else None
            aule[a["csiv"]] = {"sigla": a["sigla"], "posti": seats,
                               "dotazioni": [name for i, name in EQUIPMENT.items() if i in kit]}
        piani.append({**old.get(c, {}), "csip": c, "nome": names.get(c, c), "aule": aule})
        print(f"{c} {names.get(c, '')}: {', '.join(v['sigla'] for v in aule.values()) or 'no classrooms'}")

    text = json.dumps({"csie": csie, "piani": piani}, ensure_ascii=False, indent=2)
    dest.write_text(text + "\n")
    print(f"wrote {dest.relative_to(HERE)}")


if __name__ == "__main__":
    main(sys.argv[1])
