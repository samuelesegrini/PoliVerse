"""PROTOTIPO — l'Edificio 18 (MIA0207), via Ponzio 33: la palazzina quadrata di servizio sul
marciapiede ovest di via Ponzio, all'angolo del cortile di servizio del 15, senza aule.

Fonti, oltre alle piante del Politecnico (seminterrato e terra):
- la sagoma di OSM, un quadrato di 11 m per 10;
- l'ortofoto (Esri World Imagery): il tetto a padiglione basso;
- le panoramiche di Mapillary dell'ottobre 2024 dal marciapiede di via Ponzio, verso ovest:
  il rivestimento in piastrelline grigio-beige a corsi sfalsati, la gronda scura senza tetto
  visibile dal basso, sul fianco sud (sul cortile di servizio, poco più basso del
  marciapiede) la serranda grigia all'angolo con via Ponzio e due finestrelle quadrate più
  in là, su via Ponzio la finestra con l'inferriata e la nicchia dei contatori. Le altezze
  vengono dalle stesse foto, con la prospettiva del fianco sud: gronda a 4,2 m sulla strada
  (Overture dice 9,4 m, ma le foto non lo reggono);
- le piante: le porte del seminterrato danno sul cortile a sud e a ovest, quella del terra
  sul lato nord, verso via Corti. Le quote dei piani interni restano quelle dedotte prima.
"""
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0207"
QUOTE = {"MIA020700S": -3.2, "MIA0207000": 0.4}
CORTILE = -0.6       # il cortile di servizio a sud e a ovest, poco sotto il marciapiede
GRONDA = 4.2

PIASTRELLE = "#A59D93"
BASAMENTO = "#8F8A82"
SCURO = "#3C3F42"    # gronda, serrande, porte di servizio
SERRANDA = "#8E9398"
TELAIO = "#4A4F55"


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return GRONDA


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def _t(e, x, y):
    """La coordinata lungo il lato del punto (x, y) del campus."""
    a, _, u, _, _, _ = e
    return (x - a[0]) * u[0] + (y - a[1]) * u[1]


def _iv(e, p, q, margine=0.0):
    t0, t1 = sorted((_t(e, *p), _t(e, *q)))
    return max(0.15, t0 - margine), min(e[4] - 0.15, t1 + margine)


def finestra(k, e, t0, t1, z0, z1, sbarre=False):
    st = K.Stile(telaio=TELAIO, sguincio=0.12)
    k.foro(e, t0, t1, z0, z1, st)
    if sbarre:
        # l'inferriata in un pezzo solo: i tondini sottili da soli cadrebbero sotto la
        # soglia di area dei pannelli dell'esportatore
        n = max(3, round((t1 - t0) / 0.15))
        g = [K.rett(t0, t1, z - 0.03, z + 0.03) for z in (z0 + 0.1, z1 - 0.1)]
        g += [K.rett(t0 + (t1 - t0) * i / n - 0.025, t0 + (t1 - t0) * i / n + 0.025, z0, z1) for i in range(1, n)]
        k.pannello(SCURO, e, K.unary_union(g), 0.02, 0.08)


def serranda(k, e, t0, t1, z0, z1):
    k.pannello(SERRANDA, e, K.rett(t0, t1, z0, z1), -0.12, -0.08)
    z = z0 + 0.25
    while z < z1 - 0.1:
        k.pannello("#7D8287", e, K.rett(t0, t1, z - 0.012, z + 0.012), -0.09, -0.07)
        z += 0.25
    k.pannello(SCURO, e, K.rett(t0 - 0.08, t1 + 0.08, z1, z1 + 0.35), 0.0, 0.12)   # il cassonetto


