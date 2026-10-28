"""A stand-in for the App Store Connect API, for exercising asc-bootstrap.py:
just the endpoints it uses, in memory. Shapes follow the OpenAPI spec 4.5.1.

  python3 -I fake_asc.py PORT TEAM      serves; POST /_admin/app makes a record
"""

import itertools
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

TEAM = sys.argv[2]
ids = (f"id{n}" for n in itertools.count(1))
db: dict[str, dict[str, dict]] = {t: {} for t in (
    "bundleIds", "apps", "appInfos", "appInfoLocalizations", "betaAppLocalizations",
    "betaGroups", "betaTesters", "builds", "betaBuildLocalizations")}
links: dict[str, set] = {}  # group id -> tester ids

db["bundleIds"]["b0"] = {"id": "b0", "attributes": {"identifier": "org.example.other", "seedId": TEAM}}
db["betaTesters"]["t0"] = {"id": "t0", "attributes": {"email": "tikitu@logophile.org"}}


def new(kind, attrs, rel=None):
    i = next(ids)
    db[kind][i] = {"id": i, "type": kind, "attributes": attrs, "rel": rel or {}}
    return db[kind][i]


def out(o):
    return {k: v for k, v in o.items() if k != "rel"}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body):
        raw = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        p = u.path
        if p == "/v1/bundleIds":
            r = [b for b in db["bundleIds"].values()
                 if "filter[identifier]" not in q or q["filter[identifier]"] in b["attributes"]["identifier"]]
            return self.send(200, {"data": [out(b) for b in r][: int(q.get("limit", 200))]})
        if p == "/v1/apps":
            r = [a for a in db["apps"].values() if a["attributes"]["bundleId"] == q.get("filter[bundleId]")]
            return self.send(200, {"data": [out(a) for a in r]})
        if m := re.fullmatch(r"/v1/apps/(\w+)/(appInfos|betaAppLocalizations|betaGroups)", p):
            r = [o for o in db[m[2]].values() if o["rel"].get("app") == m[1]]
            return self.send(200, {"data": [out(o) for o in r]})
        if m := re.fullmatch(r"/v1/appInfos/(\w+)/appInfoLocalizations", p):
            r = [o for o in db["appInfoLocalizations"].values() if o["rel"].get("appInfo") == m[1]]
            return self.send(200, {"data": [out(o) for o in r]})
        if m := re.fullmatch(r"/v1/betaGroups/(\w+)/betaTesters", p):
            return self.send(200, {"data": [out(db["betaTesters"][t]) for t in links.get(m[1], ())]})
        if p == "/v1/betaTesters":
            r = [t for t in db["betaTesters"].values() if t["attributes"]["email"] == q.get("filter[email]")]
            return self.send(200, {"data": [out(t) for t in r]})
        if p == "/v1/builds":
            r = [b for b in db["builds"].values()
                 if b["rel"]["app"] == q["filter[app]"] and b["attributes"]["version"] == q["filter[version]"]]
            return self.send(200, {"data": [out(b) for b in r]})
        if m := re.fullmatch(r"/v1/builds/(\w+)/betaBuildLocalizations", p):
            r = [o for o in db["betaBuildLocalizations"].values() if o["rel"]["build"] == m[1]]
            return self.send(200, {"data": [out(o) for o in r]})
        self.send(404, {"errors": [{"detail": f"fake has no GET {p}"}]})

    def body(self):
        return json.loads(self.rfile.read(int(self.headers["Content-Length"])))

    def do_POST(self):
        p, b = urlparse(self.path).path, self.body()
        if p == "/_admin/app":  # the step done by hand in the website
            a = new("apps", {"bundleId": b["bundleId"], "name": b["name"]})
            info = new("appInfos", {}, {"app": a["id"]})
            new("appInfoLocalizations", {"locale": "en-GB", "name": b["name"]}, {"appInfo": info["id"]})
            return self.send(201, {"data": out(a)})
        if p == "/_admin/build":
            bd = new("builds", {"version": b["version"]}, {"app": b["app"]})
            return self.send(201, {"data": out(bd)})
        d = b["data"]
        if m := re.fullmatch(r"/v1/betaGroups/(\w+)/relationships/betaTesters", p):
            links.setdefault(m[1], set()).update(t["id"] for t in d)
            self.send_response(204)
            return self.end_headers()
        rel = {k: v["data"]["id"] for k, v in d.get("relationships", {}).items() if isinstance(v["data"], dict)}
        if p == "/v1/bundleIds":
            o = new("bundleIds", {**d["attributes"], "seedId": TEAM})
        elif p == "/v1/betaGroups":
            o = new("betaGroups", d["attributes"], rel)
        elif p == "/v1/betaAppLocalizations":
            o = new("betaAppLocalizations", d["attributes"], rel)
        elif p == "/v1/betaBuildLocalizations":
            o = new("betaBuildLocalizations", d["attributes"], rel)
        elif p == "/v1/betaTesters":
            o = new("betaTesters", d["attributes"])
            for g in d["relationships"]["betaGroups"]["data"]:
                links.setdefault(g["id"], set()).add(o["id"])
        else:
            return self.send(404, {"errors": [{"detail": f"fake has no POST {p}"}]})
        self.send(201, {"data": out(o)})

    def do_PATCH(self):
        p, d = urlparse(self.path).path, self.body()["data"]
        kind, i = p.split("/")[2:4]
        if kind == "apps" or kind not in db:  # the PoC never patches apps
            return self.send(409, {"errors": [{"detail": f"fake refuses PATCH {p}"}]})
        db[kind][i]["attributes"].update(d["attributes"])
        self.send(200, {"data": out(db[kind][i])})


HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
