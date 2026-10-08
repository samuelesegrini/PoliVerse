"""PROTOTIPO — l'Edificio 41 (MIA0314), la nuova sede del DCMIC e del DEIB in via Bassini
(inaugurata il 16 dicembre 2025): l'esterno rifatto dalle piante e dalle foto.

Fonti, oltre alle piante del Politecnico (piante/MIA0314-geometria.json):
- il contorno di ogni piano viene dalle piante: il corpo a pettine con tre corpi neri (un
  blocco sul fronte nord e la sua ala verso sud) e due connettori vetrati fra i blocchi.
  Dal primo al quarto piano i lati delle ali hanno i risalti pieni (2,2 m, sporgono 1,3 m)
  e fra uno e l'altro la finestra arretrata; al terra il vetro corre dritto sotto i risalti;
- le foto Urbanfile (18 dicembre 2025 e 12 gennaio 2026) e quelle del Politecnico
  (inaugurazione): pannelli neri in fasce di un piano con la piega in basso, finestre a
  feritoia sfalsate sul fronte nord come nelle piante, il terra tutto vetrato; i connettori
  vetrati dal primo al quarto piano (al quinto la terrazza con la ringhiera) verso il largo Volontari del Sangue e verso i cortili,
  al terra il portale nero con i cancelli a lamelle, in cima la fascia grigia con la
  scritta; le testate sud delle ali chiuse da frangisole orizzontali che salgono oltre il
  tetto; sui lati delle ali il quinto piano (gli impianti, nelle piante una sala unica con i
  pilastri) è una fascia piena a filo dei risalti e sopra corre la fascia a lamelle; il vano
  scala vetrato sul lato est con la ringhiera in cima; il tunnel vetrato al primo piano verso
  l'Edificio 20A, la striscia di lamelle accanto alla torre dell'ascensore ovest e il box a
  lamelle ai suoi piedi; i cortili fra le ali a prato con gli alberi giovani;
- le foto dal drone del Politecnico (zenitale e da nord) e l'ortofoto 2025: i tre corpi neri
  più alti dei connettori, il fotovoltaico sui blocchi nord e al centro delle ali, le due
  strisce di impianti ai lati di ogni ala, il lucernario dell'atrio in testa all'ala, un
  lucernario su ogni connettore.

Le quote vengono dalle scale (pedate da 30 cm, due rampe da 14 alzate per piano): piani da
4,4 m, il terra più alto (4,8 m). Il seminterrato è il parcheggio interrato da 110 posti, che
nelle piante ha un'origine sua: è riportato sotto l'edificio (spostamenti in bassini.json)
facendo combaciare le tre scale del fronte nord con quelle del terra, e così cade proprio
sullo scavo del 2021 dell'ortofoto. Coordinate Z-up del frame del campus: x est, y sud.
"""
import json
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union

CSIE = "MIA0314"
PIANI = ["MIA031400S", "MIA0314000", "MIA0314001", "MIA0314002", "MIA0314003", "MIA0314004", "MIA0314005"]
Z_S, Z_0, Z_1 = -4.4, 0.0, 4.8
H = 4.4
QUOTE = {"MIA031400S": Z_S, "MIA0314000": Z_0, **{f"MIA031400{k}": round(Z_1 + H * (k - 1), 2) for k in range(1, 6)}}
TETTO = round(Z_1 + H * 5, 2)        # 26,8 m: il solaio del tetto
Z_5 = QUOTE["MIA0314005"]
# I connettori hanno quattro piani vetrati sopra il portale (foto da nord e dal cortile): al
# quinto c'è una terrazza con la ringhiera su entrambi i fronti e, arretrato di 3 m, un volume
# basso col lucernario, che da terra non si vede (nella foto zenitale è la fascia chiara).
CONN_ARRETRA = 3.0
TETTO_CONN = Z_5 + 3.4
# I blocchi nord finiscono poco sopra il quinto piano (foto da nord: 0,8 m di pannello), le ali
# salgono più in alto con la corona a frangisole e le strisce di impianti (foto zenitale e dai
# cortili): fra blocco e ala resta il gradino col lucernario dell'atrio.
CORONA_N = TETTO + 0.4
PARAPETTO_N = CORONA_N + 0.4
CORONA = TETTO + 2.0
PARAPETTO = CORONA + 0.5
SCHERMO = CORONA + 1.0               # le strisce di impianti sulle ali, chiuse dai frangisole

