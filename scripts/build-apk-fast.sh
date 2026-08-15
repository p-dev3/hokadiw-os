#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.env
source "$ROOT/config.env"

WORK="${HOKADIW_WORK:-$ROOT/.work}"
APP_DIR="$WORK/termux-app"
OUT="$ROOT/dist/app"
UPSTREAM_PACKAGE="com.termux"
APK_PACKAGE="${HOKADIW_APK_PACKAGE:-$HOKADIW_PACKAGE}"
BOOTSTRAP_VERSION="2026.02.12-r1%2Bapt.android-7"
BOOTSTRAP_SHA256="ea2aeba8819e517db711f8c32369e89e7c52cee73e07930ff91185e1ab93f4f3"
BOOTSTRAP_URL="https://github.com/termux/termux-packages/releases/download/bootstrap-${BOOTSTRAP_VERSION}/bootstrap-aarch64.zip"
UPSTREAM_BOOTSTRAP="$WORK/bootstrap-aarch64-upstream.zip"
LOCAL_BOOTSTRAP="$APP_DIR/app/src/main/cpp/bootstrap-aarch64.zip"

if [ "${#UPSTREAM_PACKAGE}" -ne "${#APK_PACKAGE}" ]; then
    echo "HOKADIW Android package must be ${#UPSTREAM_PACKAGE} characters for safe bootstrap prefix rewriting: $APK_PACKAGE" >&2
    exit 1
fi

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
    "https://github.com/termux/termux-app.git" \
    "$TERMUX_APP_REF" \
    "$APP_DIR"

if [ ! -f "$UPSTREAM_BOOTSTRAP" ] ||
    ! printf '%s  %s\n' "$BOOTSTRAP_SHA256" "$UPSTREAM_BOOTSTRAP" | sha256sum -c - >/dev/null 2>&1; then
    rm -f "$UPSTREAM_BOOTSTRAP.tmp"
    curl --fail --location \
        --retry 5 --retry-delay 2 --retry-all-errors \
        --output "$UPSTREAM_BOOTSTRAP.tmp" \
        "$BOOTSTRAP_URL"
    printf '%s  %s\n' "$BOOTSTRAP_SHA256" "$UPSTREAM_BOOTSTRAP.tmp" | sha256sum -c -
    mv "$UPSTREAM_BOOTSTRAP.tmp" "$UPSTREAM_BOOTSTRAP"
fi

mkdir -p "$(dirname -- "$LOCAL_BOOTSTRAP")"
if [ "$APK_PACKAGE" = "$UPSTREAM_PACKAGE" ]; then
    cp "$UPSTREAM_BOOTSTRAP" "$LOCAL_BOOTSTRAP"
    echo "Using the upstream bootstrap prefix for full package compatibility"
else
    python3 - "$UPSTREAM_BOOTSTRAP" "$LOCAL_BOOTSTRAP" "$UPSTREAM_PACKAGE" "$APK_PACKAGE" <<'PY'
from __future__ import annotations

import copy
import sys
from pathlib import Path
from zipfile import ZipFile

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
old_package = sys.argv[3]
new_package = sys.argv[4]

old_prefix = f"/data/data/{old_package}".encode()
new_prefix = f"/data/data/{new_package}".encode()
if len(old_prefix) != len(new_prefix):
    raise SystemExit("Bootstrap prefixes must have identical byte lengths")

replacement_count = 0
with ZipFile(source, "r") as input_zip, ZipFile(destination, "w", allowZip64=True) as output_zip:
    for original_info in input_zip.infolist():
        data = input_zip.read(original_info.filename)
        count = data.count(old_prefix)
        if count:
            data = data.replace(old_prefix, new_prefix)
            replacement_count += count

        output_info = copy.copy(original_info)
        output_zip.writestr(output_info, data)

if replacement_count == 0:
    destination.unlink(missing_ok=True)
    raise SystemExit(f"No {old_prefix.decode()} paths found in bootstrap")

with ZipFile(destination, "r") as result_zip:
    for info in result_zip.infolist():
        if old_prefix in result_zip.read(info.filename):
            raise SystemExit(f"Unpatched prefix remains in {info.filename}")

print(f"Rewrote {replacement_count} bootstrap prefix occurrence(s)")
print(f"  {old_prefix.decode()} -> {new_prefix.decode()}")
PY
fi

python3 "$ROOT/scripts/patch-app.py" "$APP_DIR" \
    --package "$APK_PACKAGE" \
    --app-name "$HOKADIW_APP_NAME" \
    --owner "$HOKADIW_GITHUB_OWNER" \
    --repo "$HOKADIW_GITHUB_REPO"

(
    cd "$APP_DIR"
    export GRADLE_USER_HOME="$WORK/gradle-home"
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

mkdir -p "$OUT"
cp "${apks[0]}" "$OUT/HOKADIW-Terminal-v${HOKADIW_VERSION}-arm64-debug.apk"
cp "$APP_DIR/HOKADIW_APP_IDENTITY.txt" "$OUT/"
printf 'BOOTSTRAP_SOURCE=%s\nBOOTSTRAP_SHA256=%s\n' \
    "$BOOTSTRAP_URL" "$BOOTSTRAP_SHA256" >> "$OUT/HOKADIW_APP_IDENTITY.txt"
(
    cd "$OUT"
    sha256sum ./*.apk > SHA256SUMS
)

echo "Fast APK build complete:"
ls -lh "$OUT"
