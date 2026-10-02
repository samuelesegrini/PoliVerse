#!/usr/bin/env python3
"""Writes two preview images of a building's isometric view: by day, and with one
floor's lights on. Hidden layers are dropped, so the files are small and show
exactly what they look like.

    python3 strumenti/anteprime-iso.py leonardo/MIA0203-isometrico.svg MIA0203000 out/
"""
import pathlib
import re
import sys


def strip_hidden(s):
    out, i = [], 0
    while True:
        m = re.search(r'<g id="livello-[^"]*"[^>]*style="display: none">', s[i:])
        if not m:
            out.append(s[i:])
            return "".join(out)
        start = i + m.start()
        out.append(s[i:start])
        depth = 0
        for t in re.finditer(r"<g[\s>]|</g>", s[start:]):
            depth += 1 if t.group(0) != "</g>" else -1
            if depth == 0:
                i = start + t.end()
                break


def main():
    src, csip, dest = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
    dest.mkdir(parents=True, exist_ok=True)
    s = src.read_text()
    (dest / "iso-giorno.svg").write_text(strip_hidden(s))
    # Every layer of that floor (its storey, its skylights) swaps to its lit twin.
    day = re.compile(r'(<g id="livello-[^"]*" data-livello="[^"]*" data-piano="%s")>' % re.escape(csip))
    lit = re.compile(r'(<g id="livello-[^"]*-acceso" data-livello="[^"]*" data-piano="%s" data-acceso="true") style="display: none">' % re.escape(csip))
    if not day.search(s) or not lit.search(s):
        sys.exit(f"{csip} is not a floor of {src}")
    s = lit.sub(r"\1>", day.sub(r'\1 style="display: none">', s))
    (dest / f"iso-{csip}-acceso.svg").write_text(strip_hidden(s))


if __name__ == "__main__":
    main()