NERO = "#383B40"           # i pannelli neri (alluminio verniciato, opaco)
FUGA = "#1B1C1F"           # le fughe fra i pannelli e il fondo delle finestre
PIEGA = "#4B4F55"          # la piega in basso di ogni fascia, che prende la luce
VETRO = "#3E4A56"          # il vetro scuro delle finestre e del terra
VETRO_CONN = "#A7BBC9"     # i connettori, chiari e trasparenti
TELAIO = "#24262A"
LAMELLE = "#232528"
TETTO_COL = "#B8BBBE"
COPERTINA = "#C8CBCE"      # la copertina chiara dei parapetti (foto dal drone)
FASCIA = "#80858B"         # la fascia grigia in cima ai connettori, con la scritta
PV = "#2A3550"
PV_TELAIO = "#9AA1A8"
PRATO = "#8FB46E"
LASTRE = "#C9C8C2"
CHIOMA, TRONCO = "#9CBF7E", "#7A6248"

# I connettori vetrati, fra i blocchi nord (x) e fino a dove arrivano verso sud (y).
CONNETTORI = [(345.0, 361.4), (382.9, 399.4)]
Y_CONN = 91.5
# I tre corpi neri, fra i connettori.
CORPI = [(323.7, 344.8), (361.7, 382.8), (399.7, 420.8)]
# Le ali, sotto il fronte nord: da qui in giù i lati del quinto piano sono a frangisole.
Y_ALI = 91.2
# Il tunnel vetrato al primo piano verso l'Edificio 20A (OSM w1485857923).
TUNNEL = box(305.3, 87.9, 320.9, 89.9)
# Il vano scala vetrato sul lato est, fra il blocco nord e l'ala.
SCALA_EST = box(420.95, 82.0, 424.5, 91.0)
# Il box a lamelle davanti alla torre dell'ascensore ovest, accanto alla sbarra del passo carraio.
BOX_NO = box(316.4, 90.0, 321.1, 98.6)
# Il ponte vetrato al primo piano verso l'Edificio 21, come lo disegna la pianta.
PONTE = box(423.35, 87.6, 434.0, 91.0)


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def _piante(E):
    return json.loads((E.SRC / "piante" / f"{CSIE}-geometria.json").read_text())["piani"]


def _contorni(geo, csip):
    """I contorni del piano, il più grande per primo, ripuliti dai gradini di pochi cm."""
    out = []
    for r in geo[csip]["contorno"]:
        p = Polygon(r).buffer(0).simplify(0.06)
        if p.area > 2:
            out.append(p)
    return sorted(out, key=lambda p: -p.area)


def _chiuso(p, r=1.1):
    """Il contorno con le rientranze strette (le feritoie fra i risalti) riempite."""
    return p.buffer(r, join_style=2).buffer(-r, join_style=2)


def rett(t0, t1, z0, z1):
    return Polygon([(t0, z0), (t1, z0), (t1, z1), (t0, z1)])


def _mid(e):
    a, c = e[0], e[1]
    return ((a[0] + c[0]) / 2, (a[1] + c[1]) / 2)


def connettore(e):
    """Il lato è un fronte vetrato di un connettore (verso nord o verso i cortili)."""
    x, y = _mid(e)
    return abs(e[3][1]) > 0.9 and y < Y_CONN and any(x0 + 0.3 < x < x1 - 0.3 for x0, x1 in CONNETTORI)


def testata(e):
    """Una testata sud di un'ala (o un suo risvolto), chiusa dai frangisole."""
    x, y = _mid(e)
    return y > 109.0 and (e[3][1] > 0.9 or (abs(e[3][0]) > 0.9 and y > 110.2))


