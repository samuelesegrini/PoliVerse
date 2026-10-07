"""PROTOTIPO — l'Edificio 12 (MIA0202), via Bonardi: la torre di sette piani fra il Trifoglio e
il 14, senza aule.

Fonti, oltre alle piante del Politecnico (seminterrato e soppalco, rialzato, dal primo al
sesto):
- la sagoma di OSM, su cui stanno il seminterrato e il rialzato;
- le piante: i piani dal primo al quinto sono disegnati con un'origine loro, e stanno sul
  rialzato spostandoli finché la scala coincide (gli `spostamenti` in `leonardo.json`); sono un
  po' più stretti del rialzato, che sporge a est. Il sesto è un attico sul lato ovest. Le
  finestre su tutti i lati, fitte;
- l'ortofoto (Esri World Imagery): il tetto piano grigio della torre con qualche impianto, la
  lunga ombra verso nord, la striscia più bassa del rialzato a est.

- le foto del campus rinnovato (Urbanfile, giugno 2021, col totem "12 Cesare Chiodi"): la torre
  in klinker testa di moro, con le finestre delle piante incorniciate di bianco e legate da
  lesene bianche che salgono per tutta l'altezza.

Piani da 3,3 m e il rialzato a un metro da terra.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0202"
H = 3.3
R = 1.0
SU = [f"MIA020200{i}" for i in range(1, 7)]
QUOTE = {"MIA020200S": -3.0, "MIA0202S0S": -1.4, "MIA020200R": R, **{c: round(R + (i + 1) * H, 2) for i, c in enumerate(SU)}}
TETTO = round(QUOTE["MIA0202005"] + H, 2)

KLINKER = "kit_klinker_scuro"
BIANCO = "#E6E5E0"           # le cornici e le lesene delle finestre
ZOCCOLO = "#5E4D45"
TELAIO = "#D9D9D5"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=KLINKER, davanzale=0.9, architrave=2.5, telaio=TELAIO, sguincio=0.15, reach=1.4,
                 ripiego=(2.6, 1.3, 10.0), cornice=BIANCO, lesene=(0.08, 0.16, BIANCO))
    rialzato = k.squadra(k.contorno("MIA020200R", chiudi=0.6))
    torre = k.squadra(k.contorno("MIA0202002", chiudi=0.6))
    attico = k.squadra(k.contorno("MIA0202006", chiudi=0.6))
    k.piano(rialzato, -0.3, R, K.Stile(muro=ZOCCOLO, finestre=None))
    k.piano(rialzato, R, QUOTE["MIA0202001"], st.con(davanzale=0.6), csip="MIA020200R", porte=True)
    k.tetto_piano(rialzato.difference(torre.buffer(0.2, join_style=2)), QUOTE["MIA0202001"], parapetto=0.8, muro=KLINKER)
    for c in SU[:-1]:
        k.piano(torre, QUOTE[c], QUOTE[c] + H, st, csip=c)
    k.tetto_piano(torre.difference(attico.buffer(0.2, join_style=2)), TETTO, parapetto=1.0, muro=KLINKER)
    k.piano(attico, TETTO, TETTO + 3.0, st, csip="MIA0202006")
    k.tetto_piano(attico, TETTO + 3.0, parapetto=0.6, muro=KLINKER)
    x0, y0, x1, y1 = torre.bounds
    k.impianto(x1 - 4.0, y0 + 4.0, 3.0, 2.0, TETTO + 0.1, h=1.5)
    k.impianto(x1 - 4.0, y1 - 5.0, 2.4, 2.0, TETTO + 0.1, h=1.2)
    return k.fine()
