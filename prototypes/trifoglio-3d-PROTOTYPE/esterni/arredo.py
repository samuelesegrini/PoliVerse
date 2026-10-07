#!/usr/bin/env python3
"""PROTOTIPO — l'arredo urbano dettagliato della zona, sopra il suolo di esterni3d.py.

esterni3d.py `terreno()` disegna strade, marciapiedi, verde e alberi; qui si aggiunge il
dettaglio che ci sta sopra, sempre da OpenStreetMap (zona.json e arredo.json, scritto da
importa_arredo.py):

- **alberi** più veri: tronco rastremato con i rami, chioma a lobi irregolari (a globo o
  ovale), conifere a palchi, palme (Trachycarpus) con le foglie a ventaglio. Sostituisce
  `albero()` di esterni3d.py, quindi restano i gruppi `Chiome` e `Tronchi`;
- **marciapiedi**: i cordoli in granito verso la carreggiata (abbassati agli attraversamenti)
  e le formelle degli alberi sul marciapiede;
- **panchine** per tipo (legno e ghisa con schienale e braccioli, pietra, cemento, metallo),
  girate verso il percorso o la strada più vicina, o come dice OSM (`direction`);
- **lampioni** per tipo: stradali a pastorale sulla carreggiata, a palo dritto, lanterne
  in ghisa nei parchi;
- cestini, rastrelliere ad archetto, dissuasori, fontanelle (le vedovelle verdi), pensiline
  e paline delle fermate, idranti;
- **sport**: porte, canestri, reti da tennis e padel con le pareti in vetro, pali da rugby,
  la struttura della calistenica, giochi dei parchi (altalene, scivoli, dondoli, molle),
  le righe dei campi fuori dal Giuriati; le recinzioni delle aree cani;
- **pergole** e fioriere della terrazza della Sala Lettura (corte di MIA0114 in leonardo.json).

esporta3d.py `campus()`:

    arredo.prima(esterni3d, zona)            # prima di terreno(): alberi nuovi, niente arredi vecchi
    esterni3d.terreno(E, sc, "Campus", zona, escludi, ingombri)
    arredo.arreda(E, esterni3d, sc, "Campus", zona, dettagli, escludi, ingombri, leonardo)

giuriati/esterni3d.py, per i campi del Giuriati (che hanno già le righe):

    arredo.sport(E, sc, gruppo, nome, tipo, pianta, righe=False)

Frame Z-su dei poligoni (x est, y sud, metri), girato in Y-su da E.YUP come il resto.
Posizioni © OpenStreetMap contributors (ODbL).
"""
import importlib.util, json, math, pathlib, zlib
import numpy as np
import trimesh
from shapely import STRtree, affinity
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union, nearest_points

QUI = pathlib.Path(__file__).resolve().parent
COL = {
    "ghisa": "#3B4A3F", "vedovella": "#2F5E3F", "legno": "#A07A52", "pietra": "#C2BDB3", "cemento": "#BDBAB3",
    "metallo": "#80878F", "palo": "#5B6168", "luce": "#F6EBC8", "granito": "#CFCBC3", "terra": "#7A624A",
    "bianco": "#F4F4F0", "rete": "#4E5560", "vetro": "#BFD6E2", "arancio": "#E07B39", "blu": "#3D7CC9",
    "rosso": "#D9534F", "giallo": "#F2C14E", "verde_gioco": "#5DAE6A", "gomma": "#2E3238", "fermata": "#E9A13B",
    "idrante": "#C0392B", "vite": "#7FA866", "siepe": "#6E9E5B", "imbottitura": "#2D5DA8", "sabbia": "#E6D3A3",
    "tronco": "#7A5C40",
}
H_ISO = 4.0 / 18.0                     # m per unità iso della mappa (ISO_FLOOR = 18 per piano)


def caso(x, y, k=0):
    """Lo stesso numero fra 0 e 1 di esterni3d.caso(): un oggetto non cambia a ogni esportazione."""
    return (zlib.crc32(f"{x:.1f},{y:.1f},{k}".encode()) % 10007) / 10007


# ------------------------------------------------------------------ primitive (frame Z-su)

def scatola(dx, dy, dz, x=0.0, y=0.0, z=0.0):
    """Una scatola centrata in (x, y), dal piano z in su."""
    m = trimesh.creation.box([dx, dy, dz])
    m.apply_translation([x, y, z + dz / 2])
    return m


def asta(p0, p1, r0, r1=None, sez=6):
    """Un cilindro (rastremato da r0 a r1) fra due punti 3D."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    v = p1 - p0
    h = float(np.linalg.norm(v))
    m = trimesh.creation.cylinder(radius=1.0, height=h, sections=sez)
    vs = m.vertices.copy()
    t = (vs[:, 2] + h / 2) / h
    rr = r0 * (1 - t) + (r0 if r1 is None else r1) * t
    vs[:, :2] *= rr[:, None]
    vs[:, 2] += h / 2
    m.vertices = vs
    m.apply_transform(trimesh.geometry.align_vectors([0, 0, 1], v / h))
    m.apply_translation(p0)
    return m


def sfera(r, x, y, z, sz=1.0, sub=1, scossa=0.0, seme=0):
    m = trimesh.creation.icosphere(subdivisions=sub, radius=r)
    if scossa:
        rng = np.random.default_rng(seme)
        m.vertices *= (1 + scossa * (rng.random(len(m.vertices)) - 0.5))[:, None]
    m.apply_scale([1, 1, sz])
    m.apply_translation([x, y, z])
    return m


def ruota(m, ang, x=0.0, y=0.0, z=0.0):
    T = trimesh.transformations.rotation_matrix(ang, [0, 0, 1])
    T[:3, 3] = [x, y, z]
    m.apply_transform(T)
    return m


class Pezzi:
    """Parti per colore: un modello si costruisce una volta nel suo frame e si posa dove serve."""

    def __init__(self):
        self.p = {}

    def add(self, col, *ms):
        self.p.setdefault(col, []).extend(m for m in ms if m is not None)
        return self

    def compatta(self):
        self.p = {c: [trimesh.util.concatenate(ms)] for c, ms in self.p.items() if ms}
        return self

    def posa(self, modello, x, y, ang=0.0, z=0.0):
        T = trimesh.transformations.rotation_matrix(ang, [0, 0, 1])
        T[:3, 3] = [x, y, z]
        for c, ms in modello.p.items():
            for m in ms:
                mm = m.copy()
                mm.apply_transform(T)
                self.add(c, mm)

    def emetti(self, E, sc, gruppo, nome):
        for c, ms in sorted(self.p.items()):
            if not ms:
                continue
            m = trimesh.util.concatenate(ms)
            m.apply_transform(E.YUP)
            m.invert() if m.volume < 0 else None
            sc.mesh(f"{nome}_{c}", gruppo, E.colour(m, COL.get(c, c)))


def faccia_verso(fx, fy):
    """L'angolo che porta il davanti di un modello (+y locale) sulla direzione (fx, fy)."""
    return math.atan2(-fx, fy)


