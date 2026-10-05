#!/usr/bin/python3
"""Find, and optionally delete, Xcode DerivedData directories whose source is gone.

Usage:
  derived-data-orphans.py                      # report only
  derived-data-orphans.py --json               # the same, for a script
  derived-data-orphans.py --delete             # delete what is proven orphaned
  derived-data-orphans.py --delete --also NAME # and this source-missing-in-repo entry

Standard library only. Read the skill's SKILL.md for what each status means.

A directory is ORPHANED only when all of these hold:
  * its name is <name>-<28 letters>, and the letters are the hash Xcode makes
    from the source path it records (info.plist WorkspacePath), or from the
    path recorded by a sibling with the same letters;
  * that path does not exist (only "no such file" counts; any other error,
    or a dangling symlink, makes it UNKNOWN);
  * its nearest existing ancestor is not inside a git work tree (if it is,
    a checkout could bring the path back: SOURCE-MISSING-IN-REPO);
  * that ancestor is at least two levels deep: if it is "/", "/Volumes" or
    "/Users", the path may be on an unmounted volume or in a renamed home.
Everything is checked again immediately before each deletion.
"""

import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Optional

DEFAULT_ROOT = os.path.expanduser("~/Library/Developer/Xcode/DerivedData")
ENTRY = re.compile(r"^(?P<name>.+)-(?P<hash>[a-z]{28})$")

IN_USE = "in-use"
ORPHANED = "orphaned"
IN_REPO = "source-missing-in-repo"
UNKNOWN = "unknown"
NOT_PROJECT = "not-a-project"


def derived_data_hash(path):
    """The 28 letters Xcode appends: MD5 of the path, each 8-byte half in base 26."""
    digest = hashlib.md5(path.encode("utf-8")).digest()
    out = ""
    for half in (digest[:8], digest[8:]):
        n = int.from_bytes(half, "big")
        letters = ""
        for _ in range(14):
            letters = chr(ord("a") + n % 26) + letters
            n //= 26
        out += letters
    return out


@dataclass
class Entry:
    name: str
    status: str
    reason: str
    source: str = ""
    repo: str = ""
    kbytes: Optional[int] = None  # None: not measured
    last_used: str = ""


def read_workspace_path(entry_dir):
    """WorkspacePath from info.plist, None if there is no info.plist."""
    plist = os.path.join(entry_dir, "info.plist")
    try:
        with open(plist, "rb") as f:
            data = plistlib.load(f)
    except FileNotFoundError:
        return None
    path = data.get("WorkspacePath")
    if not isinstance(path, str) or not path.startswith("/"):
        raise ValueError("info.plist has no absolute WorkspacePath")
    return path


def path_state(path):
    """'exists', 'missing', or an error string. Only ENOENT counts as missing."""
    try:
        os.stat(path)
        return "exists"
    except FileNotFoundError:
        pass
    except OSError as e:
        return f"cannot stat {path}: {e.strerror}"
    try:
        os.lstat(path)
        return f"{path} is a dangling symlink"
    except FileNotFoundError:
        return "missing"
    except OSError as e:
        return f"cannot lstat {path}: {e.strerror}"


