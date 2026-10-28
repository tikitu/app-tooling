#!/usr/bin/env bash
#
# check-sync-configuration-test.sh — tests for check-sync-configuration.sh,
# on fake bundles signed ad hoc with the entitlements of each case. Ad hoc
# signing accepts any entitlements; the bundles are never launched.
#
# Imported by peru from the app-tooling pattern `sync-configuration`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/sync-configuration/ says how to use it.
#
# Usage: scripts/tests/check-sync-configuration-test.sh
# (`make sync-check-test`). Runs as it is in app-tooling too, from
# patterns/sync-configuration/files/. Needs codesign, clang, lipo and segedit
# (Xcode's command-line tools).
set -euo pipefail

CHECK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/check-sync-configuration.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REAL_ID="com.example.MyApp"
SCRATCH_ID="com.example.MyApp.scratch"
REAL_GROUP="group.com.example.myapp"
SCRATCH_GROUP="group.com.example.myapp.scratch"
# The options a project with a separate scratch app passes.
SCRATCH_APP=(--prefix MyApp --bundle-id "$REAL_ID" --app-groups "$REAL_GROUP"
	--scratch-bundle-id "$SCRATCH_ID" --scratch-app-groups "$SCRATCH_GROUP"
	--app-group-key MyAppAppGroup)

# make_app <name> <bundle id> <sync: true|false|-> <environment|-> <app group|->
#          <entitlements environment|none|-> <entitlements group|->
#   sync/environment/app group "-": leave the Info.plist key out.
#   entitlements environment "none": no iCloud keys; "-": iCloud keys without
#   an environment. Entitlements group "-": no App Groups.
make_app() {
	local name="$1" bundle_id="$2" sync="$3" environment="$4" group="$5" ent_env="$6" ent_group="$7"
	local app="$TMP/$name/MyApp.app"
	mkdir -p "$app/Contents/MacOS"
	cp /usr/bin/true "$app/Contents/MacOS/MyApp"
	local plist="$app/Contents/Info.plist"
	plutil -create xml1 "$plist"
	plutil -insert CFBundleIdentifier -string "$bundle_id" "$plist"
	plutil -insert CFBundleExecutable -string MyApp "$plist"
	plutil -insert CFBundlePackageType -string APPL "$plist"
	[ "$sync" = - ] || plutil -insert MyAppSyncEnabled -bool "$sync" "$plist"
	[ "$environment" = - ] || plutil -insert MyAppCloudKitEnvironment -string "$environment" "$plist"
	[ "$group" = - ] || plutil -insert MyAppAppGroup -string "$group" "$plist"

	local ent="$TMP/$name/entitlements.plist"
	plutil -create xml1 "$ent"
	if [ "$ent_group" != - ]; then
		plutil -insert com\\.apple\\.security\\.application-groups -array "$ent"
		plutil -insert com\\.apple\\.security\\.application-groups -string "$ent_group" -append "$ent"
	fi
	if [ "$ent_env" != none ]; then
		plutil -insert com\\.apple\\.developer\\.icloud-container-identifiers -array "$ent"
		plutil -insert com\\.apple\\.developer\\.icloud-container-identifiers -string iCloud.com.example.myapp -append "$ent"
		[ "$ent_env" = - ] || plutil -insert com\\.apple\\.developer\\.icloud-container-environment -string "$ent_env" "$ent"
	fi
	codesign -s - -f --entitlements "$ent" "$app" 2>/dev/null
	echo "$app"
}

PASSED=0
FAILED=0
expect() { # <description> <expected exit> <args...>
	local description="$1" expected="$2" status=0
	shift 2
	"$CHECK" "$@" >"$TMP/out" 2>&1 || status=$?
	# A pass must say so, and a failure must say why: never an empty result.
	if [ $status -eq "$expected" ] && [ -s "$TMP/out" ]; then
		PASSED=$((PASSED + 1))
	else
		FAILED=$((FAILED + 1))
		echo "✗ $description: exit $status, expected $expected" >&2
		sed 's/^/    /' "$TMP/out" >&2
	fi
}

# --- A separate scratch app, with its own ids and App Group ---------------

scratch=$(make_app scratch "$SCRATCH_ID" false - "$SCRATCH_GROUP" none "$SCRATCH_GROUP")
production=$(make_app production "$REAL_ID" true Production "$REAL_GROUP" Production "$REAL_GROUP")

