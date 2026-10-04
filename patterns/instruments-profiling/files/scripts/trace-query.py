#!/usr/bin/env python3
# Imported by peru from the app-tooling pattern `instruments-profiling`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/instruments-profiling/ says how to use it.
"""Read an Instruments .trace from the command line, via `xctrace export`.

xctrace exports tables as XML in which every repeated value is written once
with an id="N" and afterwards only as ref="N". This resolves those, so each
row reads as plain columns. Standard library only.

  trace-query.py tables TRACE                 every table: schema, rows, options
  trace-query.py rows TRACE SCHEMA [--limit N] [--json]
                                              a table's rows, one per line
  trace-query.py profile TRACE [--binary NAME] [--main-thread] [--top N]
                                              where CPU time went (time-profile)
  trace-query.py delays TRACE                 (or `hangs`) what the Hangs instrument saw, by its own
                                              category (Potential Interaction Delay,
                                              Brief Unresponsiveness, Microhang, Hang),
                                              and hitches
  trace-query.py memory TRACE [--top N]       Allocations statistics and Leaks
  trace-query.py detail TRACE TRACK DETAIL [--limit N]
                                              a track's detail rows as JSON (e.g.
                                              Allocations "Allocations List")
  trace-query.py swiftui TRACE [--module NAME] [--top N]
                                              view body updates, expensive updates,
                                              and what caused the app's views to update

SCHEMA is a schema name from `tables` (e.g. potential-hangs). When a schema
appears more than once, --index picks one (default: the first).
"""

import argparse
import collections
import itertools
import json
import statistics
import subprocess
import sys
import xml.etree.ElementTree as ET


def xctrace_export(trace, xpath=None, toc=False):
    args = ["xcrun", "xctrace", "export", "--input", trace]
    args += ["--toc"] if toc else ["--xpath", xpath]
    out = subprocess.run(args, capture_output=True)
    if out.returncode != 0:
        sys.exit(f"xctrace export failed ({out.returncode}): {out.stderr.decode().strip()}")
    if not out.stdout.strip():
        # A failed export can exit 0 with no output; never read that as "no rows".
        sys.exit("xctrace export printed nothing")
    return ET.fromstring(out.stdout)


def toc_tables(trace, run):
    toc = xctrace_export(trace, toc=True)
    r = toc.find(f"run[@number='{run}']")
    if r is None:
        sys.exit(f"no run {run} in {trace}")
    return r.findall("data/table")


class Value:
    """One cell: its display text (fmt), raw text, and resolved children."""

    def __init__(self, el, ids):
        self.tag = el.tag
        self.attrs = dict(el.attrib)
        self.text = (el.text or "").strip()
        self.children = [resolve(c, ids) for c in el]

    @property
    def fmt(self):
        return self.attrs.get("fmt", self.text)

    def find(self, tag):
        return [c for c in self.children if c.tag == tag]

    def __repr__(self):
        return self.fmt


def resolve(el, ids):
    if "ref" in el.attrib:
        return ids[el.attrib["ref"]]
    v = Value(el, ids)
    if "id" in el.attrib:
        ids[el.attrib["id"]] = v
    return v


