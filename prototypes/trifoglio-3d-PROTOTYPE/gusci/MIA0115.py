"""PROTOTIPO — l'Edificio 3A (MIA0115), Lerici: il corpo basso a terrazze fra il 3 e il 5,
senza aule.

Fonti, oltre alle piante del Politecnico (seminterrato, terra, primo): la sagoma di OSM, su cui
sta il seminterrato; il terra copre la parte di mezzo, il primo quella sud; l'ortofoto (Esri
World Imagery): a nord il giardino sopra il seminterrato, a scalini, e a sud il tetto chiaro
del primo. Le finestre sono quelle delle piante. Nessuna foto; piani da 3,6 m, il seminterrato
che esce di un metro.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0115"
H = 3.6
QUOTE = {"MIA011500S": -2.6, "MIA0115000": 1.0, "MIA0115001": 1.0 + H}
TETTO = 1.0 + 2 * H


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro="#D8D2C6", davanzale=0.9, architrave=2.8, telaio="#464B51", sguincio=0.15, reach=1.5,
                 ripiego=(3.0, 1.3, 10.0), marcapiano=(0.3, 0.05, "#C6C0B4"))
    sotto = max(k.pezzi(k.squadra(k.contorno("MIA011500S", chiudi=0.6))), key=lambda g: g.area)
    terra = max(k.pezzi(k.squadra(k.contorno("MIA0115000", chiudi=0.6))), key=lambda g: g.area)
    primo = max(k.pezzi(k.squadra(k.contorno("MIA0115001", chiudi=0.6))), key=lambda g: g.area)
    k.piano(sotto, -0.3, 1.0, K.Stile(muro="#A5A199", finestre="nastro", davanzale=0.2, architrave=1.1, telaio="#464B51"))
    k.tetto_piano(sotto.difference(terra.buffer(0.2, join_style=2)), 1.0, parapetto=0.9, muro="#A5A199", colore="#7C9660")
    k.piano(terra, 1.0, 1.0 + H, st, csip="MIA0115000", porte=True)
    k.tetto_piano(terra.difference(primo.buffer(0.2, join_style=2)), 1.0 + H, parapetto=0.9, muro="#D8D2C6", colore="#7C9660")
    k.piano(primo, 1.0 + H, TETTO, st, csip="MIA0115001")
    k.tetto_piano(primo, TETTO, parapetto=0.8, muro="#D8D2C6", colore="#D2CEC6")
    return k.fine()