expect "the scratch app passes" 0 "${SCRATCH_APP[@]}" "$scratch"
expect "the real app passes" 0 "${SCRATCH_APP[@]}" "$production"
expect "the scratch app passes --expect scratch" 0 "${SCRATCH_APP[@]}" --expect scratch "$scratch"
expect "the real app passes --expect production" 0 "${SCRATCH_APP[@]}" --expect production "$production"
expect "the real app passes --expect sync" 0 "${SCRATCH_APP[@]}" --expect sync "$production"
expect "the scratch app fails --expect production" 1 "${SCRATCH_APP[@]}" --expect production "$scratch"
expect "the scratch app fails --expect sync" 1 "${SCRATCH_APP[@]}" --expect sync "$scratch"
expect "the real app fails --expect scratch" 1 "${SCRATCH_APP[@]}" --expect scratch "$production"
expect "one failing bundle among several fails" 1 "${SCRATCH_APP[@]}" --expect scratch "$scratch" "$production"

expect "a scratch app with an iCloud entitlement fails" 1 "${SCRATCH_APP[@]}" \
	"$(make_app scratch-icloud "$SCRATCH_ID" false - "$SCRATCH_GROUP" Production "$SCRATCH_GROUP")"
expect "a scratch app with the real group fails" 1 "${SCRATCH_APP[@]}" \
	"$(make_app scratch-real-group "$SCRATCH_ID" false - "$SCRATCH_GROUP" none "$REAL_GROUP")"
expect "a scratch app with the real bundle id fails" 1 "${SCRATCH_APP[@]}" \
	"$(make_app scratch-real-id "$REAL_ID" false - "$SCRATCH_GROUP" none "$SCRATCH_GROUP")"
expect "a scratch app declaring an environment fails" 1 "${SCRATCH_APP[@]}" \
	"$(make_app scratch-env "$SCRATCH_ID" false Production "$SCRATCH_GROUP" none "$SCRATCH_GROUP")"
expect "a scratch app naming the real group in its Info.plist fails" 1 "${SCRATCH_APP[@]}" \
	"$(make_app scratch-declares-real "$SCRATCH_ID" false - "$REAL_GROUP" none "$SCRATCH_GROUP")"
expect "a real app signed for Development, declaring Production, fails" 1 "${SCRATCH_APP[@]}" \
	"$(make_app production-development "$REAL_ID" true Production "$REAL_GROUP" Development "$REAL_GROUP")"
expect "a real app declaring Development, signed for Production, fails" 1 "${SCRATCH_APP[@]}" \
	"$(make_app production-declares-development "$REAL_ID" true Development "$REAL_GROUP" Production "$REAL_GROUP")"
expect "a real app with no environment entitlement fails" 1 "${SCRATCH_APP[@]}" \
	"$(make_app production-no-env "$REAL_ID" true Production "$REAL_GROUP" - "$REAL_GROUP")"
expect "a real app without iCloud entitlements fails" 1 "${SCRATCH_APP[@]}" \
	"$(make_app production-no-icloud "$REAL_ID" true Production "$REAL_GROUP" none "$REAL_GROUP")"
expect "a real app with the scratch group fails" 1 "${SCRATCH_APP[@]}" \
	"$(make_app production-scratch-group "$REAL_ID" true Production "$SCRATCH_GROUP" Production "$SCRATCH_GROUP")"
expect "a real app with the scratch bundle id fails" 1 "${SCRATCH_APP[@]}" \
	"$(make_app production-scratch-id "$SCRATCH_ID" true Production "$REAL_GROUP" Production "$REAL_GROUP")"
expect "a missing SyncEnabled fails" 1 "${SCRATCH_APP[@]}" \
	"$(make_app no-sync-key "$SCRATCH_ID" - - "$SCRATCH_GROUP" none "$SCRATCH_GROUP")"
expect "a missing app group key fails" 1 "${SCRATCH_APP[@]}" \
	"$(make_app no-group-key "$SCRATCH_ID" false - - none "$SCRATCH_GROUP")"

# --- One app, ad hoc or signed, as with build.sh ---------------------------
# Only the prefix is given: the two shapes share their ids.

