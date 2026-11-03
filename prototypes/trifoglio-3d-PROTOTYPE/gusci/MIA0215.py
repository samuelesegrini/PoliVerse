"""PROTOTIPO — l'Edificio 16C (MIA0215), via Bonardi: il padiglione delle aule 16C.0.1-0.3
del campus di Renzo Piano (2021), sulla piazza ribassata fra le due ali della Nave e il 15.

Fonti, oltre alla pianta del Politecnico (un solo piano, "seminterrato" rispetto a via
Bonardi ma al livello della piazza, come il portico della Nave):
- le foto di Urbanfile dell'inaugurazione (marzo e giugno 2021): un padiglione basso con la
  facciata tutta vetrata dietro una fila fitta di lame verticali di alluminio grigio chiaro,
  che salgono oltre il solaio e fanno da parapetto al tetto; il tetto è una terrazza
  pavimentata con le fioriere di cemento, le betulle e le panche; lungo il lato nord la scala
  che sale verso via Bonardi, fra la Nave e le lame, con la ringhiera di vetro e piatti;
- OSM (via Overture): l'altezza, 6 m; le panche di cemento e gli alberi sul tetto, la scala
  lungo il lato nord;
- l'ortofoto (Esri World Imagery): il tetto chiaro con le macchie verdi delle fioriere nella
  metà ovest.

Le lame e la terrazza sono quelle delle foto; la posizione esatta di fioriere e panche viene
da OSM.
"""
import sys
import pathlib
import trimesh
from shapely.geometry import Polygon, box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0215"
QUOTE = {"MIA021500S": 0.0}
SOFFITTO = 4.4          # sotto il solaio di copertura
TERRAZZA = 5.0          # il pavimento della terrazza sul tetto
CIMA_LAME = 6.1         # le lame salgono oltre il solaio e fanno da parapetto

ALLUMINIO = "#BFC4C8"
TELAIO = "#8C9399"
VETRO = "#53636F"
CEMENTO = "#C9C6BF"
PIETRA = "#D8D5CE"

# da OSM: gli alberi e le panche sulla terrazza
ALBERI = [(80, 24), (83, 28), (78.5, 33), (81, 33), (81, 37), (78.5, 41), (82, 40), (80, 45)]
PANCHE = [(83, 23), (79, 28), (83, 32), (79, 32), (79, 40), (83, 36), (83, 44)]


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return SOFFITTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def lame(k, e, z0, z1, passo=0.75, d0=0.12, d1=0.36):
    """Le lame verticali davanti alla vetrata, a passo regolare lungo il lato."""
    L = e[4]
    n = max(1, int((L - 0.2) / passo))
    t0 = (L - (n - 1) * passo) / 2
    for i in range(n):
        t = t0 + i * passo
        k.pannello(ALLUMINIO, e, K.rett(t - 0.025, t + 0.025, z0, z1), d0, d1)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    corpo = k.squadra(Polygon(b["pianta"]), passo=0.5)
    st = K.Stile(finestre="vetrata", telaio=TELAIO, vetro=VETRO, passo_montanti=1.25, architrave=3.2)
    k.piano(corpo, 0.0, SOFFITTO, st)
    # il solaio di copertura: la fascia di alluminio sul filo della vetrata e la terrazza
    E.prisma(k.S, CEMENTO, E.ring_ccw(corpo), SOFFITTO, TERRAZZA - 0.05)
    E.prisma(k.S, PIETRA, E.ring_ccw(corpo.buffer(-0.1, join_style=2)), TERRAZZA - 0.05, TERRAZZA)
    for e in E.edges(E.ring_ccw(corpo)):
        k.pannello(ALLUMINIO, e, K.rett(0, e[4], SOFFITTO, TERRAZZA), 0.0, 0.12)
        lame(k, e, 0.0, CIMA_LAME)
        # la ringhiera della terrazza: il vetro dietro le lame e il corrimano
        k.pannello("#A9C0CC", e, K.rett(0.1, e[4] - 0.1, TERRAZZA, TERRAZZA + 1.1), -0.12, -0.1)
        k.pannello(TELAIO, e, K.rett(0.1, e[4] - 0.1, TERRAZZA + 1.05, TERRAZZA + 1.12), -0.16, -0.06)
    # le fioriere di cemento con le betulle e le panche
    for x, y in ALBERI:
        k.S.solid(CEMENTO, E.box_z(x, y, 1.6, 2.4, TERRAZZA, TERRAZZA + 0.55))
        k.S.solid("#6F5B45", E.box_z(x, y, 1.4, 2.2, TERRAZZA + 0.55, TERRAZZA + 0.58))
        k.S.solid("#E9E6DF", trimesh.creation.cylinder(radius=0.1, height=3.2, sections=6)
                  .apply_translation([x, y, TERRAZZA + 0.58 + 1.6]))
        k.S.solid(K.CHIOMA, trimesh.creation.icosphere(subdivisions=1, radius=1.3)
                  .apply_scale([1, 1, 1.6]).apply_translation([x, y, TERRAZZA + 4.2]))
    for x, y in PANCHE:
        k.S.solid(CEMENTO, E.box_z(x, y, 0.6, 2.0, TERRAZZA, TERRAZZA + 0.45))
    scala(k, E)
    k.top = CIMA_LAME
    return k.fine()


def scala(k, E):
    """La scala lungo il lato nord, fra la Nave e le lame: sale verso est fino alla quota della
    terrazza, con la ringhiera di vetro e piatti verso la Nave."""
    x0, x1, y0, y1 = 84.5, 100.0, 18.6, 20.9
    n = 30
    a = (x1 - x0) / n
    for i in range(n):
        z = TERRAZZA * (i + 1) / n
        k.S.solid(PIETRA, E.box_z(x0 + a * (i + 0.5), (y0 + y1) / 2, a, y1 - y0, max(0.0, z - 0.6), z))
    k.S.solid(PIETRA, E.box_z(101.5, (y0 + y1) / 2, 3.0, y1 - y0, TERRAZZA - 0.4, TERRAZZA))
    # la ringhiera a nord: un piatto ogni 1,2 m, il vetro e il corrimano inclinato
    x = x0
    while x <= 103.0:
        z = TERRAZZA * min(1.0, max(0.0, (x - x0) / (x1 - x0)))
        k.S.solid(ALLUMINIO, E.box_z(x, y0 + 0.05, 0.06, 0.1, z, z + 1.15))
        x += 1.2
    for i in range(n):
        xa, z = x0 + a * i, TERRAZZA * (i + 1) / n
        k.S.solid("#A9C0CC", E.box_z(xa + a / 2, y0 + 0.05, a, 0.03, z, z + 1.05))
