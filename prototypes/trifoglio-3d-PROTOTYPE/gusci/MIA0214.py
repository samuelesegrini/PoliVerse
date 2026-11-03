"""PROTOTIPO — l'Edificio 16A (MIA0214), via Bonardi: il corpo sotto la piazza rialzata fra il
Trifoglio e il viale, senza aule. Il tetto è la piazza del progetto di Renzo Piano (2021).

Fonti, oltre alle piante del Politecnico (primo interrato, seminterrato, terra):
- la sagoma di OSM, un rettangolo di 44 m per 16;
- l'ortofoto (Esri World Imagery, 20 cm): la piazza chiara; tutto intorno il cortile ribassato
  del seminterrato, in ombra a nord (4 m) e a sud (3 m), coperto da due tettoie di vetro
  rigate a ovest e a est; a sud i due ponti verso il viale, il quadrato scuro dell'apertura
  sulla scala e accanto la pensilina chiara dell'ascensore;
- le foto di Urbanfile dell'inaugurazione (23 giugno 2021, Roberto Arsuffi): la piazza in lastre
  di pietra grigio chiaro; le fioriere basse di cemento con le betulle e le panche di pietra;
  la ringhiera di vetro con i piatti verticali grigio chiaro, che scendono davanti alla vetrata
  del seminterrato fino al fondo del cortile; sotto la ringhiera la fascia di cemento del bordo
  della piazza; la torretta di cemento dell'ascensore con la grande pensilina di vetro sulle
  mensole d'acciaio; i gradini che salgono dal viale alla piazza (sei alzate); la tettoia di
  vetro su travi e pilastri tondi sopra il cortile, verso il Trifoglio.

Il suolo del campus è pieno a quota 0, così il cortile ribassato è il suo fondo scuro a quota
0 e la vetrata del seminterrato sale da lì al bordo della piazza.
"""
import sys
import pathlib
from shapely.geometry import box, LineString
from shapely.ops import unary_union

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _kit as K

CSIE = "MIA0214"
PIAZZA = 0.9
QUOTE = {"MIA021401I": -8.0, "MIA021400S": -4.0, "MIA0214000": PIAZZA}

PIETRA = "#DDDAD2"          # le lastre della piazza
CEMENTO = "#CBC9C2"         # bordo della piazza, fioriere, torretta
PANCA = "#B5B3AC"
FONDO = "#6E7276"           # il fondo del cortile ribassato, visto dall'alto in ombra
METALLO = "#C4C8CB"         # ringhiere e piatti, alluminio chiaro
VETRO_R = "#CBD6DB"         # il vetro delle ringhiere
VETRATA = "#8FA3AE"         # la vetrata del seminterrato
TELAIO = "#7B8288"
TETTOIA = "#8E9AA0"         # le tettoie di vetro, grigie nell'ortofoto
PENSILINA_VETRO = "#D5DEE2" # la pensilina dell'ascensore, chiara nell'ortofoto e nelle foto
TRAVI = "#8C9399"
BETULLA_TRONCO, BETULLA_CHIOMA = "#E6E3DA", "#A7C98A"

# dall'ortofoto, nel frame del campus (x est, y sud)
PIAZZA_R = box(-4.5, 40.2, 39.7, 56.4)
CORTILE_N = box(-13.7, 36.3, 49.0, 40.2)
CORTILE_S = [box(-15.8, 56.4, 2.6, 59.5), box(12.7, 56.4, 22.7, 59.5), box(33.1, 56.4, 55.0, 59.5)]
TETTOIE = [box(-13.7, 36.3, -4.5, 56.4), box(39.7, 36.3, 49.0, 56.4)]
PONTI = [box(2.6, 56.4, 12.7, 61.2), box(22.7, 56.4, 33.1, 61.2)]
APERTURA = box(6.2, 49.9, 12.5, 54.3)
TORRETTA = box(9.3, 54.9, 12.0, 57.6)
PENSILINA = box(7.7, 53.9, 13.5, 58.9)


def quote(b, E):
    return dict(QUOTE)


def tetto(b, E):
    return PIAZZA


def piante(b, geo, aule, E):
    return K.completa_piante(geo, aule)


def lastra(k, poly, z0, z1, colore):
    """Un prisma dritto. Estruso qui e non con E.prisma, che semplifica a 5 cm e scarta i pezzi
    sotto 0,05 m²: i piatti e i vetri delle ringhiere sparirebbero."""
    import trimesh
    for q in getattr(poly.buffer(0), "geoms", [poly.buffer(0)]):
        if q.geom_type == "Polygon" and q.area > 1e-4:
            k.S.solid(colore, trimesh.creation.extrude_polygon(q, z1 - z0).apply_translation([0, 0, z0]))


