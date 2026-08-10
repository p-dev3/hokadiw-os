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

bash "$ROOT/scripts/make-flat-repo.sh" "$OUT/debs" "$OUT/apt-repo"

cp "$PACKAGES_DIR/HOKADIW_BUILD_IDENTITY.txt" "$OUT/"

printf '\nRuntime build complete:\n'
find "$OUT" -maxdepth 2 -type f -print | sort