def bussola(gradi):
    """La direzione di OSM (0 = nord, 90 = est) nel frame: nord è -y."""
    b = math.radians(gradi)
    return math.sin(b), -math.cos(b)


# ------------------------------------------------------------------ alberi

def albero(x, y, chioma, alto, tipo):
    """Al posto di esterni3d.albero(): (tipo, parti della chioma, parti del tronco), Z-su.
    Le dimensioni vengono da OSM dove ci sono, se no da un albero di città di 9-12 m."""
    k = caso(x, y)
    seme = zlib.crc32(f"{x:.1f},{y:.1f}".encode())
    if tipo == "conifera":
        h = alto or 10 + 4 * k
        r = chioma or h * 0.22
        palchi = []
        for i in range(5):                                   # cinque palchi che si stringono
            f = i / 5
            c = trimesh.creation.cone(radius=r * (1 - 0.72 * f) * (0.92 + 0.16 * caso(x, y, 20 + i)),
                                      height=h * 0.3, sections=9)
            ruota(c, caso(x, y, 30 + i) * 6.28, x, y, h * (0.2 + 0.56 * f))
            palchi.append(c)
        return "conifera", palchi, [asta((x, y, 0), (x, y, h * 0.55), 0.2 + 0.02 * r, 0.08)]
    if tipo == "palma":
        # la palma di Milano è la Trachycarpus: fusto sottile e diritto, foglie a ventaglio
        h = alto or 6 + 3 * k
        s = (chioma or 2.2) / 2.2
        tronco = [asta((x, y, 0), (x, y, h), 0.17, 0.14, 7),
                  asta((x, y, h - 1.0), (x, y, h - 0.1), 0.3, 0.42, 7)]   # le foglie secche sotto la chioma
        foglie = []
        for i in range(12):
            az = 2 * math.pi * (i / 12 + 0.05 * caso(x, y, 40 + i))
            su = math.radians(55 - 75 * caso(x, y, 60 + i))     # alcune in su, le vecchie piegate in giù
            settore = Polygon([(0.45 * s, 0)] + [(0.45 * s + 1.25 * s * math.cos(a), 1.25 * s * math.sin(a))
                                                  for a in np.radians(np.linspace(-50, 50, 7))])
            f = trimesh.creation.extrude_polygon(settore, 0.03)
            f.apply_transform(trimesh.transformations.rotation_matrix(-su, [0, 1, 0]))
            ruota(f, az, x, y, h)
            foglie.append(f)
            foglie.append(asta((x, y, h), (x + 0.5 * s * math.cos(az) * math.cos(su),
                                           y + 0.5 * s * math.sin(az) * math.cos(su),
                                           h + 0.5 * s * math.sin(su)), 0.03, 0.02, 4))
        return "palma", foglie, tronco
    r = chioma or 2.8 + 1.2 * k
    h = alto or max(8.0, r * 2.6 + 2 * caso(x, y, 1))
    a0 = 2 * math.pi * caso(x, y, 2)
    snello = h > 2.9 * r + 2 or caso(x, y, 7) < 0.25          # tigli e carpini: chioma ovale
    if snello:
        base = max(2.2, h - 2.4 * r)
        lobi = [(0, 0, base + 0.75 * r, 0.82 * r), (0, 0, base + 1.55 * r, 0.7 * r),
                (0.35 * r * math.cos(a0), 0.35 * r * math.sin(a0), base + 1.15 * r, 0.6 * r)]
    else:                                                     # platani, bagolari: a globo, più larga
        base = max(2.5, h - 1.9 * r)
        lobi = [(0, 0, base + 0.95 * r, 0.8 * r)]
        for i in range(2):
            a = a0 + i * math.pi + 0.6 * caso(x, y, 3 + i)
            lobi.append((0.5 * r * math.cos(a), 0.5 * r * math.sin(a), base + (0.62 + 0.2 * caso(x, y, 6 + i)) * r,
                         (0.56 + 0.12 * caso(x, y, 9 + i)) * r))
        lobi.append((0.2 * r * math.cos(a0 + 1), 0.2 * r * math.sin(a0 + 1), base + 1.45 * r, 0.52 * r))
    # il lobo grande liscio (80 triangoli), i piccoli più grezzi (20): sono quasi 2000 alberi
    chiome = [sfera(rr, x + dx, y + dy, z, 0.88, 1 if rr > 0.69 * r else 0, 0.22 if rr > 0.69 * r else 0.12, seme + i)
              for i, (dx, dy, z, rr) in enumerate(lobi)]
    lx, ly = 0.25 * (caso(x, y, 12) - 0.5), 0.25 * (caso(x, y, 13) - 0.5)   # un tronco mai del tutto dritto
    rt = 0.1 + 0.035 * r
    forca = (x + lx, y + ly, base * 0.92)
    tronco = [asta((x, y, 0), forca, rt * 1.25, rt * 0.75, 6)]
    for dx, dy, z, rr in lobi[1:]:                                        # i rami principali
        tronco.append(asta(forca, (x + dx * 0.8, y + dy * 0.8, z - rr * 0.2), rt * 0.55, 0.04, 4))
    return f"latifoglia{int(caso(x, y, 9) * 3)}", chiome, tronco


# ------------------------------------------------------------------ modelli dell'arredo

def panchina(v):
    """Una panchina nel suo frame: seduta lungo x, davanti verso +y."""
    lung = max(1.2, 0.6 * v.get("posti", 3))
    mat = v.get("materiale", "wood")
    p = Pezzi()
    if not v.get("schienale", True) and mat in ("stone", "concrete"):
        col = "pietra" if mat == "stone" else "cemento"     # il blocco pieno, con lo zoccolo rientrato
        lung = max(lung, 2.0)
        p.add(col, scatola(lung, 0.5, 0.36, z=0.09), scatola(lung - 0.2, 0.36, 0.09))
        return p.compatta()
    seduta, telaio = ("metallo", "metallo") if "metal" in mat and "wood" not in mat else (
        ("pietra", "pietra") if mat in ("stone", "concrete") else ("legno", "ghisa"))
    for i in range(4):                                       # le doghe della seduta
        p.add(seduta, scatola(lung, 0.09, 0.035, y=0.2 - i * 0.115, z=0.42))
    for xs in (-lung / 2 + 0.15, lung / 2 - 0.15):           # i fianchi in ghisa
        p.add(telaio, asta((xs, 0.2, 0), (xs, 0.17, 0.42), 0.035, 0.03, 4),
              asta((xs, -0.17, 0), (xs, -0.17, 0.42), 0.035, 0.03, 4),
              scatola(0.05, 0.42, 0.04, xs, 0.02, 0.38))
        if v.get("schienale", True):
            p.add(telaio, asta((xs, -0.17, 0.42), (xs, -0.3, 0.86), 0.03, 0.025, 4))
        if v.get("braccioli"):
            p.add(telaio, scatola(0.06, 0.45, 0.04, xs, -0.02, 0.64), asta((xs, 0.18, 0.42), (xs, 0.18, 0.64), 0.025, 0.025, 4))
    if v.get("schienale", True):
        for i in range(3):                                   # lo schienale, inclinato all'indietro
            d = scatola(lung, 0.03, 0.09)
            d.apply_transform(trimesh.transformations.rotation_matrix(math.radians(-17), [1, 0, 0]))
            d.apply_translation([0, -0.2 - 0.035 * i, 0.52 + 0.12 * i])
            p.add(seduta, d)
    return p.compatta()


