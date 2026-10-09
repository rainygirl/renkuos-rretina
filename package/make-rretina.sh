#!/bin/sh
# Builds rretina-<version>-<arch>.hpkg from dist/<arch>/{app_server,libtracker.so}
# with the Linux-hosted package tool of a Haiku build tree in a container.
#
#   package/make-rretina.sh <arch> <haiku version the binaries were built for>
#   e.g. package/make-rretina.sh arm64 r1~beta6_hrev60071_15_dirty
#
# The binaries use app_server's and libtracker's private interfaces, so the
# package requires exactly that haiku version.
#
#   CONTAINER  default haiku-builder
#   GEN        default /root/renku-arm64-work/generated.arm64
#   VERSION    default 1.0.0, REVISION default 1
set -e
ARCH="${1:?arch}"
HAIKU_VERSION="${2:?haiku version}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINER="${CONTAINER:-haiku-builder}"
GEN="${GEN:-/root/renku-arm64-work/generated.arm64}"
VERSION="${VERSION:-1.0.0}"
REVISION="${REVISION:-1}"
NAME="rretina-$VERSION-$REVISION-$ARCH.hpkg"
# pkgman.rainygirl.com's arm64 repository is "RENKU Apps", and package_repo
# refuses a package from another vendor
case "$ARCH" in
arm64) VENDOR="RENKU"; PACKAGER="RENKU <renku@localhost>" ;;
*) VENDOR="rainygirl"; PACKAGER="rainygirl <rainygirl@localhost>" ;;
esac

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
# The files go where the haiku package has its own. packagefs shows, for a
# path more than one package provides, a system package's file over another
# package's, and among system packages the newest one; so rretina is a system
# package and its files are stamped now. Removing it brings the haiku
# package's files back by itself, and a later haiku package (newer files)
# would win over rretina's.
mkdir -p "$STAGE/servers" "$STAGE/lib" "$STAGE/documentation/packages/rretina"
cp "$HERE/dist/$ARCH/app_server" "$STAGE/servers/app_server"
cp "$HERE/dist/$ARCH/libtracker.so" "$STAGE/lib/libtracker.so"
cp "$HERE/README.md" "$STAGE/documentation/packages/rretina/"
cp -R "$HERE/patches" "$STAGE/documentation/packages/rretina/"
chmod 755 "$STAGE/servers/app_server" "$STAGE/lib/libtracker.so"
touch "$STAGE/servers/app_server" "$STAGE/lib/libtracker.so"

cat > "$STAGE/.PackageInfo" <<INFO
name			rretina
version			$VERSION-$REVISION
architecture	$ARCH
summary			"R Retina: HiDPI scaling for RenkuOS"
description		"Picks the user interface scale from the display's pixel density (EDID) instead of the resolution alone, and keeps desktop icons on their grid when the scale changes. Replaces app_server and libtracker of $HAIKU_VERSION while installed; reboot after installing or removing it."
packager		"$PACKAGER"
vendor			"$VENDOR"
licenses		{ "MIT" }
copyrights		{ "2001-2026 Haiku, Inc. et al" "2026 rainygirl" }
provides		{ rretina = $VERSION }
requires		{ haiku == $HAIKU_VERSION }
flags			{ system_package }
INFO

( cd "$STAGE" && COPYFILE_DISABLE=1 tar --no-xattrs -cf - . ) \
	| docker exec -i "$CONTAINER" sh -c "
		set -e
		W=/tmp/rretina-\$\$; rm -rf \$W; mkdir -p \$W/s && cd \$W/s && tar xf - 2>/dev/null
		export LD_LIBRARY_PATH=$GEN/objects/linux/lib
		$GEN/objects/linux/arm64/release/tools/package/package create -z zlib -C \$W/s \$W/out.hpkg >&2
		cat \$W/out.hpkg; rm -rf \$W" > "$HERE/dist/$NAME"
ls -la "$HERE/dist/$NAME"
