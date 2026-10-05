#!/usr/bin/python3
"""Tests for derived-data-orphans.py, on a made-up DerivedData directory.

Run: scripts/test-derived-data-orphans.py
"""

import importlib.util
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "derived-data-orphans.py")
spec = importlib.util.spec_from_file_location("ddo", SCRIPT)
ddo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ddo)


class Fixture(unittest.TestCase):
    def setUp(self):
        # realpath, so the fixture's paths contain no symlinks (/var is one).
        self.tmp = os.path.realpath(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)
        self.root = os.path.join(self.tmp, "DerivedData")
        self.src = os.path.join(self.tmp, "src")
        os.makedirs(self.root)
        os.makedirs(self.src)
        ok, _ = ddo.git_toplevel(self.tmp)
        self.assertFalse(ok, "the temporary directory must not be inside a git work tree")

    def entry(self, name, source, plist=True, hash_of=None):
        """Make <name>-<hash> with a Build/ dir; info.plist recording source if plist."""
        h = ddo.derived_data_hash(hash_of or source)
        d = os.path.join(self.root, f"{name}-{h}")
        os.makedirs(os.path.join(d, "Build"))
        if plist:
            with open(os.path.join(d, "info.plist"), "wb") as f:
                plistlib.dump({"WorkspacePath": source}, f)
        return os.path.basename(d)

    def run_script(self, *args):
        result = subprocess.run(
            [SCRIPT, "--root", self.root, *args], capture_output=True, text=True
        )
        return result

    def statuses(self):
        result = self.run_script("--json", "--no-sizes")
        self.assertEqual(result.returncode, 0, result.stderr)
        return {e["name"]: e["status"] for e in json.loads(result.stdout)["entries"]}


class HashTests(unittest.TestCase):
    def test_matches_this_macs_xcode(self):
        """Every directory Xcode made here hashes from the path it recorded.

        If a future Xcode changes the scheme, this fails, and the script itself
        classifies every such directory as unknown and deletes none of them.
        """
        root = ddo.DEFAULT_ROOT
        names = os.listdir(root) if os.path.isdir(root) else []
        checked = 0
        for name in names:
            m = ddo.ENTRY.match(name)
            plist = os.path.join(root, name, "info.plist")
            if not m or not os.path.exists(plist):
                continue
            with open(plist, "rb") as f:
                source = plistlib.load(f).get("WorkspacePath")
            if isinstance(source, str):
                self.assertEqual(ddo.derived_data_hash(source), m["hash"], name)
                checked += 1
        if not checked:
            self.skipTest(f"no Xcode-made directories in {root} to check against")


