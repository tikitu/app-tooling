#!/usr/bin/env bash
#
# mac-install.sh — put a built Mac app in /Applications, replacing the copy
# there, and register it with LaunchServices.
#
# Imported by peru from the app-tooling pattern `mac-install`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/mac-install/ says what it is for.
#
# Usage:
#   scripts/mac-install.sh [--dir <dir>] <built .app>
#
# Installs as <dir>/<the bundle's own name>, <dir> being /Applications
# unless given. In order:
#
# 1. Checks the built app's signature, and compares its CFBundleVersion with
#    the installed copy's. A build number that has not risen is only a
#    warning: the install goes ahead, but the Dock and Finder may keep
#    showing the old icon (the pattern's README says what to do then).
# 2. Quits the installed copy if it is running, found by the absolute path
#    of its executable, never by bundle id (that would also reach a build
#    from a checkout). It is asked to quit, not killed: this is the real app,
#    possibly in the middle of something. If it has not gone after
#    MAC_INSTALL_QUIT_TIMEOUT seconds (default 10), nothing is installed.
# 3. Replaces the installed copy with `ditto`, and checks the signature of
#    what arrived.
# 4. `lsregister -f` on it, so LaunchServices reads the new bundle now
#    rather than whenever it next notices.
# 5. Starts it again, in the background, only if it was running before.
set -euo pipefail

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

DIR=/Applications
if [ "${1:-}" = "--dir" ]; then
	DIR="${2:?usage: mac-install.sh [--dir <dir>] <built .app>}"
	shift 2
fi
SRC="${1:?usage: mac-install.sh [--dir <dir>] <built .app>}"
SRC="${SRC%/}"
[ -d "$SRC" ] && [ -f "$SRC/Contents/Info.plist" ] || { echo "✗ no app at $SRC — did the build fail?" >&2; exit 1; }
[ -d "$DIR" ] || { echo "✗ no directory $DIR to install into" >&2; exit 1; }
DIR="$(cd "$DIR" && pwd -P)"
DEST="$DIR/$(basename "$SRC")"
[ "$(cd "$SRC" && pwd -P)" != "$DEST" ] || { echo "✗ $SRC is already the installed copy" >&2; exit 1; }

codesign --verify --deep --strict "$SRC" || { echo "✗ $SRC fails its signature check; not installing it" >&2; exit 1; }

# Up to three dot-separated integers, compared part by part, as macOS and
# App Store Connect compare CFBundleVersion. Exit 0 when $1 > $2.
version_above() {
	awk -v a="$1" -v b="$2" 'BEGIN {
		na = split(a, x, "."); nb = split(b, y, ".")
		n = na > nb ? na : nb
		for (i = 1; i <= n; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
		exit 1
	}'
}

NEW_VERSION="$(plutil -extract CFBundleVersion raw "$SRC/Contents/Info.plist" 2>/dev/null || echo "")"
[ -n "$NEW_VERSION" ] || { echo "✗ $SRC has no CFBundleVersion" >&2; exit 1; }
if [ -f "$DEST/Contents/Info.plist" ]; then
	OLD_VERSION="$(plutil -extract CFBundleVersion raw "$DEST/Contents/Info.plist" 2>/dev/null || echo "")"
	if ! version_above "$NEW_VERSION" "${OLD_VERSION:-0}"; then
		echo "⚠ build $NEW_VERSION is not above the installed $OLD_VERSION: if the icon changed, the Dock may keep the old one" >&2
		echo "  (docs/app-tooling/mac-install/README.md, \"When the old icon stays\")" >&2
	fi
fi

# Processes whose command line starts with the installed executable's
# directory: this copy and nothing else.
running_pids() {
	ps -axo pid=,args= | awk -v p="$DEST/Contents/MacOS/" \
		'{ pid = $1; sub(/^ *[0-9]+ /, ""); if (index($0, p) == 1) print pid }'
}

WAS_RUNNING=""
pids="$(running_pids)"
if [ -n "$pids" ]; then
	WAS_RUNNING=yes
	for pid in $pids; do
		osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSRunningApplication.runningApplicationWithProcessIdentifier($pid).terminate" >/dev/null 2>&1 || true
	done
	timeout="${MAC_INSTALL_QUIT_TIMEOUT:-10}"
	for _ in $(seq $((timeout * 5))); do
		[ -n "$(running_pids)" ] || break
		sleep 0.2
	done
	if [ -n "$(running_pids)" ]; then
		echo "✗ $DEST did not quit within ${timeout}s; quit it and run this again" >&2
		exit 1
	fi
	echo "✓ quit the running $DEST"
fi

rm -rf "$DEST"
ditto "$SRC" "$DEST"
codesign --verify --deep --strict "$DEST" || { echo "✗ $DEST fails its signature check after copying" >&2; exit 1; }
"$LSREGISTER" -f "$DEST"
echo "✓ installed $DEST, build $NEW_VERSION, and registered it with LaunchServices"

if [ -n "$WAS_RUNNING" ]; then
	open -g "$DEST"
	echo "✓ started it again, in the background"
fi
