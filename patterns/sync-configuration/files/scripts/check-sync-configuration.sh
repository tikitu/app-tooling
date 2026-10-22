#!/usr/bin/env bash
#
# check-sync-configuration.sh — refuse a built app whose signature and
# Info.plist do not agree on whether it may sync, and against which CloudKit
# environment.
#
# Imported by peru from the app-tooling pattern `sync-configuration`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/sync-configuration/ says how to use it.
#
# Usage:
#   check-sync-configuration.sh --prefix <prefix> [options] [--expect <shape>] <App.app>...
#
# Reads what each bundle is actually signed with (codesign; for a simulator
# build, the entitlements linked into its executable), not the files the
# build was given, and compares that with what its Info.plist declares.
# Exactly two shapes pass, for the app and every extension in it:
#
#   scratch  <prefix>SyncEnabled false, no <prefix>CloudKitEnvironment,
#            no com.apple.developer.icloud-* entitlement anywhere.
#   sync     <prefix>SyncEnabled true, <prefix>CloudKitEnvironment the same
#            as the app's icloud-container-environment entitlement
#            (Development or Production), with a container named; an
#            extension with iCloud keys pins the same environment.
#
# Options (each optional; a check is made only for what is given):
#   --expect scratch|sync|production
#                          fail any other shape; production is a sync build
#                          on Production, as every TestFlight build must be
#   --bundle-id <id>       a sync build's CFBundleIdentifier
#   --app-groups <g,...>   a sync build's App Groups, exactly, in the app
#                          and every extension
#   --scratch-bundle-id <id>, --scratch-app-groups <g,...>
#                          the same for a scratch build, when it is a
#                          separate app
#   --app-group-key <key>  an Info.plist key in which the app and each
#                          extension name their App Group: it must be one
#                          of the shape's groups, and the same in all
#
# Exit 0 when every bundle passes, 1 when any fails, 2 for a usage error.
# A signature that cannot be read fails: it never reads as "no iCloud keys".
set -euo pipefail

usage() {
	echo "usage: $0 --prefix <prefix> [--expect scratch|sync|production] [--bundle-id <id>]" >&2
	echo "         [--app-groups <g,...>] [--scratch-bundle-id <id>] [--scratch-app-groups <g,...>]" >&2
	echo "         [--app-group-key <key>] <App.app>..." >&2
	exit 2
}

PREFIX=""
EXPECT=""
BUNDLE_ID=""
APP_GROUPS=""
SCRATCH_BUNDLE_ID=""
SCRATCH_APP_GROUPS=""
APP_GROUP_KEY=""
while [ $# -gt 0 ]; do
	case "$1" in
		--prefix | --expect | --bundle-id | --app-groups | --scratch-bundle-id | --scratch-app-groups | --app-group-key)
			[ $# -ge 2 ] || usage
			case "$1" in
				--prefix) PREFIX="$2" ;;
				--expect) EXPECT="$2" ;;
				--bundle-id) BUNDLE_ID="$2" ;;
				--app-groups) APP_GROUPS="$2" ;;
				--scratch-bundle-id) SCRATCH_BUNDLE_ID="$2" ;;
				--scratch-app-groups) SCRATCH_APP_GROUPS="$2" ;;
				--app-group-key) APP_GROUP_KEY="$2" ;;
			esac
			shift 2
			;;
		--) shift; break ;;
		-*) usage ;;
		*) break ;;
	esac
