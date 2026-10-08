"""PROTOTIPO — l'Edificio 10 (MIA0110), la Posta: la palazzina a un piano nel campus di piazza
Leonardo, senza aule.

Fonti, oltre alla pianta del Politecnico (il terra): la sagoma di OSM, e il `profilo` che
`leonardo.json` ha preso dall'illustrazione della mappa: intonaco, finestre rette a campate di
3,6 m, un piano da 5 m, il cornicione e il tetto a terrazza grigio. Nessuna foto.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0110"
QUOTE = {"MIA0110000": 0.0}
TETTO = 5.0


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    corpo = k.squadra(k.contorno("MIA0110000", chiudi=0.4))
    k.piano(corpo, 0.0, TETTO, K.Stile(muro="#E0D9C9", finestre=("passo", 3.6, 1.4), davanzale=1.0, architrave=3.3,
                                       telaio="#4A4F55", sguincio=0.15, cornice="#CFC7B4"), csip="MIA0110000", porte=True)
    k.tetto_piano(corpo, TETTO, parapetto=0.8, muro="#D3CBB9", colore="#A3A19A")
    for e in E.edges(E.ring_ccw(corpo)):
        k.pannello("#C9C1AE", e, K.rett(0, e[4], TETTO + 0.4, TETTO + 0.8), 0.0, 0.4)
    return k.fine()
