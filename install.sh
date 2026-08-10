#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/payload/hkd"

if [ -z "${PREFIX:-}" ]; then
  echo "PREFIX is not set. Run this installer inside Termux." >&2
  exit 1
fi

if [ ! -f "$SOURCE" ]; then
  echo "Missing $SOURCE" >&2
  exit 1
fi

install -m 0755 "$SOURCE" "$PREFIX/bin/hkd"

MANAGED_HOME="$HOME/.local/share/hokadiw-os-toolkit"
if [ -d "$SCRIPT_DIR/.git" ]; then
  mkdir -p "$(dirname "$MANAGED_HOME")"
  if [ "$SCRIPT_DIR" != "$MANAGED_HOME" ]; then
    rm -rf "$MANAGED_HOME"
    git clone --local "$SCRIPT_DIR" "$MANAGED_HOME" >/dev/null 2>&1 || true
  fi
fi

printf '\nHOKADIW dashboard installed.\nRun: hkd\n'
