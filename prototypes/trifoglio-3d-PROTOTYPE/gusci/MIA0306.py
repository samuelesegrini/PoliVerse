"""PROTOTIPO — l'Edificio 21 (MIA0306), via Golgi 39: il Dipartimento di Chimica, Materiali e
Ingegneria Chimica e, nel seminterrato e al terra, le aule EG.

Fonti, oltre alle piante del Politecnico (seminterrato e sette piani, dal terra al sesto):
- la sagoma di OSM (w41277540) e le piante: il corpo principale fino a x 468,5, l'ala a sud-est
  che arriva a 474,9 e, davanti, la scala esterna su via Golgi;
- le foto di via Golgi (Urbanfile, gennaio 2020): il calcestruzzo chiaro e caldo con le alette
  verticali, le finestre e i pannelli scuri sotto che fanno strisce continue, e la scala
  esterna: una torre aperta di rampe perpendicolari al muro, a gradini anche sotto, con i
  parapetti pieni che seguono i gradini e i pianerottoli a sbalzo in testa, davanti al muro
  cieco a costoline fitte dell'ala;
- la vista dall'alto (Google 3D, in Urbanfile novembre 2019): i parapetti del tetto con le
  teste delle alette che spuntano, il torrino degli impianti scuro in mezzo al corpo
  principale;
- le piante della scala (`linee.scale`): due rampe affiancate fra y 105,8 e 109,6, da
  x 476,9 a 480,4, il pianerottolo del piano verso il muro e quello di mezzo piano in testa;
  fra la scala e l'edificio un disimpegno vetrato. L'ala sul lato della scala non ha finestre
  nelle piante: è il muro cieco delle foto.

L'altezza di OSM (14,9 m) non regge sette piani: i piani sono da 3,6 m, come nei laboratori
del dopoguerra del campus.
"""
import sys
import pathlib
import trimesh
from shapely.geometry import box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0306"
H = 3.6
PIANI = [f"MIA030600{i}" for i in range(7)]
QUOTE = {"MIA030600S": -3.8, **{c: round(i * H, 2) for i, c in enumerate(PIANI)}}
TETTO = round(7 * H, 2)
# la scala esterna su via Golgi, dalle piante: la torre delle rampe e, fra lei e l'ala,
# il disimpegno vetrato di ogni piano
SCALA = box(476.1, 105.8, 481.4, 109.6)
DISIMPEGNO = box(474.8, 106.5, 476.1, 109.0)
RAMPE = (476.9, 480.4)                       # da dove a dove salgono le rampe, verso est
RAMPA_A = (105.8, 107.1)                     # sale verso la strada, al mezzo piano
RAMPA_B = (108.35, 109.6)                    # torna verso il muro, al piano
MURO_CIECO = 473.5                           # i lati est oltre questa x sono il muro a costoline

CLS = "#C6C1B5"            # il calcestruzzo chiaro e caldo delle foto
ALETTE = "#D0CCC2"
SCALE = "#B3AEA3"          # il calcestruzzo granuloso della scala
TETTI = "#B9B7B0"          # le piastrelle chiare dei tetti, dall'alto
SCURO = "#3B4246"          # i pannelli sotto le finestre
TELAIO = "#3C4045"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    st = K.Stile(muro=CLS, finestre="pianta", ripiego=(1.8, 1.25, 6.0), davanzale=0.9, architrave=2.9,
                 telaio=TELAIO, sguincio=0.12, lesene=(0.45, 0.16, ALETTE), sottofinestra=SCURO)
    cieco = K.Stile(muro=CLS, finestre=None)

    def stile(e, m, s=st):
        # il muro dell'ala dietro la scala non ha finestre: lo fanno le costoline, dopo;
        # sul lato nord, dall'alto, i pilastri sono grossi e sporgenti
        if K.verso(e) == "E" and m[0] > MURO_CIECO:
            return cieco
        return s.con(lesene=(0.6, 0.5, ALETTE)) if K.verso(e) == "N" else s

    # i piani dal primo al sesto hanno lo stesso contorno nelle piante, a meno di pochi
    # centimetri: un corpo solo, squadrato; il terra ha il suo
    via = SCALA.union(DISIMPEGNO).buffer(0.25, join_style=2)
    terra = max(k.pezzi(k.squadra(k.contorno("MIA0306000", chiudi=1.5), passo=0.5).difference(via)), key=lambda g: g.area)
    corpo = max(k.pezzi(k.squadra(k.contorno("MIA0306002", chiudi=1.5), passo=0.5).difference(via)), key=lambda g: g.area)
    k.piano(terra, 0.0, H, lambda e, m: stile(e, m, st.con(davanzale=0.3, architrave=3.0)), csip="MIA0306000", porte=True)
    k.tetto_piano(terra.difference(corpo.buffer(0.2, join_style=2)), H, parapetto=0.9, muro=CLS)
    for i in range(1, 7):
        k.piano(corpo, i * H, (i + 1) * H, stile, csip=PIANI[i])
    k.tetto_piano(corpo, TETTO, parapetto=1.1, muro=CLS, colore=TETTI)
    teste_alette(k, corpo, st)
    costoline(k, corpo)
    scala(k)
    # il torrino degli impianti, scuro, in mezzo al corpo principale (vista dall'alto e
    # ombra lunga nell'ortofoto), con le macchine sopra; le canne dei laboratori
    tor = box(455.0, 93.0, 465.0, 103.0)
    k.piano(tor, TETTO, TETTO + 3.6, K.Stile(muro="#A8A49B", finestre=None))
    k.tetto_piano(tor, TETTO + 3.6, parapetto=0.4, colore="#6E7175", muro="#A8A49B")
    k.impianto(458.0, 96.5, 4.0, 3.0, TETTO + 3.7, h=1.5)
    k.impianto(462.0, 100.0, 3.0, 2.2, TETTO + 3.7, h=1.2)
    for j in range(5):
        k.S.solid("#9A9EA2", trimesh.creation.cylinder(radius=0.25, height=2.4, sections=10).apply_translation([440.0 + j * 2.4, 89.0, TETTO + 1.2]))
    k.impianto(444.0, 112.0, 4.0, 2.4, TETTO + 0.1, h=1.8)
    return k.fine()


