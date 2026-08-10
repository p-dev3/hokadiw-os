#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/dist/runtime/apt-repo"
DST="$ROOT/docs/apt"

if [ ! -d "$SRC" ]; then
    echo "Missing $SRC; build the runtime first" >&2
    exit 1
fi

rm -rf "$DST"
mkdir -p "$DST"
cp -a "$SRC"/. "$DST"/

echo "Development APT repository copied to docs/apt"
echo "Commit it, then enable GitHub Pages from main:/docs"
