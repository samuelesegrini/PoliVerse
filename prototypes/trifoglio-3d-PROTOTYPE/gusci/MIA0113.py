"""PROTOTIPO — l'Edificio 9A (MIA0113), Poli.Radio: la palazzina stretta di due piani a est del 9,
senza aule.

Fonti, oltre alle piante del Politecnico (terra e primo): la sagoma di OSM; il terra era
disegnato 3 m più a ovest del primo e ci sta sopra con lo `spostamento` in `leonardo.json`
(la scala coincide); il `profilo` dell'illustrazione della mappa: intonaco, finestre rette,
due piani, il cornicione e il tetto in coppi, che l'ortofoto conferma (falde rosse). Nessuna
foto delle facciate; piani da 3,8 m.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0113"
H = 3.8
QUOTE = {"MIA0113000": 0.0, "MIA0113001": H}
TETTO = 2 * H


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro="#E3D3B4", davanzale=0.9, architrave=2.8, telaio="#5A4A3A", sguincio=0.15, reach=1.5,
                 ripiego=(3.0, 1.1, 8.0), cornice="#D2C2A2", marcapiano=(0.25, 0.06, "#D2C2A2"))
    corpo = k.contorno("MIA0113001", chiudi=0.4).minimum_rotated_rectangle
    k.piano(corpo, 0.0, H, st, csip="MIA0113000", porte=True)
    k.piano(corpo, H, TETTO, st, csip="MIA0113001")
    for e in E.edges(E.ring_ccw(corpo)):
        k.pannello("#D2C2A2", e, K.rett(0, e[4], TETTO - 0.5, TETTO), 0.0, 0.45)
    k.falde(corpo, TETTO, pendenza=0.45, sporto=0.5, colore="kit_coppi", gronda="#E2D6BE")
    return k.fine()