def porta_cieca(k, e, t0, t1, z0, h):
    k.pannello(SCURO, e, K.rett(t0, t1, z0, z0 + h), -0.1, -0.06)
    k.pannello(TELAIO, e, K.rett(t0 - 0.05, t1 + 0.05, z0 + h, z0 + h + 0.05), -0.06, 0.0)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    corpo = k.contorno("MIA020700S", chiudi=0.4).minimum_rotated_rectangle
    # il nucleo: dal cortile alla gronda, le pelli lato per lato qui sotto
    k.piano(corpo, CORTILE, GRONDA, lambda e, c: None)
    for e in E.edges(E.ring_ccw(corpo)):
        v, L = K.verso(e), e[4]
        if v in ("S", "O"):
            zb = CORTILE
        else:
            zb = -0.3
        buchi, dopo = [], []
        if v == "S":
            # la serranda all'angolo con via Ponzio (le due porte affiancate del seminterrato)
            s0, s1 = _iv(e, (135.3, -13.7), (137.7, -13.7))
            buchi.append((s0, s1, CORTILE, 2.8))
            dopo.append(lambda e=e, s0=s0, s1=s1: serranda(k, e, s0, s1, CORTILE, 2.8))
            # la porta del seminterrato più a ovest
            p0, p1 = _iv(e, (128.6, -13.6), (129.4, -13.6), 0.05)
            buchi.append((p0, p1, CORTILE + 0.2, CORTILE + 2.4))
            dopo.append(lambda e=e, p0=p0, p1=p1: porta_cieca(k, e, p0, p1, CORTILE + 0.2, 2.2))
            # le due finestrelle quadrate del terra, accanto alla serranda
            for xc in (132.6, 130.9):
                f0, f1 = _iv(e, (xc - 0.4, -13.6), (xc + 0.4, -13.6))
                buchi.append((f0, f1, 2.1, 2.8))
                dopo.append(lambda e=e, f0=f0, f1=f1: finestra(k, e, f0, f1, 2.1, 2.8))
        elif v == "O":
            # le due porte del seminterrato sul cortile
            for y0, y1 in ((-21.95, -20.85), (-23.1, -22.0)):
                p0, p1 = _iv(e, (127.3, y0), (127.3, y1))
                buchi.append((p0, p1, CORTILE + 0.2, CORTILE + 2.4))
                dopo.append(lambda e=e, p0=p0, p1=p1: porta_cieca(k, e, p0, p1, CORTILE + 0.2, 2.2))
            for yc in (-16.0, -19.0):
                f0, f1 = _iv(e, (127.3, yc - 0.4), (127.3, yc + 0.4))
                buchi.append((f0, f1, 2.1, 2.8))
                dopo.append(lambda e=e, f0=f0, f1=f1: finestra(k, e, f0, f1, 2.1, 2.8))
        elif v == "E":
            # su via Ponzio: la finestra con l'inferriata verso nord, la nicchia dei contatori all'angolo sud
            f0, f1 = _iv(e, (138.0, -21.4), (138.0, -20.5))
            buchi.append((f0, f1, 1.5, 2.9))
            dopo.append(lambda e=e, f0=f0, f1=f1: finestra(k, e, f0, f1, 1.5, 2.9, sbarre=True))
            n0, n1 = _iv(e, (138.0, -14.9), (138.0, -14.2))
            buchi.append((n0, n1, 0.1, 1.1))
            dopo.append(lambda e=e, n0=n0, n1=n1: k.pannello("#8A8C8C", e, K.rett(n0, n1, 0.1, 1.1), -0.2, -0.16))
        else:
            # verso via Corti: l'ingresso del terra e due finestrelle
            p0, p1 = _iv(e, (134.7, -24.35), (135.55, -24.35), 0.1)
            buchi.append((p0, p1, 0.0, 2.4))
            dopo.append(lambda e=e, p0=p0, p1=p1: porta_cieca(k, e, p0, p1, 0.0, 2.3))
            for xc in (130.0, 132.4):
                f0, f1 = _iv(e, (xc - 0.4, -24.3), (xc + 0.4, -24.3))
                buchi.append((f0, f1, 2.1, 2.8))
                dopo.append(lambda e=e, f0=f0, f1=f1: finestra(k, e, f0, f1, 2.1, 2.8))
        # lo zoccolo grigio, poi la pelle di piastrelline fino sotto la gronda
        k.muro(e, zb, zb + 0.3, BASAMENTO, [b_ for b_ in buchi if b_[2] < zb + 0.3])
        k.muro(e, zb + 0.3, GRONDA, PIASTRELLE, [b_ for b_ in buchi if b_[3] > zb + 0.3])
        for f in dopo:
            f()
        # la gronda scura e spessa che fa da cornice al tetto
        k.pannello(SCURO, e, K.rett(-0.3, L + 0.3, GRONDA, GRONDA + 0.3), 0.0, 0.3)
    k.falde(corpo, GRONDA + 0.3, pendenza=0.18, sporto=0.3, colore="#8C8B87", gronda=SCURO)
    return k.fine()