development=$(make_app development "$REAL_ID" true Development - Development -)
adhoc=$(make_app adhoc "$REAL_ID" false - - none -)
expect "an ad-hoc build with no entitlements at all passes" 0 --prefix MyApp --expect scratch "$adhoc"
expect "a sync build on Development fails" 1 --prefix MyApp "$development"
expect "a sync build on Development fails --expect sync" 1 --prefix MyApp --expect sync "$development"
expect "a sync build on Development passes --allow-development" 0 --prefix MyApp --allow-development "$development"
expect "a sync build on Development passes --expect sync --allow-development" 0 \
	--prefix MyApp --expect sync --allow-development "$development"
expect "a sync build on Development fails --expect production, even with --allow-development" 1 \
	--prefix MyApp --expect production --allow-development "$development"
expect "a sync build with no SyncEnabled under this prefix fails" 1 --prefix OtherApp "$development"

# --- Signatures that cannot be read ----------------------------------------

unsigned="$TMP/unsigned/MyApp.app"
mkdir -p "$(dirname "$unsigned")"
cp -R "$scratch" "$unsigned"
codesign --remove-signature "$unsigned"
expect "an unsigned bundle fails: no signature is not 'no iCloud keys'" 1 "${SCRATCH_APP[@]}" "$unsigned"
unsigned_adhoc="$TMP/unsigned-adhoc/MyApp.app"
mkdir -p "$(dirname "$unsigned_adhoc")"
cp -R "$adhoc" "$unsigned_adhoc"
codesign --remove-signature "$unsigned_adhoc"
expect "an unsigned bundle fails even when nothing else is checked" 1 --prefix MyApp "$unsigned_adhoc"

expect "a missing bundle fails" 1 "${SCRATCH_APP[@]}" "$TMP/nothing/MyApp.app"
expect "no arguments is a usage error" 2
expect "no --prefix is a usage error" 2 "$scratch"
expect "an unknown --expect is a usage error" 2 --prefix MyApp --expect real "$scratch"

# --- Extensions follow their app -------------------------------------------

with_extension() { # <name> <extension source app> <extensions dir>: the scratch app, holding it
	local app="$TMP/$1/MyApp.app"
	mkdir -p "$(dirname "$app")"
	cp -R "$scratch" "$app"
	mkdir -p "$app/Contents/$3"
	cp -R "$2" "$app/Contents/$3/ShareExtension.appex"
	codesign -s - -f --entitlements "$TMP/scratch/entitlements.plist" "$app" 2>/dev/null
	echo "$app"
}
expect "a scratch app with a scratch extension passes" 0 "${SCRATCH_APP[@]}" \
	"$(with_extension extension-ok \
		"$(make_app appex-ok "$SCRATCH_ID.ShareExtension" false - "$SCRATCH_GROUP" none "$SCRATCH_GROUP")" PlugIns)"
expect "a scratch app with an extension in the real group fails" 1 "${SCRATCH_APP[@]}" \
	"$(with_extension extension-real-group \
		"$(make_app appex-real "$SCRATCH_ID.ShareExtension" false - "$REAL_GROUP" none "$REAL_GROUP")" PlugIns)"
expect "a scratch app with an iCloud extension under Extensions/ fails" 1 "${SCRATCH_APP[@]}" \
	"$(with_extension extension-icloud \
		"$(make_app appex-icloud "$SCRATCH_ID.ShareExtension" false - "$SCRATCH_GROUP" Production "$SCRATCH_GROUP")" Extensions)"

# A sync app holding an extension with iCloud keys: refused unless the
# project opts out, and then only if it pins the app's environment.
with_sync_extension() { # <name> <extension environment|none>
	local app="$TMP/$1/MyApp.app"
	mkdir -p "$(dirname "$app")"
	cp -R "$production" "$app"
	mkdir -p "$app/Contents/PlugIns"
	cp -R "$(make_app "$1-appex" "$REAL_ID.ShareExtension" true Production "$REAL_GROUP" "$2" "$REAL_GROUP")" \
		"$app/Contents/PlugIns/ShareExtension.appex"
	codesign -s - -f --entitlements "$TMP/production/entitlements.plist" "$app" 2>/dev/null
	echo "$app"
}
sync_extension_plain=$(with_sync_extension sync-extension-plain none)
sync_extension_icloud=$(with_sync_extension sync-extension-icloud Production)
sync_extension_development=$(with_sync_extension sync-extension-development Development)
expect "a real app with an extension without iCloud keys passes" 0 "${SCRATCH_APP[@]}" "$sync_extension_plain"
expect "a real app with an iCloud extension fails" 1 "${SCRATCH_APP[@]}" "$sync_extension_icloud"
expect "a real app with an iCloud extension passes --allow-extension-icloud" 0 \
	"${SCRATCH_APP[@]}" --allow-extension-icloud "$sync_extension_icloud"
