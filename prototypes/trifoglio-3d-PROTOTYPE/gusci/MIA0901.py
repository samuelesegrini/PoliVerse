"""PROTOTIPO — la Casa dello Studente (MIA0901), viale Romagna: la residenza del Politecnico, con
l'aula auditorium al terra.

Fonti, oltre alle piante del Politecnico (seminterrato e sette piani, dal terra al sesto):
- la sagoma e l'altezza di OSM (w40123288, 20,5 m): la manica ovest lungo la strada, quella
  lunga in diagonale verso nord-est sul viale col tram e il corpo di mezzo verso il cortile;
- le piante: le tre maniche ai piani tipo, il corpo di mezzo solo dal secondo al quinto (al
  terra c'è la sala grande, al primo è aperto), il sesto arretrato dal fronte sul viale; le
  finestre delle camere su tutti i lati;
- l'ortofoto (Esri World Imagery; qui l'edificio alto pende verso nord-est e lo spostamento non
  è regolare): i tetti piani, scuri sulla manica ovest con un lungo lucernario, chiari sul
  corpo di mezzo con gli impianti;
- le foto: l'angolo sul viale (Wikimedia Commons, "Milano casa dello Studente"), quella del
  1939-40 da Urbanfile e le panoramiche Mapillary del 2025 dal viale e dalla strada a ovest.

Com'è fatto, dalle foto:
- un basamento in granito grigio su tutto il giro (seminterrato e terra), con un marcapiano;
- tre corpi in mattone rosso a vista dal primo al quarto: il blocco d'angolo (circa 14 m sulla
  manica ovest, 20 m sul viale) e i due padiglioni in testa alle maniche; un marcapiano in
  pietra sopra il secondo, il quinto in pietra chiara;
- in mezzo le ali in intonaco giallo chiaro dal primo al quarto, con le persiane verdi, e il
  quinto in mattone fra due fasce di pietra;
- sul fronte d'angolo il portico del terra con due colonne, la fascia con la scritta, le
  finestre del primo con le cornici in pietra e i tre archi alti due piani (terzo e quarto) a
  ghiera di mattoni con il fondo in ocra;
- il cornicione in pietra sopra il quinto e il sesto arretrato in ocra, con le finestre ad arco
  sui lati lunghi e, sull'angolo, cieco con il comignolo in pietra in mezzo.

Le finestre sono quelle delle piante: il terra da 3,8 m e i piani delle camere da 2,95 m, per
stare nei 20,5 m di OSM.
"""
import sys
import math
import pathlib
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString
from shapely.ops import unary_union

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0901"
PIANI = [f"MIA090100{i}" for i in range(7)]
T0, H = 3.8, 2.95
QUOTE = {"MIA090100S": -3.4, **{c: (0.0 if i == 0 else round(T0 + (i - 1) * H, 2)) for i, c in enumerate(PIANI)}}
TETTO = round(T0 + 6 * H, 2)

GRANITO = "#A9A69F"        # il basamento
MATTONE = "kit_mattone"    # l'angolo e i padiglioni
INTONACO = "#E3CF9E"       # le ali, giallo chiaro
PIETRA = "#CBC8C0"         # marcapiani, cornici, il quinto dei corpi in mattone
OCRA = "#D6A15F"           # il sesto e il fondo degli archi
TELAIO = "#E4E1DA"         # i telai bianchi
PERSIANE = "#3F6E57"       # le persiane verdi delle ali
TAPPARELLE = "#5F6366"     # le tapparelle grigie dell'angolo
COPERTINA_ATTICO = "#D9D5CC"

