#!/usr/bin/env bash
#
# testflight.sh — archive the iOS app from a clean commit, check the archive,
# and send it to App Store Connect: validated only, or uploaded to TestFlight.
#
# Imported by peru from the app-tooling pattern `testflight`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/testflight/ says what it is for.
#
# Usage:
#   scripts/testflight.sh validate   # App Store Connect checks it; nothing is uploaded
#   scripts/testflight.sh upload     # upload to TestFlight
#
# Configured through the environment; mk/testflight.mk sets these from the
# project's make variables:
#   TESTFLIGHT_PROJECT        the .xcodeproj to archive
#   TESTFLIGHT_SCHEME         its app scheme
#   TESTFLIGHT_TEAM           the team id to sign and upload as
#   TESTFLIGHT_BRANCH         the one branch builds go up from (default: main)
#   TESTFLIGHT_XCODE_FLAGS    extra xcodebuild flags, e.g. the project's pins
#   TESTFLIGHT_INTERNAL_ONLY  YES marks uploads for internal testers only
#                             (default: NO)
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID
#                             an App Store Connect API key, all three or
#                             none; without them, the Apple account signed
#                             into Xcode is used
#
# Requires the app-tooling pattern `git-commit-stamp`: the build number is
# the commit count it stamps, which is why the tree must be clean and the
# branch fixed.
set -euo pipefail

die() { echo "✗ $*" >&2; exit 1; }

ACTION="${1:-}"
case "$ACTION" in
validate) METHOD=validation ;;
upload) METHOD=app-store-connect ;;
*) die "usage: testflight.sh validate|upload" ;;
esac
: "${TESTFLIGHT_PROJECT:?set TESTFLIGHT_PROJECT}"
: "${TESTFLIGHT_SCHEME:?set TESTFLIGHT_SCHEME}"
: "${TESTFLIGHT_TEAM:?set TESTFLIGHT_TEAM}"
BRANCH="${TESTFLIGHT_BRANCH:-main}"
INTERNAL_ONLY="${TESTFLIGHT_INTERNAL_ONLY:-NO}"

# ---------------------------------------------------------------------------
# A build of a commit, from the branch whose counts rise
# ---------------------------------------------------------------------------
[ -z "$(git status --porcelain)" ] ||
	die "commit or stash first: a TestFlight build is a build of a commit, and a dirty tree would be stamped <count>.1"
CURRENT="$(git symbolic-ref --short -q HEAD || echo "a detached HEAD")"
[ "$CURRENT" = "$BRANCH" ] ||
	die "on $CURRENT, not $BRANCH: build numbers are commit counts, which only rise along one branch (TESTFLIGHT_BRANCH names it)"

COMMIT="$(git rev-parse --short=12 HEAD)"
OUT=build/testflight
ARCHIVE="$OUT/$TESTFLIGHT_SCHEME-$COMMIT.xcarchive"
mkdir -p "$OUT"
rm -rf "$ARCHIVE"

echo "→ archiving $TESTFLIGHT_SCHEME at $COMMIT (Release)"
# TESTFLIGHT_XCODE_FLAGS is split into words on purpose.
# shellcheck disable=SC2086
xcodebuild archive -project "$TESTFLIGHT_PROJECT" -scheme "$TESTFLIGHT_SCHEME" \
	-configuration Release -destination 'generic/platform=iOS' \
	-archivePath "$ARCHIVE" -allowProvisioningUpdates \
	${TESTFLIGHT_XCODE_FLAGS:-} >"$OUT/archive-$COMMIT.log" 2>&1 ||
	{ tail -20 "$OUT/archive-$COMMIT.log" >&2; die "archive failed; the whole log is $OUT/archive-$COMMIT.log"; }

# ---------------------------------------------------------------------------
# Check what was archived, before anything leaves the machine
# ---------------------------------------------------------------------------
APP="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' | head -1)"
[ -n "$APP" ] || die "no .app in $ARCHIVE"
PLIST="$APP/Info.plist"

