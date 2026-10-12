"""PROTOTIPO — l'Edificio 25 "Emilio Massa" (MIA0403), via Golgi 40, all'angolo tra via Bernardo
Ugo Secondo (a sud) e via Clericetti (a est): l'edificio delle aule del campus di via Golgi,
1996-2000, con la supervisione artistica di Luigi Caccia Dominioni (progetto di CSA Studio).

Fonti, oltre alle piante del Politecnico (seminterrato, terra, primo, secondo, sottotetto):
- le 21 foto della scheda di CSA Studio (csastudio.it, "Nuovo edificio dipartimentale del
  Politecnico di Milano in via Camillo Golgi, 40"): viste da via Golgi, da via Secondo e da via
  Clericetti, il fronte sud, l'ingresso, gli spigoli;
- l'ortofoto (Esri World Imagery, spostata di circa 8 m verso est e 5 m verso nord rispetto a
  OSM) per la posizione del tamburo tondo sul tetto, sulla falda nord.

Com'è nelle foto:
- tre piani fuori terra rivestiti di pannelli di fibrocemento grigio antracite a punta di
  diamante (bugne a piramide da circa 40 cm), quasi neri;
- il tetto a padiglione basso in lamiera chiara, con una fascia di gronda alta in metallo
  chiaro; sopra, un tamburo tondo di cemento grigio e due comignoli d'acciaio verso ovest;
  i pluviali d'acciaio sugli spigoli;
- sul fronte sud, verso via Secondo, la campata dell'ingresso: sotto, la vetrata verde con
  la scritta "Edificio 25 aule D", la tabella di legno "Politecnico di Milano" e i pilastrini
  di granito con il cappello tondo davanti alle porte; sopra, due logge arretrate con le
  ringhiere e i frontalini gialli dei solai; la campata è orlata di granito grigio;
- a ovest le finestre sono poche e quadrate, con lo sguincio di granito; a est, su via
  Clericetti, corrono a nastri di 6 m tra lesene di granito, sopra uno zoccolo di granito;
  sotto alcune corrono fasce gialle: lunghe sui fronti est e ovest, corte sotto la colonna di
  finestre a ovest dell'ingresso.

Il fronte est e quello sud sono verificati anche sui panorami Mapillary del 2025 da via
Clericetti e da via Secondo. Sul fronte ovest le piante disegnano tre nastri per piano, ma le
foto ne mostrano solo tre finestre: qui le finestre sono date una per una, dove le foto le
mostrano. Le quote sono
dedotte: piani da 4,5 m, la fascia di gronda da 13,5 a 14,4 m.
"""
import sys
import pathlib
import numpy as np
import trimesh
from shapely.geometry import Polygon, box

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0403"
QUOTE = {"MIA040300S": -3.9, "MIA0403000": 0.6, "MIA0403001": 5.1, "MIA0403002": 9.6, "MIA040300V": 14.1}
PIANI = ((0.6, 5.1), (5.1, 9.6), (9.6, 13.5))     # terra, primo, secondo: la fascia di gronda da 13,5
GRONDA = 14.4
PENDENZA = 0.25                                    # la falda bassa delle foto

X0, Y0, X1, Y1 = 541.1, 262.3, 571.9, 291.1        # il quadrato del piano terra (y verso sud)
BAIA = (550.9, 562.1)                               # la campata dell'ingresso sul fronte sud
LOGGIA = 1.6                                        # quanto sono arretrate le logge

DIAMANTE = "e25_diamante"
GIALLO = "#D9AE2C"
GRANITO = "#8C8F91"
LAMIERA = "kit_lamiera"
FASCIA = "#B9BCBD"
CEMENTO = "#A5A39D"
ACCIAIO = "#C6CACD"
TELAIO = "#2F433F"
VETRO = "#3D5159"
VERDE = "#4E6B63"                                   # la vetrata verde dell'ingresso
LEGNO = "#B39A70"
ZOCCOLO = "#4A4C4E"
ANIMA = "#55595F"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return GRONDA


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


# ------------------------------------------------------------------ il rivestimento

def _diamante():
    """Le bugne a piramide dei pannelli: 2 x 2 per ripetizione da 80 cm, antracite."""
    from PIL import Image
    rng = np.random.default_rng(25)
    size, n = 256, 2
    y, x = np.mgrid[0:size, 0:size] / size
    fx, fy = (x * n) % 1.0 - 0.5, (y * n) % 1.0 - 0.5
    height = np.clip(1 - 2 * np.maximum(np.abs(fx), np.abs(fy)), 0, 1)
    gola = np.maximum(np.abs(fx), np.abs(fy)) > 0.46
    # la luce dall'alto: le facce della piramide rivolte in su più chiare
    tono = 0.82 + 0.25 * np.where(np.abs(fy) > np.abs(fx), -np.sign(fy), 0.3 * -np.sign(fx)) * (1 - height) ** 0.5
    rgb = np.array([0.22, 0.225, 0.235])[None, None] * (tono + rng.normal(0, 0.02, (size, size)))[..., None]
    rgb[gola] *= 0.6
    gy, gx = np.gradient(height)
    nrm = np.dstack([-gx * 9.0, gy * 9.0, np.ones_like(height)])
    nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
    to8 = lambda a: Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return to8(rgb), to8(nrm * 0.5 + 0.5)