def lato_ala(e):
    x, y = _mid(e)
    return abs(e[3][0]) > 0.9 and y > Y_ALI


def _conn():
    return unary_union([box(x0 + 0.05, 70.0, x1 - 0.05, Y_CONN) for x0, x1 in CONNETTORI])


def finestre(geo, csip, e, reach=0.9):
    """Gli intervalli [t0, t1] delle finestre della pianta su questo lato: i telai disegnati
    paralleli al lato, entro reach dal suo filo."""
    a, c, u, n, L, _ = e
    iv = []
    for s in geo[csip]["linee"].get("finestre", []):
        p, q = np.array(s[:2]), np.array(s[2:])
        d = q - p
        ln = np.linalg.norm(d)
        if ln < 0.3 or abs(np.dot(d / ln, u)) < 0.95:
            continue
        ds = [float(np.dot(r - np.array(a), np.array(n))) for r in (p, q)]
        if not all(-reach < v < 0.25 for v in ds):
            continue
        ts = sorted(float(np.dot(r - np.array(a), np.array(u))) for r in (p, q))
        if ts[1] < 0.1 or ts[0] > L - 0.1:
            continue
        iv.append((max(0.0, ts[0]), min(L, ts[1])))
    iv.sort()
    out = []
    for t0, t1 in iv:
        if out and t0 < out[-1][1] + 0.05:
            out[-1] = (out[-1][0], max(out[-1][1], t1))
        else:
            out.append((t0, t1))
    return [(t0, t1) for t0, t1 in out if t1 - t0 > 0.5]


# ------------------------------------------------------------------ le facciate

def pannelli(E, S, e, z0, z1, buchi, passo=1.5):
    """Una fascia di un piano in pannelli neri: fughe orizzontali e verticali scure, la
    piega in basso che sporge e prende la luce (foto), i buchi delle finestre."""
    a, c, u, n, L, _ = e
    fori = unary_union([rett(t0, t1, zz0, zz1) for t0, t1, zz0, zz1 in buchi]) if buchi else Polygon()
    k = max(1, round(L / passo))
    for i in range(k):
        t0, t1 = L * i / k + 0.015, L * (i + 1) / k - 0.015
        E.panel(S, NERO, e, rett(t0, t1, z0 + 0.03, z1 - 0.03).difference(fori), 0.0, 0.1)
    E.panel(S, PIEGA, e, rett(0.0, L, z0 + 0.03, z0 + 0.14).difference(fori), 0.1, 0.17)
    E.panel(S, FUGA, e, rett(0.0, L, z0, z1), -0.05, 0.02)


def finestra(E, S, e, t0, t1, z0, z1):
    """La finestra arretrata nel pannello: il vetro scuro, il telaio nero, un traverso."""
    E.panel(S, VETRO, e, rett(t0, t1, z0, z1), 0.0, 0.03)
    tel = rett(t0, t1, z0, z1).difference(rett(t0 + 0.07, t1 - 0.07, z0 + 0.07, z1 - 0.07))
    E.panel(S, TELAIO, e, tel, 0.0, 0.06)
    zt = z0 + (z1 - z0) * 0.72
    E.panel(S, TELAIO, e, rett(t0, t1, zt - 0.03, zt + 0.03), 0.0, 0.05)
    if t1 - t0 > 1.3:
        tm = (t0 + t1) / 2
        E.panel(S, TELAIO, e, rett(tm - 0.03, tm + 0.03, z0, z1), 0.0, 0.05)


def lamelle(E, S, e, t0, t1, z0, z1, d=0.12, passo=0.16):
    """I frangisole: lamelle orizzontali nere su un fondo scuro."""
    E.panel(S, FUGA, e, rett(t0, t1, z0, z1), -0.05, 0.02)
    z = z0 + passo / 2
    while z < z1 - 0.02:
        E.panel(S, LAMELLE, e, rett(t0, t1, z - 0.035, z + 0.035), d, d + 0.1)
        z += passo
    for t in np.arange(t0, t1 + 0.01, max(1.0, (t1 - t0) / max(1, round((t1 - t0) / 3.0)))):
        E.panel(S, TELAIO, e, rett(max(t0, t - 0.04), min(t1, t + 0.04), z0, z1), 0.02, d)


