"""PROTOTIPO — l'Edificio 19 "Mario Silvestri" (MIA0302), via Ponzio 34/3: i laboratori e gli
uffici di Energia, con un'aula al terra.

Fonti, oltre alle piante del Politecnico (secondo interrato, seminterrato, terra, primo,
secondo):
- la sagoma di OSM (w26144878, 7,6 m, tre piani), che tiene insieme la stecca delle piante e il
  corpo basso a nord, che nelle piante non c'è;
- l'ortofoto (Esri World Imagery, spostata di circa 8 m verso est e 5 m verso nord): la stecca
  col tetto bianco a padiglione molto basso, i due lucernari sopra il cavedio del secondo
  piano; il corpo a nord col tetto piano scuro e un volume chiaro al centro;
- le piante: le finestre su tutti i lati, la scala di sicurezza esterna sulla testata est. La
  grande sala del seminterrato verso via Ponzio sta sotto il cortile, e non esce.

Nessuna foto delle facciate: intonaco chiaro con le finestre delle piante, piani da 3,4 m. Il
corpo nord è solo un volume, alto due piani, senza finestre disegnate.
"""
import sys
import pathlib
from shapely.geometry import Polygon, box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0302"
H = 3.4
QUOTE = {"MIA030201I": -7.4, "MIA030200S": -3.8, "MIA0302000": 0.0, "MIA0302001": H, "MIA0302002": 2 * H}
TETTO = 3 * H
STECCA = box(227.3, 126.4, 264.9, 145.0)

INTONACO = "#E2DED4"
TELAIO = "#4A4F55"
NORD = "#BDB6A8"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=INTONACO, davanzale=0.9, architrave=2.7, telaio=TELAIO, sguincio=0.15, reach=1.5, ripiego=(2.7, 1.4, 12.0),
                 marcapiano=(0.3, 0.05, "#CBC7BD"))
    corpo = k.squadra(k.contorno("MIA0302001", chiudi=0.6).intersection(STECCA.buffer(0.5, join_style=2)))
    corpo = max(k.pezzi(corpo), key=lambda g: g.area)
    for i, csip in enumerate(("MIA0302000", "MIA0302001", "MIA0302002")):
        k.piano(corpo, i * H, (i + 1) * H, st.con(davanzale=0.5) if i == 0 else st, csip=csip, porte=i == 0)
    # il tetto bianco a padiglione, quasi piano
    k.falde(corpo.minimum_rotated_rectangle, TETTO, pendenza=0.12, sporto=0.4, colore="#E6E6E2", gronda="#CFCFCA")
    # il corpo basso a nord, dalla sagoma di OSM
    nord = Polygon(b["pianta"]).difference(corpo.buffer(0.3, join_style=2))
    for q in k.pezzi(nord, 20):
        q = k.squadra(q)
        k.piano(q, 0.0, 2 * H, K.Stile(muro=NORD, finestre=("passo", 3.0, 1.2), davanzale=1.0, architrave=2.6, telaio=TELAIO))
        k.tetto_piano(q, 2 * H, parapetto=0.6, muro=NORD, colore="#55595C")
        if q.area > 200:
            c = q.centroid
            k.piano(box(c.x - 3.5, c.y - 2.0, c.x + 3.5, c.y + 2.0), 2 * H, 2 * H + 1.6, K.Stile(muro="#D8CFC0", finestre=None))
            k.tetto_piano(box(c.x - 3.5, c.y - 2.0, c.x + 3.5, c.y + 2.0), 2 * H + 1.6, parapetto=0.2)
    return k.fine()
