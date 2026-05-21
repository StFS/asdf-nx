#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

files=()
for f in bin/*; do [[ -f $f ]] && files+=("$f"); done
for f in lib/*.bash scripts/*.bash; do [[ -f $f ]] && files+=("$f"); done

shfmt -w -i 4 -ci -sr "${files[@]}"
echo "formatted ${#files[@]} files"