def vetrata(E, S, e, z0, z1, passo=1.6, colore=VETRO_CONN, traversi=(), t0=0.0, t1=None):
    """Una facciata continua: il vetro, i montanti ogni passo, i traversi."""
    a, c, u, n, L, _ = e
    t1 = L if t1 is None else t1
    E.panel(S, colore, e, rett(t0, t1, z0, z1), -0.02, 0.02)
    k = max(1, round((t1 - t0) / passo))
    for i in range(k + 1):
        t = t0 + (t1 - t0) * i / k
        E.panel(S, TELAIO, e, rett(max(t0, t - 0.03), min(t1, t + 0.03), z0, z1), 0.0, 0.14)
    for z in (z0, z1, *traversi):
        E.panel(S, TELAIO, e, rett(t0, t1, max(z0, z - 0.04), min(z1, z + 0.04)), 0.0, 0.1)


def portale(E, S, e, z0, z1):
    """Il terra dei connettori (foto dal largo): il portale nero con tre varchi, i cancelli a
    lamelle in quelli laterali, la porta vetrata in mezzo, la fascia nera sopra."""
    a, c, u, n, L, _ = e
    zv = z0 + 3.4
    larghi = [(0.07, 0.22), (0.36, 0.64), (0.78, 0.93)]
    varchi = [(L * p, L * q) for p, q in larghi]
    pieno = rett(0.0, L, z0, z1).difference(unary_union([rett(t0, t1, z0, zv) for t0, t1 in varchi]))
    E.panel(S, NERO, e, pieno, 0.0, 0.25)
    E.panel(S, PIEGA, e, rett(0.0, L, zv + 0.4, zv + 0.5), 0.25, 0.3)
    for i, (t0, t1) in enumerate(varchi):
        E.panel(S, FUGA, e, rett(t0, t1, z0, zv), -0.6, -0.5)
        if i == 1:
            vetrata(E, S, e, z0, zv - 0.05, passo=1.2, colore=VETRO, t0=t0, t1=t1)
        zz = z0 + 0.1
        while zz < zv - 0.1:
            E.panel(S, LAMELLE, e, rett(t0, t1, zz, zz + 0.07), 0.05 if i != 1 else -0.25, 0.12 if i != 1 else -0.18)
            zz += 0.18 if i != 1 else 0.45


# ------------------------------------------------------------------ il guscio

