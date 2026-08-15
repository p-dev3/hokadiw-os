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
CUSTOM_BOOTSTRAP="$ROOT/dist/runtime/bootstrap-${HOKADIW_ARCH}.zip"
LOCAL_BOOTSTRAP="$APP_DIR/app/src/main/cpp/bootstrap-aarch64.zip"
SELECTED_BOOTSTRAP_SOURCE=""
SELECTED_BOOTSTRAP_SHA256=""

if [ "${#UPSTREAM_PACKAGE}" -ne "${#APK_PACKAGE}" ]; then
    echo "HOKADIW Android package must be ${#UPSTREAM_PACKAGE} characters for safe compatibility rewriting: $APK_PACKAGE" >&2
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

mkdir -p "$(dirname -- "$LOCAL_BOOTSTRAP")"

# Correct standalone builds must use a bootstrap produced by build-runtime.sh.
# That bootstrap contains packages compiled natively for io.hokadiw and an APT
# source pointing to the HOKADIW package repository. The upstream bootstrap is
# retained only as a compatibility fallback for com.termux builds.
if [ -f "$CUSTOM_BOOTSTRAP" ]; then
    cp "$CUSTOM_BOOTSTRAP" "$LOCAL_BOOTSTRAP"
    SELECTED_BOOTSTRAP_SOURCE="dist/runtime/bootstrap-${HOKADIW_ARCH}.zip"
    SELECTED_BOOTSTRAP_SHA256="$(sha256sum "$CUSTOM_BOOTSTRAP" | awk '{print $1}')"
    echo "Using HOKADIW runtime bootstrap: $CUSTOM_BOOTSTRAP"
elif [ "$APK_PACKAGE" = "$UPSTREAM_PACKAGE" ]; then
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
    cp "$UPSTREAM_BOOTSTRAP" "$LOCAL_BOOTSTRAP"
    SELECTED_BOOTSTRAP_SOURCE="$BOOTSTRAP_URL"
    SELECTED_BOOTSTRAP_SHA256="$BOOTSTRAP_SHA256"
    echo "Using upstream bootstrap for com.termux compatibility build"
else
    echo "ERROR: standalone $APK_PACKAGE build requires $CUSTOM_BOOTSTRAP" >&2
    echo "Run scripts/build-runtime.sh before scripts/build-apk-fast.sh" >&2
    exit 1
fi

# Scan decompressed bootstrap members. A standalone build must not contain the
# old Termux data prefix anywhere, while it must contain the HOKADIW prefix.
python3 - "$LOCAL_BOOTSTRAP" "$UPSTREAM_PACKAGE" "$APK_PACKAGE" <<'PY'
from pathlib import Path
from zipfile import ZipFile
import sys

archive = Path(sys.argv[1])
old_package = sys.argv[2]
new_package = sys.argv[3]
old_prefix = f"/data/data/{old_package}".encode()
new_prefix = f"/data/data/{new_package}".encode()
old_count = 0
new_count = 0
old_members = []
with ZipFile(archive, "r") as zf:
    for info in zf.infolist():
        data = zf.read(info.filename)
        count_old = data.count(old_prefix)
        count_new = data.count(new_prefix)
        if count_old:
            old_members.append(info.filename)
            old_count += count_old
        new_count += count_new

if old_package != new_package and old_count:
    raise SystemExit(
        f"Bootstrap still contains {old_count} occurrence(s) of {old_prefix.decode()} "
        f"in: {old_members[:10]}"
    )
if new_count == 0:
    raise SystemExit(f"Bootstrap contains no {new_prefix.decode()} references")
print(f"Bootstrap prefix verification passed: {new_count} HOKADIW reference(s), 0 stale Termux reference(s)")
PY

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
printf 'BOOTSTRAP_SOURCE=%s\nBOOTSTRAP_SHA256=%s\nAPT_URL=%s\n' \
    "$SELECTED_BOOTSTRAP_SOURCE" "$SELECTED_BOOTSTRAP_SHA256" "$HOKADIW_APT_URL" \
    >> "$OUT/HOKADIW_APP_IDENTITY.txt"
(
    cd "$OUT"
    sha256sum ./*.apk > SHA256SUMS
)

echo "Fast APK build complete:"
ls -lh "$OUT"
