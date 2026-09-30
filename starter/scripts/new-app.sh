#!/usr/bin/env bash
#
# new-app.sh — turn a fresh copy of the template into a named app, in one pass.
#
# Usage:
#   scripts/new-app.sh --list
#   scripts/new-app.sh NewName --with <practices> [--display "Display Name"] [--bundle-id id]
#
#   NewName        a Swift identifier, capitalised: the package (NewNameKit),
#                  the executable (NewNameMac) and NewName.app.
#   --with         the project practices to adopt, comma-separated, or `all`
#                  or `none`. Required: it is a choice, so make it. `--list`
#                  says what each one is; practices/README.md says why.
#   --display      what the Dock, the menu bar and the window title say.
#                  Defaults to NewName.
#   --bundle-id    defaults to com.example.<newname>.
#
# Run it once, from the repo root, before the first build. It rewrites every
# text file, renames files and directories to match, adds the chosen
# practices to AGENTS.md, removes build output (whose cached paths would be
# stale), and deletes practices/ and itself.
set -euo pipefail

usage() { sed -n '3,22p' "$0" >&2; exit 2; }

[ -d practices ] && [ -d Packages/StarterKit ] || {
	echo "✗ run this from the root of an unused copy of the template" >&2
	exit 1
}
command -v uvx >/dev/null 2>&1 || {
	echo "✗ uv is needed to restore the files imported from app-tooling (brew install uv)" >&2
	exit 1
}
available=$(cd practices && for d in */; do echo "${d%/}"; done)

if [ "${1:-}" = "--list" ]; then
	for practice in $available; do
		printf '%-20s %s\n' "$practice" "$(cat "practices/$practice/summary")"
	done
	exit 0
fi

[ $# -ge 1 ] || usage
NAME="$1"
shift
WITH=""
APP_DISPLAY=""
BUNDLE_ID=""
while [ $# -gt 0 ]; do
	case "$1" in
	--with) WITH="${2:?}"; shift 2 ;;
	--display) APP_DISPLAY="${2:?}"; shift 2 ;;
	--bundle-id) BUNDLE_ID="${2:?}"; shift 2 ;;
	*) usage ;;
	esac
done

[[ "$NAME" =~ ^[A-Z][A-Za-z0-9]*$ ]] || {
	echo "✗ '$NAME' must be a capitalised Swift identifier: letters and digits, starting A-Z" >&2
	exit 2
}
LOWER="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]')"
CAMEL="$(printf '%s' "${NAME:0:1}" | tr '[:upper:]' '[:lower:]')${NAME:1}"
APP_DISPLAY="${APP_DISPLAY:-$NAME}"
BUNDLE_ID="${BUNDLE_ID:-com.example.$LOWER}"
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || {
	echo "✗ '$BUNDLE_ID' is not a reverse-DNS bundle id" >&2
	exit 2
}

case "$WITH" in
"") echo "✗ choose practices with --with (a list, 'all' or 'none'); see --list" >&2; exit 2 ;;
all) chosen="$available" ;;
none) chosen="" ;;
*) chosen="$(printf '%s' "$WITH" | tr ',' ' ')" ;;
esac
for practice in $chosen; do
	[ -d "practices/$practice" ] || {
		echo "✗ no practice '$practice'; known: $(echo $available)" >&2
		exit 2
	}
done

rm -rf build .build dist Packages/*/.build Packages/*/.swiftpm

# Practices: each adds its section to AGENTS.md, in place of the marker, and
# copies its files in. Done before renaming, so their text is renamed too.
sections=""
for practice in $chosen; do
	sections="$sections$(cat "practices/$practice/agents.md")"$'\n\n'
	if [ -d "practices/$practice/files" ]; then cp -R "practices/$practice/files/." .; fi
done
SECTIONS="$sections" perl -0pi -e 's/<!-- practices -->\n/$ENV{SECTIONS}/' AGENTS.md
perl -0pi -e 's/\n+\z/\n/' AGENTS.md
rm -rf practices

# Contents. Most specific first, so the bundle id and the display name are
# replaced before the plain name inside them is:
#   org.example.starter  → the bundle id
#   Starter App          → the display name
#   Starter              → NewName
#   starterSomething     → newNameSomething (Swift identifiers)
#   starter              → newname (paths, the notary profile)
export NAME APP_DISPLAY LOWER CAMEL BUNDLE_ID
find . -type f -not -path './.git/*' -not -name new-app.sh -print0 |
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

# The renaming above also rewrote files imported from app-tooling (its docs
# say "starter"). Put them back as peru.yaml's rev has them, which also
# checks that the copy is complete.
uvx peru@1.3.5 sync --force --quiet

rm -- "$0"

echo "✓ created $NAME (\"$APP_DISPLAY\", $BUNDLE_ID)"
echo "  practices: $(echo ${chosen:-none})"
echo "  next: make check && make test && make run"
echo "  then work through 'Making it yours' in README.md and delete it"