def _piano(E, S, geo, csip, z0, z1, ultimo):
    terra = csip.endswith("000")
    corpo = _contorni(geo, csip)
    if ultimo:
        # Il quinto piano delle ali è quello degli impianti: nella foto da sud-est è una fascia
        # piena a filo dei risalti, senza feritoie. Il guscio è quello del quarto con le
        # rientranze chiuse.
        corpo = [_chiuso(p) for p in _contorni(geo, "MIA0314004")]
    if not terra:              # il ponte verso l'Edificio 21 si disegna a parte (guscio)
        corpo = [max(E.clean(p.difference(PONTE)), key=lambda q: q.area) for p in corpo]
    if ultimo:                 # al quinto i connettori sono terrazze (_connettori_quinto)
        corpo = E.clean(corpo[0].difference(_conn()))
    for k, poly in enumerate(corpo):
        pts = E.ring_ccw(poly)
        E.prisma(S, FUGA if not terra else TELAIO, pts, z0, z1)
        if k > 0 and not ultimo:
            continue          # il ponte verso l'Edificio 21 al primo piano, a parte sotto
        for e in E.edges(pts):
            a, c, u, n, L, _ = e
            x, y = _mid(e)
            if terra:
                if connettore(e):
                    portale(E, S, e, z0, z1)
                elif testata(e):
                    # i frangisole delle testate scendono fino a terra (foto dai cortili)
                    lamelle(E, S, e, 0.0, L, z0, z1)
                elif x < 323.5 and 82.0 < y < 91.0:          # il vano dell'ascensore a ovest
                    pannelli(E, S, e, z0, z1, [])
                elif x > 421.3:                                    # l'annesso basso a est
                    pannelli(E, S, e, z0, z1, [(t0, t1, z0 + 0.9, z0 + 3.4) for t0, t1 in finestre(geo, csip, e)])
                else:
                    # il terra tutto vetrato, montanti ogni 1,5 m, la fascia nera del solaio sopra
                    vetrata(E, S, e, z0, z1 - 0.7, passo=1.5, colore=VETRO, traversi=(z0 + 3.2,))
                    pannelli(E, S, e, z1 - 0.7, z1, [])
                continue
            if connettore(e):
                # la fascia del solaio dietro il vetro, chiara (foto dal drone), poi la vetrata
                E.panel(S, "#8C9CA6", e, rett(0.0, L, z0, z0 + 0.7), 0.0, 0.03)
                vetrata(E, S, e, z0, z1, passo=1.6, traversi=(z0 + 0.7, z0 + 3.5))
                continue
            if x > 420.8 and 82.0 < y < 91.0 and n[0] > 0.9:           # il vano scala est, vetrato
                vetrata(E, S, e, z0, z1, passo=1.35, colore=VETRO_CONN, traversi=(z0 + 2.2,))
                continue
            if testata(e) or (x < 323.6 and 90.6 < y < 93.6 and n[0] < -0.9):
                # le testate sud, e la striscia di lamelle fra la torre dell'ascensore e il
                # primo risalto dell'ala ovest (foto da via Bassini)
                lamelle(E, S, e, 0.0, L, z0, z1)
                continue
            fin = [] if ultimo and lato_ala(e) else finestre(geo, csip, e)
            buchi = [(t0, t1, z0 + 0.55, z0 + 3.75) for t0, t1 in fin]
            # sul fronte nord i pannelli sono larghi quanto lo spazio fra due feritoie (foto)
            pannelli(E, S, e, z0, z1, buchi, passo=2.8 if n[1] < -0.9 and y < Y_ALI else 1.5)
            for t0, t1, zz0, zz1 in buchi:
                finestra(E, S, e, t0, t1, zz0, zz1)
    return corpo


