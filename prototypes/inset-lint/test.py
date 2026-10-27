#!/usr/bin/env python3
"""Run inset-lint over each fixture dir; check flags against `// expect:` comments."""
import os, re, subprocess, sys
here = os.path.dirname(os.path.abspath(__file__))
tool = os.path.join(here, ".build/release/inset-lint")
fails = 0
for case in sorted(os.listdir(os.path.join(here, "fixtures"))):
    root = os.path.join(here, "fixtures", case)
    out = subprocess.run([tool, root], capture_output=True, text=True).stdout
    got = {}
    for l in out.splitlines():
        m = re.match(r"(.*?):(\d+): .* over a split view: (.*)$", l)
        if m: got[(os.path.realpath(m[1]), int(m[2]))] = m[3]
    want = {}
    for dp, _, fs in os.walk(root):
        for f in fs:
            p = os.path.realpath(os.path.join(dp, f))
            for i, l in enumerate(open(p), 1):
                m = re.search(r"// expect: (.*?)(?: \(|$)", l)
                if m: want[(p, i)] = m[1].strip()
    for k, v in want.items():
        g = got.pop(k, "ok")
        ok = g == v
        print(f"{'PASS' if ok else 'FAIL'} {case}: {os.path.basename(k[0])}:{k[1]} want {v!r} got {g!r}")
        fails += not ok
    for k, v in got.items():
        print(f"FAIL {case}: unexpected {os.path.basename(k[0])}:{k[1]} {v}"); fails += 1
print("ok" if not fails else f"{fails} failures"); sys.exit(1 if fails else 0)