def git_toplevel(directory):
    """(True, toplevel) inside a work tree, (False, '') if definitely not, else raises."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    result = subprocess.run(
        ["git", "-C", directory, "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, env=env,
    )
    if result.returncode == 0:
        return True, result.stdout.strip() or directory
    if "not a git repository" in result.stderr:
        return False, ""
    # Inside a .git directory, dubious ownership, git missing...: be safe.
    raise RuntimeError(f"git in {directory}: {result.stderr.strip() or result.returncode}")


def classify_source(source):
    """(status, reason, repo) for a recorded source path."""
    state = path_state(source)
    if state == "exists":
        return IN_USE, "source exists", ""
    if state != "missing":
        return UNKNOWN, state, ""
    ancestor = os.path.dirname(source)
    while True:
        state = path_state(ancestor)
        if state == "exists":
            break
        if state != "missing":
            return UNKNOWN, state, ""
        ancestor = os.path.dirname(ancestor)
    parts = [p for p in ancestor.split("/") if p]
    if len(parts) < 2:
        return UNKNOWN, f"nearest existing ancestor is {ancestor} (unmounted volume or moved home?)", ""
    try:
        inside, top = git_toplevel(ancestor)
    except RuntimeError as e:
        return UNKNOWN, str(e), ""
    if inside:
        return IN_REPO, f"source missing but {ancestor} is in a git work tree", top
    return ORPHANED, f"source missing; nearest existing ancestor {ancestor} is not in git", ""


def classify(root, name, known_paths):
    """Classify one entry. known_paths maps hash -> source path proven by an info.plist."""
    entry_dir = os.path.join(root, name)
    if os.path.islink(entry_dir) or not os.path.isdir(entry_dir):
        return Entry(name, NOT_PROJECT, "not a plain directory")
    m = ENTRY.match(name)
    if not m:
        return Entry(name, NOT_PROJECT, "shared cache, not one project's (left alone)")
    h = m["hash"]
    try:
        source = read_workspace_path(entry_dir)
    except (ValueError, OSError, plistlib.InvalidFileException) as e:
        return Entry(name, UNKNOWN, f"unreadable info.plist: {e}")
    if source is not None:
        if derived_data_hash(source) != h:
            return Entry(name, UNKNOWN, "info.plist path does not hash to the directory name", source)
        how = "info.plist"
    elif h in known_paths:
        source = known_paths[h]
        how = "sibling with the same hash"
    else:
        return Entry(name, UNKNOWN, "no info.plist (made by xcodebuild?) and no sibling with the same hash")
    status, reason, repo = classify_source(source)
    return Entry(name, status, f"{reason} (path from {how})", source, repo)


def known_paths(root, names):
    out = {}
    for name in names:
        m = ENTRY.match(name)
        if not m:
            continue
        try:
            source = read_workspace_path(os.path.join(root, name))
        except Exception:
            continue
        if source and derived_data_hash(source) == m["hash"]:
            out[m["hash"]] = source
    return out


def scan(root):
    names = sorted(os.listdir(root))
    known = known_paths(root, names)
    return [classify(root, n, known) for n in names], known


def last_used(entry_dir):
    """info.plist LastAccessedDate, else the newest mtime among the top-level items."""
    try:
        with open(os.path.join(entry_dir, "info.plist"), "rb") as f:
            when = plistlib.load(f).get("LastAccessedDate")
        if isinstance(when, datetime):
            return when.replace(tzinfo=timezone.utc).astimezone().strftime("%Y-%m-%d")
    except Exception:
        pass
    try:
        times = [os.lstat(os.path.join(entry_dir, n)).st_mtime for n in os.listdir(entry_dir)]
        times.append(os.lstat(entry_dir).st_mtime)
        return datetime.fromtimestamp(max(times)).strftime("%Y-%m-%d")
    except OSError:
        return ""


def kbytes(path):
    result = subprocess.run(["du", "-sk", path], capture_output=True, text=True)
    try:
        return int(result.stdout.split()[0])
    except (IndexError, ValueError):
        return 0


def human(kb):
    if kb is None:
        return "-"
    for unit in ("K", "M", "G"):
        if kb < 1024 or unit == "G":
            return f"{kb:.0f}{unit}" if unit == "K" else f"{kb:.1f}{unit}"
        kb /= 1024


def check_root(args):
    if args.root:
        return os.path.abspath(args.root)
    custom = subprocess.run(
        ["defaults", "read", "com.apple.dt.Xcode", "IDECustomDerivedDataLocation"],
        capture_output=True, text=True,
    )
    if custom.returncode == 0 and custom.stdout.strip():
        sys.exit(f"Xcode uses a custom DerivedData location ({custom.stdout.strip()}); pass --root.")
    return DEFAULT_ROOT


def delete(root, entries, also, known):
    freed = 0
    for e in entries:
        allowed = e.status == ORPHANED or (e.status == IN_REPO and e.name in also)
        if not allowed:
            continue
        # Check again now, from scratch: the source may have come back.
        fresh = classify(root, e.name, known)
        if fresh.status != e.status or fresh.source != e.source:
            print(f"skip {e.name}: now {fresh.status} ({fresh.reason})", file=sys.stderr)
            continue
        target = os.path.join(root, e.name)
        if os.path.islink(target) or os.path.dirname(os.path.realpath(target)) != os.path.realpath(root):
            print(f"skip {e.name}: not a plain directory directly inside {root}", file=sys.stderr)
            continue
        shutil.rmtree(target)
        freed += e.kbytes or 0
        print(f"deleted {e.name} ({human(e.kbytes)}; source was {e.source})")
    print(f"freed about {human(freed)}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--root", help=f"DerivedData directory (default {DEFAULT_ROOT})")
    p.add_argument("--json", action="store_true", help="print the classification as JSON")
    p.add_argument("--delete", action="store_true", help="delete entries classified orphaned")
    p.add_argument("--also", nargs="+", default=[], metavar="NAME",
                   help=f"with --delete, also delete these {IN_REPO} entries (named exactly)")
    p.add_argument("--no-sizes", action="store_true", help="skip measuring sizes (faster)")
    args = p.parse_args()
    if args.also and not args.delete:
        p.error("--also needs --delete")

    root = check_root(args)
    if not os.path.isdir(root):
        sys.exit(f"no such directory: {root}")
    entries, known = scan(root)
    by_name = {e.name: e for e in entries}
    for name in args.also:
        if name not in by_name or by_name[name].status != IN_REPO:
            sys.exit(f"--also {name}: not a {IN_REPO} entry"
                     + (f" (it is {by_name[name].status})" if name in by_name else ""))
    if not args.no_sizes:
        for e in entries:
            e.kbytes = kbytes(os.path.join(root, e.name))
    for e in entries:
        e.last_used = last_used(os.path.join(root, e.name))

    if args.json:
        print(json.dumps({"root": root, "entries": [asdict(e) for e in entries]}, indent=2))
    else:
        order = [ORPHANED, IN_REPO, UNKNOWN, IN_USE, NOT_PROJECT]
        print(f"DerivedData: {root}\n")
        for status in order:
            group = [e for e in entries if e.status == status]
            if not group:
                continue
            total = None if args.no_sizes else sum(e.kbytes for e in group)
            print(f"{status} ({len(group)}, {human(total)})")
            for e in group:
                print(f"  {human(e.kbytes):>7}  {e.last_used:10}  {e.name}")
                if e.source:
                    print(f"{'':23}source: {e.source}")
                if e.repo:
                    print(f"{'':23}repo:   {e.repo}")
                if status != IN_USE:
                    print(f"{'':23}why:    {e.reason}")
            print()

    if args.delete:
        delete(root, entries, set(args.also), known)


if __name__ == "__main__":
    main()
