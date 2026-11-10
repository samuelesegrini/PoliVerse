#!/bin/sh
# Builds every LaTeX document under docs/ into docs/out/<name>/main.pdf.
# Needs latexmk (MacTeX: eval "$(/usr/libexec/path_helper)").
set -e
cd "$(dirname "$0")/../docs"
python3 plan/plan.py > /dev/null
status=0
for doc in rasd dd plan; do
  [ -f "$doc/main.tex" ] || continue
  (cd "$doc" && latexmk -interaction=nonstopmode -halt-on-error main.tex) || status=1
done
exit $status
