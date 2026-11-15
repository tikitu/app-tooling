#!/usr/bin/env bash
#
# make-scratch-app.sh — make a Mac app's scratch build from its real build.
#
# Imported by peru from the app-tooling pattern `scratch-data`
# (https://github.com/tikitu/app-tooling). Never edit it here: the change
# belongs in app-tooling. docs/app-tooling/scratch-data/ says how to use it.
#
# Usage: scripts/make-scratch-app.sh <MyApp.app> <MyApp Scratch.app>
#
# Copies the real bundle and makes the copy another app, which always opens
# scratch data:
#   - bundle id <id>.scratch, so its container, defaults and data are its own;
#   - CFBundleName and CFBundleDisplayName (where set) end " Scratch";
#   - Info.plist ScratchBuild = YES, which ScratchBuild.isScratch reads;
#   - its .icns icon banded by scripts/make-scratch-icon.py (scratch-look);
#   - the entitlements it was signed with, less every one a provisioning
#     profile grants (iCloud, push, keychain groups: com.apple.developer.*
#     and the like), and with each App Group given ".scratch";
#   - signed ad hoc.
# Every app bundle inside it (a login item, a menu-bar helper) gets the same,
# before the app itself. The real bundle is not touched.
#
# For an app a script bundles (build.sh). An Xcode app uses a scratch build
# configuration instead (apply.md).
set -euo pipefail

usage() { sed -n '9,25p' "$0" >&2; exit 2; }
fail() { echo "✗ $*" >&2; exit 1; }

[ $# -eq 2 ] || usage
real="${1%/}"
scratch="${2%/}"

[ -f "$real/Contents/Info.plist" ] || fail "$real is not an app bundle"
case "$(plutil -extract CFBundleIdentifier raw -o - "$real/Contents/Info.plist" 2>/dev/null)" in
*.scratch) fail "$real is already a scratch build; give this the real build" ;;
esac
# The destination is deleted first: make sure it can only be a scratch build.
case "$(basename "$scratch")" in
*" Scratch.app") ;;
*) fail "the scratch bundle's name must end \" Scratch.app\": $scratch" ;;
esac
[ "$(cd "$(dirname "$real")" && pwd)/$(basename "$real")" != \
	"$(mkdir -p "$(dirname "$scratch")" && cd "$(dirname "$scratch")" && pwd)/$(basename "$scratch")" ] ||
	fail "the scratch bundle must differ from the real one"

icon_script="$(cd "$(dirname "$0")" && pwd)/make-scratch-icon.py"
[ -x "$icon_script" ] ||
	fail "needs scripts/make-scratch-icon.py (scratch-look) beside it, to band the icon"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

plist_get() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

# Bands the .icns the bundle names, in place.
band_icon() {
	local bundle="$1" plist="$1/Contents/Info.plist" icon icns
	if icon="$(plist_get "$plist" CFBundleIconFile)"; then
		icns="$bundle/Contents/Resources/${icon%.icns}.icns"
		[ -f "$icns" ] || fail "$bundle names CFBundleIconFile $icon, but $icns is missing"
		rm -rf "$work/real.iconset" "$work/scratch.iconset"
		iconutil -c iconset -o "$work/real.iconset" "$icns"
		"$icon_script" "$work/real.iconset" "$work/scratch.iconset" >/dev/null
		iconutil -c icns -o "$icns" "$work/scratch.iconset"
		echo "  banded $icns"
	elif plist_get "$plist" CFBundleIconName >/dev/null; then
		fail "$bundle's icon is in an asset catalog (CFBundleIconName), which this cannot band: build the scratch app with AppIcon-Scratch instead (scratch-look)"
	else
		echo "  (no icon in $bundle to band)"
	fi
}

# The entitlements the bundle was signed with, made fit for an ad hoc scratch
# build, in $work/entitlements.plist; fails (returns 1) if it has none.
scratch_entitlements() {
	codesign -d --entitlements - --xml "$1" >"$work/entitlements.plist" 2>/dev/null || return 1
	[ -s "$work/entitlements.plist" ] || return 1
	python3 -I - "$work/entitlements.plist" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, "rb") as f:
    entitlements = plistlib.load(f)
kept = {}
for key, value in entitlements.items():
    # Granted by a provisioning profile, which an ad hoc build has not got:
    # iCloud, push, keychain groups, the team and application identifiers.
    if key.startswith("com.apple.developer.") or key in (
        "com.apple.application-identifier",
        "application-identifier",
        "keychain-access-groups",
    ):
        print(f"  dropped entitlement {key}")
        continue
    if key == "com.apple.security.application-groups":
        value = [g if g.endswith(".scratch") else g + ".scratch" for g in value]
        print(f"  App Groups: {', '.join(value)}")
    kept[key] = value
with open(path, "wb") as f:
    plistlib.dump(kept, f)
PY
}

# One bundle: identity, icon, entitlements, signature.
make_scratch() {
	local bundle="$1" plist="$1/Contents/Info.plist" id key value
	id="$(plist_get "$plist" CFBundleIdentifier)" || fail "$bundle has no CFBundleIdentifier"
	case "$id" in *.scratch) fail "$bundle already has a scratch bundle id ($id); give this the real build" ;; esac
	echo "→ $bundle: $id.scratch"
	plutil -replace CFBundleIdentifier -string "$id.scratch" "$plist"
	for key in CFBundleName CFBundleDisplayName; do
		if value="$(plist_get "$plist" "$key")"; then
			plutil -replace "$key" -string "$value Scratch" "$plist"
		fi
	done
	plutil -replace ScratchBuild -bool YES "$plist"
	band_icon "$bundle"
	rm -f "$bundle/Contents/embedded.provisionprofile"
	if scratch_entitlements "$bundle"; then
		codesign --force --sign - --entitlements "$work/entitlements.plist" "$bundle"
	else
		codesign --force --sign - "$bundle"
	fi
}

rm -rf "$scratch"
ditto "$real" "$scratch"

# Embedded apps first, deepest first: a bundle is signed after everything in
# it, since changing what is inside breaks the signature around it.
find "$scratch/Contents" -type d -name '*.app' | awk -F/ '{ print NF "\t" $0 }' |
	sort -rn | cut -f2- | while IFS= read -r helper; do
	make_scratch "$helper"
done
make_scratch "$scratch"

codesign --verify --strict "$scratch"
echo "✓ $scratch: a scratch build of $(basename "$real")"