def teste_alette(k, corpo, st):
    """Le alette spuntano di 40 cm sopra il parapetto: la merlatura della vista dall'alto."""
    E = k.E
    sp, w, col = st.lesene
    for e in E.edges(E.ring_ccw(corpo)):
        if K.verso(e) == "E" and K.mid(e)[0] > MURO_CIECO:
            continue
        iv = k.finestre_pianta(PIANI[6], e, st.reach, st.minima)
        if not iv and e[4] > st.ripiego[2]:
            iv = k.finestre_passo(e[4], st.ripiego[0], st.ripiego[1])
        ts = sorted({round(t, 2) for t0, t1 in iv for t in (t0 - w / 2 - 0.02, t1 + w / 2 + 0.02)})
        for t in ts:
            if w / 2 < t < e[4] - w / 2:
                k.pannello(col, e, K.rett(t - w / 2, t + w / 2, TETTO, TETTO + 1.5), 0.0, sp)


def costoline(k, corpo):
    """Il muro cieco dell'ala dietro la scala: costoline verticali fitte, dal primo al tetto."""
    E = k.E
    for e in E.edges(E.ring_ccw(corpo)):
        if not (K.verso(e) == "E" and K.mid(e)[0] > MURO_CIECO):
            continue
        n = int(e[4] / 0.3)
        for j in range(1, n):
            t = j * e[4] / n
            k.pannello(ALETTE, e, K.rett(t - 0.05, t + 0.05, H, TETTO + 1.1), 0.0, 0.1)


def scala(k):
    """La scala esterna su via Golgi, come nelle foto e nelle piante: per ogni piano due rampe
    affiancate perpendicolari al muro, la prima sale verso la strada fino al pianerottolo di
    mezzo piano, a sbalzo in testa, la seconda torna al pianerottolo del piano davanti al
    disimpegno vetrato. Le rampe sono a gradini anche sotto e i parapetti pieni ne seguono i
    gradini: il dente di sega delle foto."""
    E, S = k.E, k.S
    x0, y0, x1, y1 = SCALA.bounds
    ra, rb = RAMPE
    n = 10                                    # alzate per rampa (18 cm)
    pd = (rb - ra) / n
    for j in range(2 * 7):
        z0 = j * H / 2
        alz = H / 2 / n
        verso_strada = j % 2 == 0
        ya, yb = RAMPA_A if verso_strada else RAMPA_B
        lato = ya if verso_strada else yb      # il lato libero, verso fuori
        for g in range(n):
            xg = ra + g * pd if verso_strada else rb - (g + 1) * pd
            zt = z0 + (g + 1) * alz
            # il gradino, col suo dente sotto
            S.solid(SCALE, E.box_z(xg + pd / 2, (ya + yb) / 2, pd + 0.01, yb - ya, zt - 0.6, zt))
            # i due parapetti pieni, anche loro a denti
            for yp in (ya + 0.09, yb - 0.09):
                S.solid(SCALE, E.box_z(xg + pd / 2, yp, pd + 0.01, 0.2, zt - 0.75, zt + 1.0))
        z1 = z0 + H / 2
        if verso_strada:
            # il pianerottolo di mezzo piano, a sbalzo in testa, chiuso su tre lati
            S.solid(SCALE, E.box_z((rb + x1) / 2, (y0 + y1) / 2, x1 - rb, y1 - y0, z1 - 0.5, z1))
            S.solid(SCALE, E.box_z(x1 - 0.1, (y0 + y1) / 2, 0.2, y1 - y0, z1 - 0.5, z1 + 1.1))
            for yy in (y0 + 0.09, y1 - 0.09):
                S.solid(SCALE, E.box_z((rb + x1) / 2, yy, x1 - rb, 0.18, z1 - 0.5, z1 + 1.1))
        else:
            # il pianerottolo del piano, fra le rampe e il disimpegno
            S.solid(SCALE, E.box_z((x0 + ra) / 2, (y0 + y1) / 2, ra - x0, y1 - y0, z1 - 0.3, z1))
            # la ringhiera sul pozzo fra le due rampe
            S.solid("#5A5E61", E.box_z((x0 + ra) / 2 + 0.3, (RAMPA_A[1] + RAMPA_B[0]) / 2, 0.05, RAMPA_B[0] - RAMPA_A[1], z1 + 1.0, z1 + 1.05))
    # il pozzo fra le rampe resta aperto; il disimpegno di ogni piano è vetrato
    for i in range(1, 7):
        k.piano(DISIMPEGNO, i * H, (i + 1) * H, K.Stile(muro=CLS, finestre="vetrata", telaio=TELAIO, architrave=2.6))
    k.tetto_piano(DISIMPEGNO, TETTO, parapetto=0.6, muro=CLS)
    k.tetto_piano(SCALA, TETTO + 0.0, parapetto=1.1, muro=SCALE)
    k.top = max(k.top, TETTO + 1.1)
