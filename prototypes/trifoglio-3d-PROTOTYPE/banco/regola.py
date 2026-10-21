#!/usr/bin/env python3
"""PROTOTIPO — il regolatore: il banco 3D come sistema a ciclo chiuso, sul Mac con l'iPhone attaccato.

    python3 banco/regola.py --dd <derivedData> [--test-dd <derivedData>] [--giri 3] [--passate 0]

Lo schema è quello del controllo in retroazione:

  configurazione iniziale + correzioni   le manopole di Trifoglio3DTuning (Trifoglio3DView.swift);
                                         `migliore` parte dai valori di oggi
  sistema                                l'app sull'iPhone, lanciata con -Trifoglio3DBenchTour
  disturbo                               il calore del telefono: non si aspetta che passi, si
                                         registra a ogni turno e le configurazioni confrontate si
                                         alternano nello stesso avvio, così lo subiscono uguale
  uscita osservata → stima → misura      il JSON del banco: fps, durata dei frame, frame persi per
                                         fase del volo, attesa dei piani, CPU, memoria, GPU
  riferimento                            OBIETTIVI, qui sotto, gli stessi di banco/README.md
  analisi e scatti di regolazione        costo di ogni turno, confrontato a coppie con `migliore`
  misure di regolazione (+/-)            una manopola girata alla volta; vince se il costo
                                         scende in quasi ogni giro e di più del rumore

Una passata gira ogni manopola contro la configurazione migliore e adotta chi vince; ogni
`--xctest-ogni` passate fa girare anche i test XCTest del 3D con la migliore. Continua finché
una passata intera non cambia nulla (o per `--passate` passate): allora le manopole sono
esaurite e serve codice nuovo, cioè una manopola in più. Tutto finisce in `--out`:
storia.jsonl (ogni turno), stato.json (la migliore e le decisioni), registro.md.
"""
import argparse, datetime, json, pathlib, statistics, subprocess, sys, time

UDID = "00008101-0004514A3E86001E"
BUNDLE = "segrini.samuele.PoliVerse"
FRAME_MS = 1000 / 60

# Il riferimento: dove il ciclo deve portare l'app (banco/README.md).
OBIETTIVI = {
    "volo, ms di frame persi al secondo": 5,
    "attesa dei piani, ms": 300,
    "campus fermo, fps": 59,
    "aula ferma, fps": 59,
    "edificio fermo, fps": 59,
    "GPU, MB": 160,
    "memoria, MB": 300,
}

# Le manopole e i valori da provare. Nessuna toglie dettaglio ai modelli.
MANOPOLE = {
    "graphLight": [True, False],
    "bakedEverywhere": [True, False],
    "tapShells": [True, False],
    "shadowsInFlight": [True, False],
    "shadows": [False, True],
    "dropFullOpacity": [True, False],
    "skipNoopFades": [True, False],
    "hideTreesAtOnce": [True, False],
    "distantShells": [False, True],
    "detailedOnArrival": [True, False],
    "tapShapesAfterArrival": [True, False],
    "pulseEvery": [3, 1],
    "labelWhileMoving": [False, True],
    "noMotionBlur": [True, False],
    "noDepthOfField": [True, False],
    "noCameraGrain": [True, False],
    "standardRange": [True, False],
}

# Le fasi del volo in cui la camera si muove; "attesa dei piani" è latenza, non fluidità.
ATTESA = "attesa dei piani"


def ora():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%H:%M:%S")


def persi(window):
    """Millisecondi di frame persi in una finestra: i vsync a 60 Hz che non hanno avuto un frame."""
    attesi = window["seconds"] * 60
    contati = window["fps"] * window["seconds"]
    return max(0.0, attesi - contati) * FRAME_MS


