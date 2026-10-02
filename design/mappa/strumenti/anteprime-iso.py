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
    day = f'id="livello-{csip}" data-livello="piani" data-piano="{csip}">'
    lit = f'id="livello-{csip}-acceso" data-livello="piani" data-piano="{csip}" data-acceso="true" style="display: none">'
    if day not in s or lit not in s:
        sys.exit(f"{csip} is not a floor of {src}")
    s = s.replace(day, day[:-1] + ' style="display: none">').replace(lit, lit.replace(' style="display: none"', ""))
    (dest / f"iso-{csip}-acceso.svg").write_text(strip_hidden(s))


if __name__ == "__main__":
    main()
