# Upstream / License Notice

HOKADIW Termux Edition is based on and builds from the Termux project.

Upstream source:
- https://github.com/termux/termux-app

The Termux app repository is distributed under GPL-3.0. When distributing a modified Termux binary,
you must comply with the upstream license and provide the corresponding source in the manner required
by that license.

This toolkit keeps its modifications as a reproducible patch script. A workflow build records the
upstream commit SHA used for the APK so the modified source can be reconstructed from:

1. the recorded upstream Termux commit; and
2. `scripts/patch_termux.py` from the matching HOKADIW toolkit revision.

"HOKADIW Termux Edition" is an independent modified build and is not an official Termux release.
Do not represent it as being published or supported by the Termux maintainers.
