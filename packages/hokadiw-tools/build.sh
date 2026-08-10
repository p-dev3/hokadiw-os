TERMUX_PKG_HOMEPAGE=https://github.com/p-dev3/hokadiw-os
TERMUX_PKG_DESCRIPTION="HOKADIW distribution identity and maintenance command"
TERMUX_PKG_LICENSE="MIT"
TERMUX_PKG_LICENSE_FILE="LICENSE"
TERMUX_PKG_MAINTAINER="HOKADIW"
TERMUX_PKG_VERSION="0.1.1"
TERMUX_PKG_AUTO_UPDATE=false
TERMUX_PKG_SKIP_SRC_EXTRACT=true
TERMUX_PKG_PLATFORM_INDEPENDENT=true
TERMUX_PKG_DEPENDS="bash, coreutils"

termux_step_make_install() {
	local hkd="$TERMUX_PREFIX/bin/hkd"

	mkdir -p "$TERMUX_PREFIX/bin" "$TERMUX_PREFIX/etc" \
		"$TERMUX_PREFIX/share/doc/hokadiw-tools"

	sed \
		-e "s|@TERMUX_PREFIX@|$TERMUX_PREFIX|g" \
		-e "s|@HOKADIW_APT_URL@|https://p-dev3.github.io/hokadiw-os/apt|g" \
		"$TERMUX_PKG_BUILDER_DIR/hkd.in" > "$hkd"
	chmod 700 "$hkd"

	cat > "$TERMUX_PREFIX/etc/hokadiw-release" <<- EOF
	NAME="HOKADIW Terminal"
	VERSION="0.1.1"
	ID="hokadiw"
	ANDROID_APPLICATION_ID="com.hokadiw.terminal"
	PREFIX="$TERMUX_PREFIX"
	APT_URL="https://p-dev3.github.io/hokadiw-os/apt"
	EOF

	install -Dm600 "$TERMUX_PKG_BUILDER_DIR/LICENSE" \
		"$TERMUX_PREFIX/share/doc/hokadiw-tools/LICENSE"
}