def _registra(E):
    E.TEX.setdefault(DIAMANTE, 0.8)
    if DIAMANTE not in E._TEXTURES:
        E._TEXTURES[DIAMANTE] = _diamante()


# ------------------------------------------------------------------ i fronti

def _lato(E, a, c):
    """Un fronte da a a c, con la normale verso fuori (a destra andando da a a c, y a sud)."""
    L = float(np.hypot(c[0] - a[0], c[1] - a[1]))
    u = ((c[0] - a[0]) / L, (c[1] - a[1]) / L)
    return (a, c, u, E.normal_out(a, c), L, 0.0)


def _t(e, x, y):
    return (x - e[0][0]) * e[2][0] + (y - e[0][1]) * e[2][1]


def guscio(b, E):
    k = K.Kit(E, CSIE)
    _registra(E)
    S, P = k.S, k.pannello
    st = K.Stile(muro=DIAMANTE, davanzale=1.0, architrave=3.1, telaio=TELAIO, vetro=VETRO, sguincio=0.32,
                 cornice=GRANITO, montante=0.9)

    sud = _lato(E, (X1, Y1), (X0, Y1))
    ovest = _lato(E, (X0, Y1), (X0, Y0))
    nord = _lato(E, (X0, Y0), (X1, Y0))
    est = _lato(E, (X1, Y0), (X1, Y1))
    tb0, tb1 = sorted((_t(sud, BAIA[0], Y1), _t(sud, BAIA[1], Y1)))

    # le finestre, in coordinate del fronte: (t0, t1) per piano
    def lungo_y(e, y0, y1):
        return tuple(sorted((_t(e, X0 if e is ovest else X1, y0), _t(e, X0 if e is ovest else X1, y1))))

    def lungo_x(e, x0, x1, y):
        return tuple(sorted((_t(e, x0, y), _t(e, x1, y))))

    finestre = {
        id(ovest): [lungo_y(ovest, 264.6, 267.2), lungo_y(ovest, 272.0, 274.0), lungo_y(ovest, 279.4, 280.9)],
        id(est): [lungo_y(est, 263.2, 268.9), lungo_y(est, 270.2, 276.1), lungo_y(est, 277.3, 283.2),
                  lungo_y(est, 284.5, 290.3)],
        id(nord): [lungo_x(nord, 554.3, 556.3, Y0), lungo_x(nord, 556.6, 558.6, Y0)],
        id(sud): [lungo_x(sud, 547.8, 549.5, Y1)],
    }

    # l'anima piena dei piani, dietro le logge
    E.prisma(S, ANIMA, E.ring_ccw(box(X0 + 0.4, Y0 + 0.4, X1 - 0.4, Y1 - LOGGIA - 0.4)), 0.0, PIANI[-1][1])
    E.prisma(S, ANIMA, E.ring_ccw(box(X0 + 0.4, Y1 - LOGGIA - 0.5, BAIA[0] - 0.2, Y1 - 0.4)), 0.0, PIANI[-1][1])
    E.prisma(S, ANIMA, E.ring_ccw(box(BAIA[1] + 0.2, Y1 - LOGGIA - 0.5, X1 - 0.4, Y1 - 0.4)), 0.0, PIANI[-1][1])

    # lo zoccolo: il seminterrato affiora appena, in granito scuro
    for e in (sud, ovest, nord, est):
        buchi = [(tb0, tb1, -0.3, 0.6)] if e is sud else []
        k.muro(e, -0.3, 0.6, ZOCCOLO, buchi, d=0.08)

    # i tre piani, fronte per fronte
    for z0, z1 in PIANI:
        k._zpiano = z0
        for e in (sud, ovest, nord, est):
            iv = finestre[id(e)]
            zf0, zf1 = z0 + st.davanzale, min(z1 - 0.3, z0 + st.architrave)
            buchi = [(t0, t1, zf0, zf1) for t0, t1 in iv]
            if e is sud:
                buchi.append((tb0, tb1, z0, z1))
            k.muro(e, z0, z1, DIAMANTE, buchi)
            for t0, t1 in iv:
                k.foro(e, t0, t1, zf0, zf1, st)

    # le fasce gialle
    def fascia(e, t0, t1, z0, z1, sp=0.1):
        P(GIALLO, e, K.rett(t0, t1, z0, z1), 0.06, 0.06 + sp)     # davanti alla pelle del muro

    o = lambda y0, y1: lungo_y(ovest, y0, y1)
    t0, t1 = o(Y0, 281.4)
    fascia(ovest, t0, t1, 9.0, 9.7)                    # la lunga, tra il primo e il secondo
    t0, t1 = o(268.4, 281.4)
    fascia(ovest, t0, t1, 4.5, 5.2)                    # tra il terra e il primo, a L
    t0, t1 = o(268.4, 269.1)
    fascia(ovest, t0, t1, 1.2, 4.5)
    t0, t1 = lungo_x(sud, 547.6, 549.7, Y1)            # sotto la colonna di finestre a ovest dell'ingresso
    for z0, _ in PIANI:
        fascia(sud, t0, t1, z0 + 0.35, z0 + 0.85)
    # sul fronte est le fasce sotto i nastri del secondo e del primo, legate da un tratto verticale
    t0, t1 = lungo_y(est, 269.6, 290.6)
    fascia(est, t0, t1, PIANI[2][0] + 0.3, PIANI[2][0] + 0.8)
    t0, t1 = lungo_y(est, 276.7, 290.6)
    fascia(est, t0, t1, PIANI[1][0] + 0.3, PIANI[1][0] + 0.8)
    t0, t1 = lungo_y(est, 283.5, 284.1)
    fascia(est, t0, t1, PIANI[1][0] + 0.8, PIANI[2][0] + 0.3)
    # e le lesene di granito tra i nastri, con lo zoccolo di granito del terra
    for y in (269.55, 276.7, 283.85):
        t0, t1 = lungo_y(est, y - 0.5, y + 0.5)
        P(GRANITO, est, K.rett(t0, t1, 0.6, PIANI[-1][1]), 0.06, 0.12)
    P(GRANITO, est, K.rett(0.0, est[4], 0.0, 1.5), 0.06, 0.14)

    # la campata dell'ingresso: le logge arretrate, i solai coi frontalini gialli, le ringhiere
    fondo = _lato(E, (BAIA[1], Y1 - LOGGIA), (BAIA[0], Y1 - LOGGIA))
    for z0, z1 in PIANI[1:]:
        k.muro(fondo, z0, z1, GRANITO, [(0.4, fondo[4] - 0.4, z0 + 0.15, z1 - 0.5)])
        st_l = st.con(passo_montanti=1.4)
        k.vetrata(fondo, z0 + 0.15, z1 - 0.5, st_l, t0=0.4, t1=fondo[4] - 0.4, traversi=(z0 + 2.5,))
        # il solaio della loggia, il frontalino giallo e la ringhiera
        E.prisma(S, CEMENTO, E.ring_ccw(box(BAIA[0], Y1 - LOGGIA, BAIA[1], Y1)), z0 - 0.35, z0)
        fascia(sud, tb0, tb1, z0 - 0.55, z0 + 0.1, sp=0.1)
        _ringhiera(k, sud, tb0 + 0.1, tb1 - 0.1, z0 + 0.1, z0 + 1.15, d=-0.15)
    # il soffitto di legno sotto la gronda
    E.prisma(S, "#7C6A52", E.ring_ccw(box(BAIA[0], Y1 - LOGGIA, BAIA[1], Y1)), PIANI[-1][1] - 0.25, PIANI[-1][1])
    # le spalle della campata in granito
    for x, verso in ((BAIA[0], 1), (BAIA[1], -1)):
        a, c = ((x, Y1 - LOGGIA), (x, Y1)) if verso > 0 else ((x, Y1), (x, Y1 - LOGGIA))
        e = _lato(E, a, c)
        k.muro(e, 0.6, PIANI[-1][1], GRANITO, d=0.02, dentro=0.3)
        tt = _t(sud, x, Y1)
        P(GRANITO, sud, K.rett(tt - 0.55, tt, 0.6, PIANI[-1][1]) if verso < 0 else K.rett(tt, tt + 0.55, 0.6, PIANI[-1][1]), 0.0, 0.04)

    # al terra: la vetrata verde arretrata, le porte, la tabella di legno, i pilastrini di granito
    vt = _lato(E, (BAIA[1] - 0.6, Y1 - 0.8), (BAIA[0] + 0.6, Y1 - 0.8))
    k.vetrata(vt, 0.6, PIANI[1][0] - 0.55, K.Stile(telaio="#2E3B37", vetro=VERDE, passo_montanti=0.9),
              traversi=(3.3,))
    E.prisma(S, ANIMA, E.ring_ccw(box(BAIA[0], Y1 - LOGGIA - 0.4, BAIA[1], Y1 - 0.9)), 0.0, PIANI[1][0] - 0.4)
    for i in range(3):
        tc = vt[4] * (i + 1) / 4
        k.porta(vt, tc - 1.0, tc + 1.0, 0.6, h=2.5, telaio="#5E6062")
    P(LEGNO, sud, K.rett(tb0 + 0.6, tb1 - 0.6, 3.15, 3.75), -0.75, -0.55)
    for i in range(5):
        tc = tb0 + 0.9 + (tb1 - tb0 - 1.8) * i / 4
        _pilastrino(k, sud, tc, 0.6, 3.1)

    # la fascia di gronda in metallo chiaro, con la sua riga
    anello = box(X0, Y0, X1, Y1).buffer(0.3, join_style=2).difference(box(X0 + 0.2, Y0 + 0.2, X1 - 0.2, Y1 - 0.2))
    S.solid(FASCIA, trimesh.creation.extrude_polygon(anello, GRONDA - PIANI[-1][1]).apply_translation([0, 0, PIANI[-1][1]]))
    riga = box(X0, Y0, X1, Y1).buffer(0.34, join_style=2).difference(box(X0, Y0, X1, Y1).buffer(0.25, join_style=2))
    S.solid("#8F9394", trimesh.creation.extrude_polygon(riga, 0.05).apply_translation([0, 0, 14.0]))

    # il tetto a padiglione basso in lamiera
    k.falde(box(X0, Y0, X1, Y1), GRONDA, pendenza=PENDENZA, sporto=0.3, colore=LAMIERA, gronda=FASCIA)
    # il tamburo tondo di cemento sulla falda nord, sopra la scala del sottotetto
    cx, cy = 556.4, 269.4
    S.solid(CEMENTO, trimesh.creation.cylinder(radius=4.2, height=4.2, sections=48).apply_translation([cx, cy, 16.8]))
    S.solid("#8E8C87", trimesh.creation.cylinder(radius=4.0, height=0.1, sections=48).apply_translation([cx, cy, 18.95]))
    # i due comignoli d'acciaio verso ovest
    for y in (268.0, 271.6):
        S.solid(ACCIAIO, trimesh.creation.cylinder(radius=0.2, height=3.2, sections=12).apply_translation([545.6, y, 16.2]))
        S.solid(ACCIAIO, trimesh.creation.cylinder(radius=0.3, height=0.25, sections=12).apply_translation([545.6, y, 17.9]))
    # i pluviali sugli spigoli
    for x, y in ((X0 - 0.15, Y0 - 0.15), (X1 + 0.15, Y0 - 0.15), (X1 + 0.15, Y1 + 0.15), (X0 - 0.15, Y1 + 0.15)):
        S.solid(ACCIAIO, trimesh.creation.cylinder(radius=0.09, height=13.8, sections=10).apply_translation([x, y, 6.8]))

    # la scala esterna verso il seminterrato, a ovest: il parapetto intorno al pozzo
    pozzo = Polygon([(531.0, 292.0), (533.0, 287.2), (537.6, 287.2), (539.6, 292.0)])
    for r in k.pezzi(pozzo.difference(pozzo.buffer(-0.25, join_style=2)), 0.05):
        S.solid(ZOCCOLO, trimesh.creation.extrude_polygon(r, 1.1))
    k.top = max(k.top, 19.05)
    return k.fine()


