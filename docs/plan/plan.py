#!/usr/bin/env python3
"""Computes the plan from data/*.csv and writes the LaTeX under generated/.

Standard library only. Run from anywhere: python3 docs/plan/plan.py
"""
import csv
import math
from datetime import date, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA, OUT = HERE / "data", HERE / "generated"
OUT.mkdir(exist_ok=True)

# Planning assumptions, stated in the document.
START = date(2026, 11, 16)
HOURS_PER_DAY = 2          # 10 hours a week on five working days
SLOC_PER_FP = 53           # backfiring factor, see the Estimate section
COCOMO_A, COCOMO_B = 2.94, 0.91
SCALE_FACTORS = 18.97      # nominal sum of the five scale factors
HOURS_PER_PM = 152


def read(name):
    with open(DATA / name, newline="") as f:
        return list(csv.DictReader(f))


def tex(s):
    return s.replace("&", r"\&").replace("%", r"\%").replace("_", r"\_")


def write(name, text):
    (OUT / name).write_text(text)


# --- Estimate -----------------------------------------------------------------
fp = read("fp.csv")
ufp = sum(int(r["weight"]) for r in fp)
rows = "\n".join(
    f"{tex(r['item'])} & {r['type']} & {r['det']} & {r['ret_or_ftr']} & {r['complexity']} & {r['weight']} \\\\"
    for r in fp)
write("fp-table.tex", rf"""\begin{{longtable}}{{@{{}}p{{0.45\linewidth}} l r r l r@{{}}}}
\toprule Function & Type & DET & RET/FTR & Complexity & FP \\ \midrule
{rows}
\midrule \multicolumn{{5}}{{@{{}}l}}{{Unadjusted function points}} & {ufp} \\
\bottomrule
\end{{longtable}}
""")
ksloc = ufp * SLOC_PER_FP / 1000
exponent = COCOMO_B + 0.01 * SCALE_FACTORS
pm = COCOMO_A * ksloc ** exponent
write("estimate.tex", rf"""\begin{{center}}
\begin{{tabular}}{{@{{}}l r@{{}}}}
\toprule
Unadjusted function points & {ufp} \\
Size at {SLOC_PER_FP} lines per function point & {ksloc:.2f} KSLOC \\
COCOMO II exponent ($B + 0.01 \sum SF$, nominal) & {exponent:.4f} \\
Effort ($A \cdot \mathrm{{KSLOC}}^E$, $A = {COCOMO_A}$, multipliers nominal) & {pm:.1f} person-months \\
Effort at {HOURS_PER_PM} hours per person-month & {pm * HOURS_PER_PM:.0f} hours \\
\bottomrule
\end{{tabular}}
\end{{center}}
""")

# --- WBS and schedule -----------------------------------------------------------
wbs = read("wbs.csv")
leaves = [r for r in wbs if r["estimate_h"]]
by_id = {r["id"]: r for r in wbs}
for r in leaves:
    r["h"] = float(r["estimate_h"])
    r["left"] = r["h"] * (1 - float(r["percent_complete"] or 0) / 100)
    r["deps"] = r["depends_on"].split()
bac = sum(r["h"] for r in leaves)

# Critical path method on estimates, as if tasks could run in parallel.
es, ef = {}, {}
order = []
pending = list(leaves)
while pending:
    for r in pending:
        if all(d in ef for d in r["deps"]):
            es[r["id"]] = max((ef[d] for d in r["deps"]), default=0.0)
            ef[r["id"]] = es[r["id"]] + r["h"]
            order.append(r)
            pending.remove(r)
            break
    else:
        raise SystemExit("cycle in depends_on")
length = max(ef.values())
ls, lf = {}, {}
for r in reversed(order):
    succ = [s for s in leaves if r["id"] in s["deps"]]
    lf[r["id"]] = min((ls[s["id"]] for s in succ), default=length)
    ls[r["id"]] = lf[r["id"]] - r["h"]
float_h = {r["id"]: ls[r["id"]] - es[r["id"]] for r in leaves}
critical = [r for r in order if abs(float_h[r["id"]]) < 1e-9]

# One developer: tasks run one after another, in the order of the file,
# which follows the milestones and respects every dependency.
def add_working_days(d, n):
    while n > 0:
        d += timedelta(days=1)
        if d.weekday() < 5:
            n -= 1
    return d

serial = leaves
seen = set()
for r in serial:
    assert all(d in seen for d in r["deps"]), f"{r['id']} is listed before a task it depends on"
    seen.add(r["id"])
done = 0.0  # hours of work since START
for r in serial:
    if r["left"] <= 0:
        r["start"] = r["end"] = ""
        continue
    first = math.floor(done / HOURS_PER_DAY)
    done += r["left"]
    last = max(first, math.ceil(done / HOURS_PER_DAY) - 1)
    r["start"] = add_working_days(START, first).isoformat()
    r["end"] = add_working_days(START, last).isoformat()
planned_end = max(r["end"] for r in leaves if r["end"])

with open(DATA / "wbs.csv", "w", newline="") as f:
    fields = ["id", "name", "parent", "estimate_h", "depends_on", "start", "end",
              "percent_complete", "milestone"]
    w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore", lineterminator="\n")
    w.writeheader()
    w.writerows(wbs)

rows = []
for r in wbs:
    if not r["estimate_h"]:
        total = sum(c["h"] for c in leaves if c["parent"] == r["id"])
        rows.append(rf"\midrule \textbf{{{r['id']}}} & \textbf{{{tex(r['name'])}}} & \textbf{{{total:g}}} & & & \\")
    else:
        crit = "yes" if r in critical else ""
        rows.append(f"{r['id']} & {tex(r['name'])} & {r['h']:g} & {tex(r['depends_on'])} & {float_h[r['id']]:g} & {crit} \\\\")