class ClassifyTests(Fixture):
    def test_existing_source_is_in_use(self):
        proj = os.path.join(self.src, "App.xcodeproj")
        os.makedirs(proj)
        name = self.entry("App", proj)
        self.assertEqual(self.statuses()[name], ddo.IN_USE)

    def test_deleted_source_outside_git_is_orphaned(self):
        name = self.entry("Gone", os.path.join(self.src, "gone-worktree", "App.xcodeproj"))
        self.assertEqual(self.statuses()[name], ddo.ORPHANED)

    def test_missing_source_inside_git_is_not_orphaned(self):
        repo = os.path.join(self.src, "repo")
        os.makedirs(os.path.join(repo, "apps"))
        subprocess.run(["git", "init", "-q", repo], check=True)
        name = self.entry("Moved", os.path.join(repo, "App.xcodeproj"))
        self.assertEqual(self.statuses()[name], ddo.IN_REPO)

    def test_unmounted_volume_is_unknown(self):
        name = self.entry("Ext", "/Volumes/NoSuchVolume-ddo-test/App/App.xcodeproj")
        self.assertEqual(self.statuses()[name], ddo.UNKNOWN)

    def test_renamed_home_is_unknown(self):
        name = self.entry("Home", "/Users/no-such-user-ddo-test/code/App.xcodeproj")
        self.assertEqual(self.statuses()[name], ddo.UNKNOWN)

    def test_plist_not_matching_hash_is_unknown(self):
        name = self.entry("Odd", os.path.join(self.src, "gone"), hash_of="/elsewhere")
        self.assertEqual(self.statuses()[name], ddo.UNKNOWN)

    def test_dangling_symlink_source_is_unknown(self):
        link = os.path.join(self.src, "link")
        os.symlink(os.path.join(self.tmp, "nowhere"), link)
        name = self.entry("Link", os.path.join(link, "App.xcodeproj"))
        self.assertEqual(self.statuses()[name], ddo.UNKNOWN)
        name2 = self.entry("Link2", link)
        self.assertEqual(self.statuses()[name2], ddo.UNKNOWN)

    def test_no_plist_alone_is_unknown(self):
        name = self.entry("CLI", os.path.join(self.src, "gone"), plist=False)
        self.assertEqual(self.statuses()[name], ddo.UNKNOWN)

    def test_no_plist_sharing_hash_takes_siblings_path(self):
        gone = os.path.join(self.src, "gone")
        self.entry("Xcode", gone)
        name = self.entry("cli", gone, plist=False)
        self.assertEqual(self.statuses()[name], ddo.ORPHANED)
        live = os.path.join(self.src, "live")
        os.makedirs(live)
        self.entry("Xcode2", live)
        name2 = self.entry("cli2", live, plist=False)
        self.assertEqual(self.statuses()[name2], ddo.IN_USE)

    def test_shared_caches_and_symlinks_are_not_projects(self):
        os.makedirs(os.path.join(self.root, "ModuleCache.noindex"))
        target = os.path.join(self.tmp, "elsewhere")
        os.makedirs(target)
        h = ddo.derived_data_hash("/x")
        os.symlink(target, os.path.join(self.root, f"Sym-{h}"))
        s = self.statuses()
        self.assertEqual(s["ModuleCache.noindex"], ddo.NOT_PROJECT)
        self.assertEqual(s[f"Sym-{h}"], ddo.NOT_PROJECT)


class DeleteTests(Fixture):
    def make_all(self):
        live = os.path.join(self.src, "live")
        os.makedirs(live)
        repo = os.path.join(self.src, "repo")
        os.makedirs(repo)
        subprocess.run(["git", "init", "-q", repo], check=True)
        return {
            "in_use": self.entry("Live", live),
            "orphan": self.entry("Gone", os.path.join(self.src, "gone")),
            "orphan_cli": self.entry("gone-cli", os.path.join(self.src, "gone"), plist=False),
            "in_repo": self.entry("Moved", os.path.join(repo, "Old.xcodeproj")),
            "unknown": self.entry("CLI", os.path.join(self.src, "x"), plist=False),
        }

    def remaining(self):
        return set(os.listdir(self.root))

    def test_report_deletes_nothing(self):
        names = self.make_all()
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.remaining(), set(names.values()))

    def test_delete_removes_only_orphans(self):
        names = self.make_all()
        result = self.run_script("--delete")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.remaining(), {names["in_use"], names["in_repo"], names["unknown"]}
        )

    def test_also_removes_named_in_repo_entry(self):
        names = self.make_all()
        result = self.run_script("--delete", "--also", names["in_repo"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.remaining(), {names["in_use"], names["unknown"]})

    def test_also_refuses_other_statuses(self):
        names = self.make_all()
        for key in ("in_use", "unknown", "orphan"):
            result = self.run_script("--delete", "--also", names[key])
            self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.remaining(), set(names.values()))

    def test_source_returning_before_delete_is_skipped(self):
        names = self.make_all()
        entries, known = ddo.scan(self.root)
        os.makedirs(os.path.join(self.src, "gone"))  # the worktree comes back
        ddo.delete(self.root, entries, set(), known)
        self.assertEqual(self.remaining(), set(names.values()))


if __name__ == "__main__":
    unittest.main(verbosity=1)
