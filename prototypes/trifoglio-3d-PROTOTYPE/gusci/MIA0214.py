"""PROTOTIPO — l'Edificio 16A (MIA0214), via Bonardi: il corpo sotto la piazza fra il Trifoglio e
il 14, senza aule.

Fonti, oltre alle piante del Politecnico (primo interrato, seminterrato, terra):
- la sagoma di OSM, un rettangolo di 44 m per 16;
- le piante: il seminterrato ha finestre su tutti i lati, sulle bocche di lupo; il terra è un
  unico spazio aperto (la piazza) con i due corpi d'ingresso a sud, ognuno con la sua scala
  che scende; la sala rotonda nel seminterrato a ovest;
- l'ortofoto (Esri World Imagery): la piazza pavimentata chiara con le fioriere e gli alberi,
  il lucernario quadrato scuro a sud-ovest, le bocche di lupo in ombra lungo i lati lunghi.

Nessuna foto: la piazza a 60 cm sopra il viale, i due ingressi come padiglioni vetrati bassi.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0214"
QUOTE = {"MIA021401I": -8.0, "MIA021400S": -4.0, "MIA0214000": 0.6}
PIAZZA = 0.6

PIETRA = "#B3AEA4"
PAVIMENTO = "#D8D1C3"
TELAIO = "#41464C"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return PIAZZA


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    corpo = k.squadra(k.contorno("MIA021400S", chiudi=0.6))
    corpo = max(k.pezzi(corpo), key=lambda g: g.area)
    # il seminterrato affiora sulle bocche di lupo con le sue finestre
    k.piano(corpo, -1.6, PIAZZA, K.Stile(muro=PIETRA, finestre="nastro", davanzale=0.3, architrave=1.9, telaio=TELAIO))
    k.tetto_piano(corpo, PIAZZA, parapetto=0.5, muro=PIETRA, colore=PAVIMENTO)
    # i due ingressi a sud: quello che il terra disegna fuori dal rettangolo
    vetro = K.Stile(muro=PIETRA, finestre="vetrata", telaio=TELAIO, vetro=K.VETRO_CHIARO, passo_montanti=1.4, architrave=99)
    terra = k.contorno("MIA0214000", chiudi=0.6)
    for q in k.pezzi(terra.difference(corpo.buffer(0.3, join_style=2)), 15.0):
        q = k.squadra(q)
        k.piano(q, 0.0, 3.2, vetro, csip="MIA0214000", porte=True)
        k.tetto_piano(q, 3.2, parapetto=0.3, colore="#6B6F72")
    # il lucernario quadrato e le fioriere con gli alberi
    k.piano(box(5.5, 47.5, 11.5, 53.5), PIAZZA, PIAZZA + 0.6, K.Stile(muro=PIETRA, finestre=None))
    k.tetto_piano(box(5.5, 47.5, 11.5, 53.5), PIAZZA + 0.6, parapetto=0.0, colore=K.VETRO)
    for x, y in ((0.0, 44.0), (2.0, 50.0), (31.0, 42.0), (33.0, 49.5), (5.0, 41.5), (28.0, 53.0)):
        k.piano(box(x - 1.2, y - 1.2, x + 1.2, y + 1.2), PIAZZA, PIAZZA + 0.5, K.Stile(muro=PIETRA, finestre=None))
        k.albero(x, y, r=2.0, h=None)
    return k.fine()
