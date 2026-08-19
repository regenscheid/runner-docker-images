#!/usr/bin/env bash
# Smoke tests for the texlive-slim image. Copies the test sources into the
# container (working tree stays clean) and exercises:
#   1. lualatex baseline (baked-in packages only)
#   2. pdflatex baseline
#   3. on-demand discovery + install + retry (needs network)
#   4. preinstall from a <jobname>.packages file (needs network)
#
# NOTE: these run as root (texlive-slim has no USER), so they do not cover
# the non-root install path. The runner-texlive CI test exercises texbuild
# as uid 1001 against the runner-owned tree.
set -euo pipefail

IMAGE="${1:-texlive-slim:local}"
HERE="$(cd "$(dirname "$0")" && pwd)"

run() {
  local name="$1"; shift
  echo "==> $name"
  docker run --rm -v "$HERE/texlive:/src:ro" "$IMAGE" \
    bash -ec "cp /src/* /workdir/ && $*"
  echo "PASS: $name"
}

run "lualatex baseline"  "texbuild basic-lualatex.tex && head -c4 basic-lualatex.pdf | grep -q %PDF"
run "math baseline"      "texbuild math-lualatex.tex && head -c4 math-lualatex.pdf | grep -q %PDF"
run "pdflatex baseline"  "texbuild --pdflatex basic-pdflatex.tex && head -c4 basic-pdflatex.pdf | grep -q %PDF"
run "on-demand install"  "texbuild ondemand.tex && head -c4 ondemand.pdf | grep -q %PDF && grep -q fontawesome5 texbuild-packages.txt"
run "preinstall list"    "texbuild preinstall.tex && head -c4 preinstall.pdf | grep -q %PDF"

echo "All smoke tests passed."
