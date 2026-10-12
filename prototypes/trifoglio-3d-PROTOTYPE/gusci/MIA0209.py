"""PROTOTIPO — l'Edificio 14B (MIA0209), via Bonardi: la palazzina a L di tre livelli all'angolo
nord-ovest del 14, senza aule.

Fonti, oltre alle piante del Politecnico (seminterrato, terra, primo):
- la sagoma di OSM, una L col braccio corto verso est;
- le piante: l'angolo sud-ovest tagliato in diagonale (verso il passaggio fra il 14 e il
  Trifoglio), la scala nel braccio corto, le finestre su tutti i lati al primo;
- l'ortofoto di Google (z21, 2025): il tetto segue il primo piano, con la tacca a V verso
  sud e l'angolo tagliato; il manto è chiaro (#B1A99E), non scuro come sembrava
  nell'ortofoto Esri, e c'è un'unità di condizionamento sul lato est. L'ombra sul vialetto
  della piscina (3,0 m) e lo scivolamento del tetto (2,5 m) tornano con tre livelli fuori
  terra da 3,4 m più la fascia in cima;
- i panorami Mapillary del 15 novembre 2024 dal vialetto a ovest (id 3771834289698189,
  591975983503212): il seminterrato, che su tutti i lati è il piano terra, è grigio ardesia
  con una lunga parete in vetrocemento e la porta all'angolo nord; i due piani sopra sono
  rivestiti di pannelli metallici color argento a giunti verticali, ognuno con un nastro di
  finestre a telaio scuro nella metà alta; sopra l'ultimo nastro una fascia piena di 1,2 m.
  I piani argento sporgono di una trentina di centimetri sul piano terra.
"""
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0209"
H = 3.4
# il "seminterrato" ha le porte sul vialetto della piscina e sul passaggio a sud-ovest: è il
# piano terra rispetto al suolo che c'è intorno, i due piani sopra stanno fuori terra
QUOTE = {"MIA020900S": 0.0, "MIA0209000": H, "MIA0209001": 2 * H}
TETTO = 3 * H

ARGENTO = "#D5D8DA"
ARDESIA = "#4F5660"
VETROCEMENTO = "#D8DEDC"
TELAIO = "#3A3F46"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    corpo = max(k.pezzi(k.contorno("MIA0209001", chiudi=0.6).simplify(0.3)), key=lambda g: g.area)
    x1 = corpo.bounds[2]
    # il lato verso il 14A e la Nave resta nudo: ci si attacca il capannone
    def lati(st):
        return lambda e, m: None if m[0] > x1 - 0.3 else st
    nastro = K.Stile(muro=ARGENTO, finestre="nastro", davanzale=1.7, architrave=3.0, telaio=TELAIO,
                     vetro=K.VETRO, passo_montanti=1.3)
    base = K.Stile(muro=ARDESIA, finestre="nastro", davanzale=0.4, architrave=3.0, telaio="#AEB6B5",
                   vetro=VETROCEMENTO, passo_montanti=0.25)
    # i due piani argento sporgono un poco sul piano terra scuro; il vetrocemento è solo a ovest
    terra = corpo.buffer(-0.3, join_style=2)
    x0 = terra.bounds[0]
    k.piano(terra, 0.0, H, lambda e, m: None if m[0] > x1 - 0.6 else base if m[0] < x0 + 0.3
            else K.Stile(muro=ARDESIA, finestre=None), csip="MIA020900S", porte=True)
    k.piano(corpo, H, 2 * H, lati(nastro))
    k.piano(corpo, 2 * H, TETTO, lati(nastro))
    k.tetto_piano(corpo, TETTO, parapetto=1.2, muro=ARGENTO, colore="#B1A99E")
    k.impianto(59.5, -20.0, 2.0, 1.4, TETTO + 0.1, h=1.2)
    return k.fine()
