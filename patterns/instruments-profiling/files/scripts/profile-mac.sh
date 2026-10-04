#!/bin/zsh
#
# profile-mac.sh — record an Instruments trace of a Mac app with no one at the
# keyboard: a copy of the app, a copy of its data, a scenario, and a check
# afterwards that the trace is of the process it meant to trace.
#
# Imported by peru from the app-tooling pattern `instruments-profiling`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/instruments-profiling/ says how to use it and how to read
# what it records.
#
# Usage:
#   scripts/profile-mac.sh TEMPLATE [SCENARIO] [--app PATH] [--data FILE]
#       [--out DIR] [--time-limit 30s] [--option-file JSON] [--allow-network]
#       [--start-timeout S] [--stop-timeout S] [--scenario-timeout S]
#
# TEMPLATE  any `xcrun xctrace list templates` name: "Animation Hitches",
#           "Time Profiler", "SwiftUI", "Allocations", "Leaks", ...
# SCENARIO  one the project defines in profiling.conf.zsh (`scenario_NAME`);
#           default `idle`: launch and wait.
# --app     profile this build instead of the configured one, e.g. a build
#           from another worktree, to compare before and after.
# --data    copy this file instead of the real data, e.g. a frozen copy so
#           that every run of a comparison reads the same rows.
#
# Everything about the app comes from the project's own profiling.conf.zsh
# ($PROFILING_CONF to use another): which build, where its real data is and
# how to copy it, how to point the app at the copy, and its scenarios. The
# guide, docs/app-tooling/instruments-profiling/guide.md, lists the keys.
#
# What it guarantees, because each of these has gone wrong once:
#
# * The real data is never handed to the app. It is copied, the app is
#   launched pointed at the copy, and once the app is running, `lsof` must
#   show it does not have the real file open: a redirect that silently did
#   not take is caught, not trusted.
# * A build that can sync is refused (REFUSE_ENTITLEMENTS, by default iCloud):
#   given a copy of real data, it would upload it.
# * The traced binary is the one named. xctrace resolves an `.app` argument
#   through LaunchServices, which can pick another copy with the same bundle
#   id, so this launches the executable inside the bundle, and afterwards
#   checks the launched process's path in the trace.
# * Nothing else distorts it: another recording (which also holds the
#   system's kperf lock), or another copy of the app unless the project allows
#   that (ALLOW_OTHER_COPIES), refuses the run. So does a nearly full disk.
# * Network is refused unless --allow-network: it captures all HTTP traffic on
#   the Mac, unencrypted, into the trace and the system log, and --no-prompt
#   (passed below) would otherwise accept that warning silently.
# * xctrace's multi-gigabyte staging file in $TMPDIR, which it never removes,
#   is removed once the trace is saved.
#
# The app is a copy re-signed ad hoc with get-task-allow added to its own
# entitlements, which Allocations and Leaks need to attach. They also need
# the Instruments authorization right: a password dialog the first time in
# ~10 hours. Headless, the recording just waits; --start-timeout says so.
set -euo pipefail
zmodload zsh/datetime  # EPOCHREALTIME

ROOT=${0:A:h:h}
CONF=${PROFILING_CONF:-$ROOT/profiling.conf.zsh}
WORK=$ROOT/build/profile
DRIVER=$ROOT/build/ui-drive