def _tetto(E, S, geo):
    """Sopra il quinto piano (foto dal drone, da nord e zenitale): i blocchi nord finiscono
    con un parapetto basso, le ali salgono ancora di una fascia piena, la corona degli
    impianti; i connettori si fermano al quarto con la terrazza (_connettori_quinto).
    Sulle ali la corona è a frangisole sui lati, e sopra stanno due strisce di impianti
    chiuse dalle lamelle, coperte di fotovoltaico; in mezzo il fotovoltaico e, verso nord,
    il lucernario dell'atrio."""
    poly = _chiuso(_contorni(geo, "MIA0314004")[0])
    conn = _conn()
    # il vano scala vetrato a est finisce col quinto piano, con la ringhiera (foto da sud-est)
    scala = poly.intersection(SCALA_EST)
    for q in E.clean(scala):
        E.prisma(S, TETTO_COL, E.ring_ccw(q), TETTO, TETTO + 0.15)
        x0, y0, x1, y1 = q.bounds
        for a_, c_ in (((x1 - 0.1, y0), (x1 - 0.1, y1)), ((x0, y0 + 0.1), (x1, y0 + 0.1)), ((x0, y1 - 0.1), (x1, y1 - 0.1))):
            E.trave(S, TELAIO, (*a_, TETTO + 1.2), (*c_, TETTO + 1.2), 0.05)
            for k in range(int(np.hypot(c_[0] - a_[0], c_[1] - a_[1]) / 1.5) + 1):
                f = k * 1.5 / max(0.01, np.hypot(c_[0] - a_[0], c_[1] - a_[1]))
                pp = (a_[0] + (c_[0] - a_[0]) * f, a_[1] + (c_[1] - a_[1]) * f)
                E.trave(S, TELAIO, (*pp, TETTO + 0.15), (*pp, TETTO + 1.2), 0.04)
    poly = poly.difference(SCALA_EST)
    _connettori_quinto(E, S, poly.intersection(conn))
    # i corpi neri: il blocco nord finisce col parapetto poco sopra il quinto, l'ala sale con
    # la corona piena (a frangisole sui lati); dove l'ala supera il blocco, il lucernario
    for q in E.clean(poly.difference(conn)):
        for parte, cz, pz in ((box(0, 0, 999, Y_ALI), CORONA_N, PARAPETTO_N), (box(0, Y_ALI, 999, 999), CORONA, PARAPETTO)):
            for r_ in E.clean(q.intersection(parte)):
                pts = E.ring_ccw(r_)
                E.prisma(S, FUGA, pts, TETTO, cz)
                for e in E.edges(pts):
                    x, y = _mid(e)
                    if cz == CORONA and abs(y - Y_ALI) < 0.2 and e[3][1] < -0.9:
                        vetrata(E, S, e, CORONA_N, CORONA, passo=1.5, colore="#56687A")
                    elif cz == CORONA_N and abs(y - Y_ALI) < 0.2:
                        continue
                    elif lato_ala(e) or testata(e):
                        lamelle(E, S, e, 0.0, e[4], TETTO, SCHERMO if testata(e) else cz)
                    else:
                        pannelli(E, S, e, TETTO, cz, [])
                dentro = r_.buffer(-0.35, join_style=2)
                E.prisma(S, TETTO_COL, E.ring_ccw(dentro), cz, cz + 0.08)
                bordo = r_.difference(dentro)
                if cz == CORONA_N:     # nessun parapetto contro la parete dell'ala
                    bordo = bordo.difference(box(0, Y_ALI - 0.4, 999, 999))
                for r in E.clean(bordo):
                    S.solid(NERO, trimesh.creation.extrude_polygon(r, pz - cz).apply_translation([0, 0, cz]))
                    S.solid(COPERTINA, trimesh.creation.extrude_polygon(r, 0.06).apply_translation([0, 0, pz]))
    for x0, x1 in CORPI:
        ala = poly.intersection(box(x0 - 3, Y_ALI, x1 + 3, 120.0))
        # le due strisce di impianti lungo i lati, a frangisole, col fotovoltaico sopra
        for xa, xb in ((x0 - 3, x0 + 4.2), (x1 - 4.2, x1 + 3)):
            for g in E.clean(ala.intersection(box(xa, Y_ALI + 0.4, xb, 113.6)).buffer(-0.05, join_style=2)):
                S.solid(FUGA, trimesh.creation.extrude_polygon(g, SCHERMO - CORONA).apply_translation([0, 0, CORONA]))
                for e in E.edges(E.ring_ccw(g)):
                    lamelle(E, S, e, 0.0, e[4], CORONA, SCHERMO)
                gx0, gy0, gx1, gy1 = g.bounds
                _fotovoltaico(E, S, box(max(gx0, x0) + 0.4, gy0 + 0.4, min(gx1, x1) - 0.4, gy1 - 0.4), SCHERMO)
        # in mezzo: il lucernario dell'atrio verso nord, poi il fotovoltaico
        S.solid(TELAIO, E.box_z((x0 + x1) / 2, 94.2, x1 - x0 - 9.0, 4.4, CORONA, CORONA + 0.5))
        S.solid("#56687A", E.box_z((x0 + x1) / 2, 94.2, x1 - x0 - 9.4, 4.0, CORONA + 0.5, CORONA + 0.6))
        _fotovoltaico(E, S, box(x0 + 4.8, 97.4, x1 - 4.8, 109.6), CORONA)
        # il blocco nord: due campi di pannelli
        _fotovoltaico(E, S, box(x0 + 1.2, 77.0, x1 - 1.2, 89.4), CORONA_N)
    return SCHERMO + 0.2


