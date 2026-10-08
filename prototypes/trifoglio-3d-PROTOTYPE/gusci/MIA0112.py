"""PROTOTIPO — l'Edificio 4A "Gaudenzio Fantoli" (MIA0112): la palazzina lunga di due piani fra
il 4 e il 5, con un'aula al primo.

Fonti, oltre alle piante del Politecnico (seminterrato, terra, primo):
- la sagoma di OSM e le piante, che combaciano;
- l'ortofoto (Esri World Imagery): il tetto è una volta ribassata lungo l'asse nord-sud,
  coperta di pannelli scuri (vetro o fotovoltaico) in sei campi fra costoloni bianchi, con la
  testata nord arrotondata.

Nessuna foto delle facciate: intonaco chiaro come il 4 accanto, con le finestre delle piante;
piani da 4,2 m.
"""
import sys
import pathlib
import numpy as np
from shapely.geometry import box
from shapely import affinity

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0112"
H = 4.2
QUOTE = {"MIA011200S": -3.4, "MIA0112000": 0.0, "MIA0112001": H}
TETTO = 2 * H

INTONACO = "#DCCFB3"
TELAIO = "#4F4A44"
PANNELLI = "#34404C"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=INTONACO, davanzale=0.9, architrave=3.0, telaio=TELAIO, sguincio=0.15, reach=1.5,
                 ripiego=(3.0, 1.4, 8.0), marcapiano=(0.25, 0.05, "#CBBE9F"))
    corpo = k.squadra(k.contorno("MIA0112001", chiudi=0.6))
    k.piano(corpo, 0.0, H, st.con(davanzale=0.6), csip="MIA0112000", porte=True)
    k.piano(corpo, H, TETTO, st, csip="MIA0112001")
    for e in E.edges(E.ring_ccw(corpo)):
        k.pannello("#E4DBC8", e, K.rett(0, e[4], TETTO - 0.4, TETTO), 0.0, 0.3)
    # la volta coperta di pannelli scuri, con i costoloni bianchi
    r = corpo.minimum_rotated_rectangle
    k.volta(r, TETTO, 2.2, colore=PANNELLI)
    x0, y0, x1, y1 = r.bounds
    for y in np.linspace(y0 + 0.3, y1 - 0.3, 4):
        seg = box(x0, y - 0.25, x1, y + 0.25)
        k.volta(seg, TETTO + 0.05, 2.2, colore="#E8E8E4")
    k.top = max(k.top, TETTO + 2.3)
    return k.fine()