# il fronte d'angolo, smussato verso sud-ovest, e l'asse della manica sul viale
SMUSSO = ((-313.1, 382.1), (-298.0, 390.8))
VIALE_A, VIALE_U = np.array([-298.0, 390.8]), np.array([0.866, -0.5])


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return TETTO


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def zona(p):
    """'mattone' (blocco d'angolo e padiglioni) o 'ala' (intonaco), dal punto in pianta."""
    x, y = p
    if x < -299.0:                                     # la manica ovest
        return "mattone" if y > 368.0 or y < 341.0 else "ala"
    s = float(np.dot(np.array(p) - VIALE_A, VIALE_U))  # lungo la manica sul viale
    if -270.0 < x < -262.0 and y < 362.0 or -283.6 <= x <= -266.0 and y < 360.0:
        return "ala"                                    # il corpo di mezzo, nel cortile
    return "mattone" if s < 20.0 or s > 61.0 else "ala"


def tratti(e, passo=0.5):
    """Il lato spezzato dove cambia la zona: [(t0, t1, zona)]."""
    a, _, u, _, L, _ = e
    n = max(1, int(L / passo))
    zs = [zona((a[0] + u[0] * L * (i + 0.5) / n, a[1] + u[1] * L * (i + 0.5) / n)) for i in range(n)]
    out = []
    for i, z in enumerate(zs):
        t0, t1 = L * i / n, L * (i + 1) / n
        if out and out[-1][2] == z:
            out[-1] = (out[-1][0], t1, z)
        else:
            out.append((t0, t1, z))
    return out


def sotto(e, t0, t1):
    a, _, u, n, _, t = e
    a2 = (a[0] + u[0] * t0, a[1] + u[1] * t0)
    c2 = (a[0] + u[0] * t1, a[1] + u[1] * t1)
    return (a2, c2, u, n, t1 - t0, t + t0)


def e_smusso(e):
    a, c = e[0], e[1]
    m = ((a[0] + c[0]) / 2, (a[1] + c[1]) / 2)
    return e[4] > 10.0 and abs(e[2][0] * 0.866 + e[2][1] * 0.5) > 0.97 and math.dist(m, (-305.5, 386.5)) < 4.0