def _ringhiera(E, S, a_, c_, z0, h=1.1, passo=1.5):
    L = float(np.hypot(c_[0] - a_[0], c_[1] - a_[1]))
    E.trave(S, TELAIO, (*a_, z0 + h), (*c_, z0 + h), 0.05)
    E.trave(S, TELAIO, (*a_, z0 + 0.15), (*c_, z0 + 0.15), 0.04)
    for k in range(int(L / passo) + 1):
        f = min(1.0, k * passo / max(0.01, L))
        pp = (a_[0] + (c_[0] - a_[0]) * f, a_[1] + (c_[1] - a_[1]) * f)
        E.trave(S, TELAIO, (*pp, z0), (*pp, z0 + h), 0.04)


def _connettori_quinto(E, S, zona):
    """Il quinto piano dei connettori: la terrazza sul solaio del quarto, col bordo nero e la
    ringhiera sui due fronti (la scritta del dipartimento sulla ringhiera nord, foto dal
    drone), e arretrato il volume basso grigio con la finestra a nastro e il lucernario."""
    for q in E.clean(zona):
        x0, y0, x1, y1 = q.bounds
        pts = E.ring_ccw(q)
        E.prisma(S, LASTRE, pts, Z_5, Z_5 + 0.12)
        for e in E.edges(pts):
            if not connettore(e):
                continue
            E.panel(S, NERO, e, rett(0.0, e[4], Z_5 - 0.15, Z_5 + 0.35), 0.0, 0.12)
            a_, c_ = e[0], e[1]
            dn = (e[3][0] * -0.1, e[3][1] * -0.1)
            _ringhiera(E, S, (a_[0] + dn[0], a_[1] + dn[1]), (c_[0] + dn[0], c_[1] + dn[1]), Z_5 + 0.35)
            if e[3][1] < -0.9:          # la scritta, verso il largo
                m = e[4] / 2
                E.panel(S, "#2F6FB5", e, rett(m - 1.6, m + 1.6, Z_5 + 0.55, Z_5 + 1.25), 0.02, 0.06)
                E.panel(S, "#F4F5F7", e, rett(m - 1.3, m + 1.3, Z_5 + 0.7, Z_5 + 1.1), 0.06, 0.08)
        nucleo = box(x0, y0 + CONN_ARRETRA, x1, y1 - CONN_ARRETRA)
        pn = E.ring_ccw(nucleo)
        E.prisma(S, FASCIA, pn, Z_5 + 0.12, TETTO_CONN)
        for e in E.edges(pn):
            if abs(e[3][1]) > 0.9:
                E.panel(S, VETRO, e, rett(0.4, e[4] - 0.4, Z_5 + 0.9, Z_5 + 2.6), 0.0, 0.03)
                E.panel(S, FASCIA, e, rett(0.0, e[4], TETTO_CONN - 0.5, TETTO_CONN), 0.0, 0.1)
        E.prisma(S, TETTO_COL, E.ring_ccw(nucleo.buffer(-0.2, join_style=2)), TETTO_CONN, TETTO_CONN + 0.06)
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        S.solid(TELAIO, E.box_z(cx, cy, 6.4, 5.0, TETTO_CONN, TETTO_CONN + 0.4))
        S.solid("#AFC4D3", E.box_z(cx, cy, 6.0, 4.6, TETTO_CONN + 0.4, TETTO_CONN + 0.55))


def _fotovoltaico(E, S, zona, z):
    """File di pannelli da 1 m, con 0,5 m fra l'una e l'altra."""
    bx0, by0, bx1, by1 = zona.bounds
    if bx1 - bx0 < 1.0:
        return
    y = by0
    while y + 1.0 <= by1:
        S.solid(PV_TELAIO, E.box_z((bx0 + bx1) / 2, y + 0.5, bx1 - bx0, 1.0, z + 0.25, z + 0.37))
        S.solid(PV, E.box_z((bx0 + bx1) / 2, y + 0.5, bx1 - bx0 - 0.1, 0.92, z + 0.37, z + 0.41))
        y += 1.5


