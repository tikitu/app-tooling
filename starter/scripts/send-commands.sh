#!/usr/bin/env bash
#
# send-commands.sh — drive the running app with commands, without clicks and
# without taking focus. See docs/commands.md for the command format.
#
# Usage:
#   scripts/send-commands.sh '<json>'      # needs the app started by `make run-scratch`
#   scripts/send-commands.sh @file.json
#
# Prints the app's result.json; exits non-zero if a command failed or no
# result arrived. The sending is app-tooling's (command-inbox), in
# scripts/command-inbox-send.sh; this fills in the app's values, which the
# Makefile's run-scratch and the entitlements must agree with.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/scripts/command-inbox-send.sh" \
	--notification org.example.starter.commands \
	--dir "$HOME/Library/Caches/Starter-scratch/Commands" \
	--process "$ROOT/build/Starter.app/Contents/MacOS/StarterMac.*--commands" \
	"$@"
