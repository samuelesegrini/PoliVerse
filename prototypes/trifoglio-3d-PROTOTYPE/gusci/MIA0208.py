"""PROTOTIPO — l'Edificio 14A (MIA0208), via Bonardi: il capannone lungo 50 m fra la Nave e
la piscina Romano, senza aule.

Fonti, oltre alle piante del Politecnico (seminterrato e soppalco):
- la sagoma di OSM, un rettangolo di 50 m per 15;
- le piante: una sola sala alta su tutta la lunghezza, il soppalco solo all'estremità ovest
  e le finestre del soppalco su tutto il lato nord, verso la piscina;
- l'ortofoto di Google (z21, 2025): tetto piano color sabbia (#B9AEA0) con un lucernario
  lungo 36 m e largo 4 (x 69-105) a metà della sala, più chiaro (#DED0BB). L'ombra che il
  14A getta sul vialetto della piscina è lunga 2,7 m contro i 3,0 del 14B, e il suo tetto
  "scivola" a nord di 1,7 m contro 2,5: il colmo sta quindi a circa 6,5 m da terra, non
  a 1,2 come in un seminterrato basso. Il lucernario ne fa altri 1,8.

Nessuna foto delle facciate (la piscina e il vialetto non compaiono nelle foto trovate):
intonaco grigio chiaro, nastro di finestre dove la pianta del soppalco le disegna.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0208"
QUOTE = {"MIA020800S": -3.6, "MIA0208S0S": 0.4}
TETTO = 6.0
LUCERNARIO = (69.5, -18.8, 105.0, -14.8, 1.8)    # x0, y0, x1, y1, altezza (dall'ortofoto)

INTONACO = "#CFCBC2"
ZOCCOLO = "#9C988F"
TELAIO = "#3F444A"
MANTO = "#B9AEA0"
LUCE = "#DED0BB"


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
    # la parte sotto il vialetto resta cieca; sopra, le finestre del soppalco
    k.piano(corpo, -3.6, 0.4, K.Stile(muro=ZOCCOLO, finestre=None))
    st = K.Stile(muro=INTONACO, davanzale=1.1, architrave=3.4, telaio=TELAIO, sguincio=0.12, reach=1.5,
                 marcapiano=(0.25, 0.04, ZOCCOLO))
    k.piano(corpo, 0.4, TETTO, st, csip="MIA0208S0S")
    k.tetto_piano(corpo, TETTO, parapetto=0.6, muro=INTONACO, colore=MANTO)
    x0, y0, x1, y1, h = LUCERNARIO
    lu = box(x0, y0, x1, y1)
    vetri = K.Stile(muro=INTONACO, finestre="nastro", davanzale=0.3, architrave=h - 0.3, telaio=TELAIO,
                    vetro=K.VETRO_CHIARO, passo_montanti=1.2)
    k.piano(lu, TETTO, TETTO + h, lambda e, m: vetri if abs(m[0] - (x0 + x1) / 2) < (x1 - x0) / 2 - 0.1
            else K.Stile(muro=INTONACO, finestre=None))
    k.tetto_piano(lu, TETTO + h, parapetto=0.0, colore=LUCE)
    return k.fine()