def lampione(tipo, braccio=True):
    """Davanti (+y) verso la strada. stradale: palo a pastorale da 8 m che sporge sulla
    carreggiata; dritto: palo da 7 m con la lampada in cima; lanterna: ghisa, 4,5 m."""
    p = Pezzi()
    if tipo == "lanterna":
        p.add("ghisa", asta((0, 0, 0), (0, 0, 0.9), 0.16, 0.11, 8), asta((0, 0, 0.9), (0, 0, 4.0), 0.07, 0.05, 8),
              asta((0, 0, 4.0), (0, 0, 4.12), 0.12, 0.12, 8),
              trimesh.creation.cone(radius=0.3, height=0.3, sections=8).apply_translation([0, 0, 4.72]))
        p.add("luce", asta((0, 0, 4.12), (0, 0, 4.72), 0.16, 0.24, 8))
        return p.compatta()
    if tipo == "dritto" or not braccio:
        p.add("palo", asta((0, 0, 0), (0, 0, 7.0), 0.1, 0.055, 8),
              asta((0, 0, 6.9), (0, 0.6, 6.95), 0.035, 0.035, 5))
        p.add("palo", scatola(0.32, 0.6, 0.1, 0, 0.75, 6.92))
        p.add("luce", scatola(0.26, 0.5, 0.02, 0, 0.75, 6.9))
        return p.compatta()
    pts = [(0, 0, 7.0)] + [(0, 1.6 * (1 - math.cos(a)), 7.0 + 0.7 * math.sin(a)) for a in np.linspace(0.3, math.pi / 2, 4)]
    p.add("palo", asta((0, 0, 0), (0, 0, 7.0), 0.11, 0.06, 8), asta((0, 0, 0), (0, 0, 1.0), 0.14, 0.13, 8))
    for a, b in zip(pts, pts[1:]):                               # il pastorale, curvo verso la strada
        p.add("palo", asta(a, b, 0.05, 0.045, 6))
    p.add("palo", scatola(0.34, 0.75, 0.12, 0, 1.6 + 0.3, 7.6))
    p.add("luce", scatola(0.28, 0.62, 0.02, 0, 1.6 + 0.3, 7.58))
    return p.compatta()


def cestino():
    p = Pezzi()
    p.add("palo", asta((0, -0.24, 0), (0, -0.24, 1.0), 0.04, 0.04, 6))
    p.add("ghisa", asta((0, 0, 0.35), (0, 0, 0.95), 0.2, 0.22, 10), asta((0, 0, 0.95), (0, 0, 1.0), 0.24, 0.24, 10))
    return p.compatta()


def archetto():
    """La rastrelliera ad archetto di Milano: una U rovesciata, due bici per archetto."""
    p = Pezzi()
    p.add("metallo", asta((0, -0.35, 0), (0, -0.35, 0.72), 0.03, 0.03, 4), asta((0, 0.35, 0), (0, 0.35, 0.72), 0.03, 0.03, 4),
          asta((0, -0.35, 0.72), (0, -0.2, 0.82), 0.03, 0.03, 4), asta((0, 0.35, 0.72), (0, 0.2, 0.82), 0.03, 0.03, 4),
          asta((0, -0.2, 0.82), (0, 0.2, 0.82), 0.03, 0.03, 4))
    return p.compatta()


def dissuasore():
    p = Pezzi()
    p.add("ghisa", asta((0, 0, 0), (0, 0, 0.85), 0.1, 0.08, 6), sfera(0.09, 0, 0, 0.86, 1.0, 0))
    return p.compatta()


def vedovella():
    """La fontanella di Milano in ghisa verde, con il becco di drago verso +y."""
    p = Pezzi()
    p.add("pietra", scatola(0.55, 0.75, 0.12, 0, 0.12))
    p.add("ghisa", scatola(0.4, 0.28, 0.08, 0, 0.32, 0.12))                          # la griglia di scarico
    p.add("vedovella", asta((0, 0, 0), (0, 0, 0.25), 0.22, 0.2, 10), asta((0, 0, 0.25), (0, 0, 1.25), 0.15, 0.13, 10),
          asta((0, 0, 1.25), (0, 0, 1.38), 0.2, 0.2, 10), sfera(0.17, 0, 0, 1.4, 0.7, 1),
          asta((0, 0.1, 0.85), (0, 0.32, 0.8), 0.04, 0.03, 6))
    return p.compatta()


def pensilina(con_panchina=True):
    """La pensilina di una fermata: schiena di vetro, tetto a sbalzo, davanti (+y) la strada."""
    p = Pezzi()
    for x in (-1.9, 1.9):
        p.add("metallo", scatola(0.1, 0.1, 2.55, x, -0.6))
    p.add("vetro", scatola(3.7, 0.03, 2.0, 0, -0.6, 0.25), scatola(0.03, 1.1, 2.0, 1.9, -0.05, 0.25))
    p.add("metallo", scatola(4.2, 1.7, 0.1, 0, 0.05, 2.55))
    p.add("fermata", scatola(0.08, 0.6, 1.0, -2.2, 0.3, 2.0), asta((-2.2, 0.3, 0), (-2.2, 0.3, 2.0), 0.04, 0.04, 6))
    if con_panchina:
        p.add("metallo", scatola(2.2, 0.35, 0.05, 0, -0.38, 0.45), scatola(0.05, 0.3, 0.45, -1.0, -0.38),
              scatola(0.05, 0.3, 0.45, 1.0, -0.38))
    return p.compatta()


def palina():
    p = Pezzi()
    p.add("palo", asta((0, 0, 0), (0, 0, 2.8), 0.04, 0.04, 6))
    p.add("fermata", scatola(0.5, 0.06, 0.7, 0, 0, 2.15))
    return p.compatta()