def arco(t0, t1, z0, z1, seg=12):
    """Un'apertura con il tutto sesto in alto."""
    r = (t1 - t0) / 2
    zc = z1 - r
    pts = [(t0, z0), (t1, z0), (t1, zc)]
    pts += [((t0 + t1) / 2 + r * math.cos(math.pi * i / seg), zc + r * math.sin(math.pi * i / seg)) for i in range(1, seg)]
    pts += [(t0, zc)]
    return Polygon(pts)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    P = k.pannello
    base = K.Stile(davanzale=0.9, architrave=2.3, telaio=TELAIO, sguincio=0.15, reach=1.4,
                   ripiego=(3.4, 1.1, 12.0))
    corpi = []
    for csip in PIANI:
        g = unary_union([q for q in k.pezzi(k.contorno(csip, chiudi=0.8), 25.0)]).simplify(0.35)
        corpi.append(g)
    # il terra: il fronte d'angolo dritto come ai piani sopra (nella pianta ci sono i pilastri
    # del portico); la testata nord della manica ovest a filo, contro la casa vicina
    (ax, ay), (cx, cy) = SMUSSO
    fuori = Polygon([(ax, ay), (cx, cy), (cx - 20, cy + 35), (ax - 30, ay + 15)])
    corpi[0] = unary_union([corpi[0], corpi[1]]).difference(fuori).buffer(0.3, join_style=2).buffer(-0.3, join_style=2).simplify(0.35)
    vicina = Polygon([(-320, 320), (-299.5, 320), (-299.5, 332.4), (-320, 332.4)])
    corpi = [g.difference(vicina) for g in corpi]
    # il sesto arretrato di 1,5 m dal fronte d'angolo, dietro il comignolo
    nx, ny = 0.5, -0.866
    corpi[6] = corpi[6].difference(Polygon([(ax - 30 * 0.866, ay - 30 * 0.5), (cx + 30 * 0.866, cy + 30 * 0.5),
                                            (cx + 30 * 0.866 + 1.5 * nx, cy + 30 * 0.5 + 1.5 * ny),
                                            (ax - 30 * 0.866 + 1.5 * nx, ay - 30 * 0.5 + 1.5 * ny)]))
    # il portico del terra, profondo 3 m dietro il fronte d'angolo
    L = math.dist((ax, ay), (cx, cy))
    ux, uy = (cx - ax) / L, (cy - ay) / L
    portico = Polygon([(ax + ux * 1.6, ay + uy * 1.6), (cx - ux * 1.6, cy - uy * 1.6),
                       (cx - ux * 1.6 + nx * 3.0, cy - uy * 1.6 + ny * 3.0), (ax + ux * 1.6 + nx * 3.0, ay + uy * 1.6 + ny * 3.0)])

    def stile(i, z):
        if i == 0:
            return base.con(muro=GRANITO, telaio="#4D4740", vetro=PERSIANE, davanzale=1.5, architrave=3.3,
                            cornice=PIETRA)
        if z == "mattone":
            st = base.con(muro=PIETRA if i == 5 else MATTONE, vetro=PERSIANE)
            if i == 1:
                st = st.con(marcapiano=(0.4, 0.12, GRANITO))
            if i == 3:
                st = st.con(marcapiano=(0.3, 0.12, PIETRA))
            if i == 5:
                st = st.con(marcapiano=(0.25, 0.08, PIETRA))
            return st
        st = base.con(muro=MATTONE if i == 5 else INTONACO, vetro=PERSIANE)
        if i == 5:
            st = st.con(finestre=("passo", 3.4, 1.1))
        if i == 1:
            st = st.con(marcapiano=(0.4, 0.12, GRANITO))
        if i == 5:
            st = st.con(marcapiano=(0.3, 0.1, PIETRA))
        return st

    for i, (csip, g) in enumerate(zip(PIANI, corpi)):
        z0 = QUOTE[csip]
        z1 = T0 if i == 0 else z0 + H
        k._zpiano = z0
        for q in k.pezzi(g):
            nucleo = q.buffer(-K.SPESSORE + 0.02, join_style=2)
            if i == 0:
                nucleo = nucleo.difference(portico)
            for c in k.pezzi(nucleo, 0.5):
                E.prisma(k.S, "#55595F", E.ring_ccw(c), z0, z1)
            for e in E.edges(E.ring_ccw(q)):
                if e_smusso(e) and i in (0, 3, 4, 6):
                    angolo(k, e, i, csip, z0, z1, stile)
                    continue
                for t0, t1, z in tratti(e):
                    if t1 - t0 < 0.3:
                        continue
                    se = sotto(e, t0, t1)
                    if i == 6:
                        attico(k, se, z0, z1)
                    elif e_smusso(e):
                        st = stile(i, z).con(vetro=TAPPARELLE)
                        k.lato(se, z0, z1, st.con(cornice=PIETRA) if i == 1 else st, csip)
                    else:
                        k.lato(se, z0, z1, stile(i, z), csip)
                        if i == 0:
                            for p0, p1 in k.porte_esterne(csip, se):
                                k.porta(se, p0, p1, z0)
                            seminterrato(k, se, csip)
        k.top = max(k.top, z1)
        # il tetto di quello che il piano sopra non copre
        sopra = corpi[i + 1].buffer(0.2, join_style=2) if i + 1 < len(corpi) else None
        resto = g.difference(sopra) if sopra is not None else g
        for q in k.pezzi(resto, 6.0):
            alto = i + 1 == len(corpi)
            k.tetto_piano(q, z1, parapetto=0.9 if alto else 1.0, muro=OCRA if alto else PIETRA if i == 5 else INTONACO,
                          colore="#5B5F62" if alto else K.GUAINA)
    # le spalle del portico, in granito
    for s in (1.6, L - 1.6):
        x0, y0 = ax + ux * s, ay + uy * s
        spalla = LineString([(x0, y0), (x0 + nx * 3.0, y0 + ny * 3.0)]).buffer(0.06, cap_style=2)
        E.prisma(k.S, GRANITO, E.ring_ccw(spalla), 0.0, 3.0)
    # il cornicione sopra il quinto, tutto intorno
    zc = QUOTE["MIA0901006"]
    for q in k.pezzi(corpi[5]):
        for e in E.edges(E.ring_ccw(q)):
            P(PIETRA, e, K.rett(-0.5, e[4] + 0.5, zc - 0.35, zc), 0.0, 0.55)
            P(PIETRA, e, K.rett(-0.3, e[4] + 0.3, zc - 0.6, zc - 0.35), 0.0, 0.25)
    # l'attico d'angolo a gradoni: i due blocchi ai lati più alti del mezzo
    for s0, s1 in ((0.0, 4.0), (L - 4.0, L)):
        q = [(ax + ux * s + nx * d, ay + uy * s + ny * d) for s, d in ((s0, 1.5), (s1, 1.5), (s1, 5.5), (s0, 5.5))]
        g = Polygon(q).intersection(corpi[6])
        for c in k.pezzi(g, 2.0):
            E.prisma(k.S, OCRA, E.ring_ccw(c), TETTO, TETTO + 1.7)
            E.prisma(k.S, COPERTINA_ATTICO, E.ring_ccw(c.buffer(0.1, join_style=2)), TETTO + 1.7, TETTO + 1.8)
    # il comignolo in pietra al centro dell'attico d'angolo
    zt = TETTO
    m = E.box_z(0, 0, 3.2, 1.2, zc, zt + 1.4)
    m.apply_transform(trimesh.transformations.rotation_matrix(math.radians(-30.0), [0, 0, 1]))
    m.apply_translation([-305.1, 385.6, 0])
    k.S.solid(PIETRA, m)
    k.S.solid(PIETRA, trimesh.creation.cylinder(radius=0.25, height=3.6, sections=10).apply_translation([-305.1, 385.6, zt + 3.2]))
    # gli impianti sul tetto del corpo di mezzo
    k.impianto(-278.0, 340.0, 2.2, 1.6, QUOTE["MIA0901006"] + 0.1, h=1.2)
    k.impianto(-275.0, 346.0, 2.2, 1.6, QUOTE["MIA0901006"] + 0.1, h=1.2)
    k.top = max(k.top, zt + 5.2)
    return k.fine()


