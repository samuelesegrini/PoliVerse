#!/usr/bin/env python3
"""PROTOTIPO — il campus di notte: quali vetri si accendono e la tavolozza notturna.

    python3 banco/notte.py "<PoliVerse/Preview Content/Trifoglio3D>"

Come Apple Maps con i suoi edifici 3D in aspetto scuro: i volumi si scuriscono verso il blu,
come sotto la luna, e una parte delle finestre resta accesa di un bianco caldo. Qui le
finestre non sono oggetti a parte: sono le facce che i gusci colorano con un colore di vetro
(le costanti `VETRO…` e gli argomenti `vetro=` di esporta3d.py e di gusci/). Ogni colore di
vetro è acceso o spento per intero, scelto dal suo codice, così edifici e fasce diverse non
si accendono tutti insieme.

Scrive nella cartella dei modelli:
- `notte.json`: i colori di vetro (sRGB a 8 bit) e, per quelli accesi, il colore della luce.
  Trifoglio3DScene lo usa per gli involucri veri, che hanno un materiale per colore.
- `lontano_notte.png`: la tavolozza di `campus_lontano.usdz` già scurita, con le caselle dei
  vetri accesi nel colore della luce. Trifoglio3DScene la scambia con quella di giorno.

Va rilanciato dopo aver rigenerato `campus_lontano.usdz` o cambiato un colore di vetro.
Dipendenze: numpy, pillow.
"""
import hashlib, io, json, pathlib, re, sys, zipfile
import numpy as np
from PIL import Image

QUI = pathlib.Path(__file__).resolve().parent.parent
NOTTE = np.array([0.24, 0.28, 0.38])                 # quanto resta di ogni canale, in lineare
LUCI = [(255, 214, 150), (255, 196, 118), (255, 226, 178)]   # bianco caldo, ambra, più chiaro
ACCESI = 0.6                                         # la parte dei colori di vetro che si accende
VICINO = 3                                           # scarto per canale entro cui un colore è quel vetro


def vetri():
    """I colori di vetro dei gusci: {hex: luce o None}. Fuori quelli usati anche per altro."""
    nomi = {}
    for f in [QUI / "esporta3d.py", *sorted((QUI / "gusci").glob("*.py"))]:
        for nome, hex_ in re.findall(r"(\w+)\s*=\s*\"(#[0-9A-Fa-f]{6})\"", f.read_text()):
            nomi.setdefault(hex_.upper(), set()).add(nome.lower())
    out = {}
    for hex_, ns in sorted(nomi.items()):
        if not all(n.startswith("vetr") for n in ns):
            continue
        h = hashlib.sha1(hex_.encode()).digest()
        out[hex_] = LUCI[h[1] % len(LUCI)] if h[0] / 255 < ACCESI else None
    return out


def lineare(c):
    c = np.asarray(c, float) / 255
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def srgb(c):
    c = np.clip(c, 0, 1)
    return np.round(np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055) * 255).astype(np.uint8)


def main(cartella):
    cartella = pathlib.Path(cartella)
    glass = {tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)): luce for h, luce in vetri().items()}
    (cartella / "notte.json").write_text(json.dumps(
        {"vetri": [{"colore": list(c), "luce": list(l) if l else None} for c, l in glass.items()]},
        indent=1) + "\n")
    with zipfile.ZipFile(cartella / "campus_lontano.usdz") as z:
        nome = next(n for n in z.namelist() if n.endswith("lontano.png"))
        giorno = np.array(Image.open(io.BytesIO(z.read(nome))).convert("RGB"))
    notte = srgb(lineare(giorno) * NOTTE)
    accese = 0
    keys = np.array(list(glass)) if glass else np.zeros((0, 3), int)
    for y in range(giorno.shape[0]):
        for x in range(giorno.shape[1]):
            if not len(keys):
                continue
            d = np.abs(keys - giorno[y, x].astype(int)).max(axis=1)
            k = int(d.argmin())
            luce = glass[tuple(keys[k])]
            if d[k] <= VICINO and luce:
                notte[y, x] = luce
                accese += 1
    Image.fromarray(notte).save(cartella / "lontano_notte.png")
    print(f"{len(glass)} colori di vetro, {sum(1 for l in glass.values() if l)} accesi; "
          f"{accese // 64} caselle accese nella tavolozza")


if __name__ == "__main__":
    main(sys.argv[1])
