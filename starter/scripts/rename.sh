#!/usr/bin/env bash
#
# rename.sh — turn a fresh copy of the template into a named app, in one pass.
#
# Usage:
#   scripts/rename.sh NewName ["Display Name"] [bundle.id]
#
#   NewName       a Swift identifier, capitalised: the package (NewNameKit),
#                 the executable (NewNameMac) and NewName.app.
#   Display Name  what the Dock, the menu bar and the window title say.
#                 Defaults to NewName.
#   bundle.id     defaults to com.example.<newname>.
#
# Run it once, from the repo root, before the first build. It rewrites every
# text file, renames files and directories to match, removes build output
# (whose cached paths would be stale) and deletes itself.
set -euo pipefail

[ $# -ge 1 ] && [ $# -le 3 ] || { sed -n '3,15p' "$0" >&2; exit 2; }

NAME="$1"
APP_DISPLAY="${2:-$NAME}"
LOWER="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]')"
CAMEL="$(printf '%s' "${NAME:0:1}" | tr '[:upper:]' '[:lower:]')${NAME:1}"
BUNDLE_ID="${3:-com.example.$LOWER}"

[[ "$NAME" =~ ^[A-Z][A-Za-z0-9]*$ ]] || {
	echo "✗ '$NAME' must be a capitalised Swift identifier: letters and digits, starting A-Z" >&2
	exit 2
}
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || {
	echo "✗ '$BUNDLE_ID' is not a reverse-DNS bundle id" >&2
	exit 2
}
[ -d Packages/StarterKit ] || {
	echo "✗ no Packages/StarterKit here — run this from the root of an unrenamed copy" >&2
	exit 1
}

rm -rf build .build dist Packages/StarterKit/.build Packages/StarterKit/.swiftpm

# Contents. Most specific first, so the bundle id and the display name are
# replaced before the plain name inside them is:
#   org.example.starter  → the bundle id
#   Starter App          → the display name
#   Starter              → NewName
#   starterSomething     → newNameSomething (Swift identifiers)
#   starter              → newname (paths, the notary profile)
export NAME APP_DISPLAY LOWER CAMEL BUNDLE_ID
find . -type f -not -path './.git/*' -not -name rename.sh -print0 |
	{ xargs -0 grep -lI -e 'Starter' -e 'starter' || true; } |
	while IFS= read -r file; do
		perl -pi -e '
			s/org\.example\.starter/$ENV{BUNDLE_ID}/g;
			s/Starter App/$ENV{APP_DISPLAY}/g;
			s/Starter/$ENV{NAME}/g;
			s/starter(?=[A-Z])/$ENV{CAMEL}/g;
			s/starter/$ENV{LOWER}/g;
		' "$file"
	done

# Paths, deepest first, so a directory is renamed after what is inside it.
find . -depth -name '*Starter*' -not -path './.git/*' | while IFS= read -r path; do
	dir="$(dirname "$path")"
	base="$(basename "$path")"
	mv "$path" "$dir/${base//Starter/$NAME}"
done

# A longer or shorter name moves line breaks; put them back where the
# formatter wants them, so `make lint` passes from the start.
swift format --configuration .swift-format --recursive --in-place Packages

rm -- "$0"

echo "✓ renamed to $NAME (\"$APP_DISPLAY\", $BUNDLE_ID)"
echo "  next: make check && make test && make run"
echo "  then work through PLAN.md §0 and delete it"