write("wbs-table.tex", rf"""\begin{{longtable}}{{@{{}}l p{{0.42\linewidth}} r p{{0.16\linewidth}} r l@{{}}}}
\toprule Id & Task & Hours & Depends on & Float & Critical \\
\endhead
{chr(10).join(rows)}
\midrule & \textbf{{Budget at completion}} & \textbf{{{bac:g}}} & & & \\
\bottomrule
\end{{longtable}}
""")

lines = []
for r in wbs:
    if not r["estimate_h"]:
        kids = [c for c in leaves if c["parent"] == r["id"] and c["start"]]
        if not kids:
            continue
        lines.append(rf"\ganttgroup{{{r['id']} {tex(r['name'])}}}{{{min(c['start'] for c in kids)}}}{{{max(c['end'] for c in kids)}}} \\")
    elif r["start"]:
        style = "[bar/.append style={fill=gray!85}]" if r in critical else ""
        lines.append(rf"\ganttbar{style}{{{r['id']}}}{{{r['start']}}}{{{r['end']}}} \\")
        if r["milestone"] == "yes":
            lines.append(rf"\ganttmilestone{{{by_id[r['parent']]['id']} done}}{{{r['end']}}} \\")
lines[-1] = lines[-1].rstrip("\\ ").rstrip()
chart_end = (date.fromisoformat(planned_end).replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(days=1)
write("gantt.tex", rf"""\begin{{ganttchart}}[
  time slot format=isodate, x unit=0.047cm, y unit chart=0.36cm, y unit title=0.45cm,
  title label font=\scriptsize, bar label font=\scriptsize, group label font=\scriptsize\bfseries,
  milestone label font=\scriptsize\itshape, bar height=0.6, group height=0.25,
  milestone height=0.6, vgrid={{*6{{draw=none}}, dotted}}, hgrid=false
  ]{{{START.replace(day=1).isoformat()}}}{{{chart_end.isoformat()}}}
\gantttitlecalendar{{year, month=shortname}} \\
{chr(10).join(lines)}
\end{{ganttchart}}
""")

ms = [r for r in leaves if r["milestone"] == "yes"]
rows = "\n".join(
    f"{by_id[r['parent']]['id']} {tex(by_id[r['parent']]['name'])} & {r['end']} & {tex(r['name'])} \\\\" for r in ms)
write("milestones.tex", rf"""\begin{{center}}\small
\begin{{tabularx}}{{\linewidth}}{{@{{}}l l X@{{}}}}
\toprule Milestone & Planned date & Closed by \\ \midrule
{rows}
\bottomrule
\end{{tabularx}}
\end{{center}}
""")
write("schedule-facts.tex",
      rf"\newcommand\planbac{{{bac:g}}}" "\n"
      rf"\newcommand\planleft{{{sum(r['left'] for r in leaves):g}}}" "\n"
      rf"\newcommand\plancritical{{{', '.join(r['id'] for r in critical)}}}" "\n"
      rf"\newcommand\plancriticalhours{{{length:g}}}" "\n"
      rf"\newcommand\planend{{{date.fromisoformat(planned_end).strftime('%-d %B %Y')}}}" "\n"
      rf"\newcommand\planstart{{{START.strftime('%-d %B %Y')}}}" "\n")

# --- Risks ----------------------------------------------------------------------
risks = sorted(read("risks.csv"), key=lambda r: -int(r["likelihood"]) * int(r["impact"]))
rows = "\n".join(
    f"{r['id']} & {tex(r['description'])} & {r['category']} & {r['likelihood']} & {r['impact']} & "
    f"{int(r['likelihood']) * int(r['impact'])} & {tex(r['mitigation'])} \\\\"
    for r in risks if r["status"] == "open")
write("risk-register.tex", rf"""{{\small
\begin{{longtable}}{{@{{}}l p{{0.27\linewidth}} l r r r p{{0.33\linewidth}}@{{}}}}
\toprule Id & Risk & Category & L & I & L$\times$I & Mitigation \\ \midrule
\endhead
{rows}
\bottomrule
\end{{longtable}}}}
""")
cells = {}
for r in risks:
    cells.setdefault((int(r["likelihood"]), int(r["impact"])), []).append(r["id"])
draw = []
for l in range(1, 6):
    for i in range(1, 6):
        shade = min(60, 4 * l * i)
        draw.append(rf"\fill[gray!{shade}] ({i - 1},{l - 1}) rectangle ({i},{l});")
        if (l, i) in cells:
            draw.append(rf"\node[font=\scriptsize] at ({i - 0.5},{l - 0.5}) {{{' '.join(cells[(l, i)])}}};")
write("risk-plot.tex", rf"""\begin{{tikzpicture}}[x=1.7cm, y=0.9cm]
{chr(10).join(draw)}
\draw (0,0) grid (5,5);
\foreach \n in {{1,...,5}} {{
  \node[font=\scriptsize] at (\n-0.5,-0.3) {{\n}};
  \node[font=\scriptsize] at (-0.2,\n-0.5) {{\n}};
}}
\node[font=\small] at (2.5,-0.8) {{Impact}};
\node[font=\small, rotate=90] at (-0.6,2.5) {{Likelihood}};
\end{{tikzpicture}}
""")

print(f"UFP {ufp}, COCOMO {pm:.1f} PM = {pm * HOURS_PER_PM:.0f} h")
print(f"BAC {bac:g} h, left {sum(r['left'] for r in leaves):g} h")
print("critical path:", " ".join(r["id"] for r in critical), f"({length:g} h)")
print("planned end:", planned_end)
