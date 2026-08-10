#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.env
source "$ROOT/config.env"

WORK="${HOKADIW_WORK:-$ROOT/.work}"
APP_DIR="$WORK/termux-app"
RUNTIME="$ROOT/dist/runtime"
OUT="$ROOT/dist/app"
BOOTSTRAP="$RUNTIME/bootstrap-${HOKADIW_ARCH}.zip"

if [ ! -f "$BOOTSTRAP" ]; then
    echo "Missing $BOOTSTRAP; run scripts/build-runtime.sh first" >&2
    exit 1
fi

rm -rf "$APP_DIR" "$OUT"
mkdir -p "$WORK" "$OUT"

git init -q "$APP_DIR"
git -C "$APP_DIR" remote add origin https://github.com/termux/termux-app.git
git -C "$APP_DIR" fetch --depth=1 origin "$TERMUX_APP_REF"
git -C "$APP_DIR" checkout -q --detach FETCH_HEAD

python3 "$ROOT/scripts/patch-app.py" "$APP_DIR" \
    --package "$HOKADIW_PACKAGE" \
    --app-name "$HOKADIW_APP_NAME" \
    --owner "$HOKADIW_GITHUB_OWNER" \
    --repo "$HOKADIW_GITHUB_REPO"

mkdir -p "$APP_DIR/app/src/main/cpp"
cp "$BOOTSTRAP" "$APP_DIR/app/src/main/cpp/bootstrap-aarch64.zip"

(
    cd "$APP_DIR"
    export TERMUX_PACKAGE_VARIANT="apt-android-7"
    export TERMUX_SPLIT_APKS_FOR_DEBUG_BUILDS="0"
    export TERMUX_APP_VERSION_NAME="$HOKADIW_VERSION"
    export TERMUX_APK_VERSION_TAG="hokadiw-v${HOKADIW_VERSION}-arm64-debug"
    ./gradlew --no-daemon assembleDebug
)

mapfile -t apks < <(
    find "$APP_DIR/app/build/outputs/apk/debug" -type f -name '*.apk' -print | sort
)
if [ "${#apks[@]}" -ne 1 ]; then
    printf 'Expected exactly one APK, found %d:\n' "${#apks[@]}" >&2
    printf '%s\n' "${apks[@]:-}" >&2
    exit 1
fi

cp "${apks[0]}" "$OUT/HOKADIW-Terminal-v${HOKADIW_VERSION}-arm64-debug.apk"
cp "$APP_DIR/HOKADIW_APP_IDENTITY.txt" "$OUT/"
(
    cd "$OUT"
    sha256sum ./*.apk > SHA256SUMS
)

echo "APK build complete:"
ls -lh "$OUT"
