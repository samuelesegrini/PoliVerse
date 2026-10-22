"""PROTOTIPO — l'Edificio CT1 (MIA0109), il Centralino: la palazzina bassa a un piano nel
campus di piazza Leonardo, senza aule, col fronte nord sul filo della cancellata di via Bassini.

Fonti, oltre alla pianta del Politecnico (il terra) e alla sagoma di OSM (1 piano, tetto piano):
- i panorami Mapillary dell'ottobre 2024 dal marciapiede di via Bassini, verso est (immagini
  433491256455987 e 400723819765745): un corpo basso a intonaco crema scandito da lesene piatte
  fitte, con una finestra alta e piccola in ogni campata che spunta sopra la cancellata, e sopra
  niente cornicione: la soletta del tetto sporge di poco, col bordo scuro;
- l'ortofoto Esri (z19): guaina scura grigio-oliva (#606050 medio, ombre comprese) senza
  impianti, bordo più chiaro; condizionatori e tubi stanno sul tetto della cabina accanto a est,
  che in OSM è un altro edificio.
Gli altri tre lati non si vedono da nessuna foto raggiungibile: hanno la stessa scansione.
"""
import sys
import pathlib
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0109"
QUOTE = {"MIA0109000": 0.0}
TETTO = 4.5
CAMPATA = 2.1    # passo delle lesene sul fronte di via Bassini
LESENA = 0.45
FINESTRA = 0.8


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    corpo = k.squadra(k.contorno("MIA0109000", chiudi=0.4))
    st = K.Stile(muro="#E3DAC4", finestre=[], davanzale=3.15, architrave=3.95, telaio="#3F4347",
                 sguincio=0.12, cornice=None)

    def campate(e):
        n = max(1, round(e[4] / CAMPATA))
        return [(e[4] * i / n, e[4] * (i + 1) / n) for i in range(n)]

    def stile(e, c):
        # una finestra alta in mezzo a ogni campata
        return st.con(finestre=[((a + b) / 2 - FINESTRA / 2, (a + b) / 2 + FINESTRA / 2) for a, b in campate(e)])

    k.piano(corpo, 0.0, TETTO, stile, csip="MIA0109000", porte=True)
    for e in E.edges(E.ring_ccw(corpo)):
        # le lesene tra le campate e agli spigoli, e uno zoccolo appena più scuro
        for a, _ in campate(e) + [(e[4], None)]:
            t0, t1 = max(0.0, a - LESENA / 2), min(e[4], a + LESENA / 2)
            k.pannello("#E9E1CD", e, K.rett(t0, t1, 0.0, TETTO - 0.18), 0.0, 0.15)
        k.pannello("#BDB4A0", e, K.rett(0, e[4], 0.0, 0.45), 0.0, 0.08)
    # la soletta che sporge col bordo scuro, poi la guaina senza parapetto
    for q in k.pezzi(corpo):
        E.prisma(k.S, "#4F504C", E.ring_ccw(q.buffer(0.35, join_style=2)), TETTO - 0.18, TETTO)
        E.prisma(k.S, "#8A877C", E.ring_ccw(q.buffer(0.3, join_style=2)), TETTO, TETTO + 0.04)
    k.tetto_piano(corpo, TETTO + 0.04, parapetto=0, colore="#67665B", spessore=0.05)
    return k.fine()
