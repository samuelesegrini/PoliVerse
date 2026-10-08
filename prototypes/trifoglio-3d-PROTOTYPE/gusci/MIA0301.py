"""PROTOTIPO — l'Edificio 20 (MIA0301), via Ponzio 34/5: la stecca del DEIB lungo via Bassini,
con l'aula 20.S.1 nel seminterrato.

Fonti, oltre alle piante del Politecnico (seminterrato, terra, primo, secondo, terzo):
- la sagoma e l'altezza di OSM (w643507930, 18 m, quattro piani, tetto piano);
- le piante: la stecca lunga 93 m e larga 17, uffici sui due lati del corridoio con le
  finestre fitte, e la torre delle scale a pianta quadrata girata di 45° sul lato nord;
- l'ortofoto (Esri World Imagery, spostata di circa 8 m verso est e 5 m verso nord): il tetto
  bianco con due lunghe file di pannelli fotovoltaici, la testata est più bassa e scura con
  gli impianti, la torre delle scale col tetto a piramide.

- le foto di via Ponzio e via Bassini (Urbanfile, gennaio 2020 e giugno 2025, col numero 20
  all'ingresso): la pelle di pannelli bianchi, le finestre a coppie con un pannello grigio
  scuro sotto e una lama frangisole sopra, il terra più scuro.

Piani da 4,5 m.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0301"
H = 4.5
QUOTE = {"MIA030100S": -4.0, "MIA0301000": 0.0, "MIA0301001": 4.5, "MIA0301002": 9.0, "MIA0301003": 13.5}
TETTO = 18.0
EST = 377.0                    # da qui la testata est, coi tetti scuri degli impianti

INTONACO = "#E5E6E4"       # i pannelli bianchi
TERRA = "#B4B8BC"
SOTTO = "#7E8389"          # il pannello sotto le finestre
TELAIO = "#4E545A"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=INTONACO, davanzale=0.95, architrave=3.0, telaio=TELAIO, sguincio=0.15, reach=1.5, ripiego=(2.7, 1.4, 15.0),
                 sottofinestra=SOTTO, frangisole=(0.6, "#C8CBCE"))
    vetro = K.Stile(muro=INTONACO, finestre="vetrata", telaio=TELAIO, vetro=K.VETRO_CHIARO, passo_montanti=1.2, architrave=99)
    for csip in ("MIA0301000", "MIA0301001", "MIA0301002", "MIA0301003"):
        tutto = k.contorno(csip, chiudi=0.4)
        corpo = k.squadra(tutto.intersection(box(0, 134.6, 1000, 200)), passo=0.5)
        torre = max(k.pezzi(tutto.difference(box(0, 134.8, 1000, 200)).buffer(-0.6, join_style=2).buffer(0.6, join_style=2)), key=lambda g: g.area)
        z0 = QUOTE[csip]
        k.piano(corpo, z0, z0 + H, st.con(davanzale=0.4, muro=TERRA, sottofinestra=None, frangisole=None) if csip.endswith("000") else st, csip=csip, porte=csip.endswith("000"))
        # la torre delle scale: i lati liberi vetrati, a tutta altezza
        k.piano(torre.simplify(0.3), z0, z0 + H, vetro)
    k.tetto_piano(corpo, TETTO, parapetto=1.0, muro=INTONACO, colore="#E8E8E4")
    ovest = corpo.intersection(box(0, 0, EST, 200))
    x0, y0, x1, y1 = ovest.bounds
    k.fotovoltaico(box(x0 + 4, y0 + 2.0, x1 - 6, y0 + 6.0), TETTO + 0.08)
    k.fotovoltaico(box(x0 + 8, y1 - 6.5, x1 - 2, y1 - 2.0), TETTO + 0.08)
    est = corpo.intersection(box(EST, 0, 1000, 200))
    k.tetto_piano(est, TETTO, parapetto=1.0, muro=INTONACO, colore="#6F7276")
    ex0, ey0, ex1, ey1 = est.bounds
    for i, (x, y) in enumerate(((ex0 + 4, ey0 + 4), (ex0 + 9, ey0 + 5), (ex0 + 14, ey1 - 5), (ex0 + 6, ey1 - 4))):
        k.impianto(x, y, 3.0, 2.0, TETTO + 0.08, h=1.4 + 0.3 * (i % 2))
    k.falde(torre.simplify(0.3), TETTO, pendenza=0.5, sporto=0.2, colore="#B8BDC2", gronda="#D9DBDC")
    return k.fine()
