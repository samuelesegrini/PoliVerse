"""PROTOTIPO — l'Edificio 26 (MIA1401), via Golgi 20: le aule L26 e, nel seminterrato, la mensa
Golgi.

Fonti, oltre alle piante del Politecnico (seminterrato, terra rialzato, primo):
- la sagoma di OSM (w26013442, 9 m, due piani);
- l'ortofoto (Esri World Imagery, spostata di circa 8 m verso est e 5 m verso nord rispetto a
  OSM): il tetto piano tutto coperto di file di pannelli fotovoltaici in senso est-ovest,
  diviso da una linea a un terzo da nord, dove il primo piano comincia (come nelle piante, che
  disegnano il primo solo sulla parte sud); al centro del tetto del primo il blocco degli
  impianti con il suo parapetto;
- le piante: il terra ha finestre su tutto il perimetro e le porte verso via Golgi a ovest e
  verso il parcheggio a nord; le scale di sicurezza esterne del primo scendono a sud.

Nessuna foto delle facciate: sono dedotte, intonaco chiaro con le finestre delle piante e il
marcapiano sul filo dei solai. Il terra è rialzato (le sale studio "al rialzato"), il
seminterrato sta sotto il livello della strada.
"""
import sys
import pathlib
import trimesh
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA1401"
QUOTE = {"MIA140100S": -3.0, "MIA1401000": 1.2, "MIA1401001": 5.4}
TETTO_0, TETTO_1 = 5.4, 9.4

INTONACO = "#D9D5CB"
ZOCCOLO = "#9B9A94"
TELAIO = "#4A4F55"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO_1


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=INTONACO, davanzale=0.9, architrave=3.0, telaio=TELAIO, sguincio=0.15, reach=1.6,
                 marcapiano=(0.4, 0.08, "#C4C0B6"))
    terra = k.squadra(k.contorno("MIA1401000", chiudi=0.8))
    primo = k.squadra(k.contorno("MIA1401001", chiudi=0.8))
    k.piano(terra, -0.2, 1.2, K.Stile(muro=ZOCCOLO, finestre=None))
    k.piano(terra, 1.2, TETTO_0, st, csip="MIA1401000", porte=True)
    k.piano(primo, TETTO_0, TETTO_1, st, csip="MIA1401001")
    # i tetti piani: la parte nord del terra e il primo, coperti di fotovoltaico
    basso = terra.difference(primo.buffer(0.2, join_style=2))
    k.tetto_piano(basso, TETTO_0, parapetto=0.6, muro=INTONACO)
    k.tetto_piano(primo, TETTO_1, parapetto=0.8, muro=INTONACO)
    for q in k.pezzi(basso, 20):
        k.fotovoltaico(q.buffer(-0.8, join_style=2), TETTO_0 + 0.08)
    impianti = box(534.0, 471.0, 554.0, 482.0)
    for q in k.pezzi(primo.buffer(-0.9, join_style=2).difference(impianti.buffer(1.0, join_style=2)), 10):
        k.fotovoltaico(q, TETTO_1 + 0.08)
    # il blocco degli impianti al centro, col parapetto suo
    k.piano(impianti, TETTO_1, TETTO_1 + 2.4, K.Stile(muro="#CFCBC2", finestre=None))
    k.tetto_piano(impianti, TETTO_1 + 2.4, parapetto=0.4)
    for x, y in ((539.0, 476.0), (546.0, 475.0), (550.0, 478.5)):
        k.impianto(x, y, 2.2, 1.6, TETTO_1 + 2.5, h=1.0)
    return k.fine()
