"""PROTOTIPO — l'Edificio 14B (MIA0209), via Bonardi: la palazzina a L di due piani all'angolo
nord-ovest del 14, senza aule.

Fonti, oltre alle piante del Politecnico (seminterrato, terra, primo):
- la sagoma di OSM, una L col braccio corto verso est;
- le piante: l'angolo sud-ovest tagliato in diagonale (verso il passaggio fra il 14 e il
  Trifoglio), la scala nel braccio corto, le finestre su tutti i lati al primo;
- l'ortofoto (Esri World Imagery): il tetto piano scuro col parapetto chiaro.

Nessuna foto delle facciate: intonaco chiaro con le finestre delle piante, piani da 4 m.
"""
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0209"
H = 4.0
QUOTE = {"MIA020900S": -3.6, "MIA0209000": 0.0, "MIA0209001": H}
TETTO = 2 * H

INTONACO = "#DAD5CB"
TELAIO = "#464B51"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=INTONACO, davanzale=0.9, architrave=3.0, telaio=TELAIO, sguincio=0.15, reach=1.5,
                 ripiego=(2.8, 1.3, 9.0), marcapiano=(0.3, 0.05, "#C6C1B6"))
    corpo = max(k.pezzi(k.contorno("MIA0209001", chiudi=0.6).simplify(0.3)), key=lambda g: g.area)
    k.piano(corpo, 0.0, H, st.con(davanzale=0.6), csip="MIA0209000", porte=True)
    k.piano(corpo, H, TETTO, st, csip="MIA0209001")
    k.tetto_piano(corpo, TETTO, parapetto=0.9, muro="#E2DED6", colore="#55595C")
    return k.fine()
