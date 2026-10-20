#!/usr/bin/env bash
#
# stamp-sync-configuration.sh — say in a built app's Info.plist whether it may
# sync, and against which CloudKit environment, from the entitlements it is
# signed with.
#
# Imported by peru from the app-tooling pattern `sync-configuration`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/sync-configuration/ says how to use it.
#
# Usage: stamp-sync-configuration.sh <Info.plist> <prefix> [<iCloud entitlements>]
#
# With an entitlements file (the build will be signed with it):
#   <prefix>SyncEnabled          true
#   <prefix>CloudKitEnvironment  its com.apple.developer.icloud-container-environment
# Without one:
#   <prefix>SyncEnabled          false
#   <prefix>CloudKitEnvironment  removed
#
# Run it on the built Info.plist, before signing, with exactly the
# entitlements codesign will be given. The app reads these keys before
# touching CloudKit (CloudKitSyncConfiguration, in app-utils), because
# CKContainer(identifier:) traps for a container the app is not entitled to.
# Setting them here, from the same file, is what keeps them in agreement.
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
	echo "usage: $0 <Info.plist> <prefix> [<iCloud entitlements>]" >&2
	exit 2
fi
PLIST="$1"
PREFIX="$2"
ENTITLEMENTS="${3:-}"

if [ ! -f "$PLIST" ]; then
	echo "✗ stamp-sync-configuration: no Info.plist at $PLIST" >&2
	exit 1
fi

if [ -z "$ENTITLEMENTS" ]; then
	plutil -replace "${PREFIX}SyncEnabled" -bool false "$PLIST"
	plutil -remove "${PREFIX}CloudKitEnvironment" "$PLIST" 2>/dev/null || true
	echo "  stamped ${PREFIX}SyncEnabled=false"
	exit 0
fi

if [ ! -f "$ENTITLEMENTS" ]; then
	echo "✗ stamp-sync-configuration: no entitlements at $ENTITLEMENTS" >&2
	exit 1
fi
# Read out of the entitlements rather than passed in, so the two cannot
# disagree. PlistBuddy exits non-zero for a missing key.
ENVIRONMENT="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.icloud-container-environment' "$ENTITLEMENTS" 2>/dev/null)" || ENVIRONMENT=""
case "$ENVIRONMENT" in
	Development | Production) ;;
	*)
		echo "✗ stamp-sync-configuration: $ENTITLEMENTS names no CloudKit environment" >&2
		echo "  (com.apple.developer.icloud-container-environment: '$ENVIRONMENT')." >&2
		echo "  Pin it, so that every device of the app syncs against the same one." >&2
		exit 1
		;;
esac

plutil -replace "${PREFIX}SyncEnabled" -bool true "$PLIST"
plutil -replace "${PREFIX}CloudKitEnvironment" -string "$ENVIRONMENT" "$PLIST"
echo "  stamped ${PREFIX}SyncEnabled=true ${PREFIX}CloudKitEnvironment=$ENVIRONMENT"
