"""PROTOTIPO — l'Edificio 23 (MIA0402), via Golgi: il capannone a un piano fra il 22 e il 25,
con le aule G.0.1 e G.0.2 a ovest e i laboratori a est.

Fonti, oltre alla pianta del Politecnico (il terra, l'unico piano):
- la sagoma e l'altezza di OSM (w41758125, 10,7 m, un piano); la pianta è più lunga di OSM di
  qualche metro per parte, e sta con l'ortofoto: il guscio segue la pianta;
- l'ortofoto (Esri World Imagery, spostata di circa 8 m verso est e 5 m verso nord): il tetto
  a due lunghe coperture chiare affiancate da ovest a est, lette come due botti ribassate, e
  la testata ovest più bassa e scura;
- la pianta: le finestre sui lati lunghi e le porte verso il cortile a sud.

Nessuna foto delle facciate: muri intonacati, l'altezza del capannone presa da OSM.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0402"
GRONDA = 9.0
FRECCIA = 1.2
OVEST = 520.5                     # la testata più bassa, a ovest

INTONACO = "#DAD5CA"
TELAIO = "#4A4F55"


def quote(b, E):
    return {"MIA0402000": 0.0}


def tetto(b, E):
    return GRONDA


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=INTONACO, davanzale=0.9, architrave=3.0, telaio=TELAIO, sguincio=0.15, reach=1.5,
                 ripiego=(3.0, 1.6, 10.0), marcapiano=(0.4, 0.06, "#C6C1B6"))
    corpo = k.squadra(k.contorno("MIA0402000", chiudi=0.6))
    corpo = max(k.pezzi(corpo), key=lambda g: g.area)
    x0, y0, x1, y1 = corpo.bounds
    testata = corpo.intersection(box(0, 0, OVEST, 1000))
    capannone = corpo.difference(box(0, 0, OVEST, 1000))
    k.piano(testata, 0.0, 5.0, st, csip="MIA0402000", porte=True)
    k.tetto_piano(testata, 5.0, parapetto=0.5, muro=INTONACO, colore="#5A5E61")
    k.piano(capannone, 0.0, 4.2, st, csip="MIA0402000", porte=True)
    k.piano(capannone, 4.2, GRONDA, K.Stile(muro=INTONACO, finestre=("passo", 2.4, 1.6), davanzale=1.0, architrave=3.4, telaio=TELAIO))
    k.tetto_piano(capannone, GRONDA, parapetto=0.0, muro=INTONACO, colore="#BFC0BC")
    # le due botti chiare affiancate
    m = (y0 + y1) / 2
    for ya, yb in ((y0, m), (m, y1)):
        k.volta(box(OVEST + 0.3, ya + 0.3, x1 - 0.3, yb - 0.3), GRONDA, FRECCIA, colore="#E4E3DE")
    return k.fine()