def idrante():
    p = Pezzi()
    p.add("idrante", asta((0, 0, 0), (0, 0, 0.7), 0.1, 0.09, 8), sfera(0.1, 0, 0, 0.7, 0.8, 1),
          asta((-0.18, 0, 0.45), (0.18, 0, 0.45), 0.04, 0.04, 6))
    return p.compatta()


# ------------------------------------------------------------------ sport e giochi

def rettangolo(poly):
    """Il rettangolo orientato di un campo: centro, asse lungo (versore), asse corto, L, W."""
    r = poly.minimum_rotated_rectangle
    c = list(r.exterior.coords)[:4]
    e = [np.subtract(c[(i + 1) % 4], c[i]) for i in range(2)]
    lung, larg = (e[0], e[1]) if np.linalg.norm(e[0]) >= np.linalg.norm(e[1]) else (e[1], e[0])
    L, W = float(np.linalg.norm(lung)), float(np.linalg.norm(larg))
    return np.array(r.centroid.coords[0]), lung / L, larg / W, L, W


def porta(larga, alta, profonda):
    """Una porta da calcio, la luce verso +y, i montanti a y = 0."""
    p = Pezzi()
    for x in (-larga / 2, larga / 2):
        p.add("bianco", asta((x, 0, 0), (x, 0, alta), 0.06, 0.06, 6), asta((x, 0, alta), (x, -profonda * 0.4, alta), 0.03, 0.03, 5),
              asta((x, -profonda * 0.4, alta), (x, -profonda, 0), 0.03, 0.03, 5))
    p.add("bianco", asta((-larga / 2 - 0.06, 0, alta), (larga / 2 + 0.06, 0, alta), 0.06, 0.06, 6),
          asta((-larga / 2, -profonda, 0.03), (larga / 2, -profonda, 0.03), 0.03, 0.03, 5))
    p.add("rete", scatola(larga, 0.01, alta * 0.9, 0, -profonda * 0.75, 0.05))
    return p.compatta()


def canestro():
    """Il canestro: palo dietro la linea di fondo, il tabellone e il ferro verso +y."""
    p = Pezzi()
    p.add("palo", asta((0, -1.8, 0), (0, -1.8, 3.3), 0.09, 0.07, 8), asta((0, -1.8, 3.25), (0, 0.0, 3.25), 0.05, 0.05, 6),
          asta((0, -1.8, 2.5), (0, -0.1, 3.2), 0.035, 0.035, 5))
    p.add("bianco", scatola(1.8, 0.04, 1.05, 0, 0.0, 2.9))
    p.add("arancio", trimesh.creation.torus(0.23, 0.012, major_sections=16, minor_sections=4).apply_translation([0, 0.38, 3.05]))
    return p.compatta()


def rete_tennis(larga, alta=0.914):
    p = Pezzi()
    for x in (-larga / 2, larga / 2):
        p.add("palo", asta((x, 0, 0), (x, 0, 1.07), 0.04, 0.04, 6))
    p.add("rete", scatola(larga, 0.015, alta - 0.06, 0, 0, 0.03))
    p.add("bianco", scatola(larga, 0.03, 0.06, 0, 0, alta - 0.06))
    return p.compatta()


def pali_rugby():
    p = Pezzi()
    for x in (-2.8, 2.8):
        p.add("bianco", asta((x, 0, 0), (x, 0, 11), 0.07, 0.06, 8))
        p.add("imbottitura", asta((x, 0, 0), (x, 0, 2), 0.25, 0.25, 8))
    p.add("bianco", asta((-2.8, 0, 3), (2.8, 0, 3), 0.06, 0.06, 6))
    return p.compatta()


def calistenica(L):
    """La struttura della calistenica lungo x: sbarre a tre altezze, scala orizzontale,
    parallele, la panca."""
    p = Pezzi()
    x = -L / 2 + 1
    for h in (1.3, 1.8, 2.3):                                 # tre sbarre per le trazioni
        p.add("ghisa", asta((x, -0.6, 0), (x, -0.6, h), 0.05, 0.05, 6), asta((x + 1.2, -0.6, 0), (x + 1.2, -0.6, h), 0.05, 0.05, 6))
        p.add("metallo", asta((x, -0.6, h), (x + 1.2, -0.6, h), 0.025, 0.025, 6))
        x += 1.2
    lung = min(4.0, max(2.0, L / 2 - x - 0.5))                # la scala orizzontale (monkey bar)
    for y in (-0.9, -0.3):
        for xx in (x + 0.5, x + 0.5 + lung):
            p.add("ghisa", asta((xx, y, 0), (xx, y, 2.3), 0.05, 0.05, 6))
        p.add("metallo", asta((x + 0.5, y, 2.3), (x + 0.5 + lung, y, 2.3), 0.03, 0.03, 6))
    for k in range(int(lung / 0.4) + 1):
        xx = x + 0.5 + k * 0.4
        p.add("metallo", asta((xx, -0.9, 2.3), (xx, -0.3, 2.3), 0.02, 0.02, 5))
    for y in (0.6, 1.1):                                      # le parallele
        p.add("metallo", asta((-L / 2 + 1, y, 1.1), (-L / 2 + 3, y, 1.1), 0.03, 0.03, 6))
        for xx in (-L / 2 + 1, -L / 2 + 3):
            p.add("ghisa", asta((xx, y, 0), (xx, y, 1.1), 0.045, 0.045, 6))
    p.add("ghisa", scatola(1.6, 0.35, 0.5, -L / 2 + 5, 0.85))
    return p.compatta()


def altalena():
    p = Pezzi()
    for x in (-1.6, 1.6):
        p.add("rosso", asta((x, -0.9, 0), (x, 0, 2.3), 0.06, 0.06, 6), asta((x, 0.9, 0), (x, 0, 2.3), 0.06, 0.06, 6))
    p.add("rosso", asta((-1.65, 0, 2.3), (1.65, 0, 2.3), 0.06, 0.06, 6))
    for x in (-0.7, 0.7):
        for dx in (-0.2, 0.2):
            p.add("metallo", asta((x + dx, 0, 2.3), (x + dx, 0, 0.45), 0.01, 0.01, 4))
        p.add("gomma", scatola(0.45, 0.2, 0.04, x, 0, 0.43))
    return p.compatta()


def scivolo():
    p = Pezzi()
    for x in (-0.6, 0.6):
        for y in (-0.6, 0.6):
            p.add("giallo", asta((x, y, 0), (x, y, 2.5), 0.05, 0.05, 6))
    p.add("verde_gioco", scatola(1.3, 1.3, 0.08, z=1.3))
    p.add("blu", trimesh.creation.cone(radius=1.0, height=0.7, sections=4).apply_transform(
        trimesh.transformations.rotation_matrix(math.pi / 4, [0, 0, 1])).apply_translation([0, 0, 2.45]))
    s = scatola(0.55, 2.5, 0.06)                               # lo scivolo, in pendenza verso +y
    s.apply_transform(trimesh.transformations.rotation_matrix(math.radians(-29), [1, 0, 0]))
    s.apply_translation([0, 1.75, 0.65])
    p.add("rosso", s)
    for k in range(5):                                         # la scaletta dietro
        p.add("giallo", scatola(0.5, 0.06, 0.04, 0, -0.75 - 0.12 * k, 1.3 - 0.26 * (k + 1) + 0.0))
    return p.compatta()


