# HOKADIW OS Toolkit — Termux Edition Phase 1

This repository is the build/control layer for **HOKADIW Termux Edition**.

It intentionally does **not** vendor the full Termux source tree. GitHub Actions clones the official
[`termux/termux-app`](https://github.com/termux/termux-app) source, applies a small reproducible patch,
builds debug APKs, and uploads them as workflow artifacts.

## Phase 1 design

- Keep Android package name `com.termux`.
- Keep the standard Termux `$PREFIX` and existing bootstrap/package ecosystem.
- Brand the Android app as **HOKADIW Terminal**.
- Rename generated debug APKs to `hokadiw-termux_*`.
- Provide the `hkd` dashboard for:
  - System information
  - ADB / Shizuku helpers
  - VPN inspection/tools
  - VPS / SSH helper
  - Toolkit update
- Keep HOKADIW modifications as an overlay so rebasing to newer Termux source is easier.

## Important installation note

Phase 1 keeps `com.termux`. Android therefore treats HOKADIW Termux and official Termux as the same
application identity. APKs signed with different certificates cannot be installed over each other.

**Back up `$HOME` and any important files before uninstalling/replacing an existing Termux build.**

The GitHub workflow below builds a **debug APK** using the build configuration provided by upstream
Termux. It is for development/testing, not a production release signing setup.

## Build APK on GitHub Actions

1. Push this repository to GitHub.
2. Open **Actions**.
3. Select **Build HOKADIW Termux**.
4. Choose **Run workflow**.
5. Optionally enter an upstream branch/tag/commit. Default: `master`.
6. Download the artifact named `hokadiw-termux-apks`.

For most current Android phones, use the `arm64-v8a` APK. A `universal` APK is also built.

## Install the `hkd` dashboard

Inside Termux, from this repository:

```sh
bash install.sh
```

Then:

```sh
hkd
```

## Repository layout

```text
.github/workflows/build-hokadiw-termux.yml
scripts/patch_termux.py
payload/hkd
install.sh
NOTICE.md
```

## Upstream projects

- https://github.com/termux/termux-app
- https://github.com/termux/termux-packages
- https://github.com/termux/termux-tools

HOKADIW Termux Edition is an independent modification/toolkit and is not an official Termux release.
