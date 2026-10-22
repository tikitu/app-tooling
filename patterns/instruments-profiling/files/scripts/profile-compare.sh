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
#       [--instruments "A,B"] [--out DIR] [--scenarios "a b"] [--warmup]
#       NAME=APP [NAME=APP ...]
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
#
# --template and --instruments go to profile-mac.sh. On a busy Mac, or for
# many rounds, --template Blank --instruments "Hangs,Points of Interest,Time
# Profiler" stages megabytes a run where Animation Hitches stages gigabytes;
# it records no hitches.
#
# A run that fails is reported and the comparison goes on. It fails as a
# whole when a build has no trace for a scenario, since there is then nothing
# to compare, and stops at once when profile-mac.sh refuses to start
# (another recording, another copy of the app, a nearly full disk), since
# every run after it would be refused too.
set -euo pipefail

ROOT=${0:A:h:h}
CONF=${PROFILING_CONF:-$ROOT/profiling.conf.zsh}
COMPARE_SCENARIOS=(idle)
[[ -f $CONF ]] && source $CONF
rounds=3
template="Animation Hitches"
instruments=()
out=$ROOT/build/profile/compare
scenarios=($COMPARE_SCENARIOS)
data=""
warmup=0
builds=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --rounds) rounds=$2; shift 2 ;;
    --template) template=$2; shift 2 ;;
    --instruments) instruments=(--instruments "$2"); shift 2 ;;
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

runs=0
written=()   # NAME/SCENARIO of each measured run that wrote a trace
for round in $(seq $(( 1 - warmup )) $rounds); do
  dir=$out
  (( round == 0 )) && dir=$out-warmup
  for scenario in $scenarios; do
    for build in $builds; do
      name=${build%%=*}
      app=${build#*=}
      echo "== round $round/$rounds  $scenario  $name"
      # profile-mac.sh's last line says what happened; its status, whether
      # there is a trace (✓ and status 0, nothing else).
      st=0
      log=$($ROOT/scripts/profile-mac.sh "$template" $scenario --app $app --data $data \
        $instruments --out $dir/$name/$scenario 2>&1) || st=$?
      print -r -- ${log##*$'\n'}
      if (( st == 3 )); then
        echo "✗ profile-mac.sh refused to start (above); every run after it would be" >&2
        echo "  refused too, so the comparison stops here" >&2
        exit 1
      fi
      (( round == 0 )) && continue
      runs=$((runs + 1))
      (( st == 0 )) && written+=($name/$scenario)
    done
  done
  # The warm-up's traces are never read, and a round is gigabytes.
  if (( round == 0 )); then rm -rf -- "$out-warmup"; fi
done

missing=()
for scenario in $scenarios; do
  for build in $builds; do
    (( ${written[(Ie)${build%%=*}/$scenario]} )) || missing+=(${build%%=*}/$scenario)
  done
done
failed=$(( runs - ${#written} ))
if (( ${#missing} )); then
  echo "✗ $failed of $runs runs wrote no trace; nothing to compare for ${(j:, :)missing}" >&2
  exit 1
fi
echo "✓ $out — scripts/trace-compare.py $out${${failed:#0}:+ ($failed of $runs runs wrote no trace)}"