def costo(turno):
    """Il tempo brutto di un turno, in ms: frame persi in volo e nelle viste ferme. L'attesa dei piani
    si registra a parte: cambia di secondi da un giro all'altro e coprirebbe ogni manopola."""
    c = 0.0
    for fase in turno["tour"]["phases"]:
        if fase["name"] not in (ATTESA, "fermo"):
            c += max(0.0, fase["seconds"] * 60 - fase["frames"]) * FRAME_MS
    for vista in ("stillCampus", "stillRoom", "stillBuilding"):
        if turno.get(vista):
            c += persi(turno[vista])
    return c


def misure(turno):
    """Le uscite misurate di un turno, con i nomi di OBIETTIVI."""
    fasi = turno["tour"]["phases"]
    mossa = [f for f in fasi if f["name"] not in (ATTESA, "fermo")]
    sec = sum(f["seconds"] for f in mossa) or 1
    persi_volo = sum(max(0.0, f["seconds"] * 60 - f["frames"]) * FRAME_MS for f in mossa)
    w = turno["stillBuilding"] or turno["tour"]["window"]
    return {
        "volo, ms di frame persi al secondo": persi_volo / sec,
        "attesa dei piani, ms": sum(f["seconds"] for f in fasi if f["name"] == ATTESA) * 1000,
        "campus fermo, fps": turno["stillCampus"]["fps"],
        "aula ferma, fps": turno["stillRoom"]["fps"],
        "edificio fermo, fps": turno["stillBuilding"]["fps"],
        "GPU, MB": w["gpuMB"],
        "memoria, MB": w["memoryMB"],
    }


