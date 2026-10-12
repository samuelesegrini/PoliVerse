"""PROTOTIPO — l'Edificio 32.3 (MIA0603), via Colombo: il padiglione a un piano con le aule
E.P.1, E.P.2 ed E.P.3.

Fonti, oltre alle piante del Politecnico (seminterrato e terra):
- la sagoma di OSM (w248727402, senza altezza né piani): una L, piena a nord e con una gamba
  verso sud sul lato ovest;
- l'ortofoto (Esri World Imagery; qui combacia con OSM): un tetto piano scuro, coi lucernari
  sopra la parte nord-est e qualche impianto sulla gamba sud;
- le piante: il seminterrato sta sulla sagoma di OSM, il terra no: disegna un rettangolo pieno
  a sud con un'ala stretta a nord-est. Le due cose non si mettono d'accordo con una sola
  trasformazione, e il guscio prende l'unione delle due, a un piano solo.

Nessuna foto delle facciate e nessuna altezza: un piano da 4,5 m dedotto dall'ombra corta
dell'ortofoto, muri intonacati con le finestre della pianta del terra dove cadono sul bordo.
"""
import sys
import pathlib
from shapely.geometry import Polygon

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0603"
QUOTE = {"MIA060300S": -3.6, "MIA0603000": 0.0}
TETTO = 4.5

INTONACO = "#D6D2C8"
TELAIO = "#454A50"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=INTONACO, davanzale=0.9, architrave=3.0, telaio=TELAIO, sguincio=0.15, reach=1.5,
                 ripiego=(3.0, 1.4, 8.0), marcapiano=None)
    corpo = k.squadra(Polygon(b["pianta"]).union(k.contorno("MIA0603000", chiudi=0.6)), passo=0.5)
    corpo = max(k.pezzi(corpo), key=lambda g: g.area)
    k.piano(corpo, 0.0, TETTO, st, csip="MIA0603000", porte=True)
    k.tetto_piano(corpo, TETTO, parapetto=0.7, muro=INTONACO, colore="#55595B")
    # i lucernari sulla parte nord-est
    for x in (-67.5, -64.5, -61.5):
        k.piano(Polygon([(x, 897.5), (x + 2.2, 897.5), (x + 2.2, 902.5), (x, 902.5)]), TETTO, TETTO + 0.7,
                K.Stile(muro="#E6E6E2", finestre=None))
        k.tetto_piano(Polygon([(x, 897.5), (x + 2.2, 897.5), (x + 2.2, 902.5), (x, 902.5)]), TETTO + 0.7, parapetto=0.0, colore=K.VETRO_CHIARO)
    k.impianto(-73.0, 913.0, 2.0, 1.6, TETTO + 0.1, h=1.0)
    return k.fine()
