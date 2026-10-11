"""PROTOTIPO — l'Edificio 14B (MIA0209), via Bonardi: la palazzina a L di due piani all'angolo
nord-ovest del 14, senza aule.

Fonti, oltre alle piante del Politecnico (seminterrato, terra, primo):
- la sagoma di OSM, una L col braccio corto verso est;
- le piante: l'angolo sud-ovest tagliato in diagonale (verso il passaggio fra il 14 e il
  Trifoglio), la scala nel braccio corto, le finestre su tutti i lati al primo;
- l'ortofoto di Google (z21, 2025): il tetto segue il primo piano, con la tacca a V verso
  sud e l'angolo tagliato; il manto è chiaro (#B1A99E), non scuro come sembrava
  nell'ortofoto Esri, e c'è un'unità di condizionamento sul lato est. L'ombra sul vialetto
  della piscina (3,0 m) e lo scivolamento del tetto (2,5 m) tornano con due piani da 4 m.

Nessuna foto delle facciate: intonaco chiaro con le finestre delle piante.
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
    k.tetto_piano(corpo, TETTO, parapetto=0.9, muro="#E2DED6", colore="#B1A99E")
    k.impianto(59.5, -20.0, 2.0, 1.4, TETTO + 0.1, h=1.2)
    return k.fine()