def dondolo():
    p = Pezzi()
    p.add("giallo", asta((0, 0, 0), (0, 0, 0.45), 0.08, 0.08, 6))
    t = scatola(3.0, 0.2, 0.06)
    t.apply_transform(trimesh.transformations.rotation_matrix(math.radians(8), [0, 1, 0]))
    t.apply_translation([0, 0, 0.45])
    p.add("blu", t)
    for x in (-1.3, 1.3):
        p.add("rosso", asta((x, 0, 0.45 - x * 0.14), (x, 0, 0.75 - x * 0.14), 0.03, 0.03, 5))
    return p.compatta()


def molla(col):
    p = Pezzi()
    p.add("metallo", asta((0, 0, 0), (0, 0, 0.45), 0.08, 0.08, 6))
    p.add(col, sfera(0.32, 0, 0, 0.7, 0.8, 1), sfera(0.16, 0, 0.3, 0.95, 1.0, 1))
    return p.compatta()


def sabbiera():
    p = Pezzi()
    p.add("legno", scatola(3.0, 0.15, 0.3, 0, -1.45), scatola(3.0, 0.15, 0.3, 0, 1.45),
          scatola(0.15, 2.75, 0.3, -1.45), scatola(0.15, 2.75, 0.3, 1.45))
    p.add("sabbia", scatola(2.75, 2.75, 0.22))
    return p.compatta()


GIOCHI = [("scivolo", scivolo, 3.6), ("altalena", altalena, 3.4), ("dondolo", dondolo, 2.2),
          ("molla_r", lambda: molla("rosso"), 1.0), ("sabbiera", sabbiera, 2.2), ("molla_g", lambda: molla("verde_gioco"), 1.0)]


def righe_campo(tipo, c, u, v, L, W):
    """Le righe dei campi fuori dal Giuriati, nel rettangolo del campo."""
    pt = lambda s, t: tuple(c + u * s + v * t)
    seg = lambda s0, t0, s1, t1: LineString([pt(s0, t0), pt(s1, t1)])
    cerchio = lambda s, t, r: Point(pt(s, t)).buffer(r, quad_segs=12).exterior
    a, b = L / 2 - 0.3, W / 2 - 0.3
    out = [LineString([pt(-a, -b), pt(a, -b), pt(a, b), pt(-a, b), pt(-a, -b)])]
    if tipo == "tennis":
        a, b = min(a, 11.885), min(b, 5.485)
        bs = min(b, 4.115)
        out = [LineString([pt(-a, -b), pt(a, -b), pt(a, b), pt(-a, b), pt(-a, -b)]),
               seg(-a, -bs, a, -bs), seg(-a, bs, a, bs), seg(-6.4, -bs, -6.4, bs), seg(6.4, -bs, 6.4, bs),
               seg(-6.4, 0, 6.4, 0)]
    elif tipo == "padel":
        out += [seg(-6.95, -b, -6.95, b), seg(6.95, -b, 6.95, b), seg(-6.95, 0, 6.95, 0)]
    elif tipo == "basketball":
        out += [seg(0, -b, 0, b), cerchio(0, 0, 1.8)]
        for s in (-1, 1):
            k = s * (a - 5.8)
            out += [LineString([pt(s * a, -2.45), pt(k, -2.45), pt(k, 2.45), pt(s * a, 2.45)]), cerchio(k, 0, 1.8)]
            arco = Point(pt(s * (a - 1.575), 0)).buffer(min(6.75, b - 0.9), quad_segs=16).exterior.intersection(
                Polygon([pt(s * a, -b), pt(0, -b), pt(0, b), pt(s * a, b)]))
            out.append(arco)
    elif tipo == "soccer":
        out += [seg(0, -b, 0, b), cerchio(0, 0, min(9.15, W * 0.13))]
        pa, pl = min(16.5, L * 0.16), min(40.3, W * 0.6)
        for s in (-1, 1):
            out.append(LineString([pt(s * a, -pl / 2), pt(s * (a - pa), -pl / 2), pt(s * (a - pa), pl / 2), pt(s * a, pl / 2)]))
    elif tipo == "volleyball":
        out += [seg(0, -b, 0, b), seg(-3, -b, -3, b), seg(3, -b, 3, b)]
    return out


