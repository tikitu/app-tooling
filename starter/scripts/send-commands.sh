#!/usr/bin/env bash
#
# send-commands.sh — drive the running app with commands, without clicks and
# without taking focus. See plans/commands.md for the command format.
#
# Usage:
#   scripts/send-commands.sh '<json>'      # needs the app started by `make run-scratch`
#   scripts/send-commands.sh @file.json
#
# Prints the app's result.json; exits non-zero if a command failed or no
# result arrived.
set -euo pipefail

BUNDLE_ID="org.example.starter"
NOTIFICATION="org.example.starter.commands"
DIR="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/Commands"

[ $# -eq 1 ] || { sed -n '3,10p' "$0" >&2; exit 2; }

# The app only listens on its scratch data, so refuse rather than time out
# when it is running on the real data.
pgrep -f "StarterMac --scratch-database" >/dev/null || {
	echo "✗ the app is not running on its scratch data — run 'make run-scratch'" >&2
	exit 1
}

mkdir -p "$DIR"
rm -f "$DIR/result.json"
# Written aside and moved, so the app never reads half a file.
case "$1" in
@*) cat "${1#@}" >"$DIR/inbox.json.partial" ;;
*) printf '%s' "$1" >"$DIR/inbox.json.partial" ;;
esac
mv "$DIR/inbox.json.partial" "$DIR/inbox.json"
notifyutil -p "$NOTIFICATION"

for _ in $(seq 50); do
	if [ -f "$DIR/result.json" ]; then
		cat "$DIR/result.json"
		echo
		if grep -q '"error"' "$DIR/result.json"; then exit 1; fi
		exit 0
	fi
	sleep 0.2
done
echo "✗ no result after 10s — is the app running and accepting commands?" >&2
exit 1
