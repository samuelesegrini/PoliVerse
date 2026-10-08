"""PROTOTIPO — l'Edificio 16C (MIA0215): le aule sotto la piazza della Nave, tutte al
seminterrato.

Fonti: la pianta del Politecnico (il seminterrato, tre aule) e l'ortofoto (Esri World Imagery),
dove al suo posto c'è la piazza chiara pavimentata fra le due ali della Nave. Fuori terra non
c'è nulla: il guscio è il solaio della piazza, con un parapetto basso dove scende la scala.
"""
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0215"
QUOTE = {"MIA021500S": -4.6}
TETTO = -0.4


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    piazza = k.squadra(k.contorno("MIA021500S", chiudi=0.8))
    k.tetto_piano(piazza, 0.0, parapetto=0.0, colore="#D9D4C8")
    k.top = 0.1
    return k.fine()