def angolo(k, e, i, csip, z0, z1, stile):
    """Il fronte d'angolo: il portico al terra, i tre archi al terzo e al quarto, l'attico cieco."""
    P = k.pannello
    L = e[4]
    fin = k.finestre_pianta(PIANI[2], e, 1.4, 0.6) or k.finestre_passo(L, 4.6, 1.2)
    centri = [(a + b) / 2 for a, b in fin][:3]
    if len(centri) < 3:
        centri = [L / 2 - 4.6, L / 2, L / 2 + 4.6]
    if i == 0:
        # il portico: due pilastri d'angolo, due colonne, la fascia della scritta
        a0, a1 = 1.6, L - 1.6
        P(GRANITO, e, K.rett(0, L, z0, z1).difference(K.rett(a0, a1, z0, 3.0)), -K.SPESSORE, 0.08)
        P("#9E9B94", e, K.rett(a0 - 0.2, a1 + 0.2, 3.05, 3.7), 0.08, 0.14)
        for j, t in enumerate(np.linspace(a0 + 1.2, a1 - 1.2, 12)):
            P("#3D3A36", e, K.rett(t - 0.18, t + 0.18, 3.2, 3.55), 0.14, 0.17)    # le lettere
        dentro = -2.9
        fondo = K.rett(a0, a1, z0, 3.0)
        porta = arco(L / 2 - 1.4, L / 2 + 1.4, z0, 2.9)
        lati = [K.rett(a0 + 0.8, a0 + 2.2, 0.9, 2.6), K.rett(a1 - 2.2, a1 - 0.8, 0.9, 2.6)]
        P("#B4B1AA", e, fondo.difference(unary_union([porta] + lati)), dentro - 0.3, dentro)
        P("#4D4740", e, porta, dentro - 0.35, dentro - 0.25)
        P("#9FB4C3", e, arco(L / 2 - 1.25, L / 2 + 1.25, z0, 2.75), dentro - 0.3, dentro - 0.22)
        for r in lati:
            P(PERSIANE, e, r, dentro - 0.4, dentro - 0.32)
        P("#8E8B85", e, K.rett(a0, a1, 2.95, 3.0), dentro, 0.0)                    # il soffitto
        a, _, u, n, _, _ = e
        for t in (L / 2 - 2.6, L / 2 + 2.6):
            x, y = a[0] + u[0] * t - n[0] * 0.7, a[1] + u[1] * t - n[1] * 0.7
            k.S.solid(GRANITO, trimesh.creation.cylinder(radius=0.38, height=3.0, sections=16).apply_translation([x, y, z0 + 1.5]))
        P(PIETRA, e, K.rett(0, L, z1 - 0.2, z1 + 0.2), 0.0, 0.12)
        return
    if i == 3:
        # i tre archi alti due piani: il fondo in ocra arretrato, la ghiera in mattoni
        zt = z0 + 2 * H - 0.35
        archi = [arco(c - 1.6, c + 1.6, z0 + 0.25, zt) for c in centri]
        P(MATTONE, e, K.rett(0, L, z0, z0 + 2 * H).difference(unary_union(archi)), -K.SPESSORE, 0.06)
        for c, a_ in zip(centri, archi):
            P(MATTONE, e, arco(c - 1.95, c + 1.95, z0 + 0.25, zt + 0.35).difference(a_).difference(K.rett(c - 2, c + 2, z0, zt - 1.6)), 0.06, 0.12)
            fori = []
            for zp in (z0, z0 + H):
                fori.append(K.rett(c - 0.6, c + 0.6, zp + 0.9, zp + 2.3))
            P(OCRA, e, a_.difference(unary_union(fori)), -0.4, -0.25)
            for zp in (z0, z0 + H):
                k._zpiano = zp
                k.foro(e, c - 0.6, c + 0.6, zp + 0.9, zp + 2.3, stile(3, "mattone").con(sguincio=0.4, vetro=TAPPARELLE))
        P(PIETRA, e, K.rett(0, L, z0 - 0.15, z0 + 0.15), 0.0, 0.12)
        return
    if i == 4:
        return                                    # già fatto con il terzo
    # il sesto sull'angolo: cieco, in ocra
    P(OCRA, e, K.rett(0, L, z0, z1 + 0.5), -K.SPESSORE, 0.06)
    P(PIETRA, e, K.rett(0, L, z1 + 0.5, z1 + 0.62), 0.0, 0.12)


