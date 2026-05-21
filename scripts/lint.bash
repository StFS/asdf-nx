#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

files=()
for f in bin/*; do [[ -f $f ]] && files+=("$f"); done
for f in lib/*.bash scripts/*.bash; do [[ -f $f ]] && files+=("$f"); done

echo "==> shellcheck"
shellcheck -x "${files[@]}"

echo "==> shfmt -d"
shfmt -d -i 4 -ci -sr "${files[@]}"

echo "lint OK"
