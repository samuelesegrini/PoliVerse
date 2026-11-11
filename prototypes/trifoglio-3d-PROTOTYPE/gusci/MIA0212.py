"""PROTOTIPO — l'Edificio 16B (MIA0212), via Bonardi: la palazzina di vetro del campus di
Renzo Piano (2021), a ovest del Trifoglio, sulla piazza ribassata.

Fonti, oltre alle piante del Politecnico (primo interrato, seminterrato, terra, primo, secondo,
copertura):
- le foto di Urbanfile dell'inaugurazione (blog.urbanfile.org, 23 giugno 2021, foto 13, 14, 17,
  18): dalla piazza si vedono il seminterrato, tutto vetrato con i telai scuri e arretrato sotto i
  piani di sopra, e tre piani vetrati con un ballatoio tutto intorno (solette sottili bianche,
  parapetti di vetro); fuori dai ballatoi la gabbia di lame verticali bianche, fitte, che sale dal
  primo solaio fin sopra il tetto e fa da parapetto alla copertura;
- le sigle delle aule: 16B.0.1 è al seminterrato, quindi il seminterrato è il piano della piazza
  (come per il Trifoglio, il cui seminterrato sta a quota piazza) e la copertura (…003) è il tetto.
"""
import sys
import pathlib
import trimesh

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0212"
H0 = 4.4                     # il piano della piazza, più alto degli altri
H = 3.8
QUOTE = {"MIA021201I": -4.0, "MIA021200S": 0.0, "MIA0212000": H0, "MIA0212001": H0 + H,
         "MIA0212002": H0 + 2 * H, "MIA0212003": H0 + 3 * H}
TETTO = H0 + 3 * H
BALLATOIO = 1.5              # quanto sporgono le solette dal filo del vetro
SOLETTA = 0.32
LAMA_PASSO, LAMA_PROF, LAMA_SP = 0.85, 0.12, 0.06
PASSO_OVEST = 0.28           # sul lato ovest, verso la scala, le lame fitte fanno uno schermo
LAME_SOPRA = 1.3             # le lame salgono oltre il tetto: il parapetto della copertura

BIANCO = "#ECEEEE"
SOLETTA_COL = "#DCDFE0"
SOTTO = "#BFC4C8"            # l'intradosso dei ballatoi
TELAIO_SU = "#7F8791"
TELAIO_GIU = "#2B2E33"
VETRO_GIU = "#56636D"        # il vetro grigio e riflettente del seminterrato
PARAPETTO = "#B9CCD6"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def anello(fuori, dentro):
    return fuori.difference(dentro)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    su = max(k.pezzi(k.squadra(k.contorno("MIA0212001", chiudi=0.8), passo=0.5)), key=lambda g: g.area)
    giu = max(k.pezzi(k.squadra(k.contorno("MIA021200S", chiudi=0.8), passo=0.5)), key=lambda g: g.area)
    fuori = su.buffer(BALLATOIO, join_style=2)

    # il seminterrato sulla piazza: tutto vetro scuro fra telai neri, arretrato sotto i ballatoi
    k.piano(giu, 0.0, H0, K.Stile(finestre="vetrata", telaio=TELAIO_GIU, vetro=VETRO_GIU,
                                  passo_montanti=2.9, architrave=99))

    # i tre piani vetrati, con i ballatoi e i parapetti di vetro
    for i, csip in enumerate(("MIA0212000", "MIA0212001", "MIA0212002")):
        z = H0 + i * H
        k.piano(su, z, z + H, K.Stile(finestre="vetrata", telaio=TELAIO_SU, vetro=K.VETRO,
                                      passo_montanti=1.25, architrave=2.95))
    for i in range(4):
        z = H0 + i * H
        ring = anello(fuori, su.buffer(-0.3, join_style=2))
        k.S.solid(SOLETTA_COL, trimesh.creation.extrude_polygon(ring, SOLETTA).apply_translation([0, 0, z - SOLETTA]))
        k.S.solid(SOTTO, trimesh.creation.extrude_polygon(ring, 0.02).apply_translation([0, 0, z - SOLETTA - 0.02]))
        for e in E.edges(E.ring_ccw(fuori)):
            L = e[4]
            k.pannello(BIANCO, e, K.rett(0, L, z - SOLETTA, z + 0.04), -0.02, 0.03)     # il bordo bianco
            if i < 3:
                k.pannello(PARAPETTO, e, K.rett(0.05, L - 0.05, z + 0.05, z + 1.05), -0.22, -0.2)
                k.pannello(TELAIO_SU, e, K.rett(0.05, L - 0.05, z + 1.03, z + 1.09), -0.26, -0.16)

    # la gabbia di lame verticali fuori dai ballatoi, dal primo solaio fin sopra il tetto
    z0, z1 = H0 - SOLETTA - 0.4, TETTO + LAME_SOPRA
    for e in E.edges(E.ring_ccw(fuori)):
        L = e[4]
        passo = PASSO_OVEST if K.verso(e) == "O" else LAMA_PASSO
        n = int(L // passo)
        t = (L - n * passo) / 2
        for j in range(n + 1):
            tt = t + j * passo
            if 0.1 < tt < L - 0.1:
                k.pannello(BIANCO, e, K.rett(tt - LAMA_SP / 2, tt + LAMA_SP / 2, z0, z1), 0.08, 0.08 + LAMA_PROF)
        # i correnti che reggono le lame, a ogni solaio e in cima
        for zz in [H0 + i * H - SOLETTA / 2 for i in range(4)] + [z1 - 0.05]:
            k.pannello(BIANCO, e, K.rett(0, L, zz - 0.04, zz + 0.04), 0.03, 0.12)
        for zz in (z0, z1):
            k.pannello(BIANCO, e, K.rett(0, L, zz - 0.03, zz), 0.03, 0.08 + LAMA_PROF)

    # la copertura: guaina chiara, i lucernari delle scale, gli impianti in mezzo
    k.tetto_piano(su.buffer(-0.3, join_style=2), TETTO, parapetto=0.0, colore=K.GHIAIA)
    cx, cy = su.centroid.x, su.centroid.y
    k.impianto(cx, cy - 5.0, 4.0, 6.0, TETTO, h=1.4)
    k.impianto(cx, cy + 4.0, 3.0, 3.0, TETTO, h=1.1)
    k.top = max(k.top, z1)
    return k.fine()
