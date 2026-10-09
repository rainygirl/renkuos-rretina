#!/bin/sh
# Builds dist/rretina-<version>-<revision>-<arch>.hpkg from
# dist/<arch>/{app_server,libtracker.so,Appearance}, using the Linux-hosted
# package tool of a Haiku build tree in a container.
#
#   package/make-rretina.sh <arch> <haiku version the binaries were built for>
#   e.g. package/make-rretina.sh arm64 r1~beta6_hrev60071_15_dirty
#
# The files go where the haiku package has its own. packagefs shows, for a
# path more than one package provides, a system package's file over another
# package's, and among system packages the newest one; so rretina is a system
# package and its files are stamped now. Removing it brings the haiku
# package's files back by itself, and a later haiku package (newer files)
# would win over rretina's. The binaries use private interfaces of libbe and
# app_server, so the package requires exactly that haiku version.
#
# The three files keep the attributes of the haiku package's own (app
# signature, type, icon): they are extracted from that package in the
# container and the new contents written into them.
#
#   CONTAINER  default haiku-builder
#   GEN        default /root/renku-arm64-work/generated.arm64 (package tool)
#   BASE       haiku package of <arch> in the container,
#              default /root/rretina-base/haiku-<arch>.hpkg
#   LIBS       copy of GEN's objects/linux/lib whose libroot_build.so has its
#              attribute store path changed to STORE (same length), default
#              /root/rretina-lib
#   STORE      default /root/rretina-attrs/00000000000000000000000000000
#   VERSION    default 1.0.0, REVISION default 1
set -e
ARCH="${1:?arch}"
HAIKU_VERSION="${2:?haiku version}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINER="${CONTAINER:-haiku-builder}"
GEN="${GEN:-/root/renku-arm64-work/generated.arm64}"
BASE="${BASE:-/root/rretina-base/haiku-$ARCH.hpkg}"
LIBS="${LIBS:-/root/rretina-lib}"
STORE="${STORE:-/root/rretina-attrs/00000000000000000000000000000}"
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
mkdir -p "$STAGE/new" "$STAGE/documentation/packages/rretina"
cp "$HERE/dist/$ARCH/app_server" "$HERE/dist/$ARCH/libtracker.so" \
	"$HERE/dist/$ARCH/Appearance" "$STAGE/new/"
cp "$HERE/README.md" "$STAGE/documentation/packages/rretina/"
cp -R "$HERE/patches" "$STAGE/documentation/packages/rretina/"

cat > "$STAGE/PackageInfo" <<INFO
name			rretina
version			$VERSION-$REVISION
architecture	$ARCH
summary			"R Retina: HiDPI scaling for RenkuOS"
description		"Picks the user interface scale from the display's pixel density (EDID) instead of the resolution alone, keeps desktop icons on their grid when the scale changes, and adds a UI scale choice (Automatic, 100%, 150%, 200%) to Appearance's Fonts tab. Replaces app_server, libtracker and Appearance of $HAIKU_VERSION while installed; reboot after installing or removing it."
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
		W=/tmp/rretina-\$\$; rm -rf \$W; mkdir -p \$W/in \$W/s && cd \$W/in && tar xf - 2>/dev/null
		# The build tools keep attributes in one store keyed by inode number,
		# so files of other runs leave attributes behind for whatever reuses
		# their inodes. Use a private copy of the tools' libroot_build.so whose
		# store path points at a directory emptied here.
		export LD_LIBRARY_PATH=$LIBS
		rm -rf $STORE; mkdir -p $STORE
		P=$GEN/objects/linux/arm64/release/tools/package/package
		\$P extract -C \$W/s $BASE servers/app_server lib/libtracker.so \
			preferences/Appearance >&2
		cd \$W/s
		cat \$W/in/new/app_server > servers/app_server
		cat \$W/in/new/libtracker.so > lib/libtracker.so
		cat \$W/in/new/Appearance > preferences/Appearance
		touch servers/app_server lib/libtracker.so preferences/Appearance
		cp -R \$W/in/documentation .
		cp \$W/in/PackageInfo .PackageInfo
		\$P create -z zlib -C \$W/s \$W/out.hpkg >&2
		cat \$W/out.hpkg; rm -rf \$W $STORE" > "$HERE/dist/$NAME"
ls -la "$HERE/dist/$NAME"
