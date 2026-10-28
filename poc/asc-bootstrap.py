#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pyjwt[crypto]==2.10.1"]
# ///
"""Proof of concept: App Store Connect set up from a file in the project,
through the API, with a team API key and no Apple account in Xcode.

App Store Connect cannot create an app record through the API (spec 4.5.1,
Oct 2026: /v1/apps is GET only), so that one step stays by hand. Everything
around it is here:

  register   before the record exists: registers the bundle id, so that the
             New App form offers it, and prints what to type into the form
  sync       once it exists: makes the record's name, TestFlight test
             information, groups and testers match the file
  notes      after an upload: sets a build's "What to Test"

Nothing is written without --apply; without it, each change is printed.

  ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID   the team key (never in a repo)
  ASC_API                                   the API's base URL (for tests)
"""

import argparse
import json
import os
import sys
import time
import tomllib
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = os.environ.get("ASC_API", "https://api.appstoreconnect.apple.com")


def token() -> str:
    try:
        path, kid, iss = (os.environ[k] for k in ("ASC_KEY_PATH", "ASC_KEY_ID", "ASC_ISSUER_ID"))
    except KeyError as e:
        sys.exit(f"✗ set {e.args[0]} (all three of ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID)")
    now = int(time.time())
    claims = {"iss": iss, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    with open(path) as f:
        return jwt.encode(claims, f.read(), algorithm="ES256", headers={"kid": kid, "typ": "JWT"})


class ASC:
    def __init__(self, apply: bool):
        self.apply = apply
        self.auth = f"Bearer {token()}"
        self.changes = 0

    def get(self, path: str, **query) -> list | dict:
        return self._call("GET", path, None, query)["data"]

    def write(self, method: str, path: str, body: dict, why: str) -> dict:
        """A change: printed always, made only with --apply."""
        self.changes += 1
        print(f"→ {why}")
        if not self.apply:
            print(f"    would {method} {path} {json.dumps(body['data'])}")
            return {"id": "<dry-run>", "attributes": {}}
        return self._call(method, path, body, {}).get("data") or {}

    def _call(self, method: str, path: str, body: dict | None, query: dict) -> dict:
        url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
        req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None)
        req.add_header("Authorization", self.auth)
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            sys.exit(f"✗ {method} {path}: HTTP {e.code}\n{e.read().decode()}")


def check_team(asc: ASC, team: str) -> None:
    """Refuse a key for any other team: a bundle id's seedId is its team."""
    ids = asc.get("/v1/bundleIds", limit="1")
    if not ids:
        sys.exit("✗ the key's team has no bundle ids, so its team cannot be confirmed")
    seed = ids[0]["attributes"]["seedId"]
    if seed != team:
        sys.exit(f"✗ this key belongs to team {seed}, not {team}: stopping before anything else")
    print(f"✓ the key is for team {team}")


def find_app(asc: ASC, bundle_id: str) -> dict | None:
    apps = [a for a in asc.get("/v1/apps", **{"filter[bundleId]": bundle_id})
            if a["attributes"]["bundleId"] == bundle_id]
    return apps[0] if apps else None


# ---------------------------------------------------------------------------


def register(asc: ASC, cfg: dict) -> None:
    bundle_id, name = cfg["bundle_id"], cfg["name"]
    found = [b for b in asc.get("/v1/bundleIds", **{"filter[identifier]": bundle_id})
             if b["attributes"]["identifier"] == bundle_id]
    if found:
        print(f"✓ bundle id {bundle_id} is registered")
    else:
        asc.write("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
            "identifier": bundle_id, "name": name, "platform": "IOS"}}},
            f"registering bundle id {bundle_id}")
    if find_app(asc, bundle_id):
        print(f"✓ the app record exists; next: sync")
        return
    print(f"""
Next, by hand: https://appstoreconnect.apple.com/apps → + → New App
    Platforms:      iOS
    Name:           {name}   (unique on the App Store; sync can change it later)
    Primary language: {cfg.get('locale', 'en-GB')}
    Bundle ID:      {bundle_id}
    SKU:            {bundle_id}
    User access:    Full Access
Then run sync.""")


def sync(asc: ASC, cfg: dict) -> None:
    app = find_app(asc, cfg["bundle_id"])
    if not app:
        sys.exit(f"✗ no app record with {cfg['bundle_id']} yet: run register, and make it by hand")
    app_id = app["id"]
    locale = cfg.get("locale", "en-GB")
    print(f"✓ app record {app_id} ({cfg['bundle_id']})")

    # The name, in every localization the record has.
    for info in asc.get(f"/v1/apps/{app_id}/appInfos"):
        for loc in asc.get(f"/v1/appInfos/{info['id']}/appInfoLocalizations"):
            if loc["attributes"].get("name") != cfg["name"]:
                asc.write("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {
                    "type": "appInfoLocalizations", "id": loc["id"],
                    "attributes": {"name": cfg["name"]}}},
                    f"name ({loc['attributes']['locale']}): "
                    f"{loc['attributes'].get('name')!r} → {cfg['name']!r}")

    # TestFlight's test information: what testers see about the app.
    beta = cfg.get("beta", {})
    want = {k: v for k, v in {
        "description": beta.get("description"),
        "feedbackEmail": beta.get("feedback_email"),
        "marketingUrl": beta.get("marketing_url"),
        "privacyPolicyUrl": beta.get("privacy_policy_url"),
    }.items() if v is not None}
    have = [loc for loc in asc.get(f"/v1/apps/{app_id}/betaAppLocalizations")
            if loc["attributes"]["locale"] == locale]
    if not have:
        asc.write("POST", "/v1/betaAppLocalizations", {"data": {
            "type": "betaAppLocalizations", "attributes": {"locale": locale, **want},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}},
            f"test information ({locale}): {', '.join(want)}")
    else:
        diff = {k: v for k, v in want.items() if have[0]["attributes"].get(k) != v}
        if diff:
            asc.write("PATCH", f"/v1/betaAppLocalizations/{have[0]['id']}", {"data": {
                "type": "betaAppLocalizations", "id": have[0]["id"], "attributes": diff}},
                f"test information ({locale}): {', '.join(diff)}")

    # Groups, and who is in them.
    groups = {g["attributes"]["name"]: g for g in asc.get(f"/v1/apps/{app_id}/betaGroups")}
    for spec in cfg.get("groups", []):
        sync_group(asc, app_id, spec, groups.get(spec["name"]))

    if asc.changes == 0:
        print("✓ App Store Connect matches the file")
    elif asc.apply:
        print(f"✓ made {asc.changes} change(s); App Store Connect matches the file")
    else:
        print(f"(dry run: {asc.changes} change(s) not made; --apply makes them)")


