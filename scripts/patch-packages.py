#!/usr/bin/env python3
"""Patch a pinned termux-packages checkout for the HOKADIW runtime identity."""

from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"Expected exactly one match in {path} but found {count}: {old!r}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--package", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--apt-url", required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    properties = root / "scripts/properties.sh"
    apt_build = root / "packages/apt/build.sh"
    bootstrap_build = root / "scripts/build-bootstraps.sh"
    termux_am_build = root / "packages/termux-am/build.sh"

    if not all(
        path.is_file()
        for path in (properties, apt_build, bootstrap_build, termux_am_build)
    ):
        raise SystemExit(f"{root} is not a compatible termux-packages checkout")

    replace_once(
        properties,
        'TERMUX__NAME="Termux"',
        f'TERMUX__NAME="{args.name}"',
    )
    replace_once(
        properties,
        'TERMUX__REPOS_HOST_ORG_NAME="termux"',
        f'TERMUX__REPOS_HOST_ORG_NAME="{args.owner}"',
    )
    replace_once(
        properties,
        'TERMUX_APP__PACKAGE_NAME="com.termux"',
        f'TERMUX_APP__PACKAGE_NAME="{args.package}"',
    )

    old_sources = """\t{
\t\techo "# The main termux repository, with cloudflare cache"
\t\techo "deb https://packages-cf.termux.dev/apt/termux-main/ stable main"
\t\techo "# The main termux repository, without cloudflare cache"
\t\techo "# deb https://packages.termux.dev/apt/termux-main/ stable main"
\t} > $TERMUX_PREFIX/etc/apt/sources.list"""
    new_sources = f"""\t{{
\t\techo "# HOKADIW development repository"
\t\techo "deb [trusted=yes] {args.apt_url} ./"
\t}} > $TERMUX_PREFIX/etc/apt/sources.list"""
    replace_once(apt_build, old_sources, new_sources)

    # The pinned upstream build-bootstraps.sh force-clean path references an
    # undefined *_FOR_ARCH variable. With `-f`, it expands to `rm -f /*` in
    # the builder container. Use the directory that the same script defines,
    # and require both cleanup paths to be non-empty before rm is executed.
    replace_once(
        bootstrap_build,
        '''\t\t\trm -f "$TERMUX_BUILT_PACKAGES_DIRECTORY_FOR_ARCH"/*
\t\t\trm -f "$TERMUX_BUILT_DEBS_DIRECTORY"/*''',
        '''\t\t\trm -f -- "${TERMUX_BUILT_PACKAGES_DIRECTORY:?}"/*
\t\t\trm -f -- "${TERMUX_BUILT_DEBS_DIRECTORY:?}"/*''',
    )

    # Upstream passes a function-local variable after extract_debs returns,
    # leaving TERMUX_PACKAGE_ARCH empty in the bootstrap second-stage script.
    replace_once(
        bootstrap_build,
        'add_termux_bootstrap_second_stage_files "$package_arch"',
        'add_termux_bootstrap_second_stage_files "$TERMUX_ARCH"',
    )

    # termux-am v0.8.0 uses AGP 7.4.2, which requires Android Platform 33
    # and Build Tools 30.0.3. The current package-builder image only ships
    # newer components, and its shared ANDROID_HOME is not writable by the
    # builder user, so Gradle cannot install the missing versions itself.
    # Install the exact required components in the package's writable temp
    # directory and point Gradle at that isolated SDK root.
    replace_once(
        termux_am_build,
        '''\texport ANDROID_HOME
\texport GRADLE_OPTS="-Dorg.gradle.daemon=false -Xmx1536m -Dorg.gradle.java.home=/usr/lib/jvm/java-1.17.0-openjdk-amd64"''',
        '''\tlocal sdk_manager
\tif [ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
\t\tsdk_manager="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
\telif [ -x "$ANDROID_HOME/cmdline-tools/bin/sdkmanager" ]; then
\t\tsdk_manager="$ANDROID_HOME/cmdline-tools/bin/sdkmanager"
\telse
\t\techo "No usable sdkmanager found in $ANDROID_HOME" >&2
\t\treturn 1
\tfi

\tlocal writable_android_home="$TERMUX_PKG_TMPDIR/android-sdk"
\tmkdir -p "$writable_android_home/licenses"
\tif [ -d "$ANDROID_HOME/licenses" ]; then
\t\tcp -R "$ANDROID_HOME/licenses/." "$writable_android_home/licenses/"
\tfi
\t# With pipefail enabled, `yes` exits with SIGPIPE (141) after sdkmanager
\t# has accepted the licenses. Preserve sdkmanager's real exit status so a
\t# successful license step is not mistaken for a package build failure.
\tyes | "$sdk_manager" --sdk_root="$writable_android_home" --licenses >/dev/null || \\
\t\t[ "${PIPESTATUS[1]}" -eq 0 ]
\tyes | "$sdk_manager" --sdk_root="$writable_android_home" \\
\t\t"platforms;android-33" \\
\t\t"build-tools;30.0.3"
\texport ANDROID_HOME="$writable_android_home"
\texport GRADLE_OPTS="-Dorg.gradle.daemon=false -Xmx1536m -Dorg.gradle.java.home=/usr/lib/jvm/java-1.17.0-openjdk-amd64"''',
    )

    marker = root / "HOKADIW_BUILD_IDENTITY.txt"
    marker.write_text(
        "\n".join(
            [
                f"NAME={args.name}",
                f"PACKAGE={args.package}",
                f"APT_URL={args.apt_url}",
                "INTERNAL_NAME=termux",
                "UPSTREAM_BOOTSTRAP_FORCE_CLEAN_PATCHED=true",
                "UPSTREAM_BOOTSTRAP_ARCH_PATCHED=true",
                "UPSTREAM_TERMUX_AM_SDK_PATCHED=true",
                "",
            ]
        ),
        encoding="utf-8",
    )

    print("Patched termux-packages for HOKADIW")
    print(f"  package: {args.package}")
    print(f"  apt URL: {args.apt_url}")
    print("  internal source name: termux")


if __name__ == "__main__":
    main()