def _ringhiera(k, e, t0, t1, z0, z1, d=0.0, passo=0.13):
    """Una ringhiera di ferro scuro: i correnti e le bacchette."""
    P = k.pannello
    P("#3B3F42", e, K.rett(t0, t1, z1 - 0.06, z1), d - 0.04, d + 0.04)
    P("#3B3F42", e, K.rett(t0, t1, z0 + 0.08, z0 + 0.12), d - 0.02, d + 0.02)
    n = int((t1 - t0) / passo)
    for i in range(n + 1):
        t = t0 + (t1 - t0) * i / n
        P("#3B3F42", e, K.rett(t - 0.012, t + 0.012, z0, z1), d - 0.012, d + 0.012)


def _pilastrino(k, e, tc, z0, z1, w=0.85):
    """Un pilastrino di granito davanti alle porte, col cappello a mezzo tondo."""
    P = k.pannello
    P(GRANITO, e, K.rett(tc - w / 2, tc + w / 2, z0, z1 - w / 2), -0.25, 0.4)
    ang = np.linspace(0, np.pi, 13)
    cap = Polygon([(tc + w / 2 * np.cos(a), z1 - w / 2 + w / 2 * np.sin(a)) for a in ang])
    P("#A2A5A7", e, cap, -0.25, 0.4)
