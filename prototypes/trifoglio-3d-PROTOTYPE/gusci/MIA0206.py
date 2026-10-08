"""PROTOTIPO — l'Edificio 15 (MIA0206), via Bonardi: i laboratori a E fra il 16C e la ferrovia,
senza aule.

Fonti, oltre alle piante del Politecnico (seminterrato, terra, primo, secondo):
- la sagoma di OSM: la E aperta verso est;
- le piante: il terra copre tutta la E, il primo la C senza il braccio di mezzo, il secondo
  solo la manica sud. Il primo sta sulla sagoma; il terra e il seminterrato erano disegnati
  27 m più a est e stanno sul primo con gli `spostamenti` in `leonardo.json` (le scale
  coincidono);
- l'ortofoto (Esri World Imagery): il tetto chiaro in ghiaia della manica nord con un
  lucernario, il braccio di mezzo più basso e scuro, la manica sud col tetto scuro e un volume
  tecnico a ovest.

Nessuna foto delle facciate: intonaco chiaro con le finestre delle piante, piani da 4 m come
nei laboratori del dopoguerra del campus.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0206"
H = 4.0
PIANI = ["MIA0206000", "MIA0206001", "MIA0206002"]
QUOTE = {"MIA020600S": -3.8, **{c: i * H for i, c in enumerate(PIANI)}}
TETTO = 3 * H

INTONACO = "#DCD7CC"
TELAIO = "#474C52"
GHIAIA = "#CDBFAE"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=INTONACO, davanzale=0.9, architrave=3.0, telaio=TELAIO, sguincio=0.15, reach=1.5,
                 ripiego=(3.0, 1.4, 10.0), marcapiano=(0.3, 0.05, "#C8C3B8"))
    corpi = [max(k.pezzi(k.squadra(k.contorno(c, chiudi=0.8))), key=lambda g: g.area) for c in PIANI]
    for i, (c, g) in enumerate(zip(PIANI, corpi)):
        k.piano(g, i * H, (i + 1) * H, st.con(davanzale=0.6) if i == 0 else st, csip=c, porte=i == 0)
        sopra = corpi[i + 1].buffer(0.2, join_style=2) if i + 1 < len(corpi) else None
        resto = g.difference(sopra) if sopra is not None else g
        for q in k.pezzi(resto, 6.0):
            k.tetto_piano(q, (i + 1) * H, parapetto=0.8, muro=INTONACO, colore=GHIAIA if q.centroid.y < 38 else K.GUAINA)
    # il lucernario della manica nord e il volume tecnico della manica sud
    k.piano(box(108.0, 31.0, 111.5, 35.0), 2 * H, 2 * H + 0.8,
            K.Stile(muro="#E3E3DF", finestre=None))
    sud = corpi[2].bounds
    k.impianto(sud[0] + 5.0, sud[1] + 5.0, 6.0, 4.0, TETTO + 0.1, h=1.8, colore="#B9B6AF")
    return k.fine()