def _esterni(E, S):
    """Quello che sta fuori dal contorno: il tunnel verso il 20A, il ponte verso il 21, i
    cortili a prato fra le ali."""
    # il tunnel vetrato al primo piano (foto da via Bassini): base nera piena, vetro, tetto nero
    pts = E.ring_ccw(TUNNEL)
    E.prisma(S, NERO, pts, 0.0, Z_1)
    E.prisma(S, VETRO_CONN, E.ring_ccw(TUNNEL.buffer(-0.08, join_style=2)), Z_1, Z_1 + 3.2)
    E.prisma(S, NERO, pts, Z_1 + 3.2, Z_1 + 3.8)
    for e in E.edges(pts):
        if e[4] > 5:
            vetrata(E, S, e, Z_1, Z_1 + 3.2, passo=1.5, traversi=())
    # il box a lamelle all'angolo nord-ovest, davanti alla torre dell'ascensore (foto da via
    # Bassini): un piano, chiuso da frangisole sui tre lati liberi
    for e in E.edges(E.ring_ccw(BOX_NO)):
        if e[3][0] < 0.9:
            lamelle(E, S, e, 0.0, e[4], 0.0, 4.3, passo=0.2)
    E.prisma(S, FUGA, E.ring_ccw(BOX_NO), 0.0, 4.3)
    E.prisma(S, NERO, E.ring_ccw(BOX_NO.buffer(0.05, join_style=2)), 4.3, 4.45)
    # i cortili fra le ali: prato, i camminamenti in lastre lungo le facciate, gli alberi giovani
    for x0, x1 in CONNETTORI:
        cortile = box(x0 + 1.4, 90.8, x1 - 1.4, 114.0)
        E.prisma(S, LASTRE, E.ring_ccw(box(x0 + 0.2, 89.0, x1 - 0.2, 114.0)), 0.0, 0.08)
        E.prisma(S, PRATO, E.ring_ccw(cortile.buffer(-0.6, join_style=2)), 0.0, 0.1)
        for i in range(4):
            for xx in (x0 + 4.0, x1 - 4.0):
                y = 94.0 + i * 5.6
                S.solid(TRONCO, trimesh.creation.cylinder(radius=0.06, height=2.4, sections=6).apply_translation([xx, y, 1.3]))
                S.solid(CHIOMA, trimesh.creation.icosphere(subdivisions=1, radius=0.75).apply_translation([xx, y, 3.1]))


def guscio(b, E):
    """L'esterno dell'Edificio 41: {chiave: mesh} e la quota più alta."""
    S = E.Solidi()
    geo = _piante(E)
    for i, csip in enumerate(PIANI[1:]):
        z0 = QUOTE[csip]
        z1 = QUOTE[PIANI[i + 2]] if i + 2 < len(PIANI) else TETTO
        _piano(E, S, geo, csip, z0, z1, ultimo=(csip == PIANI[-1]))
    # i tetti piani del terra dove il primo non lo copre (l'annesso a est): lastra chiara e
    # parapetto nero, come i tetti bassi della foto zenitale
    sopra = unary_union(_contorni(geo, "MIA0314001")).buffer(0.05)
    for q in E.clean(_contorni(geo, "MIA0314000")[0].difference(sopra)):
        if q.area < 8:
            continue
        E.prisma(S, TETTO_COL, E.ring_ccw(q.buffer(-0.25, join_style=2)), Z_1, Z_1 + 0.06)
        for r in E.clean(q.difference(q.buffer(-0.25, join_style=2))):
            S.solid(NERO, trimesh.creation.extrude_polygon(r, 0.7).apply_translation([0, 0, Z_1]))
    # il ponte vetrato al primo piano verso l'Edificio 21, dove la pianta lo disegna
    for q in E.clean(_contorni(geo, "MIA0314001")[0].intersection(PONTE)):
        pts = E.ring_ccw(q)
        z1, z2 = QUOTE["MIA0314001"], QUOTE["MIA0314002"]
        E.prisma(S, NERO, pts, z1 - 0.5, z1 + 0.1)
        E.prisma(S, NERO, pts, z2 - 0.7, z2)
        for e in E.edges(pts):
            if e[4] > 3:
                vetrata(E, S, e, z1 + 0.1, z2 - 0.7, passo=1.5)
    top = _tetto(E, S, geo)
    _esterni(E, S)
    return S.meshes(), round(top, 2)
