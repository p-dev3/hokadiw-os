#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 DEB_DIR OUTPUT_REPO_DIR" >&2
    exit 2
fi

DEB_DIR="$(realpath "$1")"
OUT="$(realpath -m "$2")"

command -v dpkg-scanpackages >/dev/null 2>&1 || {
    echo "dpkg-scanpackages is missing; install the dpkg-dev package" >&2
    exit 1
}

shopt -s nullglob
debs=("$DEB_DIR"/*.deb)
if [ "${#debs[@]}" -eq 0 ]; then
    echo "No .deb files found in $DEB_DIR" >&2
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cp -f "${debs[@]}" "$OUT/"

(
    cd "$OUT"
    dpkg-scanpackages . /dev/null > Packages
    gzip -9c Packages > Packages.gz
    sha256sum Packages Packages.gz ./*.deb > SHA256SUMS
)

echo "Flat HOKADIW APT repository created at $OUT"
