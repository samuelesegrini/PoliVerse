"""PROTOTIPO — la Casa dello Studente (MIA0901), viale Romagna: la residenza del Politecnico, con
l'aula auditorium al terra.

Fonti, oltre alle piante del Politecnico (seminterrato e sette piani, dal terra al sesto):
- la sagoma e l'altezza di OSM (w40123288, 20,5 m): la manica ovest lungo la ferrovia, quella
  lunga in diagonale verso nord-est e il corpo di mezzo;
- le piante: le tre maniche ai piani tipo, il corpo di mezzo solo dal secondo al quinto (al
  terra c'è la sala grande, al primo è aperto), il sesto ridotto alla manica ovest e
  all'attacco di quella diagonale; le finestre delle camere su tutti i lati;
- l'ortofoto (Esri World Imagery; qui l'edificio alto pende verso nord-est e lo spostamento non
  è regolare): i tetti piani, scuri sulla manica ovest con un lungo lucernario, chiari sul
  corpo di mezzo con gli impianti.

Nessuna foto delle facciate: intonaco caldo con le finestre delle piante, il terra da 3,8 m e i
piani delle camere da 2,95 m, per stare nei 20,5 m di OSM.
"""
import sys
import pathlib
from shapely.ops import unary_union

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0901"
PIANI = [f"MIA090100{i}" for i in range(7)]
T0, H = 3.8, 2.95
QUOTE = {"MIA090100S": -3.4, **{c: (0.0 if i == 0 else round(T0 + (i - 1) * H, 2)) for i, c in enumerate(PIANI)}}
TETTO = round(T0 + 6 * H, 2)

INTONACO = "#D9CBB2"
TELAIO = "#4D4740"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=INTONACO, davanzale=0.9, architrave=2.3, telaio=TELAIO, sguincio=0.15, reach=1.4,
                 ripiego=(2.8, 1.1, 12.0), marcapiano=(0.25, 0.05, "#C7B89E"))
    corpi = []
    for csip in PIANI:
        g = unary_union([q for q in k.pezzi(k.contorno(csip, chiudi=0.8), 25.0)]).simplify(0.35)
        corpi.append(g)
    for i, (csip, g) in enumerate(zip(PIANI, corpi)):
        z0 = QUOTE[csip]
        z1 = T0 if i == 0 else z0 + H
        stile = st.con(davanzale=0.5, architrave=3.0) if i == 0 else st
        k.piano(g, z0, z1, stile, csip=csip, porte=i == 0)
        # il tetto di quello che il piano sopra non copre
        sopra = corpi[i + 1].buffer(0.2, join_style=2) if i + 1 < len(corpi) else None
        resto = g.difference(sopra) if sopra is not None else g
        for q in k.pezzi(resto, 6.0):
            alto = i + 1 == len(corpi)
            k.tetto_piano(q, z1, parapetto=0.9 if alto else 1.0, muro=INTONACO, colore="#5B5F62" if alto else K.GUAINA)
    # gli impianti sul tetto del corpo di mezzo
    k.impianto(-278.0, 340.0, 2.2, 1.6, QUOTE["MIA0901006"] + 0.1, h=1.2)
    k.impianto(-275.0, 346.0, 2.2, 1.6, QUOTE["MIA0901006"] + 0.1, h=1.2)
    return k.fine()
