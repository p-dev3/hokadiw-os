#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.env
source "$ROOT/config.env"

WORK="${HOKADIW_WORK:-$ROOT/.work}"
PACKAGES_DIR="$WORK/termux-packages"
OUT="$ROOT/dist/runtime"

checkout_ref() {
    local url="$1"
    local ref="$2"
    local destination="$3"

    rm -rf "$destination"
    git init -q "$destination"
    git -C "$destination" remote add origin "$url"
    git -C "$destination" fetch --depth=1 origin "$ref"
    git -C "$destination" checkout -q --detach FETCH_HEAD
}

mkdir -p "$WORK"
rm -rf "$OUT"

checkout_ref \
    "https://github.com/termux/termux-packages.git" \
    "$TERMUX_PACKAGES_REF" \
    "$PACKAGES_DIR"

rm -rf "$PACKAGES_DIR/packages/hokadiw-tools"
cp -a "$ROOT/packages/hokadiw-tools" "$PACKAGES_DIR/packages/hokadiw-tools"

python3 "$ROOT/scripts/patch-packages.py" "$PACKAGES_DIR" \
    --package "$HOKADIW_PACKAGE" \
    --name "$HOKADIW_NAME" \
    --owner "$HOKADIW_GITHUB_OWNER" \
    --apt-url "$HOKADIW_APT_URL"

# Fail before the expensive Docker build if the patched bootstrap package list
# contains a binary-only subpackage name with no source build recipe. This is
# what previously allowed `bzip2` to fail only after large dependencies had
# already compiled; the source recipe is `libbz2`, which emits bzip2 as a
# subpackage.
python3 - "$PACKAGES_DIR" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
bootstrap = root / "scripts/build-bootstraps.sh"
text = bootstrap.read_text(encoding="utf-8")

packages = set(re.findall(r'PACKAGES\+=\("([A-Za-z0-9+._-]+)"\)', text))
packages.add("hokadiw-tools")
channels = ("packages", "root-packages", "x11-packages")
missing = []
for package in sorted(packages):
    if not any((root / channel / package / "build.sh").is_file() for channel in channels):
        missing.append(package)

if missing:
    raise SystemExit(
        "Bootstrap preflight found package name(s) without source build recipes: "
        + ", ".join(missing)
    )

if 'PACKAGES+=("bzip2")' in text:
    raise SystemExit(
        "Bootstrap preflight found stale binary subpackage bzip2; build libbz2 instead"
    )
if 'PACKAGES+=("libbz2")' not in text:
    raise SystemExit("Bootstrap preflight did not find patched libbz2 source package")

print(
    f"Bootstrap source-recipe preflight passed: {len(packages)} package name(s), "
    "including libbz2 and hokadiw-tools"
)
PY

(
    cd "$PACKAGES_DIR"
    ./scripts/run-docker.sh ./scripts/build-bootstraps.sh \
        --architectures "$HOKADIW_ARCH" \
        --add hokadiw-tools \
        -f
)

bootstrap="$PACKAGES_DIR/bootstrap-${HOKADIW_ARCH}.zip"
if [ ! -f "$bootstrap" ]; then
    echo "Bootstrap was not produced: $bootstrap" >&2
    exit 1
fi

mkdir -p "$OUT/debs"
cp "$bootstrap" "$OUT/"

while IFS= read -r -d '' deb; do
    cp -f "$deb" "$OUT/debs/"
done < <(find "$PACKAGES_DIR/output" -type f -name '*.deb' -print0)

# A custom Android application id requires every Debian payload path to use
# the custom data directory. Official Termux packages contain paths rooted at
# ./data/data/com.termux and Android will deny io.hokadiw access to them.
# Fail the build before publishing if even one package has the old root.
old_root="./data/data/com.termux"
new_root="./data/data/${HOKADIW_PACKAGE}"
checked=0
for deb in "$OUT"/debs/*.deb; do
    checked=$((checked + 1))
    listing="$(dpkg-deb --fsys-tarfile "$deb" | tar -tf -)"
    if grep -Fq "$old_root" <<<"$listing"; then
        echo "ERROR: package still contains Termux payload paths: $deb" >&2
        grep -F "$old_root" <<<"$listing" | head -20 >&2
        exit 1
    fi
    if ! grep -Fq "$new_root" <<<"$listing"; then
        echo "ERROR: package does not contain the HOKADIW payload root: $deb" >&2
        exit 1
    fi
done
if [ "$checked" -eq 0 ]; then
    echo "ERROR: runtime build produced no .deb packages" >&2
    exit 1
fi
echo "Verified $checked package(s): all payload paths target $new_root"

bash "$ROOT/scripts/make-flat-repo.sh" "$OUT/debs" "$OUT/apt-repo"

cp "$PACKAGES_DIR/HOKADIW_BUILD_IDENTITY.txt" "$OUT/"

printf '\nRuntime build complete:\n'
find "$OUT" -maxdepth 2 -type f -print | sort