expect "an iCloud extension on another environment fails, even with --allow-extension-icloud" 1 \
	"${SCRATCH_APP[@]}" --allow-extension-icloud "$sync_extension_development"

# --- Simulator builds -------------------------------------------------------
# Signed ad hoc with no entitlements, which they carry in the executable's
# __TEXT,__entitlements section instead, as Xcode links it.

make_simulator_app() { # <name> <entitlements source app dir> [<arch>...]
	local name="$1" source="$2" app="$TMP/$1/MyApp.app"
	shift 2
	local arch_flags=() arch
	for arch in "$@"; do arch_flags+=(-arch "$arch"); done
	mkdir -p "$app"
	cp "$source/Contents/Info.plist" "$app/Info.plist"
	plutil -insert DTPlatformName -string iphonesimulator "$app/Info.plist"
	echo 'int main(void) { return 0; }' >"$TMP/$name/main.c"
	clang ${arch_flags[@]+"${arch_flags[@]}"} -o "$app/MyApp" "$TMP/$name/main.c" \
		-Wl,-sectcreate,__TEXT,__entitlements,"$(dirname "$source")/entitlements.plist"
	codesign -s - -f "$app" 2>/dev/null
	echo "$app"
}
expect "a simulator scratch build passes" 0 "${SCRATCH_APP[@]}" \
	"$(make_simulator_app simulator-scratch "$scratch")"
expect "a simulator real build passes" 0 "${SCRATCH_APP[@]}" \
	"$(make_simulator_app simulator-production "$production")"
expect "a simulator build for two architectures passes" 0 "${SCRATCH_APP[@]}" \
	"$(make_simulator_app simulator-fat "$scratch" arm64 x86_64)"
expect "a simulator scratch build with an iCloud entitlement fails" 1 "${SCRATCH_APP[@]}" \
	"$(make_simulator_app simulator-scratch-icloud "$TMP/scratch-icloud/MyApp.app")"

# Two slices with different entitlements.
mixed="$TMP/simulator-mixed/MyApp.app"
mkdir -p "$mixed"
cp "$scratch/Contents/Info.plist" "$mixed/Info.plist"
plutil -insert DTPlatformName -string iphonesimulator "$mixed/Info.plist"
echo 'int main(void) { return 0; }' >"$TMP/simulator-mixed/main.c"
clang -arch arm64 -o "$TMP/simulator-mixed/arm64" "$TMP/simulator-mixed/main.c" \
	-Wl,-sectcreate,__TEXT,__entitlements,"$TMP/scratch/entitlements.plist"
clang -arch x86_64 -o "$TMP/simulator-mixed/x86_64" "$TMP/simulator-mixed/main.c" \
	-Wl,-sectcreate,__TEXT,__entitlements,"$TMP/scratch-icloud/entitlements.plist"
lipo -create "$TMP/simulator-mixed/arm64" "$TMP/simulator-mixed/x86_64" -output "$mixed/MyApp"
codesign -s - -f "$mixed" 2>/dev/null
expect "a simulator build whose slices disagree fails" 1 "${SCRATCH_APP[@]}" "$mixed"

no_section="$TMP/simulator-no-section/MyApp.app"
mkdir -p "$no_section"
cp "$scratch/Contents/Info.plist" "$no_section/Info.plist"
plutil -insert DTPlatformName -string iphonesimulator "$no_section/Info.plist"
cp /usr/bin/true "$no_section/MyApp"
codesign -s - -f "$no_section" 2>/dev/null
expect "a simulator build with no entitlements section fails" 1 --prefix MyApp "$no_section"

# An iOS-layout bundle that does not say which platform it is for is
# refused, rather than read as a device build with no entitlements.
no_platform="$TMP/no-platform/MyApp.app"
mkdir -p "$no_platform"
cp "$TMP/simulator-scratch/MyApp.app/MyApp" "$no_platform/MyApp"
cp "$scratch/Contents/Info.plist" "$no_platform/Info.plist"
codesign -s - -f "$no_platform" 2>/dev/null
expect "an iOS bundle without DTPlatformName fails" 1 --prefix MyApp "$no_platform"

echo "$PASSED passed, $FAILED failed"
[ $FAILED -eq 0 ]
