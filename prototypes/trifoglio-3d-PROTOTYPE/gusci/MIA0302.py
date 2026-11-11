"""PROTOTIPO — l'Edificio 19 "Mario Silvestri" (MIA0302), via Ponzio 34/3: i laboratori e gli
uffici di Energia, con un'aula al terra.

Fonti, oltre alle piante del Politecnico (secondo interrato, seminterrato, terra, primo,
secondo):
- la sagoma di OSM (w26144878, 7,6 m, tre piani), che tiene insieme la stecca delle piante e il
  corpo basso a nord, che nelle piante non c'è;
- l'ortofoto (Esri World Imagery, spostata di circa 8 m verso est e 5 m verso nord): la stecca
  col tetto bianco a padiglione molto basso, i due lucernari sopra il cavedio del secondo
  piano; il corpo a nord col tetto piano scuro e un volume chiaro al centro;
- le piante: le finestre su tutti i lati, la scala di sicurezza esterna sulla testata est. La
  grande sala del seminterrato verso via Ponzio sta sotto il cortile, e non esce.

- le foto di via Ponzio (Urbanfile, gennaio 2020, col numero 19 sul cancello), riguardate
  da vicino e confrontate col render dagli stessi punti di vista: il klinker è marrone chiaro,
  più giallo di quello del kit; su via Ponzio il terra e il primo sono ciechi, tranne il corpo
  avanzato di mezzo metro al centro, un riquadro in pannelli bordeaux con telai di ferro grigio,
  le finestre grandi dai telai bianchi e l'ingresso sotto una pensilina scura; il secondo è un
  nastro di finestre quasi da un capo all'altro, sotto una fascia piena di klinker con la
  scossalina scura che nasconde il tetto; sulla testata est il terra e il primo sono un'unica
  griglia di finestre e pannelli bordeaux, il secondo è cieco con una finestra sola; la testata
  ovest è cieca.

Piani da 3,4 m. Il corpo nord è solo un volume, alto due piani, senza finestre disegnate.
"""
import sys
import pathlib
from shapely.geometry import Polygon, box
from shapely.ops import unary_union

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0302"
H = 3.4
QUOTE = {"MIA030201I": -7.4, "MIA030200S": -3.8, "MIA0302000": 0.0, "MIA0302001": H, "MIA0302002": 2 * H}
TETTO = 3 * H
STECCA = box(227.3, 126.4, 264.9, 145.0)

KLINKER = "kit_klinker_19"   # il klinker del 19, più chiaro e più giallo di quello del kit
TELAIO = "#E2E2DE"
VETRO = "#8797A3"          # i vetri chiari che riflettono il cielo
BORDEAUX = "#6B2F35"       # i pannelli sotto le finestre
NORD = "#9C8574"
FERRO = "#7C8085"          # i telai in ferro grigio dei riquadri e le lattonerie
ZONA_Y = 145.4             # il filo del corpo avanzato al centro della facciata su via Ponzio
PORTA = (250.6, 252.6)     # l'ingresso, a x


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def _t(e, x, y):
    """La coordinata lungo il lato di un punto del piano."""
    a, u = e[0], e[2]
    return (x - a[0]) * u[0] + (y - a[1]) * u[1]


def _lato(e):
    """Che lato è: 'zona' (il corpo avanzato al centro della facciata su via Ponzio), 'sud',
    'risvolto' (i dentini di mezzo metro ai lati della zona), 'est', 'ovest', 'nord'."""
    n, L = e[3], e[4]
    (x0, y0), (x1, y1) = e[0], e[1]
    if L < 1.0:
        return "risvolto"
    if n[1] > 0.7:
        return "zona" if y0 > ZONA_Y - 0.1 else "sud"
    if n[1] < -0.7:
        return "nord"
    return "est" if n[0] > 0 else "ovest"


def _griglia(k, e, z0, z1, t0, t1, finestre):
    """Il riquadro in pannelli bordeaux coi telai in ferro grigio dove stanno le finestre del
    terra e del primo: copre il klinker tra t0 e t1, coi buchi delle finestre."""
    buchi = [K.rett(a, b, c, d) for a, b, c, d in finestre]
    forma = K.rett(t0, t1, z0, z1)
    if buchi:
        forma = forma.difference(unary_union(buchi))
    k.pannello(BORDEAUX, e, forma, 0.06, 0.1)
    for t in (t0, t1):
        k.pannello(FERRO, e, K.rett(t - 0.07, t + 0.07, z0, z1), 0.06, 0.16)
    k.pannello(FERRO, e, K.rett(t0, t1, z0 - 0.05, z0 + 0.05), 0.06, 0.16)


