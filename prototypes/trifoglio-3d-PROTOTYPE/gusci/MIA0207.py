"""PROTOTIPO — l'Edificio 18 (MIA0207), via Bonardi: la palazzina quadrata a un piano dietro al
Trifoglio, fra gli alberi lungo la ferrovia, senza aule.

Fonti, oltre alle piante del Politecnico (seminterrato e terra):
- la sagoma di OSM, un quadrato di 11 m per 10;
- l'ortofoto (Esri World Imagery): il tetto a padiglione chiaro, quasi una piramide;
- le piante: la scala in mezzo, le stanze intorno; nessuna finestra disegnata.

Nessuna foto delle facciate: intonaco chiaro, finestre a passo regolare, un piano da 4 m.
"""
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0207"
QUOTE = {"MIA020700S": -3.2, "MIA0207000": 0.4}
GRONDA = 4.4

INTONACO = "#DED8CB"
TELAIO = "#4A4F55"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return GRONDA


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    corpo = k.contorno("MIA020700S", chiudi=0.4).minimum_rotated_rectangle
    k.piano(corpo, -0.2, 0.4, K.Stile(muro="#A19F98", finestre=None))
    k.piano(corpo, 0.4, GRONDA, K.Stile(muro=INTONACO, finestre=("passo", 2.6, 1.2), davanzale=1.0, architrave=2.8,
                                        telaio=TELAIO, sguincio=0.15), csip="MIA0207000", porte=True)
    k.falde(corpo, GRONDA, pendenza=0.4, sporto=0.5, colore="#C9C2B4", gronda="#E2DED6")
    return k.fine()
