#!/usr/bin/env python3
# Imported by peru from the app-tooling pattern `instruments-profiling`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/instruments-profiling/ says how to use it.
"""A before/after table from traces recorded by scripts/profile-compare.sh.

  trace-compare.py DIR [--builds main,fixed] [--since 3.5]
                   [-f LABEL=FUNCTION ...]

DIR holds NAME/SCENARIO/*.trace. For each trace, over the scenario only
(from the window profile-mac.sh wrote beside each trace, else from --since
seconds, so launch is left out): how many main-thread delays
the Hangs instrument reported in each of its categories (Potential
Interaction Delay, Brief Unresponsiveness, Microhang, Hang), the typical and
longest delay of any category, hitches, main-thread time, and main-thread time with each FUNCTION on the
stack (a frame name as `trace-query.py profile` prints it, e.g.
`MyView.body.getter`). Prints, per scenario, the median of the runs for
each build with their range, as a Markdown table.
"""
import argparse
import importlib.util
import statistics
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("tq", Path(__file__).with_name("trace-query.py"))
tq = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tq)


# Instruments' own names for a main-thread delay, shortest first. Its Hangs
# instrument files every one it sees under one of these; only the last is
# what Apple calls a hang, so nothing else here is called one.
STALL_TYPES = ["Potential Interaction Delay", "Brief Unresponsiveness", "Microhang", "Hang"]


def measure(trace, window, functions):
    out = {}
    try:
        _, rows = tq.read_table(str(trace), 1, "potential-hangs")
        delays = [(r["hang-type"].fmt, tq.ms(r["duration"].fmt))
                  for r in rows if tq.in_window(window, r["start"].fmt)]
    except SystemExit:
        delays = []
    for kind in STALL_TYPES + sorted({k for k, _ in delays} - set(STALL_TYPES)):
        n = sum(1 for k, _ in delays if k == kind)
        if n:
            out[f"{kind}: count"] = n
    durations = [d for _, d in delays]
    out["delay, typical: ms"] = statistics.median(durations) if durations else 0
    out["delay, longest: ms"] = max(durations, default=0)
    try:
        _, rows = tq.read_table(str(trace), 1, "hitches")
        hitches = [tq.ms(r["duration"].fmt) for r in rows if tq.in_window(window, r["start"].fmt)]
        out["hitches: count"] = len(hitches)
        out["hitch, typical: ms"] = statistics.median(hitches) if hitches else 0
        out["hitches, all: ms"] = sum(hitches)
    except SystemExit:
        pass
    # Frames shown: with the hitches, how smooth. No frame is drawn while
    # nothing moves, so compare it only between runs that move as far.
    try:
        _, rows = tq.read_table(str(trace), 1, "hitches-frame-lifetimes")
        out["frames shown: count"] = sum(1 for r in rows if tq.in_window(window, r["start"].fmt))
    except SystemExit:
        pass
    pid = tq.launched_pid(str(trace), 1)
    _, rows = tq.read_table(str(trace), 1, "time-profile")
    main = 0.0
    totals = dict.fromkeys(functions, 0.0)
    for r in rows:
        if r["process"].find("pid")[0].text != pid or "Main Thread" not in r["thread"].fmt:
            continue
        if not tq.in_window(window, r["time"].fmt):
            continue
        w = int(r["weight"].text) / 1e6
        main += w
        names = {f[0] for f in tq.frames(r["stack"])}
        for label, fn in functions.items():
            if fn in names:
                totals[label] += w
    out["main thread: ms"] = main
    out.update({f"{label}: ms": v for label, v in totals.items()})
    return out


def readable(trace, a, functions):
    """measure(), or None for a trace xctrace cannot export (a recording
    that was killed while stopping leaves one behind)."""
    try:
        return measure(trace, window(trace, a), functions)
    except Exception as e:  # noqa: BLE001 — any unreadable trace is skipped the same way
        print(f"(skipping {trace}: {type(e).__name__})", file=sys.stderr)
        return None


def window(trace, a):
    """The scenario's stretch of this trace: --since/--until if given, else
    the .window file profile-mac.sh wrote beside it, else from 3.5 s."""
    side = trace.with_suffix(".window")
    if a.since is None and side.exists():
        since, until = map(float, side.read_text().split())
        return argparse.Namespace(since=since, until=a.until or until)
    return argparse.Namespace(since=3.5 if a.since is None else a.since, until=a.until)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("dir", type=Path)
    p.add_argument("--builds", help="comma-separated, in column order (default: alphabetical)")
    p.add_argument("--since", type=float)
    p.add_argument("--until", type=float)
    p.add_argument("-f", "--function", action="append", default=[], metavar="LABEL=FUNCTION")
    a = p.parse_args()
    functions = dict(f.split("=", 1) for f in a.function)
    builds = a.builds.split(",") if a.builds else sorted(d.name for d in a.dir.iterdir() if d.is_dir())
    scenarios = sorted({s.name for b in builds for s in (a.dir / b).iterdir() if s.is_dir()})
    for scenario in scenarios:
        results = {b: [r for t in sorted((a.dir / b / scenario).glob("*.trace"))
                       if (r := readable(t, a, functions)) is not None]
                   for b in builds}
        runs = min(len(v) for v in results.values())
        print(f"\n### {scenario} (median of {runs} runs, range in brackets)\n")
        print("| | " + " | ".join(builds) + " |")
        print("|---|" + "---|" * len(builds))
        # Every key any run produced, in a stable order: a category can be
        # missing from one build's runs and present in another's.
        keys = []
        for runs_of_build in results.values():
            for r in runs_of_build:
                keys += [k for k in r if k not in keys]
        for k in keys:
            cells = []
            for b in builds:
                vals = [r.get(k, 0) for r in results[b]]
                cells.append(f"{statistics.median(vals):.0f} ({min(vals):.0f}–{max(vals):.0f})"
                             if vals else "–")
            print(f"| {k} | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()
