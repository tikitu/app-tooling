#!/usr/bin/env bash
#
# mac-stale-registrations.sh — list, and on request unregister, the
# LaunchServices registrations of a bundle id other than the installed app.
#
# Imported by peru from the app-tooling pattern `mac-install`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/mac-install/ says what it is for.
#
# Usage:
#   scripts/mac-stale-registrations.sh <bundle id> <installed .app> [--unregister]
#
# Every build that has been launched, or opened in Finder, is registered:
# DerivedData, build/, worktrees, /tmp. They all share the bundle id, and
# LaunchServices may pick any of them for an icon, a document type or
# `open -b`. This prints each one with its CFBundleVersion, and `(gone)` for
# those whose bundle no longer exists. With --unregister it runs
# `lsregister -u` on each. That deletes nothing on disk, and a build that is
# launched again simply registers again.
#
# Exits 1 if `lsregister -dump` printed nothing, rather than reporting that
# there are no registrations: an empty dump means the command failed.
set -euo pipefail

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

USAGE="usage: mac-stale-registrations.sh <bundle id> <installed .app> [--unregister]"
BUNDLE_ID="${1:?$USAGE}"
KEEP="${2:?$USAGE}"
KEEP="${KEEP%/}"
# As the dump has it: resolved, so /tmp/x is /private/tmp/x.
if [ -d "$(dirname "$KEEP")" ]; then
	KEEP="$(cd "$(dirname "$KEEP")" && pwd -P)/$(basename "$KEEP")"
fi
UNREGISTER=no
case "${3:-}" in
	"") ;;
	--unregister) UNREGISTER=yes ;;
	*) echo "$USAGE" >&2; exit 2 ;;
esac

DUMP="$(mktemp -t mac-stale-registrations)"
trap 'rm -f "$DUMP"' EXIT
"$LSREGISTER" -dump >"$DUMP" 2>/dev/null || true
[ -s "$DUMP" ] || { echo "✗ lsregister -dump printed nothing; cannot tell what is registered" >&2; exit 1; }

# The dump is records separated by lines of dashes. A bundle's record has
# `path:` (with an id in parentheses after it), `identifier:` and
# `version:`, in that order today; collected per record so the order does
# not matter. Prints path<TAB>version.
registrations() {
	awk -v id="$BUNDLE_ID" '
		function flush() { if (ident == id && path != "") print path "\t" version; path = ""; ident = ""; version = "" }
		/^-----/ { flush(); next }
		/^path:/ { sub(/^path: */, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
		/^identifier:/ { sub(/^identifier: */, ""); ident = $0 }
		/^version:/ { sub(/^version: */, ""); sub(/ \(.*$/, ""); version = $0 }
		END { flush() }
	' "$DUMP" | sort -u
}

stale=0
kept=0
while IFS=$'\t' read -r path version; do
	if [ "$path" = "$KEEP" ]; then
		kept=1
		continue
	fi
	stale=$((stale + 1))
	note=""
	[ -d "$path" ] || note=" (gone)"
	echo "  $path  [${version:-no version}]$note"
	if [ "$UNREGISTER" = yes ]; then
		"$LSREGISTER" -u "$path" 2>/dev/null || echo "    ✗ lsregister -u failed for it" >&2
	fi
done < <(registrations)

if [ "$kept" = 1 ]; then
	echo "✓ $KEEP is registered"
else
	echo "⚠ $KEEP is not registered (not installed, or never opened)"
fi
if [ "$stale" = 0 ]; then
	echo "✓ no other registrations of $BUNDLE_ID"
elif [ "$UNREGISTER" = yes ]; then
	echo "✓ unregistered the $stale above"
else
	echo "$stale other registrations of $BUNDLE_ID; unregister them with --unregister (make mac-stale-registrations UNREGISTER=1)"
fi