# --- the project's settings ----------------------------------------------------
APP_BUNDLE=""
BUILD_HINT="build it first"
REAL_DATA=""
DATA_NAME=""
LAUNCH_ENV=()
LAUNCH_ARGS=()
REFUSE_ENTITLEMENTS='icloud|ubiquity'
ALLOW_OTHER_COPIES=0
MIN_FREE_GB=10
SCENARIO_NOTIFY_PREFIX=""
SETTLE_SECONDS=2
copy_data() { sqlite3 "$1" ".backup '$2'"; }
describe_data() { echo "$(du -h "$1" | cut -f1)"; }
[[ -f $CONF ]] || { echo "✗ no $CONF: copy the example from docs/app-tooling/instruments-profiling/guide.md" >&2; exit 1; }
source $CONF
[[ -n $APP_BUNDLE ]] || { echo "✗ $CONF sets no APP_BUNDLE" >&2; exit 1; }
SRC_APP=${APP_BUNDLE:A}
[[ $APP_BUNDLE == /* ]] || SRC_APP=${ROOT}/${APP_BUNDLE}

template=${1:?usage: profile-mac.sh TEMPLATE [SCENARIO] [options]}
shift
scenario=idle
if [[ $# -gt 0 && $1 != --* ]]; then scenario=$1; shift; fi
time_limit=""
out_dir=$WORK/traces
data=""
option_file=""
start_timeout=45
stop_timeout=180
scenario_timeout=300
allow_network=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --app) SRC_APP=${2:A}; shift 2 ;;
    --data) data=$2; shift 2 ;;
    --out) out_dir=$2; shift 2 ;;
    --time-limit) time_limit=$2; shift 2 ;;
    --option-file) option_file=$2; shift 2 ;;
    --start-timeout) start_timeout=$2; shift 2 ;;
    --stop-timeout) stop_timeout=$2; shift 2 ;;
    --scenario-timeout) scenario_timeout=$2; shift 2 ;;
    --allow-network) allow_network=1; shift ;;
    *) echo "✗ unknown option $1" >&2; exit 2 ;;
  esac
done

if [[ $allow_network != 1 ]] && { [[ $template == *Network* ]] ||
    { [[ -n $option_file ]] && grep -q -i network "$option_file"; }; }; then
  echo "✗ Network records all HTTP traffic on this Mac, unencrypted. It is off unless" >&2
  echo "  the user has opted in for this session: --allow-network" >&2
  exit 2
fi

# --- the scenario's definition ----------------------------------------------------
# scenario_NAME (in profiling.conf.zsh) sets scenario_args (extra launch
# arguments), scenario_notifies=1 if the app itself posts
# $SCENARIO_NOTIFY_PREFIX.started and .done, and may define `drive`: what to
# do once the scenario has started, with $PID and $DRIVER.
scenario_args=()
scenario_notifies=0
unfunction drive 2>/dev/null || true
if (( $+functions[scenario_$scenario] )); then
  scenario_$scenario
elif [[ $scenario != idle ]]; then
  echo "✗ no scenario_$scenario in $CONF" >&2; exit 2
fi
if (( scenario_notifies )) && [[ -z $SCENARIO_NOTIFY_PREFIX ]]; then
  echo "✗ scenario $scenario waits for notifications but $CONF sets no SCENARIO_NOTIFY_PREFIX" >&2; exit 2
fi

# --- the app ----------------------------------------------------------------------
[[ -d $SRC_APP ]] || { echo "✗ $SRC_APP missing: $BUILD_HINT" >&2; exit 1; }
if [[ -n $REFUSE_ENTITLEMENTS ]] &&
    codesign -d --entitlements - "$SRC_APP" 2>/dev/null | grep -q -i -E "$REFUSE_ENTITLEMENTS"; then
  echo "✗ $SRC_APP carries entitlements matching '$REFUSE_ENTITLEMENTS': a build that can" >&2
  echo "  sync would send whatever data it is given. Profile one that cannot." >&2
  exit 1
fi
APP_NAME=${SRC_APP:t}
EXE_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$SRC_APP/Contents/Info.plist")
APP=$WORK/$APP_NAME
EXE=$APP/Contents/MacOS/$EXE_NAME

# --- nothing else running -------------------------------------------------------
# Matched by name, not path: a copy started with a relative path has no
# absolute path in its command line.
others=(${(f)"$(pgrep -f 'xctrace record' || true)"})
if (( ! ALLOW_OTHER_COPIES )); then
  others+=(${(f)"$(pgrep -f "$APP_NAME/Contents/MacOS/$EXE_NAME" || true)"})
fi
if (( ${#others} )); then
  ps -o pid=,command= -p ${(j:,:)others} | cut -c1-120 >&2
  echo "✗ these are running and would distort the measurement (or, for a recording," >&2
  echo "  hold the kperf lock); stop them first" >&2
  exit 1
fi

# --- room for the trace -----------------------------------------------------------
mkdir -p $WORK "$out_dir"
free_gb=$(df -g "$out_dir" | awk 'NR==2 {print $4}')
if (( free_gb < MIN_FREE_GB )); then
  echo "✗ only ${free_gb} GB free on the disk holding $out_dir; delete old traces first" >&2
  exit 1
fi

# --- a copy of the app, able to be attached to -------------------------------------
# get-task-allow added to the app's own entitlements, not replacing them: a
# sandboxed app re-signed without its sandbox would keep its data elsewhere.
rm -rf $APP
cp -R "$SRC_APP" $APP
ENTITLEMENTS=$WORK/profiling.entitlements
codesign -d --entitlements - --xml "$SRC_APP" > $ENTITLEMENTS 2>/dev/null || true
if [[ ! -s $ENTITLEMENTS ]]; then
  plutil -create xml1 $ENTITLEMENTS
fi
/usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' $ENTITLEMENTS 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :com.apple.security.get-task-allow bool true' $ENTITLEMENTS
codesign --force --sign - --entitlements $ENTITLEMENTS $APP 2>/dev/null

# --- a copy of the data, never the data itself -------------------------------------
DATA=""
if [[ -n $REAL_DATA || -n $data ]]; then
  source_data=${data:-$REAL_DATA}
  [[ -e $source_data ]] || { echo "✗ no data at $source_data" >&2; exit 1; }
  rm -rf $WORK/data
  mkdir -p $WORK/data
  DATA=$WORK/data/${DATA_NAME:-${REAL_DATA:t}}
  [[ -n ${DATA:t} ]] || DATA=$WORK/data/${source_data:t}
  if [[ -n $REAL_DATA && ${DATA:A} == ${REAL_DATA:A} ]]; then
    echo "✗ refusing: the copy's path is the real data's" >&2; exit 1
  fi
  copy_data "$source_data" "$DATA"
  echo "→ data: $(describe_data "$DATA"), copied to $DATA"
fi
# {DATA} in LAUNCH_ENV and LAUNCH_ARGS is the copy.
launch_env=()
for e in $LAUNCH_ENV; do
  [[ $e == *'{DATA}'* && -z $DATA ]] && { echo "✗ LAUNCH_ENV uses {DATA} but there is no data to copy" >&2; exit 1; }
  launch_env+=(--env "${e//\{DATA\}/$DATA}")
done
launch_args=()
for a in $LAUNCH_ARGS $scenario_args; do
  [[ $a == *'{DATA}'* && -z $DATA ]] && { echo "✗ LAUNCH_ARGS uses {DATA} but there is no data to copy" >&2; exit 1; }
  launch_args+=("${a//\{DATA\}/$DATA}")
done

# The real data must not be open in the app: proof that the redirect took,
# rather than trust in the settings.
holds_real_data() {
  [[ -n $REAL_DATA && -n ${1:-} ]] || return 1
  lsof -p $1 -Fn 2>/dev/null | grep -q -F "n${REAL_DATA:A}"
}

# --- the driver -------------------------------------------------------------------
if (( $+functions[drive] )) && [[ ! -x $DRIVER || $ROOT/scripts/ui-drive.swift -nt $DRIVER ]]; then
  swiftc -O $ROOT/scripts/ui-drive.swift -o $DRIVER
fi

# `|| true`: under `set -e` and `pipefail` a pgrep that finds nothing would
# end the script before it could say the app did not start.
app_pid() { pgrep -f "^$EXE" | head -1 || true; }

# One Darwin notification, waited for in the background; `wait_for PID S`
# returns once it has come, or fails after S seconds.
listen() { notifyutil -1 $1 >/dev/null & echo $!; }
wait_for() {
  for _ in $(seq 1 $(( $2 * 10 ))); do kill -0 $1 2>/dev/null || return 0; sleep 0.1; done
  kill $1 2>/dev/null; return 1
}

# --- record -----------------------------------------------------------------------
NOTIFICATION=app-tooling.profile-mac.started.$$
stamp=$(date +%Y%m%d-%H%M%S)
trace=$out_dir/${template// /_}-$scenario-$stamp.trace
args=(record --template "$template" --output "$trace" $launch_env
      --notify-tracing-started $NOTIFICATION --no-prompt)
[[ -n $time_limit ]] && args+=(--time-limit $time_limit)
[[ -n $option_file ]] && args+=(--recording-options $option_file)

# xctrace stages each recording in a multi-gigabyte instruments*.ktrace in
# $TMPDIR and never removes it; the saved .trace does not need it. Note what
# is there now, so the files this run adds can go afterwards.
ktrace_before=(${TMPDIR:-/tmp}/instruments*.ktrace(N))

scenario_started=0
scenario_done=0
if (( scenario_notifies )); then
  scenario_started=$(listen $SCENARIO_NOTIFY_PREFIX.started)
  scenario_done=$(listen $SCENARIO_NOTIFY_PREFIX.done)
fi
waiter=$(listen $NOTIFICATION)
echo "→ xctrace $template, scenario $scenario"
xcrun xctrace "${args[@]}" --launch -- $EXE $launch_args > $WORK/xctrace.log 2>&1 &
recorder=$!

listeners() { print -r -- $waiter $scenario_started $scenario_done | tr ' ' '\n' | grep -v '^0$' || true; }
cleanup() {
  kill -INT $recorder 2>/dev/null || true
  kill $(listeners) 2>/dev/null || true
  pkill -f "^$EXE" 2>/dev/null || true
  # A recorder still saving holds kperf, and the next run would fail with
  # "could not lock kperf"; wait for it to let go.
  for _ in $(seq 1 $stop_timeout); do kill -0 $recorder 2>/dev/null || break; sleep 1; done
  # A target whose recorder was killed while stopping ignores SIGTERM.
  sleep 1
  pkill -9 -f "^$EXE" 2>/dev/null || true
}
trap cleanup EXIT

started=0
for _ in $(seq 1 $start_timeout); do
  if ! kill -0 $waiter 2>/dev/null; then started=1; t0=$EPOCHREALTIME; break; fi
  kill -0 $recorder 2>/dev/null || break
  sleep 1
done
if [[ $started != 1 ]]; then
  cat $WORK/xctrace.log >&2
  echo "✗ recording did not start within ${start_timeout}s. If the template needs" >&2
  echo "  Allocations or Leaks, a password dialog is probably waiting on screen." >&2
  exit 1
fi

since=""
if [[ -z $time_limit ]]; then
  if (( scenario_notifies )); then
    wait_for $scenario_started 60 || { echo "✗ the app did not start its scenario" >&2; exit 1; }
  else
    sleep $SETTLE_SECONDS
  fi
  PID=$(app_pid)
  [[ -n $PID ]] || { cat $WORK/xctrace.log >&2; echo "✗ app did not start" >&2; exit 1; }
  if holds_real_data $PID; then
    echo "✗ the app has the real data open (${REAL_DATA}): the redirect in $CONF did not take" >&2
    exit 1
  fi
  since=$(( EPOCHREALTIME - t0 ))
  if (( $+functions[drive] )); then
    drive
  elif (( scenario_notifies )); then
    wait_for $scenario_done $scenario_timeout || { echo "✗ the scenario did not finish" >&2; exit 1; }
  else
    sleep 5
  fi
  until_=$(( EPOCHREALTIME - t0 + 0.2 ))
  if holds_real_data $PID; then
    echo "✗ the app opened the real data (${REAL_DATA}) during the run" >&2
    exit 1
  fi
  sleep 1
  kill -INT $recorder
fi

# Saving is not hanging: a big trace can take minutes to save, so the clock
# only runs until saving starts. xctrace has been seen to hang for good at
# "Stopping recording..."; give up rather than wait forever.
waited=0
while kill -0 $recorder 2>/dev/null && (( waited < stop_timeout )); do
  grep -q 'Saving output file' $WORK/xctrace.log || waited=$((waited + 1))
  sleep 1
done
if kill -0 $recorder 2>/dev/null; then
  kill -9 $recorder 2>/dev/null || true
  cat $WORK/xctrace.log >&2
  echo "✗ xctrace did not finish stopping within ${stop_timeout}s; the trace is lost. Run it again." >&2
  exit 1
fi
wait $recorder || true   # 54 is xctrace's normal "target ended" status
trap - EXIT
pkill -f "^$EXE" 2>/dev/null || true
# The listeners too: one left running holds the caller's pipe open
# (`profile-mac.sh … | tail`).
kill $(listeners) 2>/dev/null || true

# Remove the staging files this run added. The instruments service keeps
# its file open for ~45 s after the trace is saved, so wait (up to 90 s); a
# file still open after that, another recording's perhaps, is left alone.
added=()
for f in ${TMPDIR:-/tmp}/instruments*.ktrace(N); do
  (( ${ktrace_before[(Ie)$f]} )) || added+=($f)
done
if (( ${#added} )); then
  echo "→ waiting for instruments to release ${#added} staging file(s) to delete"
  for _ in $(seq 1 45); do
    open=0
    for f in $added; do lsof "$f" >/dev/null 2>&1 && open=1; done
    (( open )) || break
    sleep 2
  done
  for f in $added; do lsof "$f" >/dev/null 2>&1 || rm -f "$f"; done
fi

grep -E '\[Error\]|failed' $WORK/xctrace.log >&2 || true
[[ -d $trace ]] || { cat $WORK/xctrace.log >&2; echo "✗ no trace written" >&2; exit 1; }
# The launched process's own path, by pid: some templates list every process
# on the Mac, which can include another running copy of the app. Attribute
# order varies: with launch arguments, `arguments=` comes before `type=`.
toc=$(xcrun xctrace export --input $trace --toc)
target=$(grep -o '<process [^>]*type="launched"[^>]*>' <<<$toc | grep -o ' pid="[0-9]*"' | head -1 | tr -d ' ' || true)
traced=$(grep -o "<process name=\"[^\"]*\" $target path=\"[^\"]*\"" <<<$toc | grep -o 'path="[^"]*"' | head -1 || true)
if [[ -z $target || $traced != "path=\"$EXE\"" ]]; then
  echo "✗ the trace is not of $EXE: launched ${target:-?}, ${traced:-no path}" >&2
  exit 1
fi
# The scenario's stretch of the trace, in seconds from the start of
# recording, for trace-query.py --since/--until and trace-compare.py.
[[ -n $since ]] && printf '%.1f %.1f\n' $since $until_ > ${trace%.trace}.window
echo "✓ $trace${since:+ (scenario $(cat ${trace%.trace}.window) s)}"