done
[ -n "$PREFIX" ] || usage
case "$EXPECT" in "" | scratch | sync | production) ;; *) usage ;; esac
[ $# -ge 1 ] || usage

FAILED=0
fail() {
	echo "✗ $1" >&2
	FAILED=1
}

# The bundle's Info.plist: Contents/Info.plist on the Mac, Info.plist on iOS.
info_plist() {
	if [ -f "$1/Contents/Info.plist" ]; then echo "$1/Contents/Info.plist"; else echo "$1/Info.plist"; fi
}

plist_value() { # <plist> <key>: prints the value, or nothing if the key is missing
	/usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

# The executable: Contents/MacOS/<name> on the Mac, <name> on iOS.
executable_of() {
	local name
	name="$(plist_value "$(info_plist "$1")" CFBundleExecutable)"
	if [ -n "$name" ] && [ -f "$1/Contents/MacOS/$name" ]; then
		echo "$1/Contents/MacOS/$name"
	elif [ -n "$name" ]; then
		echo "$1/$name"
	fi
}

# A simulator build is signed ad hoc with no entitlements; the ones the
# simulator grants are linked into the executable's __TEXT,__entitlements
# section instead. Every architecture's copy must be the same.
simulator_entitlements() { # <bundle> <out file>
	local executable arch first=""
	executable="$(executable_of "$1")"
	if [ -z "$executable" ] || [ ! -f "$executable" ]; then
		fail "$1: no executable (CFBundleExecutable '${executable:-missing}')"
		return 1
	fi
	for arch in $(lipo -archs "$executable"); do
		rm -f "$TMP/thin" "$TMP/$arch.plist"
		lipo "$executable" -thin "$arch" -output "$TMP/thin" 2>/dev/null || cp "$executable" "$TMP/thin"
		if ! segedit "$TMP/thin" -extract __TEXT __entitlements "$TMP/$arch.plist" 2>/dev/null ||
			[ ! -s "$TMP/$arch.plist" ]; then
			fail "$1: a simulator build with no __entitlements section ($arch)"
			return 1
		fi
		if [ -z "$first" ]; then
			first="$arch"
			cp "$TMP/$arch.plist" "$2"
		elif ! cmp -s "$TMP/$first.plist" "$TMP/$arch.plist"; then
			fail "$1: its $first and $arch slices have different entitlements"
			return 1
		fi
	done
	if [ -z "$first" ]; then
		fail "$1: lipo found no architectures in $executable"
		return 1
	fi
}

# The entitlements the bundle is signed with, as an XML property list
# (an empty dictionary for none). Never trust empty output: a failed or
# missing signature must not read as "no iCloud keys".
signed_entitlements() { # <bundle> <out file>
	local plist platform status=0
	plist="$(info_plist "$1")"
	platform="$(plist_value "$plist" DTPlatformName)"
	case "$platform" in
		*simulator)
			simulator_entitlements "$@" || return 1
			;;
		*)
			# A bundle laid out for iOS that does not say which platform it
			# was built for could be a simulator build, whose signature has
			# no entitlements whatever the build was given.
			if [ -z "$platform" ] && [ ! -d "$1/Contents" ]; then
				fail "$1: no DTPlatformName, so a device build cannot be told from a simulator one"
				return 1
			fi
			codesign -d --entitlements - --xml "$1" >"$2" 2>"$TMP/codesign.err" || status=$?
			if [ $status -ne 0 ]; then
				fail "$1: codesign could not read its signature (exit $status: $(head -1 "$TMP/codesign.err"))"
				return 1
			fi
			# Exit 0 and no output: signed, with no entitlements at all.
			[ -s "$2" ] || plutil -create xml1 "$2"
			;;
	esac
	if ! plutil -lint "$2" >/dev/null 2>&1; then
		fail "$1: its entitlements are not a property list"
		return 1
	fi
}

has_icloud_key() { # <entitlements file>
	plutil -convert xml1 -o - "$1" | grep -q '<key>com\.apple\.developer\.icloud-'
}

groups_of() { # <entitlements file>: comma-separated, in order
	local i=0 value out=""
	while value="$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:$i" "$1" 2>/dev/null)"; do
		out="${out:+$out,}$value"
		i=$((i + 1))
	done
	echo "$out"
}