def attico(k, e, z0, z1):
    """Il sesto: ocra, con le finestre ad arco a passo regolare sui lati lunghi."""
    P = k.pannello
    L = e[4]
    fori = [arco(t0, t1, z0 + 0.8, z0 + 2.5) for t0, t1 in k.finestre_passo(L, 3.4, 1.2)] if L > 4.0 else []
    forma = K.rett(0, L, z0, z1)
    if fori:
        forma = forma.difference(unary_union(fori))
    P(OCRA, e, forma, -K.SPESSORE, 0.06)
    for f in fori:
        P(K.VETRO, e, f, -0.2, -0.16)
        P(TELAIO, e, f.difference(f.buffer(-0.06)), -0.18, -0.12)
        t0, z_, t1, _ = f.bounds
        P(PIETRA, e, K.rett(t0 - 0.05, t1 + 0.05, z_ - 0.05, z_), -0.05, 0.06)


def seminterrato(k, e, csip):
    """Le finestrelle basse del seminterrato nel basamento, sotto quelle del terra."""
    fin = k.finestre_pianta(csip, e, 1.4, 0.6)
    if not fin and e[4] > 12.0:
        fin = k.finestre_passo(e[4], 3.4, 1.1)
    for t0, t1 in fin:
        k.pannello("#4A4B4C", e, K.rett(t0, t1, 0.25, 0.85), 0.06, 0.08)
        k.pannello("#8C8983", e, K.rett(t0 - 0.06, t1 + 0.06, 0.2, 0.25), 0.06, 0.14)