def read_table(trace, run, schema, index=0):
    """(columns, rows) of one table. Rows are streamed straight off xctrace's
    output: a SwiftUI table runs to gigabytes of XML, more than can be held
    (or, past 2 GB, parsed) in one piece."""
    xpath = f'/trace-toc/run[@number="{run}"]/data/table[@schema="{schema}"]'
    proc = subprocess.Popen(["xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    events = ET.iterparse(proc.stdout, events=("start", "end"))
    cols, node, nodes_seen = [], None, -1
    for event, el in events:
        if event == "start" and el.tag == "node":
            nodes_seen += 1
            node = el
        elif event == "end" and el.tag == "mnemonic" and nodes_seen == index:
            cols.append(el.text)
        elif event == "end" and el.tag == "schema" and nodes_seen == index:
            break
    if nodes_seen < index or not cols:
        proc.kill()
        err = proc.stderr.read().decode().strip()
        sys.exit(f"no table with schema {schema!r}" + (f" ({err})" if err else ""))

    def rows():
        ids = {}
        for event, el in events:
            if event == "end" and el.tag == "row" and nodes_seen == index:
                yield dict(zip(cols, (resolve(c, ids) for c in el)))
                node.remove(el)
            elif event == "end" and el.tag == "node":
                break
        proc.kill()
        proc.wait()

    return cols, rows()


def frames(backtrace):
    """Frame names, innermost first, with the binary each is in."""
    out = []
    for f in backtrace.find("frame"):
        binary = f.find("binary")
        out.append((f.attrs.get("name", f.attrs.get("addr", "?")),
                    binary[0].attrs.get("name", "?") if binary else "?"))
    return out


def cmd_tables(a):
    for t in toc_tables(a.trace, a.run):
        attrs = dict(t.attrib)
        schema = attrs.pop("schema")
        extra = " ".join(f"{k}={v}" for k, v in attrs.items() if k in ("subsystem", "category", "codes"))
        line = f"{schema}\t{extra}"
        if a.count:
            _, rows = read_table(a.trace, a.run, schema)
            line += f"\t{sum(1 for _ in rows)} rows"
        print(line)
    toc = xctrace_export(a.trace, toc=True)
    for track in toc.findall(f"run[@number='{a.run}']/tracks/track"):
        for d in track.findall("details/detail"):
            print(f"detail: {track.get('name')} / {d.get('name')}")


def cmd_rows(a):
    cols, rows = read_table(a.trace, a.run, a.schema, a.index)
    rows = itertools.islice(rows, a.limit) if a.limit else rows
    if a.json:
        for r in rows:
            print(json.dumps({k: v.fmt for k, v in r.items()}))
        return
    print("\t".join(cols))
    for r in rows:
        print("\t".join(r[c].fmt if c in r else "" for c in cols))


def launched_pid(trace, run):
    """The pid xctrace launched, if it launched one. Templates like Animation
    Hitches sample every process, which can include another running copy of
    the same app — same binary name, someone else's data."""
    toc = xctrace_export(trace, toc=True)
    p = toc.find(f"run[@number='{run}']/info/target/process[@type='launched']")
    return p.get("pid") if p is not None else None


def cmd_profile(a):
    # time-profile (Time Profiler) and time-sample (raw) both carry stacks.
    pid = None if a.all_processes else launched_pid(a.trace, a.run)
    if pid:
        print(f"process {pid} only (the launched one; --all-processes for every process)")
    cols, rows = read_table(a.trace, a.run, a.schema)
    stack_col = next(c for c in cols if c in ("stack", "backtrace"))
    self_w = collections.Counter()
    total_w = collections.Counter()
    all_w = 0
    for r in rows:
        if pid and r["process"].find("pid")[0].text != pid:
            continue
        if not in_window(a, r["time"].fmt):
            continue
        if a.main_thread and "Main Thread" not in r["thread"].fmt:
            continue
        w = int(r["weight"].text) if "weight" in r else 1
        all_w += w
        fs = frames(r[stack_col])
        if a.binary:
            fs = [f for f in fs if f[1] == a.binary]
            if not fs:
                continue
        self_w[fs[0][0]] += w
        for name in {f[0] for f in fs}:
            total_w[name] += w
    unit = 1e6 if "weight" in cols else 1
    label = "ms" if unit == 1e6 else "samples"
    print(f"total {all_w / unit:.0f} {label}" + (f" (frames in {a.binary} only)" if a.binary else ""))
    print(f"\n-- self ({'innermost ' + a.binary + ' frame' if a.binary else 'leaf frame'})")
    for name, w in self_w.most_common(a.top):
        print(f"{w / unit:8.0f} {label}  {name}")
    print("\n-- total (frame anywhere on the stack)")
    for name, w in total_w.most_common(a.top):
        print(f"{w / unit:8.0f} {label}  {name}")


def cmd_hangs(a):
    found = False
    for schema in ("potential-hangs", "hitches", "hang-risks"):
        try:
            cols, rows = read_table(a.trace, a.run, schema)
            rows = [r for r in rows if "start" not in r or in_window(a, r["start"].fmt)]
        except SystemExit:
            continue
        found = True
        durations = [ms(r["duration"].fmt) for r in rows if "duration" in r]
        print(f"-- {schema}: {len(rows)}" + (f", {sum(durations):.0f} ms in all" if durations else ""))
        if schema == "potential-hangs" and rows:
            # Instruments' own words for each delay; only "Hang" is a hang.
            kinds = collections.defaultdict(list)
            for r in rows:
                kinds[r["hang-type"].fmt].append(ms(r["duration"].fmt))
            print("   by Instruments' category: " + "; ".join(
                f"{len(ds)}× {kind} (typical {statistics.median(ds):.0f} ms, longest {max(ds):.0f} ms)"
                for kind, ds in sorted(kinds.items(), key=lambda kv: min(kv[1]))))
        if schema == "hitches" and rows:
            buckets = collections.Counter()
            for d in durations:
                buckets[next(b for b in (10, 20, 50, 100, 250, float("inf")) if d <= b)] += 1
            print("   by duration: " + ", ".join(f"≤{b:g} ms: {n}" for b, n in sorted(buckets.items())))
            reasons = collections.Counter(r["narrative-description"].fmt or "(no reason given)" for r in rows)
            print("   by reason: " + "; ".join(f"{n}× {k}" for k, n in reasons.most_common()))
            print("   longest:")
            rows = sorted(rows, key=lambda r: -ms(r["duration"].fmt))[: a.top]
        for r in rows:
            print("\t".join(r[c].fmt for c in cols if c in r and c not in ("process", "is-system", "swap-id", "label", "display")))
    if not found:
        sys.exit("no hang or hitch tables in this trace")


def seconds(clock):
    """'00:04.440.920' (a trace's sample time) -> 4.44092."""
    parts = clock.split(":")
    minutes = int(parts[0]) if len(parts) > 1 else 0
    sec, _, frac = parts[-1].partition(".")
    return minutes * 60 + int(sec) + float("0." + frac.replace(".", "")) if frac else minutes * 60 + int(sec)


def in_window(a, clock):
    t = seconds(clock)
    return (a.since is None or t >= a.since) and (a.until is None or t <= a.until)


def ms(duration):
    """'37.22 ms' / '24.67 µs' / '208 ns' / '1.20 s' -> milliseconds."""
    value, unit = duration.split()
    return float(value) * {"s": 1000, "ms": 1, "µs": 1e-3, "ns": 1e-6}[unit]


def cmd_swiftui(a):
    _, updates = read_table(a.trace, a.run, "swiftui-updates")
    module = a.module
    body = collections.defaultdict(list)
    severe = []
    updates_seen = []
    for r in updates:
        if module and len(updates_seen) < 50000:
            updates_seen.append(r)
        if r["update-type"].fmt == "View Body Updates" and (not module or r["module"].fmt == module):
            body[r["description"].fmt].append(ms(r["duration"].fmt))
        if r["severity"].fmt in ("High", "Moderate") and (not module or r["module"].fmt in (module, "SwiftUI")):
            severe.append((ms(r["duration"].fmt), r["start"].fmt, r["duration"].fmt, r["severity"].fmt,
                           r["description"].fmt, r["root-causes"].fmt))
    if module and not body:
        modules = collections.Counter(r["module"].fmt for r in updates_seen if r["update-type"].fmt == "View Body Updates")
        print(f"(no view body updates in module {module!r}; the trace has: "
              + ", ".join(f"{m or '(none)'} {n}" for m, n in modules.most_common()) + ")")
    print(f"-- view body updates{' in ' + module if module else ''}: count, total ms, max ms")
    for name, ds in sorted(body.items(), key=lambda kv: -sum(kv[1]))[: a.top]:
        print(f"{len(ds):6d} {sum(ds):9.2f} {max(ds):8.2f}  {name}")

    print(f"\n-- High / Moderate severity updates: {len(severe)}; the {a.top} longest: start, duration, what, root cause")
    for _, start, duration, severity, what, cause in sorted(severe, reverse=True)[: a.top]:
        print(f"{start}  {duration:>10}  {severity:8}  {what[:70]}  <- {cause[:90]}")

    # What made the app's own views update: the edges into their nodes.
    views = {name.removesuffix(".body") for name in body}
    _, causes = read_table(a.trace, a.run, "swiftui-causes")
    edges = collections.Counter()
    for r in causes:
        dest = r["destination-node"].fmt.split(",")[0]
        if any(v and v in dest for v in views):
            src = r["source-node"].fmt.split(",")[0]
            edges[(src, dest, r["label"].fmt, r["changed-properties"].fmt)] += 1
    print("\n-- causes of updates to those views: count  source -> destination  [label] changed")
    for (src, dest, label, changed), n in edges.most_common(a.top):
        print(f"{n:6d}  {src[:60]} -> {dest[:50]}  [{label}] {changed[:60]}")


def read_detail(trace, run, track, detail):
    """Rows of a track's detail view (Allocations and Leaks live here, not in
    tables). Each row's values are its XML attributes."""
    xpath = f'/trace-toc/run[@number="{run}"]/tracks/track[@name="{track}"]/details/detail[@name="{detail}"]'
    root = xctrace_export(trace, xpath=xpath)
    node = root.find("node")
    if node is None:
        sys.exit(f"no detail {detail!r} in track {track!r}")
    return [dict(r.attrib) for r in node.findall("row")]


def cmd_detail(a):
    rows = read_detail(a.trace, a.run, a.track, a.detail)
    rows = rows[: a.limit] if a.limit else rows
    for r in rows:
        print(json.dumps(r))


def mib(n):
    return f"{int(n) / 1048576:8.2f} MiB"


def cmd_memory(a):
    stats = read_detail(a.trace, a.run, "Allocations", "Statistics")
    print("-- persistent (still live at the end), by category: bytes, count, total ever allocated")
    for r in sorted(stats, key=lambda r: -int(r["persistent-bytes"]))[: a.top]:
        print(f"{mib(r['persistent-bytes'])} {int(r['count-persistent']):9d}  "
              f"(total {mib(r['total-bytes']).strip()}, {int(r['count-total'])} allocs)  {r['category']}")
    print("\n-- transient (allocated and freed) churn, by category: bytes, count")
    for r in sorted(stats, key=lambda r: -int(r["transient-bytes"]))[: a.top]:
        if r["category"].startswith("All "):
            continue
        print(f"{mib(r['transient-bytes'])} {int(r['count-transient']):9d}  {r['category']}")
    try:
        leaks = read_detail(a.trace, a.run, "Leaks", "Leaks")
    except SystemExit:
        return
    by = collections.defaultdict(lambda: [0, 0])
    for r in leaks:
        k = (r.get("responsible-library", ""), r.get("responsible-frame", ""))
        by[k][0] += int(r.get("count", 1))
        by[k][1] += int(r.get("size", 0))
    print(f"\n-- leaks: {len(leaks)} objects, {sum(v[1] for v in by.values())} bytes; by responsible frame")
    for (lib, frame), (n, size) in sorted(by.items(), key=lambda kv: -kv[1][1])[: a.top]:
        print(f"{n:5d} {size:8d} B  {lib}: {frame}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    def add(name, fn):
        s = sub.add_parser(name)
        s.add_argument("trace")
        s.add_argument("--run", type=int, default=1)
        s.add_argument("--since", type=float, help="only from this many seconds into the trace")
        s.add_argument("--until", type=float, help="only up to this many seconds into the trace")
        s.set_defaults(fn=fn)
        return s

    s = add("tables", cmd_tables)
    s.add_argument("--count", action="store_true", help="count each table's rows (slow on big traces)")
    s = add("rows", cmd_rows)
    s.add_argument("schema")
    s.add_argument("--index", type=int, default=0)
    s.add_argument("--limit", type=int)
    s.add_argument("--json", action="store_true")
    s = add("profile", cmd_profile)
    s.add_argument("--schema", default="time-profile")
    s.add_argument("--binary")
    s.add_argument("--main-thread", action="store_true")
    s.add_argument("--all-processes", action="store_true")
    s.add_argument("--top", type=int, default=25)
    s = add("hangs", cmd_hangs)
    s.add_argument("--top", type=int, default=10)
    # Instruments calls the instrument Hangs; what it reports is delays.
    s = add("delays", cmd_hangs)
    s.add_argument("--top", type=int, default=10)
    s = add("detail", cmd_detail)
    s.add_argument("track")
    s.add_argument("detail")
    s.add_argument("--limit", type=int)
    s = add("memory", cmd_memory)
    s.add_argument("--top", type=int, default=20)
    s = add("swiftui", cmd_swiftui)
    s.add_argument("--module", help="only views from this module: the app's binary name (e.g. MyApp)")
    s.add_argument("--top", type=int, default=25)

    a = p.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
