#!/bin/zsh
#
# profile-compare.sh — record the same scenarios against several builds,
# interleaved, for a before/after comparison that drift on the machine
# cannot fake.
#
# Imported by peru from the app-tooling pattern `instruments-profiling`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/instruments-profiling/guide.md describes the method.
#
# Usage:
#   scripts/profile-compare.sh --data FILE [--rounds 3] [--template T]
#       [--out DIR] [--scenarios "a b"] [--warmup] NAME=APP [NAME=APP ...]
#
#   e.g. scripts/profile-compare.sh --data build/profile/frozen/data.sqlite \
#          before=build/wt-before/build/MyApp.app \
#          after=build/wt-after/build/MyApp.app
#
# Every build sees every scenario once per round, in turn, so a slow minute
# lands on all of them. --data should be a frozen copy of the real data, so
# every build reads the same thing (profile-mac.sh copies it afresh for each
# run). --scenarios defaults to COMPARE_SCENARIOS in profiling.conf.zsh.
# Traces land in DIR/NAME/SCENARIO/; read them with scripts/trace-compare.py.
#
# --warmup runs every build's scenarios once first, unrecorded in the
# comparison: anything cached on first use (downloads, thumbnails, the file
# cache) is then warm for every measured round. Without it the first round
# can differ from the rest by more than the change being measured.
set -euo pipefail

ROOT=${0:A:h:h}
CONF=${PROFILING_CONF:-$ROOT/profiling.conf.zsh}
COMPARE_SCENARIOS=(idle)
[[ -f $CONF ]] && source $CONF
rounds=3
template="Animation Hitches"
out=$ROOT/build/profile/compare
scenarios=($COMPARE_SCENARIOS)
data=""
warmup=0
builds=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --rounds) rounds=$2; shift 2 ;;
    --template) template=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --scenarios) scenarios=(${=2}); shift 2 ;;
    --data) data=$2; shift 2 ;;
    --warmup) warmup=1; shift ;;
    *=*) builds+=($1); shift ;;
    *) echo "✗ unknown argument $1" >&2; exit 2 ;;
  esac
done
[[ -n $data ]] || { echo "✗ --data FILE: a frozen copy of the data" >&2; exit 2; }
(( ${#builds} >= 2 )) || { echo "✗ give at least two NAME=APP builds" >&2; exit 2; }

for round in $(seq $(( 1 - warmup )) $rounds); do
  dir=$out
  (( round == 0 )) && dir=$out-warmup
  for scenario in $scenarios; do
    for build in $builds; do
      name=${build%%=*}
      app=${build#*=}
      echo "== round $round/$rounds  $scenario  $name"
      # A failed run is reported and the comparison goes on; trace-compare.py
      # counts the runs it has for each build.
      $ROOT/scripts/profile-mac.sh "$template" $scenario --app $app --data $data \
        --out $dir/$name/$scenario 2>&1 | tail -1 || true
    done
  done
  # The warm-up's traces are never read, and a round is gigabytes.
  if (( round == 0 )); then rm -rf -- "$out-warmup"; fi
done
echo "✓ $out — scripts/trace-compare.py $out"
