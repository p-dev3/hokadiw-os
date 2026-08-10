#!/usr/bin/env python3
"""Apply the small Phase-1 HOKADIW overlay to a termux/termux-app checkout."""

from pathlib import Path
import re
import sys

APP_NAME = "HOKADIW Terminal"


def replace_required(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"Expected text not found in {path}: {old!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_termux.py /path/to/termux-app", file=sys.stderr)
        return 2

    root = Path(sys.argv[1]).resolve()
    strings = root / "app/src/main/res/values/strings.xml"
    gradle = root / "app/build.gradle"

    if not strings.is_file() or not gradle.is_file():
        raise SystemExit(f"{root} does not look like a termux-app checkout")

    # Keep com.termux and the standard Termux PREFIX. Only change Phase-1 branding.
    replace_required(
        strings,
        '<!ENTITY TERMUX_APP_NAME "Termux">',
        f'<!ENTITY TERMUX_APP_NAME "{APP_NAME}">',
    )

    replace_required(
        gradle,
        'manifestPlaceholders.TERMUX_APP_NAME = "Termux"',
        f'manifestPlaceholders.TERMUX_APP_NAME = "{APP_NAME}"',
    )

    text = gradle.read_text(encoding="utf-8")
    old = 'outputFileName = new File("termux-app_" +'
    if old not in text:
        raise SystemExit("Could not find upstream APK output naming logic in app/build.gradle")
    text = text.replace(old, 'outputFileName = new File("hokadiw-termux_" +')
    gradle.write_text(text, encoding="utf-8")

    marker = root / "HOKADIW_PATCHED.md"
    marker.write_text(
        "# HOKADIW overlay applied\n\n"
        "Phase 1 keeps `com.termux` and the standard Termux `$PREFIX`.\n"
        f"Android display name: **{APP_NAME}**.\n",
        encoding="utf-8",
    )

    print(f"Patched Termux checkout: {root}")
    print(f"Application name: {APP_NAME}")
    print("Package name unchanged: com.termux")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
