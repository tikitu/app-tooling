#!/bin/zsh
#
# Regression tests for the instruments-profiling scripts, without Instruments:
# a stub `xcrun` serves the exports from fixtures/, and a stub profile-mac.sh
# stands in for recording. Each case is a failure that once passed silently.
#
#   patterns/instruments-profiling/tests/run.sh
#
# Not imported into projects (only files/ is).
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1   # no __pycache__ in files/

HERE=${0:A:h}
SCRIPTS=${HERE:h}/files/scripts
FIXTURES=$HERE/fixtures
WORK=$(mktemp -d "${TMPDIR:-/tmp}/instruments-profiling-tests.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
failures=0

pass() { print -r -- "✓ $1"; }
fail() { print -r -- "✗ $1"; shift; (( $# )) && print -rl -- "    "${^@}; failures=$((failures + 1)); }

# --- a stub xcrun ---------------------------------------------------------------
# `xctrace export --toc` prints fixtures/toc.xml; `--xpath …schema="S"…` prints
# fixtures/S.xml. A table with no fixture is exported as xctrace does when the
# export itself fails: nothing on stdout, a message on stderr, status 1
# (MISSING=fail, the default), or as an empty result (MISSING=empty).
mkdir -p $WORK/bin
cat > $WORK/bin/xcrun <<EOF
#!/bin/zsh
fixtures=$FIXTURES
EOF
cat >> $WORK/bin/xcrun <<'EOF'
[[ $1 == xctrace && $2 == export ]] || { echo "stub xcrun: unexpected $*" >&2; exit 2; }
if [[ $* == *--toc* ]]; then cat $fixtures/toc.xml; exit; fi
args="$*"
schema=${${args#*schema=\"}%%\"*}
if [[ -f $fixtures/$schema.xml ]]; then cat $fixtures/$schema.xml; exit; fi
if [[ ${MISSING:-fail} == empty ]]; then
  printf '<?xml version="1.0"?>\n<trace-query-result>\n</trace-query-result>\n'
  exit 0
fi
echo "Export failed: no table matching the xpath" >&2
exit 1
EOF
chmod +x $WORK/bin/xcrun
export PATH=$WORK/bin:$PATH

# A trace directory is all trace-compare.py looks for; the stub ignores it.
mkdir -p $WORK/compare/{before,after}/idle/x.trace

# --- trace-query.py profile: a sample with an empty stack -------------------------
out=$(python3 $SCRIPTS/trace-query.py profile $WORK/compare/before/idle/x.trace --top 3 2>&1)
st=$?
if (( st == 0 )) && [[ $out == *"(no stack)"* && $out == *"total 3 ms"* ]]; then
  pass "trace-query.py profile counts samples with an empty stack"
else
  fail "trace-query.py profile on samples with an empty stack (status $st)" ${(f)out}
fi

# --- trace-compare.py: traces without hitches tables -----------------------------
for missing in fail empty; do
  out=$(MISSING=$missing python3 $SCRIPTS/trace-compare.py $WORK/compare --since 0 2>&1)
  st=$?
  if (( st == 0 )) && [[ $out != *skipping* && $out == *"median of 1 runs"* && $out == *"main thread: ms | 3 (3–3) | 3 (3–3) |"* ]]; then
    pass "trace-compare.py measures traces without hitches tables (export: $missing)"
  else
    fail "trace-compare.py on traces without hitches tables (export: $missing, status $st)" ${(f)out}
  fi
done

# --- profile-compare.sh: runs that write no trace ---------------------------------
# A project of its own: profile-compare.sh finds profile-mac.sh beside itself.
project=$WORK/project
mkdir -p $project/scripts
cp $SCRIPTS/profile-compare.sh $project/scripts/
# The stub records each call, then behaves as STUB says: refuse (exit 3, the
# way profile-mac.sh refuses to start beside another recording), fail (exit 1
# after recording, no trace), or ok (a trace, and ✓).
cat > $project/scripts/profile-mac.sh <<'EOF'
#!/bin/zsh
echo call >> ${0:A:h:h}/calls
out=${@[(i)--out]}; out=${@[out+1]}
case $STUB in
  refuse) echo "✗ these are running and would distort the measurement" >&2; exit 3 ;;
  fail) echo "✗ no trace written" >&2; exit 1 ;;
  ok) mkdir -p $out/t.trace; echo "✓ $out/t.trace" ;;
esac
EOF
chmod +x $project/scripts/profile-mac.sh
print 'COMPARE_SCENARIOS=(idle scroll)' > $project/profiling.conf.zsh
compare() {
  rm -rf $project/calls $project/out
  out=$(STUB=$1 $project/scripts/profile-compare.sh --data /dev/null --rounds 2 --out $project/out \
    before=/x/Before.app after=/x/After.app 2>&1)
  st=$?
  calls=$(wc -l < $project/calls 2>/dev/null | tr -d ' ')
}

compare fail
if (( st != 0 )) && [[ $out != *"✓ $project/out"* ]]; then
  pass "profile-compare.sh fails when no run wrote a trace (status $st)"
else
  fail "profile-compare.sh when no run wrote a trace (status $st)" ${(f)out}
fi

compare refuse
if (( st != 0 )) && [[ $calls == 1 ]]; then
  pass "profile-compare.sh stops at the first refusal (status $st, 1 run)"
else
  fail "profile-compare.sh on a refusal (status $st, ${calls:-0} runs)" ${(f)out}
fi

compare ok
if (( st == 0 )) && [[ $calls == 8 && $out == *"✓ $project/out"* ]]; then
  pass "profile-compare.sh succeeds when every run wrote a trace"
else
  fail "profile-compare.sh when every run wrote a trace (status $st, ${calls:-0} runs)" ${(f)out}
fi

# One build whose runs all fail: there is nothing to compare it with.
cat > $project/scripts/profile-mac.sh <<'EOF'
#!/bin/zsh
echo call >> ${0:A:h:h}/calls
out=${@[(i)--out]}; out=${@[out+1]}
[[ $out == */after/* ]] && { echo "✗ no trace written" >&2; exit 1; }
mkdir -p $out/t.trace; echo "✓ $out/t.trace"
EOF
compare ok
if (( st != 0 )) && [[ $out == *after* ]]; then
  pass "profile-compare.sh fails when one build has no traces (status $st)"
else
  fail "profile-compare.sh when one build has no traces (status $st)" ${(f)out}
fi

# Some runs fail, but every build has a trace of every scenario: a comparison,
# which says how many runs are missing.
cat > $project/scripts/profile-mac.sh <<'EOF2'
#!/bin/zsh
echo call >> ${0:A:h:h}/calls
out=${@[(i)--out]}; out=${@[out+1]}
[[ -d $out ]] && { echo "✗ no trace written" >&2; exit 1; }
mkdir -p $out/t.trace; echo "✓ $out/t.trace"
EOF2
compare ok
if (( st == 0 )) && [[ $out == *"✓ $project/out"*"(4 of 8 runs wrote no trace)"* ]]; then
  pass "profile-compare.sh succeeds, saying how many runs failed, when every build has traces"
else
  fail "profile-compare.sh when some runs failed (status $st)" ${(f)out}
fi

(( failures == 0 )) && echo "all passed" || echo "$failures failed"
exit $(( failures > 0 ))