in_list() { # <value> <comma-separated list>
	case ",$2," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The entitlements of one bundle, app or extension, against its shape.
check_signature() { # <bundle> <shape> <environment> <is extension>
	local bundle="$1" shape="$2" environment="$3" is_extension="$4"
	local ent="$TMP/entitlements.plist" groups signed_environment expected_groups
	rm -f "$ent"
	signed_entitlements "$bundle" "$ent" || return 0
	groups="$(groups_of "$ent")"
	signed_environment="$(plist_value "$ent" com.apple.developer.icloud-container-environment)"

	if [ "$shape" = scratch ]; then
		if has_icloud_key "$ent"; then
			fail "$bundle: a scratch build is signed with an iCloud entitlement"
		fi
		expected_groups="$SCRATCH_APP_GROUPS"
	else
		if [ "$is_extension" = no ]; then
			[ "$signed_environment" = "$environment" ] ||
				fail "$bundle: signed with icloud-container-environment '${signed_environment:-missing}', but declares ${PREFIX}CloudKitEnvironment=$environment"
			[ -n "$(plist_value "$ent" com.apple.developer.icloud-container-identifiers:0)" ] ||
				fail "$bundle: a sync build is signed without an iCloud container"
		elif has_icloud_key "$ent" && [ "$signed_environment" != "$environment" ]; then
			fail "$bundle: an extension signed with icloud-container-environment '${signed_environment:-missing}', but the app's is $environment"
		fi
		expected_groups="$APP_GROUPS"
	fi
	if [ -n "$expected_groups" ] && [ "$groups" != "$expected_groups" ]; then
		fail "$bundle: a $shape build's App Groups must be exactly $expected_groups, not: ${groups:-none}"
	fi
}

check_app() {
	local app="${1%/}" plist sync environment bundle_id shape expected_id expected_groups declared_group=""
	if [ ! -d "$app" ]; then
		fail "$app: no such bundle"
		return
	fi
	local failed_before=$FAILED
	FAILED=0
	plist="$(info_plist "$app")"
	sync="$(plist_value "$plist" "${PREFIX}SyncEnabled")"
	environment="$(plist_value "$plist" "${PREFIX}CloudKitEnvironment")"
	bundle_id="$(plist_value "$plist" CFBundleIdentifier)"

	case "$sync" in
		false) shape=scratch ;;
		true) shape=sync ;;
		*)
			fail "$app: ${PREFIX}SyncEnabled is '${sync:-missing}', not true or false"
			FAILED=1
			return
			;;
	esac

	if [ "$shape" = scratch ]; then
		[ -z "$environment" ] || fail "$app: a scratch build declares ${PREFIX}CloudKitEnvironment=$environment"
		expected_id="$SCRATCH_BUNDLE_ID"
		expected_groups="$SCRATCH_APP_GROUPS"
	else
		case "$environment" in
			Development | Production) ;;
			*) fail "$app: ${PREFIX}CloudKitEnvironment is '${environment:-missing}', not Development or Production" ;;
		esac
		expected_id="$BUNDLE_ID"
		expected_groups="$APP_GROUPS"
	fi
	case "$EXPECT" in
		"") ;;
		production)
			[ "$shape" = sync ] && [ "$environment" = Production ] ||
				fail "$app: expected a production build, but it declares ${PREFIX}SyncEnabled=$sync, ${PREFIX}CloudKitEnvironment=${environment:-missing}"
			;;
		*)
			[ "$shape" = "$EXPECT" ] ||
				fail "$app: expected a $EXPECT build, but it declares ${PREFIX}SyncEnabled=$sync"
			;;
	esac
	if [ -n "$expected_id" ] && [ "$bundle_id" != "$expected_id" ]; then
		fail "$app: a $shape build's bundle id must be $expected_id, not ${bundle_id:-missing}"
	fi
	if [ -n "$APP_GROUP_KEY" ]; then
		declared_group="$(plist_value "$plist" "$APP_GROUP_KEY")"
		if [ -z "$declared_group" ]; then
			fail "$app: no $APP_GROUP_KEY in its Info.plist"
		elif [ -n "$expected_groups" ] && ! in_list "$declared_group" "$expected_groups"; then
			fail "$app: a $shape build's $APP_GROUP_KEY must be one of $expected_groups, not $declared_group"
		fi
	fi

	check_signature "$app" "$shape" "$environment" no
	local appex appex_group
	for appex in "$app"/PlugIns/*.appex "$app"/Extensions/*.appex \
		"$app"/Contents/PlugIns/*.appex "$app"/Contents/Extensions/*.appex; do
		[ -d "$appex" ] || continue
		check_signature "$appex" "$shape" "$environment" yes
		if [ -n "$APP_GROUP_KEY" ]; then
			appex_group="$(plist_value "$(info_plist "$appex")" "$APP_GROUP_KEY")"
			[ "$appex_group" = "$declared_group" ] ||
				fail "$appex: $APP_GROUP_KEY is '${appex_group:-missing}', but the app's is '$declared_group'"
		fi
	done

	if [ $FAILED -eq 0 ]; then
		if [ "$shape" = sync ]; then
			echo "✓ $app is a sync build ($environment)"
		else
			echo "✓ $app is a scratch build"
		fi
	fi
	[ $failed_before -eq 0 ] || FAILED=1
}

for app in "$@"; do
	check_app "$app"
done
exit $FAILED