VERSION="$(plutil -extract CFBundleVersion raw "$PLIST")"
[[ "$VERSION" =~ ^[0-9]+\.0$ ]] ||
	die "CFBundleVersion is '$VERSION', not <count>.0: the git-commit-stamp build phase did not run, or saw a dirty tree"
STAMP="$(plutil -extract AppGitCommit raw "$PLIST" 2>/dev/null || echo missing)"
[ "$STAMP" = "$COMMIT" ] || die "AppGitCommit is '$STAMP', not $COMMIT"
SHORT="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "$PLIST")"

plutil -extract ITSAppUsesNonExemptEncryption raw "$PLIST" >/dev/null 2>&1 ||
	die "ITSAppUsesNonExemptEncryption is not set. Whether the app uses non-exempt encryption is a legal declaration for the app's owner to make; docs/app-tooling/testflight/apply.md says how to record it"

if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q 'icloud-container-identifiers'; then
	echo "  note: this app uses iCloud, and a TestFlight build uses the Production environment"
	echo "        (docs/app-tooling/testflight/README.md, \"iCloud and CloudKit\")"
fi

# ---------------------------------------------------------------------------
# Export: validation, or upload
# ---------------------------------------------------------------------------
OPTIONS="$OUT/ExportOptions-$ACTION.plist"
plutil -create xml1 "$OPTIONS"
plutil -insert method -string "$METHOD" "$OPTIONS"
plutil -insert destination -string upload "$OPTIONS"
plutil -insert teamID -string "$TESTFLIGHT_TEAM" "$OPTIONS"
plutil -insert signingStyle -string automatic "$OPTIONS"
# The build number is the stamp's; Xcode must not replace it.
plutil -insert manageAppVersionAndBuildNumber -bool NO "$OPTIONS"
if [ "$ACTION" = upload ]; then
	plutil -insert testFlightInternalTestingOnly -bool "$INTERNAL_ONLY" "$OPTIONS"
fi

AUTH=()
if [ -n "${ASC_KEY_PATH:-}${ASC_KEY_ID:-}${ASC_ISSUER_ID:-}" ]; then
	: "${ASC_KEY_PATH:?set all three of ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID, or none}"
	: "${ASC_KEY_ID:?set all three of ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID, or none}"
	: "${ASC_ISSUER_ID:?set all three of ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID, or none}"
	AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID"
		-authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

echo "→ ${ACTION} $BUNDLE_ID $SHORT ($VERSION, $COMMIT)"
LOG="$OUT/$ACTION-$COMMIT.log"
MARK="$OUT/.export-started"
touch "$MARK"
# ${AUTH[@]+…}: an empty array is an unbound variable to bash 3.2 under set -u.
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
	-exportPath "$OUT/$ACTION-$COMMIT" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} >"$LOG" 2>&1; then
	grep -E '^error:' "$LOG" >&2 || tail -5 "$LOG" >&2
	# xcodebuild's own message is often only "Error Downloading App
	# Information"; the reason is in the distribution logs it leaves.
	if find "${TMPDIR:-/tmp}" -maxdepth 1 -name '*.xcdistributionlogs' -newer "$MARK" -print0 2>/dev/null |
		xargs -0 -I{} grep -rqs 'missingApp' {}; then
		echo "  App Store Connect has no app with the bundle id $BUNDLE_ID: create it there first" >&2
		echo "  (docs/app-tooling/testflight/apply.md, \"One-time setup\")." >&2
	fi
	die "$ACTION failed; the whole log is $LOG"
fi

if [ "$ACTION" = validate ]; then
	echo "✓ App Store Connect accepts $BUNDLE_ID $SHORT ($VERSION, $COMMIT); nothing was uploaded"
else
	echo "✓ uploaded $BUNDLE_ID $SHORT ($VERSION, $COMMIT)"
	echo "  It reaches TestFlight once App Store Connect has processed it, usually within minutes."
fi