class Regolatore:
    def __init__(self, args):
        self.args = args
        self.out = pathlib.Path(args.out)
        self.out.mkdir(parents=True, exist_ok=True)
        self.stato_path = self.out / "stato.json"
        self.stato = json.loads(self.stato_path.read_text()) if self.stato_path.exists() else {
            "migliore": {}, "decisioni": [], "passate": 0}
        self.installata = None

    def scrivi(self, riga):
        print(f"[{ora()}] {riga}", flush=True)
        with open(self.out / "registro.md", "a") as f:
            f.write(f"- {ora()} {riga}\n")

    def salva(self):
        self.stato_path.write_text(json.dumps(self.stato, indent=1, ensure_ascii=False))

    def app(self):
        return pathlib.Path(self.args.dd) / "Build/Products/Debug-iphoneos/PoliVerse.app"

    def installa(self):
        """Installa l'app quando la build è cambiata: il codice nuovo entra nel ciclo da solo."""
        stamp = (self.app() / "PoliVerse.debug.dylib").stat().st_mtime if (self.app() / "PoliVerse.debug.dylib").exists() \
            else self.app().stat().st_mtime
        if stamp == self.installata:
            return
        subprocess.run(["xcrun", "devicectl", "device", "install", "app", "--device", UDID, str(self.app())],
                       check=True, capture_output=True)
        self.installata = stamp
        self.scrivi("app installata")

    def chiudi(self):
        out = subprocess.run(["xcrun", "devicectl", "device", "info", "processes", "--device", UDID],
                             capture_output=True, text=True).stdout
        for riga in out.splitlines():
            if riga.rstrip().endswith("PoliVerse.app/PoliVerse"):
                pid = riga.split()[0]
                subprocess.run(["xcrun", "devicectl", "device", "process", "terminate", "--device", UDID,
                                "--pid", pid], capture_output=True)

    def giro(self, configurazioni, nome):
        """Un avvio dell'app che alterna le configurazioni per --giri giri; il JSON del banco, o None."""
        self.installa()
        log = self.out / f"{nome}.log"
        argomenti = ["-Trifoglio3D", "-Trifoglio3DBenchTour", "-Trifoglio3DRounds", str(self.args.giri),
                     "-Trifoglio3DTuning", json.dumps(configurazioni)]
        copia = self.out / f"{nome}.copia.json"
        copia.unlink(missing_ok=True)
        avvio = datetime.datetime.now(datetime.timezone.utc)
        p = subprocess.run(["xcrun", "devicectl", "device", "process", "launch", "--device", UDID,
                            "--terminate-existing", BUNDLE, "--", *argomenti],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True)
        log.write_text(p.stdout + p.stderr)
        if p.returncode != 0:
            errori = [r.strip() for r in (p.stdout + p.stderr).splitlines() if "rror" in r][:2]
            self.scrivi(f"{nome}: nessun risultato ({'; '.join(errori) or 'lancio fallito'})")
            return None
        # Il banco scrive Documents/trifoglio3d-bench.json alla fine: lo si copia finché è quello nuovo.
        limite = time.time() + 60 + 40 * self.args.giri * len(configurazioni)
        corpo = None
        while time.time() < limite:
            time.sleep(10)
            subprocess.run(["xcrun", "devicectl", "device", "copy", "from", "--device", UDID,
                            "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE,
                            "--source", "Documents/trifoglio3d-bench.json", "--destination", str(copia)],
                           stdin=subprocess.DEVNULL, capture_output=True)
            try:
                letto = json.loads(copia.read_text())
            except (OSError, ValueError):
                continue
            data = datetime.datetime.fromisoformat(letto["date"].replace("Z", "+00:00"))
            if data >= avvio - datetime.timedelta(seconds=5) and letto.get("turns"):
                corpo = copia.read_text()
                break
        self.chiudi()
        if corpo is None:
            self.scrivi(f"{nome}: nessun risultato (il banco non ha finito in tempo)")
            return None
        report = json.loads(corpo)
        (self.out / f"{nome}.json").write_text(corpo)
        with open(self.out / "storia.jsonl", "a") as f:
            for t in report["turns"]:
                f.write(json.dumps({"giro": nome, "configurazione": report["configurations"][t["configuration"]],
                                    "round": t["round"], "calore": t["thermal"], "costo": costo(t),
                                    "misure": misure(t)}, ensure_ascii=False) + "\n")
        return report

    def confronta(self, manopola, valore):
        """Gira una manopola contro la migliore; True se la nuova vince."""
        base = dict(self.stato["migliore"])
        prova = dict(base, **{manopola: valore})
        nome = f"p{self.stato['passate']}-{manopola}-{valore}".lower()
        report = None
        for attesa in (20, 60, 120, None):
            report = self.giro([base, prova], nome)
            if report or attesa is None:
                break
            # A volte il lancio fallisce ("Invalid argument") per un po' dopo il giro prima.
            time.sleep(attesa)
        if not report:
            return False
        costi = {}
        for t in report["turns"]:
            costi.setdefault(t["round"], {})[t["configuration"]] = costo(t)
        coppie = [(c[0], c[1]) for c in costi.values() if 0 in c and 1 in c]
        vinti = sum(1 for a, b in coppie if b < a)
        ca = statistics.median(a for a, _ in coppie)
        cb = statistics.median(b for _, b in coppie)
        calore = sorted({t["thermal"] for t in report["turns"]})
        vince = vinti >= len(coppie) - (len(coppie) // 3) and cb < ca * (1 - self.args.soglia)
        self.scrivi(f"{manopola}={valore}: costo {ca:.0f} → {cb:.0f} ms, meglio in {vinti}/{len(coppie)} giri, "
                    f"calore {'/'.join(calore)} → {'ADOTTATA' if vince else 'scartata'}")
        self.stato["decisioni"].append({"passata": self.stato["passate"], "manopola": manopola, "valore": valore,
                                        "costo_prima": ca, "costo_dopo": cb, "vinti": vinti, "giri": len(coppie),
                                        "calore": calore, "adottata": vince})
        if vince:
            self.stato["migliore"] = prova
        self.salva()
        return vince

    def scostamenti(self, report):
        """Le misure della migliore contro il riferimento: quello che resta da regolare."""
        turni = [t for t in report["turns"] if t["configuration"] == 0]
        if not turni:
            return
        righe = []
        for chiave, obiettivo in OBIETTIVI.items():
            valore = statistics.median(misure(t)[chiave] for t in turni)
            ok = valore >= obiettivo if "fps" in chiave else valore <= obiettivo
            righe.append(f"{chiave} {valore:.1f} ({'ok' if ok else f'obiettivo {obiettivo}'})")
        self.scrivi("migliore contro il riferimento: " + "; ".join(righe))

    def xctest(self):
        """I test XCTest del 3D, con la configurazione migliore; i numeri restano nel .xcresult."""
        if not self.args.test_dd:
            return
        n = self.stato["passate"]
        risultato = self.out / f"xctest-p{n}.xcresult"
        env = dict(__import__("os").environ, TEST_RUNNER_TRIFOGLIO3D_BENCH="1",
                   TEST_RUNNER_TRIFOGLIO3D_TUNING=json.dumps(self.stato["migliore"]))
        self.scrivi("XCTest del 3D con la migliore…")
        p = subprocess.run(["xcodebuild", "test-without-building", "-project", "PoliVerse.xcodeproj",
                            "-scheme", "PoliVerseUI", "-destination", f"id={UDID}",
                            "-derivedDataPath", self.args.test_dd, "-resultBundlePath", str(risultato),
                            "-only-testing:PoliVerseTests/Trifoglio3DLoadTests",
                            "-only-testing:PoliVerseUITests/Trifoglio3DPerformanceTests"],
                           env=env, capture_output=True, text=True, cwd=self.args.repo)
        (self.out / f"xctest-p{n}.log").write_text(p.stdout + p.stderr)
        medie = [r.strip() for r in p.stdout.splitlines() if "measured [" in r]
        for r in medie:
            self.scrivi("XCTest " + r.split("]: ", 1)[-1][:200])
        self.scrivi(f"XCTest finiti ({'passati' if p.returncode == 0 else 'falliti, vedi il log'})")
        self.chiudi()

    def passata(self):
        """Ogni manopola girata contro la migliore; quante sono state adottate."""
        adottate = 0
        for manopola, valori in MANOPOLE.items():
            attuale = self.stato["migliore"].get(manopola, valori[-1])
            for valore in valori:
                if valore != attuale and self.confronta(manopola, valore):
                    adottate += 1
                    break
        return adottate

    def avvia(self):
        self.scrivi(f"regolatore avviato, migliore {json.dumps(self.stato['migliore'])}")
        while True:
            adottate = self.passata()
            ultimo = sorted(self.out.glob(f"p{self.stato['passate']}-*.json"))
            if ultimo:
                self.scostamenti(json.loads(ultimo[-1].read_text()))
            self.stato["passate"] += 1
            self.salva()
            if self.args.xctest_ogni and self.stato["passate"] % self.args.xctest_ogni == 0:
                self.xctest()
            if adottate == 0:
                self.scrivi(f"passata {self.stato['passate']}: nessuna manopola cambia le cose, servono "
                            f"manopole nuove. Migliore: {json.dumps(self.stato['migliore'])}")
                if self.args.fermati:
                    return
            if self.args.passate and self.stato["passate"] >= self.args.passate:
                return


if __name__ == "__main__":
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("--dd", required=True, help="derivedData della build Debug per iphoneos")
    a.add_argument("--test-dd", help="derivedData di build-for-testing dello schema PoliVerseUI")
    a.add_argument("--repo", default=str(pathlib.Path(__file__).resolve().parents[3]))
    a.add_argument("--out", default="regola")
    a.add_argument("--giri", type=int, default=3, help="giri alternati per confronto")
    a.add_argument("--soglia", type=float, default=0.05, help="guadagno minimo sul costo, oltre il rumore")
    a.add_argument("--passate", type=int, default=0, help="0: finché serve")
    a.add_argument("--xctest-ogni", type=int, default=1, help="XCTest ogni N passate, 0 mai")
    a.add_argument("--fermati", action="store_true", help="fermarsi quando una passata non cambia nulla")
    Regolatore(a.parse_args()).avvia()
