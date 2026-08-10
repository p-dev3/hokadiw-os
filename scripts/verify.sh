#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
for relative in ("scripts/patch-packages.py", "scripts/patch-app.py"):
    path = root / relative
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY

while IFS= read -r script; do
    bash -n "$script"
done < <(
    find "$ROOT/scripts" "$ROOT/packages/hokadiw-tools" -type f \
        \( -name '*.sh' -o -name 'build.sh' -o -name '*.in' \) -print
)
bash -n "$ROOT/PUSH_TO_GITHUB.sh"

required_files=(
    README.md
    config.env
    packages/hokadiw-tools/build.sh
    packages/hokadiw-tools/hkd.in
    scripts/patch-packages.py
    scripts/patch-app.py
    scripts/build-runtime.sh
    scripts/build-app.sh
    scripts/make-flat-repo.sh
    .github/workflows/build-distribution.yml
)
for relative in "${required_files[@]}"; do
    if [ ! -f "$ROOT/$relative" ]; then
        echo "Missing required file: $relative" >&2
        exit 1
    fi
done

old_targets=(
    'p-dev3/hokadiw''-toolkit'
    'p-dev3/hokadiw-os''-toolkit'
)
for old_target in "${old_targets[@]}"; do
    if grep -RqsF "$old_target" \
        "$ROOT/README.md" "$ROOT/config.env" "$ROOT/PUSH_TO_GITHUB.sh" \
        "$ROOT/packages" "$ROOT/scripts"; then
        echo "Old repository target is still present: $old_target" >&2
        exit 1
    fi
done

grep -q '^  push:$' "$ROOT/.github/workflows/build-distribution.yml"
grep -q '^  workflow_dispatch:$' "$ROOT/.github/workflows/build-distribution.yml"
grep -q 'com.hokadiw.terminal' "$ROOT/config.env"
grep -q -- '--add hokadiw-tools' "$ROOT/scripts/build-runtime.sh"

echo "Static checks passed."
