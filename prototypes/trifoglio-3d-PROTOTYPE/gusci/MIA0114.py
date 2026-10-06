"""PROTOTIPO — l'Edificio 2A (MIA0114), la Sala Lettura: il corpo basso sotto la terrazza fra il
2 e il 3, senza aule.

Fonti, oltre alle piante del Politecnico (due interrati, seminterrato, terra): la sagoma di OSM;
il `profilo` dell'illustrazione della mappa: lo zoccolo in pietra del seminterrato, il terra in
cemento, sopra la terrazza; l'ortofoto (Esri World Imagery): la terrazza pavimentata col
vialetto in mezzo e le quattro aiuole quadrate. Le finestre sono quelle delle piante. Nessuna
foto.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0114"
QUOTE = {"MIA011402I": -9.0, "MIA011401I": -6.0, "MIA011400S": -3.0, "MIA0114000": 1.0}
TETTO = 4.2


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    corpo = max(k.pezzi(k.squadra(k.contorno("MIA0114000", chiudi=0.6))), key=lambda g: g.area)
    k.piano(corpo, -0.5, 1.0, K.Stile(muro="kit_bugnato_grigio", finestre=None))
    k.piano(corpo, 1.0, TETTO, K.Stile(muro="#B9B7B0", davanzale=0.6, architrave=2.6, telaio="#3F444A", sguincio=0.2,
                                       reach=1.5, ripiego=(3.2, 1.6, 12.0)), csip="MIA0114000", porte=True)
    k.tetto_piano(corpo, TETTO, parapetto=1.0, muro="#B9B7B0", colore="#9EA1A3")
    for x, y in ((-2.5, 118.0), (2.5, 118.0), (-2.5, 126.0), (2.5, 126.0)):
        q = box(x - 1.6, y - 2.6, x + 1.6, y + 2.6)
        k.piano(q, TETTO, TETTO + 0.5, K.Stile(muro="#8F8C84", finestre=None))
        k.tetto_piano(q, TETTO + 0.5, parapetto=0.0, colore="#6E8A55")
    return k.fine()