def sport(E, sc, gruppo, nome, tipo, pianta, righe=True):
    """L'attrezzatura di un campo (e, con righe, le sue linee), sotto `gruppo`."""
    g = pianta if hasattr(pianta, "area") else Polygon([tuple(p) for p in pianta]).buffer(0)
    if g.is_empty or g.area < 20:
        return
    c, u, v, L, W = rettangolo(g)
    if tipo == "padel" and W > 15:                     # più campi affiancati in una sola area di OSM
        n = round(W / 11)
        for i in range(n):
            t0, t1 = -W / 2 + i * W / n, -W / 2 + (i + 1) * W / n
            q = Polygon([tuple(c + u * s_ + v * t) for s_, t in ((-L / 2, t0), (L / 2, t0), (L / 2, t1), (-L / 2, t1))])
            sport(E, sc, gruppo, f"{nome}_{i + 1}", tipo, q.buffer(-0.3, join_style=2), righe)
        return
    ang = math.atan2(u[1], u[0])                       # l'asse lungo del campo è la x del modello
    p = Pezzi()
    at = lambda s, t: c + u * s + v * t
    if tipo in ("soccer", "calcio"):
        larga, alta = (7.32, 2.44) if L > 90 else (5.0, 2.0) if L > 40 else (3.0, 2.0)
        for s in (-1, 1):
            x, y = at(s * (L / 2 - 0.3), 0)
            p.posa(porta(larga, alta, 1.5 if L > 40 else 1.0), x, y, ang + (-math.pi / 2 if s < 0 else math.pi / 2))
    elif tipo == "basketball":
        for s in (-1, 1):
            x, y = at(s * (L / 2 - 0.3 - 1.2), 0)
            p.posa(canestro(), x, y, ang + (-math.pi / 2 if s < 0 else math.pi / 2))
    elif tipo in ("tennis", "volleyball", "padel"):
        x, y = at(0, 0)
        p.posa(rete_tennis(W + (0.9 if tipo == "tennis" else 0), 0.88 if tipo == "padel" else 2.43 if tipo == "volleyball" else 0.914),
               x, y, ang + math.pi / 2)                  # la rete di traverso al campo
        if tipo == "padel":                              # vetro sul fondo e sui primi 2 m dei lati, poi rete
            vetri, reti = [], []
            for s in (-1, 1):
                vetri.append(LineString([at(s * L / 2 - s * 2, -W / 2), at(s * L / 2, -W / 2), at(s * L / 2, W / 2),
                                         at(s * L / 2 - s * 2, W / 2)]))
                reti.append(LineString([at(s * L / 2, -W / 2), at(s * L / 2, W / 2)]))
            reti += [LineString([at(-L / 2 + 2, -W / 2), at(L / 2 - 2, -W / 2)]),
                     LineString([at(-L / 2 + 2, W / 2), at(L / 2 - 2, W / 2)])]
            vg = unary_union([l.buffer(0.03, cap_style=2) for l in vetri])
            sc.mesh(f"{nome}_Vetri", gruppo, E.slab(vg, 0.0, 3.0, COL["vetro"]))
            lati = unary_union([l.buffer(0.015, cap_style=2) for l in reti[2:]])
            sopra = unary_union([l.buffer(0.015, cap_style=2) for l in reti[:2]])     # la rete sopra il vetro del fondo
            sc.mesh(f"{nome}_Reti", gruppo, unisci(E, [E_slab(lati, 0.0, 3.0), E_slab(sopra, 3.0, 4.0)], "rete"))
            pali = [scatola(0.08, 0.08, 4.0 if abs(s) > L / 2 - 0.1 else 3.0, *at(s, t))
                    for s in np.linspace(-L / 2, L / 2, 6) for t in (-W / 2, W / 2)]
            p.add("rete", *pali)
    elif tipo == "rugby_union":
        meta = L / 2 - min(10, L * 0.08)
        for s in (-1, 1):
            x, y = at(s * meta, 0)
            p.posa(pali_rugby(), x, y, ang + math.pi / 2)
    elif tipo == "gymnastics":
        x, y = at(0, 0)
        p.posa(calistenica(min(L, 16)), x, y, ang)
    elif tipo in ("playground", "gioco") and g.area < 60:
        # un gioco solo (i giochi del Giuriati sono disegnati uno per uno): il più grande che ci sta
        adatti = [(nm, fn, r) for nm, fn, r in GIOCHI if r <= max(L, 2.0) / 2 + 0.5] or [GIOCHI[3]]
        nm, fn, r = adatti[int(caso(*c, 3) * len(adatti))]
        p.posa(fn(), c[0], c[1], ang)
    elif tipo in ("playground", "gioco"):
        posti = []
        dentro = g.buffer(-1.8)
        for k, (nm, fn, r) in enumerate(GIOCHI):
            if dentro.is_empty or len(posti) >= max(1, int(g.area // 70)):
                break
            # il primo punto libero di una griglia di 1 m, a partire dal centro del parco giochi
            cand = sorted(((x, y) for x in np.arange(g.bounds[0], g.bounds[2], 1.0)
                           for y in np.arange(g.bounds[1], g.bounds[3], 1.0)),
                          key=lambda q: math.dist(q, tuple(c)) + 0.3 * caso(q[0], q[1], k))
            for q in cand:
                if dentro.buffer(-r + 1.8).contains(Point(q)) and all(math.dist(q, w) > r + rw + 0.8 for w, rw in posti):
                    p.posa(fn(), q[0], q[1], ang + (math.pi / 2) * (k % 2))
                    posti.append((q, r))
                    break
    if righe and tipo not in ("playground", "gioco", "gymnastics", "track"):
        lin = [l for l in righe_campo(tipo, c, u, v, L, W) if not l.is_empty]
        if lin:
            sc.mesh(f"{nome}_Righe", gruppo, E.slab(unary_union([l.buffer(0.05, cap_style=2) for l in lin]).intersection(g),
                                                     0.07, 0.08, COL["bianco"]))
    p.emetti(E, sc, gruppo, nome)


def E_slab(g, z0, z1):
    """Una lastra Z-su non ancora girata (per unirla ad altre prima di colorarla)."""
    parti = []
    for q in getattr(g, "geoms", [g]):
        if q.geom_type == "Polygon" and q.area > 0.001:
            m = trimesh.creation.extrude_polygon(q, z1 - z0, engine="earcut")
            m.apply_translation([0, 0, z0])
            parti.append(m)
    return trimesh.util.concatenate(parti) if parti else None


def unisci(E, parti, chiave):
    parti = [m for m in parti if m is not None]
    if not parti:
        return None
    m = trimesh.util.concatenate(parti)
    m.apply_transform(E.YUP)
    m.invert() if m.volume < 0 else None
    return E.colour(m, COL[chiave])


def recinto(linee, alto=1.2, passo=2.5):
    """Una recinzione a pannelli di rete: pali ogni 2,5 m, corrimano, rete sottile."""
    p = Pezzi()
    for l in linee:
        n = max(1, int(l.length // passo))
        for k in range(n + 1):
            q = l.interpolate(k / n, normalized=True)
            p.add("ghisa", asta((q.x, q.y, 0), (q.x, q.y, alto + 0.05), 0.035, 0.035, 5))
        p.add("rete", E_slab(l.buffer(0.012, cap_style=2), 0.05, alto))
        p.add("ghisa", E_slab(l.buffer(0.025, cap_style=2), alto, alto + 0.04))
    return p


# ------------------------------------------------------------------ pergole

def pergola(x, y, w, d, z):
    """Una pergola sopra una fioriera rialzata: quattro montanti in acciaio, due travi lungo
    il lato lungo, i listelli di traverso, il rampicante che la copre in parte."""
    p = Pezzi()
    lungo_x = w >= d
    for a in (x + 0.25, x + w - 0.25):
        for b in (y + 0.25, y + d - 0.25):
            p.add("ghisa", scatola(0.12, 0.12, 2.6, a, b, z))
    if lungo_x:
        for b in (y + 0.25, y + d - 0.25):
            p.add("ghisa", scatola(w, 0.1, 0.18, x + w / 2, b, z + 2.6))
        for k in range(int(w / 0.5) + 1):
            p.add("ghisa", scatola(0.05, d + 0.3, 0.12, x + 0.1 + k * (w - 0.2) / int(w / 0.5), y + d / 2, z + 2.78))
    else:
        for a in (x + 0.25, x + w - 0.25):
            p.add("ghisa", scatola(0.1, d, 0.18, a, y + d / 2, z + 2.6))
        for k in range(int(d / 0.5) + 1):
            p.add("ghisa", scatola(w + 0.3, 0.05, 0.12, x + w / 2, y + 0.1 + k * (d - 0.2) / int(d / 0.5), z + 2.78))
    # la fioriera rialzata sotto, con la terra e gli arbusti
    p.add("cemento", scatola(w - 0.9, d - 0.9, 0.45, x + w / 2, y + d / 2, z))
    p.add("terra", scatola(w - 1.1, d - 1.1, 0.03, x + w / 2, y + d / 2, z + 0.45))
    for i in range(5):
        cx, cy = x + 0.8 + (w - 1.6) * caso(x, y, 70 + i), y + 0.8 + (d - 1.6) * caso(x, y, 80 + i)
        p.add("siepe", sfera(0.45, cx, cy, z + 0.7, 0.8, 1, 0.2, i))
    # il rampicante: lobi schiacciati sopra i listelli, su metà della copertura, giù da un montante
    for i in range(6):
        cx, cy = x + 0.5 + (w - 1) * caso(x, y, 90 + i), y + 0.5 + (d - 1) * caso(x, y, 100 + i)
        p.add("vite", sfera(0.9, cx, cy, z + 2.95, 0.35, 1, 0.3, 10 + i))
    p.add("vite", asta((x + 0.25, y + 0.25, z + 0.45), (x + 0.25, y + 0.25, z + 2.7), 0.16, 0.22, 6))
    return p


def _modulo(path, nome):
    spec = importlib.util.spec_from_file_location(nome, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def corti(E, mappa):
    """Le pergole e le fioriere delle corti dei file del campus (leonardo.json: la terrazza
    della Sala Lettura, MIA0114), alla quota del tetto del loro guscio."""
    p = Pezzi()
    for b in (mappa or {}).get("edifici", []):
        c = b.get("corte")
        if not c:
            continue
        z = 0.0
        g = QUI.parent / "gusci" / f"{b['csie']}.py"
        if g.exists():
            mod = _modulo(g, f"guscio_{b['csie']}")
            if hasattr(mod, "tetto"):
                z = float(mod.tetto(b, E)) + 0.08          # sopra il manto di tetto_piano()
        for x, y, w, d in c.get("pergole", []):
            for col, ms in pergola(x, y, w, d, z).p.items():
                p.add(col, *ms)
        for x, y, w, d, h in c.get("arredi", []):      # fioriere e sedute in cemento (h in unità iso)
            p.add("cemento", scatola(w, d, h * H_ISO, x + w / 2, y + d / 2, z))
            if h * H_ISO > 0.5:
                p.add("siepe", scatola(w - 0.3, d - 0.3, 0.35, x + w / 2, y + d / 2, z + h * H_ISO))
    return p


# ------------------------------------------------------------------ montaggio

def prima(Z, d):
    """Prima di Z.terreno(): gli alberi li fa albero() di qui; lampioni e panchine (con i
    dettagli di arredo.json) li disegna arreda(). I semafori restano a terreno()."""
    Z.albero = albero
    d["lampioni"], d["panchine"] = [], []


def arreda(E, Z, sc, radice, d, dett, escludi=None, ingombri=(), mappa=None):
    """Aggiunge sotto `radice` l'arredo (gruppo Arredi, già di terreno()), i cordoli e le
    formelle (Terreno), l'attrezzatura dei campi e dei giochi (Sport). d: zona.json; dett:
    arredo.json; mappa: leonardo.json, per le corti."""
    zona = box(*d["zona"])
    pieni = unary_union([Z.P(e["pianta"]) for e in d["edifici"]] + [g.buffer(0) for g in ingombri])
    escludi = escludi if escludi is not None else Polygon()
    terr = sc.gruppo("Terreno", radice)
    arr = sc.gruppo("Arredi", radice)
    spg = sc.gruppo("Sport", radice)
    libero = lambda x, y: zona.contains(Point(x, y)) and not pieni.contains(Point(x, y))

    # ---- carreggiate e marciapiedi come in terreno(): i cordoli, le formelle
    car = unary_union([Z.L(s["punti"]).buffer(s["larghezza"] / 2, quad_segs=4) for s in d["strade"]]).intersection(zona)
    marc = unary_union([Z.L(s["punti"]).buffer(s["larghezza"] / 2 + Z.MARCIAPIEDE[s["classe"]], quad_segs=4)
                        for s in d["strade"] if s["classe"] in Z.MARCIAPIEDE and not s.get("tipo")]
                       + [Z.L(p).buffer(1.25, quad_segs=2) for p in d["marciapiedi"]])
    marc = marc.intersection(zona).difference(car)
    passi = unary_union([Z.L(a).buffer(2.0) for a in d["attraversamenti"]])        # cordolo abbassato
    cordoli = marc.intersection(car.buffer(0.2, quad_segs=2)).difference(passi)
    sc.mesh("Cordoli", terr, E.slab(cordoli, 0.0, 0.165, COL["granito"]))
    formelle = []
    vie = STRtree([Z.L(s["punti"]) for s in d["strade"]])
    linee_vie = [Z.L(s["punti"]) for s in d["strade"]]
    for x, y, *_ in d["alberi"]:
        q = Point(x, y)
        if marc.contains(q) and libero(x, y):
            l = linee_vie[vie.nearest(q)]
            a, b = nearest_points(l, q)
            t = l.interpolate(l.project(a) + 0.5)
            ang = math.atan2(t.y - a.y, t.x - a.x)
            f = Polygon([(-0.65, -0.65), (0.65, -0.65), (0.65, 0.65), (-0.65, 0.65)])
            formelle.append(affinity.translate(affinity.rotate(f, ang, use_radians=True, origin=(0, 0)), x, y))
    fg = unary_union(formelle).intersection(marc) if formelle else Polygon()
    sc.mesh("Formelle", terr, E.slab(fg, 0.0, 0.156, COL["terra"]))
    sc.mesh("Formelle_Bordo", terr, E.slab(fg.buffer(0.06, join_style=2).difference(fg).intersection(marc), 0.0, 0.17, COL["metallo"]))

    # ---- verso cosa si gira un oggetto: il percorso, il marciapiede o la strada più vicini
    pedonali = [Z.L(p["punti"]) for p in d["percorsi"]] + [Z.L(p) for p in d["marciapiedi"]] + linee_vie
    albero_ped = STRtree(pedonali)

    def verso(x, y, linee=pedonali, albero_l=albero_ped, massimo=25):
        q = Point(x, y)
        i = albero_l.nearest(q)
        if i is None:
            return None, 1e9
        l = linee[i]
        a = nearest_points(l, q)[0]
        dist = q.distance(a)
        if dist > massimo:
            return None, dist
        if dist < 0.3:                                   # sopra la linea: di traverso
            t = l.interpolate(l.project(a) + 0.5)
            return (-(t.y - a.y), t.x - a.x), dist
        return (a.x - x, a.y - y), dist

    # ---- panchine
    pan = Pezzi()
    modelli = {}
    for v in dett["panchine"]:
        x, y = v["punto"]
        if not libero(x, y):
            continue
        if "dir" in v:
            f = bussola(v["dir"])
        else:
            f, _ = verso(x, y)
            f = f or (0, 1)
        chiave = (v.get("schienale", True), v.get("braccioli", False), v.get("materiale", "wood"), v.get("posti", 3))
        if chiave not in modelli:
            modelli[chiave] = panchina(v)
        pan.posa(modelli[chiave], x, y, faccia_verso(*f))
    pan.emetti(E, sc, arr, "Panchine")

    # ---- lampioni: il pastorale sulla carreggiata, le lanterne lontano dalle strade
    lam = Pezzi()
    mod = {k: lampione(k) for k in ("stradale", "dritto", "lanterna")}
    for v in dett["lampioni"]:
        x, y = v["punto"]
        if not libero(x, y) or v.get("tipo") == "wire":      # quelli appesi ai cavi sopra la strada no
            continue
        f, dist = verso(x, y, linee_vie, vie, 18)
        if f is None or v.get("tipo") == "pole" and dist > 9:
            k = "lanterna"
            f = (0, 1)
        else:
            k = "dritto" if v.get("tipo") in ("straight_mast", "pole") else "stradale"
        lam.posa(mod[k], x, y, faccia_verso(*f))
    lam.emetti(E, sc, arr, "Lampioni")

    # ---- cestini, dissuasori, fontanelle, idranti
    piccoli = Pezzi()
    for punti, modello in ((dett["cestini"], cestino()), (dett["dissuasori"], dissuasore()),
                           (dett["fontanelle"], vedovella()), (dett["idranti"], idrante())):
        for x, y in punti:
            if libero(x, y):
                f, _ = verso(x, y)
                piccoli.posa(modello, x, y, faccia_verso(*(f or (0, 1))))
    piccoli.emetti(E, sc, arr, "Arredo")

    # ---- rastrelliere: una fila di archetti lungo il marciapiede, uno ogni due bici
    bici = Pezzi()
    arco = archetto()
    for v in dett["bici"]:
        x, y = v["punto"]
        if not libero(x, y):
            continue
        if v.get("linea"):
            (ax, ay), (bx, by) = v["linea"]
            u = np.array([bx - ax, by - ay]) / (math.dist((ax, ay), (bx, by)) or 1)
        else:
            f, _ = verso(x, y)
            f = np.array(f or (0, 1), float)
            u = np.array([-f[1], f[0]]) / (np.linalg.norm(f) or 1)
        n = max(1, min(12, v.get("posti", 8) // 2))
        ang = math.atan2(u[1], u[0])                     # l'archetto è di traverso alla fila
        for k in range(n):
            s = (k - (n - 1) / 2) * 0.9
            bici.posa(arco, x + u[0] * s, y + u[1] * s, ang)
        if v.get("coperta"):
            lung = n * 0.9 + 0.6
            tetto = scatola(lung, 2.2, 0.08, z=2.3)
            for s in (-lung / 2 + 0.2, lung / 2 - 0.2):
                bici.add("metallo", ruota(scatola(0.08, 0.08, 2.3, s, -0.9), ang, x, y))
            bici.add("vetro", ruota(tetto, ang, x, y))
    bici.emetti(E, sc, arr, "Rastrelliere")

    # ---- fermate: pensiline e paline, davanti la strada
    ferm = Pezzi()
    pens, pal = pensilina(), palina()
    for v in dett["fermate"]:
        x, y = v["punto"]
        if not libero(x, y):
            continue
        f, _ = verso(x, y, linee_vie, vie, 30)
        ferm.posa(pens if v.get("pensilina") else pal, x, y, faccia_verso(*(f or (0, 1))))
    ferm.emetti(E, sc, arr, "Fermate")

    # ---- sport e giochi fuori dal Giuriati (lì li mette giuriati/esterni3d.py)
    conta = {}
    for s in d["sport"]:
        g = Z.P(s["pianta"], s.get("buchi", ())).intersection(zona)
        if g.is_empty or escludi.contains(g.centroid):
            continue
        conta[s["tipo"]] = conta.get(s["tipo"], 0) + 1
        sport(E, sc, spg, f"Sport_{s['tipo']}_{conta[s['tipo']]}", s["tipo"], g)

    # ---- le aree cani: recinzione a rete alta 1,2 m
    cani = [Z.P(v["pianta"], v.get("buchi", ())) for v in d["verde"] if v["tipo"] == "cani"]
    linee = []
    for g in cani:
        for q in getattr(g, "geoms", [g]):
            if q.geom_type == "Polygon":
                linee.append(q.exterior.difference(car).intersection(zona))
    linee = [l for g in linee for l in getattr(g, "geoms", [g]) if l.geom_type == "LineString" and l.length > 1]
    recinto(linee).emetti(E, sc, arr, "Recinto_cani")

    # ---- le pergole delle corti
    corti(E, mappa).emetti(E, sc, arr, "Pergole")
    return sc


def main():
    """Per provarlo da solo: il suolo di esterni3d.py con l'arredo, in zona.glb o zona.usdz."""
    import argparse, sys, tempfile
    a = argparse.ArgumentParser()
    a.add_argument("uscita", type=pathlib.Path)
    a.add_argument("--glb", action="store_true")
    a.add_argument("--riquadro", type=float, nargs=4, help="solo questo riquadro x0 y0 x1 y1, per provare in fretta")
    a = a.parse_args()
    sys.path.insert(0, str(QUI.parent))
    sys.argv = [sys.argv[0], ".", tempfile.mkdtemp()]
    import esporta3d as E
    Z = _modulo(QUI / "esterni3d.py", "esterni_zona")
    d = json.loads((QUI / "zona.json").read_text())
    dett = json.loads((QUI / "arredo.json").read_text())
    mappa = json.loads((QUI.parent.parent.parent / "design" / "mappa" / "leonardo.json").read_text())
    if a.riquadro:
        d["zona"] = a.riquadro
    gj = QUI.parent / "giuriati" / "giuriati.json"
    escludi = box(*json.loads(gj.read_text())["isolato"]) if gj.exists() else None
    sc = E.Scena("Zona")
    prima(Z, d)
    Z.terreno(E, sc, "Zona", d, escludi)
    arreda(E, Z, sc, "Zona", d, dett, escludi, (), mappa)
    a.uscita.mkdir(parents=True, exist_ok=True)
    if a.glb:
        sc.s.export(a.uscita / "zona.glb")
    else:
        E.usdz(sc, a.uscita / "zona.usdz")
    print(len(sc.s.geometry), "mesh,", sum(len(g.faces) for g in sc.s.geometry.values()), "triangoli")


if __name__ == "__main__":
    main()
