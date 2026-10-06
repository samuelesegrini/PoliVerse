"""PROTOTIPO — l'Edificio 25 "Emilio Massa" (MIA0403), via Ugo Bernardo Secondo 3: l'edificio
delle aule del campus di via Golgi, 1996-2000, con la supervisione artistica di Luigi Caccia
Dominioni (scheda di CSA Studio).

Fonti, oltre alle piante del Politecnico (seminterrato, terra, primo, secondo, sottotetto):
- la scheda di CSA Studio: quattro livelli fuori terra, quattordici aule da 50 a 150 posti,
  facciate in pannelli di fibrocemento stampati a bugnato e verniciati di grigio;
- l'ortofoto (Esri World Imagery, che qui è spostata di circa 8 m verso est e 5 m verso nord
  rispetto a OSM): un tetto a padiglione unico sul quadrato, scuro, con un lucernario tondo
  sulla falda nord, sopra la scala del sottotetto e le gradonate delle aule;
- l'altezza di OSM (21,5 m alla punta del tetto).

Le finestre sono quelle delle piante, piano per piano. Le quote sono dedotte: piani da 4,5 m
(le aule a gradoni del terra e del primo salgono di un piano intero), il seminterrato sotto
la strada, con le porte verso la bocca di lupo a nord e la scala esterna a ovest.
"""
import sys
import pathlib
import numpy as np
import trimesh
from shapely.geometry import Polygon, box, Point

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0403"
QUOTE = {"MIA040300S": -3.9, "MIA0403000": 0.6, "MIA0403001": 5.1, "MIA0403002": 9.6, "MIA040300V": 14.1}
GRONDA = 14.1
PENDENZA = 0.47                       # la punta a 21,5 m come in OSM

BUGNATO = "kit_bugnato_grigio"
ZOCCOLO = "#7E8083"
TELAIO = "#3A3D41"
LUCERNARIO = "#86A0B2"
TETTO = "#4E5558"                     # il manto scuro dell'ortofoto


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return GRONDA


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=BUGNATO, davanzale=1.0, architrave=3.3, telaio=TELAIO, sguincio=0.25,
                 cornice="#B9BBBC", montante=1.0)
    terra = k.contorno("MIA0403000", chiudi=0.4)
    # lo zoccolo: il seminterrato affiora di 60 cm, in pietra scura, con le bocche di lupo
    k.piano(terra, -0.3, 0.6, K.Stile(muro=ZOCCOLO, finestre=None))
    for csip, z1 in (("MIA0403000", 5.1), ("MIA0403001", 9.6), ("MIA0403002", GRONDA)):
        poly = k.contorno(csip, chiudi=0.4)
        k.piano(poly, QUOTE[csip], z1, st.con(marcapiano=(0.35, 0.12, "#A3A5A6")), csip=csip)
    # il cornicione sotto la gronda
    for q in k.pezzi(k.contorno("MIA0403002", chiudi=0.4)):
        for e in E.edges(E.ring_ccw(q)):
            k.pannello("#B9BBBC", e, K.rett(0, e[4], GRONDA - 0.5, GRONDA), 0.0, 0.35)
    # il tetto a padiglione: il quadrato del piano sotto, con 80 cm di sporto
    sq = k.contorno("MIA0403002", chiudi=0.4).minimum_rotated_rectangle
    k.falde(sq, GRONDA, pendenza=PENDENZA, sporto=0.8, colore=TETTO, gronda="#C9CACB")
    # il lucernario tondo sulla falda nord, sopra la scala del sottotetto
    cx, cy = 556.6, 268.8
    S = k.S
    S.solid(TELAIO, trimesh.creation.cylinder(radius=3.1, height=2.6, sections=32).apply_translation([cx, cy, 17.8]))
    S.solid(LUCERNARIO, trimesh.creation.icosphere(subdivisions=3, radius=3.0).apply_scale([1, 1, 0.45]).apply_translation([cx, cy, 19.1]))
    # la scala esterna verso il seminterrato, a ovest: il parapetto intorno al pozzo
    pozzo = Polygon([(531.0, 292.0), (533.0, 287.2), (537.6, 287.2), (539.6, 292.0)])
    for r in k.pezzi(pozzo.difference(pozzo.buffer(-0.25, join_style=2)), 0.05):
        S.solid(ZOCCOLO, trimesh.creation.extrude_polygon(r, 1.1))
    return k.fine()
