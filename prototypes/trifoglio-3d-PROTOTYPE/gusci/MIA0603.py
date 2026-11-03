"""PROTOTIPO — l'Edificio 32.3 (MIA0603), via Colombo 40: il padiglione a un piano con le aule
E.P.1, E.P.2 ed E.P.3, col fronte su via Saldini.

Fonti, oltre alle piante del Politecnico (seminterrato e terra):
- le panoramiche di Mapillary su via Saldini (gennaio-luglio 2025, per esempio 1100474022071750
  e 2354626664900371): il padiglione sta sul filo del marciapiede solo per la parte sud, quella
  del piano terra delle piante; più a nord il fronte è un muro di cinta di circa 2,8 m, coperto
  di graffiti, che arriva fino all'Edificio 32.2 e riprende a sud fino alla palazzina accanto.
  Dietro il muro si vede il bordo del tetto di un corpo arretrato, alla stessa quota. Un piano
  solo, alto poco meno di 4 m (il cornicione sta un metro sopra il muro), intonaco color sabbia,
  zoccolo grigio, finestre coi telai ocra, cornicione chiaro, tetto piano con un parapetto basso e
  sopra una ringhiera di tubolari bianca, un'unità esterna del condizionamento sull'angolo;
- l'ortofoto (Esri World Imagery; qui combacia con OSM): il tetto piano scuro sul corpo sud e su
  quello arretrato a nord-ovest; nell'angolo nord-est, sopra il seminterrato, un cortile coi
  lucernari chiari a livello del suolo;
- la sagoma di OSM (w248727402): conferma il corpo nord-ovest, ma non il fronte nord-est sulla
  strada, che nelle foto è il muro.
"""
import sys
import pathlib
import numpy as np
from shapely.geometry import Polygon, box
from shapely.ops import unary_union

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0603"
QUOTE = {"MIA060300S": -3.6, "MIA0603000": 0.0}
TETTO = 3.9

INTONACO = "#E3C79D"
ZOCCOLO = "#9D978C"
CORNICE = "#EFE6D3"
TELAIO = "#A8874A"
MURO_CINTA = "#C2BCB0"
RINGHIERA = "#E4E4DF"

NORD_OVEST = box(-78.4, 895.1, -66.4, 905.6)     # il corpo arretrato dietro il muro
CORTILE = box(-66.4, 892.2, -58.9, 902.0)        # i lucernari del seminterrato
FILO = -58.6                                     # il fronte su via Saldini


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def ringhiera(k, poly, z, h=1.0, dentro=0.35, passo=1.6):
    """Una ringhiera di tubolari lungo il bordo del tetto: montanti, corrimano e un traverso."""
    anello = poly.buffer(-dentro, join_style=2)
    pts = list(anello.exterior.coords)
    for a, c in zip(pts, pts[1:]):
        a, c = np.array(a), np.array(c)
        L = float(np.linalg.norm(c - a))
        for zz in (z + h, z + h / 2):
            k.E.trave(k.S, RINGHIERA, (*a, zz), (*c, zz), 0.045)
        for i in range(int(L // passo) + 1):
            p = a + (c - a) * min(1.0, i * passo / L)
            k.E.trave(k.S, RINGHIERA, (*p, z), (*p, z + h), 0.045)
    k.top = max(k.top, z + h)


def cornicione(k, poly, z0, z1, sporto, colore):
    anello = poly.buffer(sporto, join_style=2).difference(poly.buffer(-0.05, join_style=2))
    for r in k.pezzi(anello, 0.05):
        k.E.prisma(k.S, colore, k.E.ring_ccw(r), z0, z1)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=INTONACO, davanzale=2.0, architrave=3.35, telaio=TELAIO, sguincio=0.15, reach=1.5,
                 cornice=None, ripiego=(3.2, 1.4, 8.0), marcapiano=(1.2, 0.03, ZOCCOLO))
    terra = k.contorno("MIA0603000", chiudi=0.6)
    corpo = k.squadra(unary_union([terra, NORD_OVEST]), passo=0.5)
    corpo = max(k.pezzi(corpo), key=lambda g: g.area)
    k.piano(corpo, 0.0, TETTO, st, csip="MIA0603000", porte=True)
    cornicione(k, corpo, TETTO - 0.3, TETTO + 0.05, 0.12, CORNICE)
    k.tetto_piano(corpo, TETTO, parapetto=0.3, colore="#6B6E6F", muro=INTONACO, copertina=CORNICE)
    ringhiera(k, corpo, TETTO + 0.36)
    # le unità esterne: una sull'angolo verso la strada, una sul corpo arretrato
    k.impianto(-61.6, 905.4, 2.0, 1.3, TETTO + 0.08, h=1.1, colore="#C9CCCD")
    k.impianto(-73.0, 913.0, 1.8, 1.2, TETTO + 0.08, h=0.9, colore="#C9CCCD")
    k.impianto(-72.5, 899.0, 1.6, 1.0, TETTO + 0.08, h=0.8, colore="#C9CCCD")

    # il cortile sopra il seminterrato, coi lucernari a falda
    k.E.prisma(k.S, "#A7A39A", k.E.ring_ccw(CORTILE), 0.0, 0.12)
    for x in (-65.4, -62.9, -60.4):
        for y0, y1 in ((893.2, 897.2), (897.8, 901.4)):
            base = box(x, y0, x + 1.8, y1)
            k.E.prisma(k.S, "#D9D7D0", k.E.ring_ccw(base), 0.12, 0.5)
            k.falde(base, 0.5, pendenza=0.6, sporto=0.0, colore=K.VETRO_CHIARO, gronda="#E8E8E4", padiglione=False)

    # il muro di cinta su via Saldini, a nord fino al 32.2 e a sud fino alla palazzina accanto
    for y0, y1 in ((882.9, 902.2), (918.6, 930.4)):
        m = box(FILO - 0.35, y0, FILO, y1)
        k.E.prisma(k.S, MURO_CINTA, k.E.ring_ccw(m), 0.0, 2.8)
        k.E.prisma(k.S, "#C9C5BC", k.E.ring_ccw(m.buffer(0.05, join_style=2)), 2.8, 2.88)
    return k.fine()
