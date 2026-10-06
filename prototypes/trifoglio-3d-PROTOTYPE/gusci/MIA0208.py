"""PROTOTIPO — l'Edificio 14A (MIA0208), via Bonardi: il corpo seminterrato lungo 50 m davanti
al 14, verso il cortile, senza aule.

Fonti, oltre alle piante del Politecnico (seminterrato e soppalco):
- la sagoma di OSM, un rettangolo di 50 m per 15;
- le piante: solo il seminterrato e il soppalco, nessun piano fuori terra; le vetrate del
  soppalco guardano a sud, verso il 14;
- l'ortofoto (Esri World Imagery): il tetto chiaro poco sopra il cortile con un lungo
  lucernario in mezzo, e a sud la trincea in ombra su cui si affaccia.

Nessuna foto: il tetto è a 1,2 m sopra il cortile, la facciata sud vetrata scende nella
trincea, gli altri lati sono muri bassi in pietra.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0208"
QUOTE = {"MIA020800S": -4.0, "MIA0208S0S": -1.6}
TETTO = 1.2

PIETRA = "#A9A59C"
TELAIO = "#3F444A"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    corpo = k.squadra(k.contorno("MIA0208S0S", chiudi=0.6))
    corpo = max(k.pezzi(corpo), key=lambda g: g.area)
    vetro = K.Stile(muro=PIETRA, finestre="vetrata", telaio=TELAIO, vetro=K.VETRO, passo_montanti=1.5, architrave=99)
    muro = K.Stile(muro=PIETRA, finestre=None)
    # la facciata sud, vetrata, scende nella trincea; gli altri lati affiorano appena
    x0, y0, x1, y1 = corpo.bounds
    k.piano(corpo, -4.0, TETTO, lambda e, m: vetro if m[1] > y1 - 1.0 else muro)
    k.tetto_piano(corpo, TETTO, parapetto=0.6, muro=PIETRA, colore="#CFC9BD")
    k.piano(box(x0 + 8, (y0 + y1) / 2 - 2.5, x1 - 4, (y0 + y1) / 2 - 0.5), TETTO, TETTO + 0.5, K.Stile(muro="#E1E1DD", finestre=None))
    k.tetto_piano(box(x0 + 8, (y0 + y1) / 2 - 2.5, x1 - 4, (y0 + y1) / 2 - 0.5), TETTO + 0.5, parapetto=0.0, colore=K.VETRO_CHIARO)
    return k.fine()