def sync_group(asc: ASC, app_id: str, spec: dict, group: dict | None) -> None:
    internal = spec.get("internal", True)
    all_builds = spec.get("all_builds", True)
    feedback = spec.get("feedback", True)
    if group is None:
        group = asc.write("POST", "/v1/betaGroups", {"data": {"type": "betaGroups", "attributes": {
            "name": spec["name"], "isInternalGroup": internal,
            "hasAccessToAllBuilds": all_builds, "feedbackEnabled": feedback},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}},
            f"group {spec['name']!r}: {'internal' if internal else 'external'}"
            f"{', every build' if all_builds else ''}")
        members = set()
    else:
        a = group["attributes"]
        # Set only when a group is made: the API cannot change these after.
        for key, value in (("isInternalGroup", internal), ("hasAccessToAllBuilds", all_builds)):
            if a.get(key) != value:
                print(f"✗ group {spec['name']!r} has {key}={a.get(key)}, the file says {value}; "
                      "the API cannot change it: fix it in App Store Connect, or delete the group "
                      "there and sync again")
        if a.get("feedbackEnabled") != feedback:
            asc.write("PATCH", f"/v1/betaGroups/{group['id']}", {"data": {
                "type": "betaGroups", "id": group["id"], "attributes": {"feedbackEnabled": feedback}}},
                f"group {spec['name']!r}: feedback {'on' if feedback else 'off'}")
        members = {t["attributes"]["email"].lower()
                   for t in asc.get(f"/v1/betaGroups/{group['id']}/betaTesters", limit="200")}

    for email in spec.get("testers", []):
        if email.lower() in members:
            continue
        # An internal group takes only the team's App Store Connect users.
        known = asc.get("/v1/betaTesters", **{"filter[email]": email})
        if known:
            asc.write("POST", f"/v1/betaGroups/{group['id']}/relationships/betaTesters",
                      {"data": [{"type": "betaTesters", "id": known[0]["id"]}]},
                      f"group {spec['name']!r}: adding {email}")
        else:
            asc.write("POST", "/v1/betaTesters", {"data": {"type": "betaTesters",
                      "attributes": {"email": email}, "relationships": {"betaGroups": {"data": [
                          {"type": "betaGroups", "id": group["id"]}]}}}},
                      f"group {spec['name']!r}: inviting {email}")


def notes(asc: ASC, cfg: dict, version: str, text: str, wait: int) -> None:
    """A build's "What to Test", once App Store Connect has the build."""
    app = find_app(asc, cfg["bundle_id"])
    if not app:
        sys.exit(f"✗ no app record with {cfg['bundle_id']}")
    locale = cfg.get("locale", "en-GB")
    deadline = time.time() + wait
    while True:
        builds = asc.get("/v1/builds", **{"filter[app]": app["id"], "filter[version]": version})
        if builds or time.time() >= deadline:
            break
        print(f"  build {version} is not in App Store Connect yet; waiting")
        time.sleep(30)
    if not builds:
        sys.exit(f"✗ no build {version} after {wait}s")
    build = builds[0]
    have = [loc for loc in asc.get(f"/v1/builds/{build['id']}/betaBuildLocalizations")
            if loc["attributes"]["locale"] == locale]
    if have and have[0]["attributes"].get("whatsNew") == text:
        print(f"✓ build {version} has these notes")
    elif have:
        asc.write("PATCH", f"/v1/betaBuildLocalizations/{have[0]['id']}", {"data": {
            "type": "betaBuildLocalizations", "id": have[0]["id"], "attributes": {"whatsNew": text}}},
            f"build {version}: What to Test")
    else:
        asc.write("POST", "/v1/betaBuildLocalizations", {"data": {
            "type": "betaBuildLocalizations", "attributes": {"locale": locale, "whatsNew": text},
            "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}},
            f"build {version}: What to Test")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("action", choices=["register", "sync", "notes"])
    p.add_argument("--config", default="appstoreconnect.toml")
    p.add_argument("--apply", action="store_true")
    p.add_argument("--version", help="notes: the build's CFBundleVersion")
    p.add_argument("--text", help="notes: What to Test")
    p.add_argument("--wait", type=int, default=900, help="notes: seconds to wait for the build")
    a = p.parse_args()
    with open(a.config, "rb") as f:
        cfg = tomllib.load(f)
    asc = ASC(a.apply)
    check_team(asc, cfg["team"])
    if a.action == "register":
        register(asc, cfg)
    elif a.action == "sync":
        sync(asc, cfg)
    else:
        if not (a.version and a.text):
            p.error("notes needs --version and --text")
        notes(asc, cfg, a.version, a.text, a.wait)


if __name__ == "__main__":
    main()