def _klinker(E):
    """Il klinker del kit ritinto sul marrone chiaro delle foto di via Ponzio."""
    if KLINKER in E._TEXTURES:
        return
    from PIL import Image
    import numpy as np
    rgb, nrm = K._texture("kit_klinker")
    a = np.asarray(rgb, float) * np.array([1.12, 1.17, 1.10])
    E.TEX.setdefault(KLINKER, K.TEXTURE["kit_klinker"])
    E._TEXTURES[KLINKER] = (Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), nrm)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    _klinker(E)
    st = K.Stile(muro=KLINKER, davanzale=0.9, architrave=2.6, telaio=TELAIO, vetro=VETRO, sguincio=0.12, reach=1.5, ripiego=(2.7, 1.4, 12.0),
                 marcapiano=(0.06, 0.03, FERRO))
    cieco = st.con(finestre=None)
    corpo = k.squadra(k.contorno("MIA0302001", chiudi=0.6).intersection(STECCA.buffer(0.5, join_style=2)))
    corpo = max(k.pezzi(corpo), key=lambda g: g.area)
    lati = k.E.edges(k.E.ring_ccw(corpo))
    porta = {}
    for i, csip in enumerate(("MIA0302000", "MIA0302001", "MIA0302002")):
        z0, z1 = i * H, (i + 1) * H
        griglie = []

        def stile(e, m, i=i, z0=z0, griglie=griglie):
            lato, L = _lato(e), e[4]
            if i == 2:
                # l'ultimo piano: la finestra a nastro sotto la fascia di klinker
                if lato in ("zona", "sud"):
                    return st.con(finestre="nastro", davanzale=0.8, architrave=2.65, passo_montanti=1.25)
                if lato == "est":
                    return st.con(finestre=[(L / 2 - 0.7, L / 2 + 0.7)], davanzale=1.0, architrave=2.5)
                return cieco if lato in ("ovest", "risvolto") else st
            if lato == "zona":
                f = K.Kit.finestre_passo(L, 1.75, 1.45, margine=0.4)
                if i == 0:
                    pt = sorted(_t(e, x, ZONA_Y) for x in PORTA)
                    porta["e"], porta["t"] = e, pt
                    f = [w for w in f if w[1] < pt[0] - 0.2 or w[0] > pt[1] + 0.2]
                griglie.append((e, 0.0, L, [(a, b_, z0 + 0.75, z0 + 2.85) for a, b_ in f]))
                return st.con(finestre=f, davanzale=0.75, architrave=2.85, sottofinestra=None)
            if lato == "est":
                f = K.Kit.finestre_passo(L - 2.0, 1.55, 1.3, margine=0.3)
                f = [(a + 1.0, b_ + 1.0) for a, b_ in f]
                griglie.append((e, 0.9, L - 0.9, [(a, b_, z0 + st.davanzale, z0 + st.architrave) for a, b_ in f]))
                return st.con(finestre=f)
            if lato in ("sud", "ovest"):
                return cieco
            if lato == "risvolto":
                griglie.append((e, 0.0, L, []))
                return cieco
            return st

        k.piano(corpo, z0, z1, stile, csip=csip, porte=False)
        for e, t0, t1, f in griglie:
            _griglia(k, e, z0, z1, t0, t1, f)
    # l'ingresso col numero 19, sotto la pensilina scura
    if porta:
        t0, t1 = porta["t"]
        k.porta(porta["e"], t0, t1, 0.0, h=2.5, telaio=FERRO, pensilina=("#3E4246", 1.3))
        k.pannello(BORDEAUX, porta["e"], K.rett(t0, t1, 2.5, 2.6), 0.06, 0.1)
    # la fascia piena di klinker sopra il nastro, con la scossalina scura; dietro, il tetto
    # bianco a padiglione così basso che dalla strada non si vede
    k.tetto_piano(corpo, TETTO, parapetto=1.0, muro=KLINKER, colore="#E6E6E2", copertina="#4D4A47")
    k.falde(corpo.minimum_rotated_rectangle.buffer(-0.45, join_style=2), TETTO, pendenza=0.07, sporto=0.0,
            colore="#E6E6E2", gronda="#BDBDB8")
    # il corpo basso a nord, dalla sagoma di OSM
    nord = Polygon(b["pianta"]).difference(corpo.buffer(0.3, join_style=2))
    for q in k.pezzi(nord, 20):
        q = k.squadra(q)
        k.piano(q, 0.0, 2 * H, K.Stile(muro=NORD, finestre=("passo", 3.0, 1.2), davanzale=1.0, architrave=2.6, telaio=TELAIO))
        k.tetto_piano(q, 2 * H, parapetto=0.6, muro=NORD, colore="#55595C")
        if q.area > 200:
            c = q.centroid
            k.piano(box(c.x - 3.5, c.y - 2.0, c.x + 3.5, c.y + 2.0), 2 * H, 2 * H + 1.6, K.Stile(muro="#D8CFC0", finestre=None))
            k.tetto_piano(box(c.x - 3.5, c.y - 2.0, c.x + 3.5, c.y + 2.0), 2 * H + 1.6, parapetto=0.2)
    return k.fine()
