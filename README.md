# HOKADIW Terminal Distribution v0.1.1

HOKADIW Terminal is an experimental, independent Android terminal distribution built from the
upstream Termux source code. This repository contains the reproducible build overlay—not vendored
copies of Termux—and produces an ARM64 APK, a custom bootstrap, and a development APT repository.

## Identity

- App name: `HOKADIW Terminal`
- Android application ID: `com.hokadiw.terminal`
- Data directory: `/data/data/com.hokadiw.terminal`
- Root filesystem: `/data/data/com.hokadiw.terminal/files`
- `HOME`: `/data/data/com.hokadiw.terminal/files/home`
- `PREFIX`: `/data/data/com.hokadiw.terminal/files/usr`
- Initial target: Android 7+ / `aarch64` (`arm64-v8a`)
- Built-in HOKADIW command: `hkd`

The Java namespace remains upstream `com.termux` for v0.1.1. The Android application ID, runtime
constants, manifest placeholders, shortcuts, package build identity, and bootstrap prefix are
patched consistently. Keeping the Java namespace avoids a risky whole-tree source rename.

## Build flow

The `Build HOKADIW Distribution` workflow runs on every push to `main` and can also be started
manually. It:

1. checks out this build overlay;
2. fetches pinned Termux package and app revisions;
3. patches the package build identity to `com.hokadiw.terminal`;
4. adds and builds the custom `hokadiw-tools` package;
5. builds the ARM64 bootstrap from source;
6. generates a flat development APT repository;
7. patches the Android app identity and embeds the custom bootstrap;
8. builds an ARM64 debug APK; and
9. uploads the APK, bootstrap, APT repository, checksums, and build metadata.

The resulting artifact is named `hokadiw-distribution-arm64`.

## GitHub Actions

Open:

`https://github.com/p-dev3/hokadiw-os/actions`

A push to `main` starts the build automatically. To run it manually, choose
**Build HOKADIW Distribution → Run workflow**.

Expected artifact layout:

```text
hokadiw-distribution-arm64/
├── apk/
│   ├── HOKADIW-Terminal-v0.1.1-arm64-debug.apk
│   └── SHA256SUMS
├── apt-repo/
│   ├── Packages
│   ├── Packages.gz
│   ├── SHA256SUMS
│   └── *.deb
├── bootstrap-aarch64.zip
└── BUILD_INFO.txt
```

## Development APT repository

The bootstrap is configured for:

`https://p-dev3.github.io/hokadiw-os/apt`

After a successful runtime build, the generated repository can be copied into `docs/apt/` with:

```bash
bash scripts/publish-dev-repo.sh
```

Then commit `docs/apt/` and enable GitHub Pages from `main` → `/docs`.

v0.1.1 deliberately uses `[trusted=yes]` only to prove the end-to-end build loop. Before a public
release, add a persistent HOKADIW GPG signing key, publish a keyring, generate signed
`Release`/`InRelease` metadata, and remove `trusted=yes`.

## Local build

Use an Ubuntu/Debian Linux host with Docker:

```bash
sudo apt-get update
sudo apt-get install -y docker.io dpkg-dev git gzip python3 zip unzip

bash scripts/verify.sh
bash scripts/build-runtime.sh
bash scripts/build-app.sh
```

Runtime output is written to `dist/runtime/`; APK output is written to `dist/app/`.

## Status and safety

This is an early development build. The first full GitHub Actions run is the integration test for
the complete toolchain. Public releases must use a private, durable HOKADIW APK signing key and a
signed APT repository.

HOKADIW Terminal is derived from upstream Termux projects but is not an official Termux release.
Upstream licenses and attribution must be preserved for every distributed component.
