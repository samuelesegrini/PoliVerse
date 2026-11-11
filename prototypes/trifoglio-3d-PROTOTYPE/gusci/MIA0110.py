"""PROTOTIPO — l'Edificio 10 (MIA0110), la Posta: la palazzina a un piano nel campus di piazza
Leonardo, senza aule.

Fonti, oltre alla pianta del Politecnico (il terra) e alla sagoma di OSM: l'ortofoto, dove il tetto
piano è grigio con tre strisce chiare da nord a sud e la copertina chiara sui lati ovest e nord;
e le panoramiche di Mapillary del 2024-25 su via Bonardi, dove la palazzina sta subito dietro la
cancellata: è bassa (il tetto arriva poco sopra gli occhi di chi passa), il lato est è un muro
cieco d'intonaco ocra macchiato, sotto una fascia grigio scuro spessa che fa da gronda, all'altezza
degli occhi, e sopra si vedono le finestre ad arco del terra dell'8. La palazzina sta nel cortile
ribassato davanti al seminterrato dell'8 (la parte scura dell'ortofoto a sud): il pavimento a
-1,4 m, il tetto a 2,2 m sul piano del campus. Il 5 m del `profilo` dell'illustrazione era troppo.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K
from _kit import rett

CSIE = "MIA0110"
PAVIMENTO = -1.4               # il cortile ribassato davanti al seminterrato dell'8
QUOTE = {"MIA0110000": PAVIMENTO}
TETTO = 2.2
INTONACO = "#B09C7E"
FASCIA = "#5E6266"
COPERTINA = "#CFCBC2"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    corpo = k.contorno("MIA0110000", chiudi=0.4).minimum_rotated_rectangle   # nell'ortofoto è un rettangolo netto
    st = K.Stile(muro=INTONACO, davanzale=1.6, architrave=3.0, telaio="#4A4F55", sguincio=0.15,
                 ripiego=(3.0, 1.2, 6.0))
    k.piano(corpo, PAVIMENTO, TETTO, lambda e, m: K.Stile(muro=INTONACO, finestre=None) if e[3][0] > 0.7 else st,
            csip="MIA0110000", porte=True)
    for e in E.edges(E.ring_ccw(corpo)):
        k.pannello("#8E8A82", e, rett(0, e[4], PAVIMENTO, 0.15), 0.0, 0.03)      # lo zoccolo
        k.pannello(FASCIA, e, rett(0, e[4], TETTO - 0.3, TETTO + 0.1), 0.0, 0.15)   # la fascia di gronda
    k.tetto_piano(corpo, TETTO, parapetto=0.1, colore="#8E9193", muro=FASCIA, copertina=COPERTINA, spessore=0.35)
    # le tre strisce chiare dell'ortofoto, da nord a sud
    x0, y0, x1, y1 = corpo.bounds
    for f in (0.27, 0.63, 0.73):
        x = x0 + f * (x1 - x0)
        k.E.prisma(k.S, "#C4C6C4", list(box(x - 0.3, y0 + 0.5, x + 0.3, y1 - 0.5).exterior.coords)[:-1],
                       TETTO + 0.08, TETTO + 0.3)
    return k.fine()
