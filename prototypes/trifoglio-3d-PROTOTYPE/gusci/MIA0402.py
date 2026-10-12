"""PROTOTIPO — l'Edificio 23 (MIA0402), via Golgi: il capannone a un piano fra il 22 e il 25,
con le aule G.0.1 e G.0.2 a ovest e i laboratori a est.

Fonti, oltre alla pianta del Politecnico (il terra, l'unico piano):
- la sagoma e l'altezza di OSM (w41758125, 10,7 m, un piano); la pianta è più lunga di OSM di
  qualche metro per parte, e sta con l'ortofoto: il guscio segue la pianta;
- l'ortofoto (Esri World Imagery, spostata di circa 8 m verso est e 5 m verso nord), rimessa
  sulla pianta: la navata alta da x 514,6 a 557 coperta da due tetti chiari affiancati, uno
  largo verso nord e uno stretto verso sud, con il canale in mezzo a y 255,7; lungo il lato
  nord una navata bassa scura, sempre in ombra (è più bassa della navata alta), che comincia
  dove la pianta fa il dente a x 520; in testa verso via Golgi un corpo basso con le macchine
  sul tetto;
- la pianta: le finestre sui lati lunghi e le porte verso il cortile a sud.

Nessuna foto delle facciate: muri intonacati; sopra la navata bassa, le finestre alte della
navata.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0402"
GRONDA = 9.0
FRECCIA = 1.0
BASSO = 4.5                       # la navata bassa a nord e il corpo verso via Golgi
NORD = 249.8                      # dove comincia la navata alta
CANALE = 255.7                    # il canale fra i due tetti chiari
EST = 557.0                       # dove finisce la navata alta, verso via Golgi

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
    navata = corpo.intersection(box(0, NORD, EST, 1000))
    # tutto il piano terra, poi la navata alta sopra la navata bassa e il corpo verso la strada
    k.piano(corpo, 0.0, BASSO, st, csip="MIA0402000", porte=True)
    k.tetto_piano(corpo.difference(navata), BASSO, parapetto=0.5, muro=INTONACO, colore="#5A5E61")
    k.piano(navata, BASSO, GRONDA, K.Stile(muro=INTONACO, finestre=("passo", 2.4, 1.6), davanzale=1.2, architrave=3.4, telaio=TELAIO))
    k.tetto_piano(navata, GRONDA, parapetto=0.0, muro=INTONACO, colore="#BFC0BC")
    # i due tetti chiari affiancati, il largo a nord e lo stretto a sud
    nx0 = navata.bounds[0]
    for ya, yb in ((NORD, CANALE), (CANALE, y1)):
        k.volta(box(nx0 + 0.3, ya + 0.2, EST - 0.3, yb - 0.2), GRONDA, FRECCIA * (yb - ya) / 6.0, colore="#E4E3DE")
    # le macchine sul corpo verso via Golgi
    k.impianto((EST + x1) / 2, NORD + 2.5, 2.4, 1.6, BASSO + 0.1, h=1.2)
    k.impianto((EST + x1) / 2, NORD + 6.0, 2.4, 1.6, BASSO + 0.1, h=1.2)
    return k.fine()