def ringhiera(k, a, c, z0, h=1.1, giu=None, passo=0.6):
    """La ringhiera delle foto: una lastra di vetro fra due correnti, i piatti verticali grigio
    chiaro ogni passo. giu: la quota a cui scendono i piatti (davanti alla vetrata)."""
    ln = LineString([a, c])
    lastra(k, ln.buffer(0.012, cap_style=2), z0 + 0.08, z0 + h - 0.05, VETRO_R)
    lastra(k, ln.buffer(0.03, cap_style=2), z0 + h - 0.05, z0 + h, METALLO)
    n = max(1, round(ln.length / passo))
    for i in range(n + 1):
        p = ln.interpolate(i / n, normalized=True)
        zb = z0 if giu is None else giu
        lastra(k, _piatto(ln, p), zb, z0 + h + 0.05, METALLO)


def _piatto(ln, p, w=0.07, s=0.025):
    """Un piatto di 7 cm per 2,5, di taglio verso la ringhiera."""
    (x0, y0), (x1, y1) = ln.coords[0], ln.coords[-1]
    L = ln.length or 1
    ux, uy = (x1 - x0) / L, (y1 - y0) / L
    return LineString([(p.x - ux * w / 2, p.y - uy * w / 2), (p.x + ux * w / 2, p.y + uy * w / 2)]).buffer(s, cap_style=2)


def fioriera(k, x, y, dx, dy, alberi):
    lastra(k, box(x - dx / 2, y - dy / 2, x + dx / 2, y + dy / 2), PIAZZA, PIAZZA + 0.55, CEMENTO)
    lastra(k, box(x - dx / 2 + 0.12, y - dy / 2 + 0.12, x + dx / 2 - 0.12, y + dy / 2 - 0.12), PIAZZA + 0.55, PIAZZA + 0.5, "#5B4A3A")
    for ax, ay in alberi:
        betulla(k, ax, ay)


def betulla(k, x, y, h=6.5):
    import trimesh
    z = PIAZZA + 0.5
    k.S.solid(BETULLA_TRONCO, trimesh.creation.cylinder(radius=0.09, height=h * 0.6, sections=6).apply_translation([x, y, z + h * 0.3]))
    k.S.solid(BETULLA_CHIOMA, trimesh.creation.icosphere(subdivisions=1, radius=1.25)
              .apply_scale([1.0, 1.0, 1.7]).apply_translation([x, y, z + h * 0.62]))
    k.top = max(k.top, z + h)


def panca(k, x, y, lungo=2.2, nord_sud=False):
    dx, dy = (0.55, lungo) if nord_sud else (lungo, 0.55)
    lastra(k, box(x - dx / 2, y - dy / 2, x + dx / 2, y + dy / 2), PIAZZA + 0.36, PIAZZA + 0.46, PANCA)
    for s in (-1, 1):
        cx, cy = (x, y + s * (lungo / 2 - 0.3)) if nord_sud else (x + s * (lungo / 2 - 0.3), y)
        lastra(k, box(cx - 0.22, cy - 0.22, cx + 0.22, cy + 0.22), PIAZZA, PIAZZA + 0.36, PANCA)


