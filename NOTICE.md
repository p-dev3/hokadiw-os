# Upstream and security notes

HOKADIW Terminal v0.1.1 is derived from the Termux upstream projects, including `termux-app`,
`termux-packages`, and the packages fetched and compiled by that build system.

Upstream Termux requires forks that change the Android package name to update application/runtime
constants and rebuild the bootstrap and native packages for the new hard-coded prefix. This build
overlay performs those steps for `com.hokadiw.terminal` while retaining the upstream Java namespace.

## Licensing

The files authored specifically for this build overlay are licensed under MIT unless a file states
otherwise. Termux and every bundled package retain their own upstream licenses. Distribution of an
APK, bootstrap, or package repository must include required attribution and corresponding source
offers for copyleft components.

## Development repository trust

The v0.1.1 development APT source uses `trusted=yes`, which disables APT repository-signature
verification. It is limited to proving the independent build pipeline.

Before public release:

- create and protect a persistent HOKADIW APT signing key;
- publish the public key/keyring;
- generate and sign `Release` and `InRelease` metadata;
- remove `trusted=yes`; and
- retain published sources for distributed GPL components.

## APK signing

GitHub Actions currently builds a debug APK. Do not present it as a production release. A public
release must use a securely retained HOKADIW release keystore and a documented key-rotation and
recovery procedure.
