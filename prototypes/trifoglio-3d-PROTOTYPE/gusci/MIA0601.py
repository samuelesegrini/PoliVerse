"""PROTOTIPO — l'Edificio 32.1 (MIA0601), via Colombo: la palazzina del complesso 32, con due aule.

Fonti, oltre alle piante del Politecnico (seminterrato, terra, dal primo al terzo, sottotetto):
- la sagoma di OSM (w248727391, senza altezza): una L, il corpo lungo da nord a sud e l'ala
  corta a est in fondo;
- l'ortofoto (Esri World Imagery; qui combacia con OSM senza spostamenti): il tetto a falde in
  coppi sul corpo nord, attaccato al tetto della palazzina accanto (il muro nord è cieco), e la parte sud col tetto
  piano grigio e gli impianti;
- le piante: quattro piani pieni sulla L, il sottotetto solo all'angolo nord-est, sotto le
  falde; le finestre di ogni piano.

Nessuna foto delle facciate: intonaco chiaro con le finestre delle piante, piani da 3,6 m
dedotti dal numero dei piani.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0601"
H = 3.6
PIANI = [f"MIA060100{i}" for i in range(4)]
QUOTE = {"MIA060100S": -3.4, **{c: round(i * H, 2) for i, c in enumerate(PIANI)}, "MIA0601004": 4 * H}
GRONDA = 4 * H
FALDE = box(-98.5, 850.0, -84.0, 869.5)       # il corpo nord col tetto in coppi

INTONACO = "#E0D6C2"
TELAIO = "#4A4339"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return GRONDA


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=INTONACO, davanzale=0.9, architrave=2.8, telaio=TELAIO, sguincio=0.18, reach=1.5,
                 ripiego=(3.0, 1.2, 16.0), marcapiano=(0.25, 0.05, "#CDBF9F"))
    # i quattro piani hanno la stessa L, a meno delle scale e dei terrazzini: un corpo solo,
    # quello del secondo piano, squadrato
    corpo = max(k.pezzi(k.squadra(k.contorno("MIA0601002", chiudi=1.0), passo=0.5)), key=lambda g: g.area)
    for i, csip in enumerate(PIANI):
        k.piano(corpo, i * H, (i + 1) * H, st.con(davanzale=0.6) if i == 0 else st, csip=csip, porte=i == 0)
    nord = corpo.intersection(FALDE)
    k.falde(nord.minimum_rotated_rectangle, GRONDA, pendenza=0.45, sporto=0.5, colore="kit_coppi", gronda="#E2D9C6")
    sud = corpo.difference(FALDE)
    for q in k.pezzi(sud, 10):
        k.tetto_piano(q, GRONDA, parapetto=0.9, muro=INTONACO)
    x0, y0, x1, y1 = sud.bounds
    k.impianto(x0 + 5, y0 + 5, 3.0, 2.2, GRONDA + 0.1, h=1.6)
    k.impianto(x0 + 9.5, y0 + 4, 2.4, 2.0, GRONDA + 0.1, h=1.2)
    return k.fine()