def guscio(b, E):
    k = K.Kit(E, CSIE)
    corpo = PIAZZA_R

    # il fondo del cortile ribassato tutto intorno
    cortile = unary_union([CORTILE_N, *CORTILE_S, *TETTOIE])
    lastra(k, cortile.difference(corpo), 0.0, 0.1, FONDO)   # sopra i percorsi del campus (0,06)

    # la vetrata del seminterrato sul cortile, la fascia di cemento del bordo, la piazza
    vetrata = K.Stile(muro=CEMENTO, finestre="vetrata", telaio=TELAIO, vetro=VETRATA, passo_montanti=1.5, architrave=99)
    k.piano(corpo, 0.0, PIAZZA - 0.45, vetrata)
    k.piano(corpo, PIAZZA - 0.45, PIAZZA, K.Stile(muro=CEMENTO, finestre=None))
    lastra(k, corpo, PIAZZA - 0.02, PIAZZA, PIETRA)

    # la ringhiera sul bordo della piazza: i piatti scendono davanti alla vetrata
    x0, y0, x1, y1 = corpo.bounds
    d = 0.12
    ringhiera(k, (x0 + d, y0 + d), (x1 - d, y0 + d), PIAZZA, giu=0.0)                       # nord
    ringhiera(k, (x0 + d, y0 + d), (x0 + d, y1 - d), PIAZZA, giu=0.0)                       # ovest
    ringhiera(k, (x1 - d, y0 + d), (x1 - d, y1 - d), PIAZZA, giu=0.0)                       # est
    for a, c in ((x0 + d, 2.6), (12.7, 22.7), (33.1, x1 - d)):                              # sud, fra i ponti
        ringhiera(k, (a, y1 - d), (c, y1 - d), PIAZZA, giu=0.0)
    # e quella a terra sul bordo esterno del cortile
    cx0, cy0, cx1, _ = CORTILE_N.bounds
    ringhiera(k, (cx0, cy0), (cx1, cy0), 0.0)
    for q in CORTILE_S:
        qx0, _, qx1, qy1 = q.bounds
        ringhiera(k, (qx0, qy1), (qx1, qy1), 0.0)

    # i due ponti dal viale: sei gradini che salgono alla piazza, la ringhiera sui fianchi
    for p in PONTI:
        px0, py0, px1, py1 = p.bounds
        lastra(k, box(px0, py0, px1, py1 - 3.0), 0.0, PIAZZA, CEMENTO)
        lastra(k, box(px0, py0, px1, py1 - 3.0), PIAZZA - 0.02, PIAZZA, PIETRA)
        for i in range(6):
            y = py1 - 3.0 + i * 0.5
            lastra(k, box(px0, y, px1, y + 0.5), 0.0, PIAZZA - i * 0.15, PIETRA)
        for x in (px0 + 0.05, px1 - 0.05):
            ringhiera(k, (x, py0), (x, py1 - 3.0), PIAZZA)

    # l'apertura sulla scala che scende, con la sua ringhiera
    lastra(k, APERTURA.buffer(-0.05), PIAZZA - 0.01, PIAZZA + 0.01, FONDO)
    ax0, ay0, ax1, ay1 = APERTURA.bounds
    for a, c in (((ax0, ay0), (ax1, ay0)), ((ax1, ay0), (ax1, ay1)), ((ax1, ay1), (ax0, ay1)), ((ax0, ay1), (ax0, ay0))):
        ringhiera(k, a, c, PIAZZA)

    # la torretta dell'ascensore e la pensilina di vetro sulle mensole
    lastra(k, TORRETTA, PIAZZA, PIAZZA + 3.3, CEMENTO)
    zp = PIAZZA + 3.55
    tx, ty = TORRETTA.centroid.x, TORRETTA.centroid.y
    for s in (-1, 1):
        lastra(k, box(PENSILINA.bounds[0] + 0.4, ty + s * 0.9 - 0.06, PENSILINA.bounds[2] - 0.4, ty + s * 0.9 + 0.06), zp - 0.2, zp - 0.05, TRAVI)
        lastra(k, box(tx + s * 0.9 - 0.06, PENSILINA.bounds[1] + 0.4, tx + s * 0.9 + 0.06, PENSILINA.bounds[3] - 0.4), zp - 0.32, zp - 0.2, TRAVI)
    lastra(k, box(tx - 0.15, ty - 0.15, tx + 0.15, ty + 0.15), PIAZZA + 3.3, zp - 0.05, TRAVI)
    lastra(k, PENSILINA, zp - 0.05, zp, PENSILINA_VETRO)

    # le tettoie di vetro sul cortile, a ovest e a est: travi nord-sud, pilastri tondi
    import trimesh
    zt = PIAZZA + 0.9
    for t in TETTOIE:
        tx0, ty0, tx1, ty1 = t.bounds
        lastra(k, t, zt, zt + 0.04, TETTOIA)
        n = max(2, round((tx1 - tx0) / 2.3))
        for i in range(n + 1):
            x = tx0 + 0.1 + (tx1 - tx0 - 0.2) * i / n
            lastra(k, box(x - 0.06, ty0, x + 0.06, ty1), zt - 0.3, zt, TRAVI)
        for y in (ty0 + 1.0, (ty0 + ty1) / 2, ty1 - 1.0):
            cx = tx0 + 1.2 if tx0 < 0 else tx1 - 1.2
            k.S.solid(TRAVI, trimesh.creation.cylinder(radius=0.12, height=zt, sections=10).apply_translation([cx, y, zt / 2]))

    # le fioriere con le betulle e le panche di pietra, a ovest e a est della piazza
    for x, y, alberi in ((-1.6, 43.5, ((-1.6, 42.6), (-1.6, 44.4))),
                         (1.4, 48.0, ((1.4, 47.2), (1.4, 48.8))),
                         (-1.6, 52.5, ((-1.6, 51.6), (-1.6, 53.4))),
                         (35.0, 43.0, ((35.0, 42.2), (35.0, 43.8))),
                         (32.2, 47.5, ((32.2, 46.7), (32.2, 48.3))),
                         (35.4, 52.3, ((35.4, 51.5), (35.4, 53.1)))):
        fioriera(k, x, y, 1.6, 3.4, alberi)
    for x, y, ns in ((2.2, 43.0, True), (-1.2, 48.0, True), (3.0, 52.8, True), (16.0, 45.0, False),
                     (21.0, 51.0, False), (32.0, 42.5, True), (35.2, 47.8, True), (31.5, 52.5, True)):
        panca(k, x, y, nord_sud=ns)
    k.top = max(k.top, PIAZZA + 1.1)
    return k.fine()
