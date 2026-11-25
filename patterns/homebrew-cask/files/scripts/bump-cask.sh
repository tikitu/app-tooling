#!/usr/bin/env bash
#
# bump-cask.sh — point a Homebrew cask at a published GitHub release: sets
# `version` and `sha256` in the cask in Homebrew's clone of the tap, checks
# that Homebrew can download it and that it matches, and commits. Pushing is
# left to you.
#
# Usage:
#   scripts/bump-cask.sh --repo <owner/repo> --tap <user/tap> --cask <name> \
#     --asset <zip file name> <version>
#
# `make bump-cask` passes all of these (mk/homebrew-cask.mk).
#
# Imported by peru from the app-tooling pattern `homebrew-cask`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/homebrew-cask/ says how to use it.
set -euo pipefail

usage() { sed -n '3,12p' "$0" >&2; exit 2; }

repo="" tap="" cask_name="" asset="" version=""
while [ $# -gt 0 ]; do
	case "$1" in
		--repo) repo="${2:-}"; shift 2 ;;
		--tap) tap="${2:-}"; shift 2 ;;
		--cask) cask_name="${2:-}"; shift 2 ;;
		--asset) asset="${2:-}"; shift 2 ;;
		-*) usage ;;
		*) [ -z "$version" ] || usage; version="$1"; shift ;;
	esac
done
[ -n "$repo" ] && [ -n "$tap" ] && [ -n "$cask_name" ] && [ -n "$asset" ] && [ -n "$version" ] || usage

tap_dir="$(brew --repository "$tap")"
cask="$tap_dir/Casks/$cask_name.rb"
[ -f "$cask" ] || { echo "✗ no $cask — brew tap $tap first" >&2; exit 1; }
if [ -n "$(git -C "$tap_dir" status --porcelain)" ]; then
	echo "✗ $tap_dir has uncommitted changes" >&2; exit 1
fi
git -C "$tap_dir" pull -q --ff-only

# The checksum of what was published, not of a local build: the cask has to
# match what Homebrew will download.
sha256="$(gh release download "v$version" --repo "$repo" --pattern "$asset.sha256" --output - 2>/dev/null | awk '{print $1}')" || true
[[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || { echo "✗ no $asset.sha256 on a release v$version of $repo: make github-release first" >&2; exit 1; }

sed -i '' -E \
	-e "s/^(  version )\"[^\"]*\"/\1\"$version\"/" \
	-e "s/^(  sha256 )\"[^\"]*\"/\1\"$sha256\"/" \
	"$cask"
if git -C "$tap_dir" diff --quiet; then
	echo "✓ the cask is already at $version"; exit 0
fi

# Downloads and checks the checksum, exactly as an install would. Homebrew 7
# refuses a cask from a tap that is not trusted: `brew trust --cask
# $tap/$cask_name` once per Mac. On failure, put the cask back rather than
# leave a half-made bump.
if ! HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_AUTO_UPDATE=1 brew fetch --force --cask "$tap/$cask_name"; then
	git -C "$tap_dir" checkout -- "Casks/$cask_name.rb"
	echo "✗ Homebrew could not fetch $version; the cask is unchanged" >&2
	echo "  (an untrusted tap? brew trust --cask $tap/$cask_name)" >&2
	exit 1
fi

git -C "$tap_dir" commit -q -m "$cask_name $version" -- "Casks/$cask_name.rb"
git -C "$tap_dir" show --stat --format='%h %s' HEAD
echo "✓ committed in $tap_dir. Check it, then: git -C \"$tap_dir\" push"
