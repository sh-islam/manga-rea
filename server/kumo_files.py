#!/usr/bin/env python3
"""Kumo file service: the Panels-style "web server" half of the backend.

Suwayomi handles sources/library/downloads; this tiny stdlib-only service handles raw files so the web app and
the iOS app can upload CBZ/ZIP, make folders, move/rename, delete and download:

  roots:  local  -> /home/shad/kumo/local   (Suwayomi's Local source: <Manga>/<chapter>.cbz, read-write)
          manga  -> /home/shad/kumo/manga   (Suwayomi's own downloads, read-only: listing + download)

  POST /auth/login        {username,password}  -> {token}   (checked against Suwayomi's login, then an HMAC token)
  GET  /fs?path=local/Foo                       -> {entries:[{name,dir,size,mtime}]}
  POST /fs/mkdir          {path}
  POST /fs/move           {from,to}             (rename or move inside the local root)
  POST /fs/delete         {path}                (file or folder, local root only)
  PUT  /fs/upload?path=local/Foo/ch1.cbz        raw body, Content-Length, overwrites
  GET  /fs/file?path=...                        download, supports Range (so the phone can stream a CBZ)
  GET  /health

Auth: Authorization: Bearer <token> or ?token=<token> (for <a download> links). Listens on 127.0.0.1:4569;
Tailscale Funnel / nginx put it behind HTTPS. An optional leading "/files" path prefix is ignored.
"""
import hashlib, hmac, json, os, secrets, shutil, sys, time, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit, unquote

HOME = os.path.expanduser("~")
ROOTS = {"local": os.path.join(HOME, "kumo", "local"), "manga": os.path.join(HOME, "kumo", "manga")}
WRITABLE = {"local"}
SUWAYOMI = os.environ.get("KUMO_SUWAYOMI", "http://127.0.0.1:4567/api/graphql")
SECRET_FILE = os.path.join(HOME, "kumo", "data", "files.secret")
TOKEN_TTL = 60 * 24 * 3600
PORT = int(os.environ.get("KUMO_FILES_PORT", "4569"))


def secret():
    os.makedirs(os.path.dirname(SECRET_FILE), exist_ok=True)
    if not os.path.exists(SECRET_FILE):
        with open(SECRET_FILE, "w") as f:
            f.write(secrets.token_hex(32))
        os.chmod(SECRET_FILE, 0o600)
    return open(SECRET_FILE).read().strip()


def make_token(user):
    exp = int(time.time()) + TOKEN_TTL
    msg = f"{user}:{exp}"
    sig = hmac.new(secret().encode(), msg.encode(), hashlib.sha256).hexdigest()
    return f"{msg}:{sig}"


def check_token(tok):
    try:
        user, exp, sig = tok.split(":")
        msg = f"{user}:{exp}"
        good = hmac.new(secret().encode(), msg.encode(), hashlib.sha256).hexdigest()
        return hmac.compare_digest(good, sig) and int(exp) > time.time()
    except Exception:
        return False


def suwayomi_login(user, pw):
    q = {"query": "mutation($u:String!,$p:String!){ login(input:{username:$u,password:$p}){ accessToken } }",
         "variables": {"u": user, "p": pw}}
    req = urllib.request.Request(SUWAYOMI, data=json.dumps(q).encode(), headers={"content-type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            d = json.load(r)
        return bool(d.get("data", {}).get("login", {}).get("accessToken"))
    except Exception:
        return False


def resolve(path, write=False):
    """'local/Foo/bar.cbz' -> absolute path inside its root, or None if outside / not allowed."""
    path = unquote(path or "").strip("/")
    if not path:
        return None, None
    root, _, rest = path.partition("/")
    base = ROOTS.get(root)
    if base is None or (write and root not in WRITABLE):
        return None, None
    full = os.path.realpath(os.path.join(base, rest))
    if full != os.path.realpath(base) and not full.startswith(os.path.realpath(base) + os.sep):
        return None, None
    return full, root


class H(BaseHTTPRequestHandler):
    server_version = "KumoFiles/1"

    def log_message(self, fmt, *a):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % a))

    # ---- helpers
    def cors(self):
        self.send_header("Access-Control-Allow-Origin", self.headers.get("Origin", "*") or "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type, Range")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
        self.send_header("Access-Control-Expose-Headers", "Content-Length, Content-Range, Accept-Ranges")
        self.send_header("Vary", "Origin")

    def js(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def body_json(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def route(self):
        u = urlsplit(self.path)
        p = u.path
        if p.startswith("/files"):
            p = p[len("/files"):] or "/"
        return p, {k: v[0] for k, v in parse_qs(u.query).items()}

    def authed(self, q):
        h = self.headers.get("Authorization", "")
        tok = h[7:] if h.startswith("Bearer ") else q.get("token", "")
        return check_token(tok)

    # ---- verbs
    def do_OPTIONS(self):
        self.send_response(204)
        self.cors()
        self.end_headers()

    def do_GET(self):
        p, q = self.route()
        if p == "/health":
            return self.js(200, {"ok": True, "roots": list(ROOTS)})
        if not self.authed(q):
            return self.js(401, {"error": "login required"})
        if p == "/fs":
            full, root = resolve(q.get("path"))
            if q.get("path", "").strip("/") == "":
                return self.js(200, {"entries": [{"name": r, "dir": True, "size": 0, "mtime": 0, "writable": r in WRITABLE} for r in ROOTS]})
            if not full or not os.path.isdir(full):
                return self.js(404, {"error": "no such folder"})
            out = []
            for name in sorted(os.listdir(full), key=str.lower):
                fp = os.path.join(full, name)
                st = os.stat(fp)
                out.append({"name": name, "dir": os.path.isdir(fp), "size": st.st_size, "mtime": int(st.st_mtime)})
            return self.js(200, {"entries": out, "writable": root in WRITABLE})
        if p == "/fs/file":
            full, _ = resolve(q.get("path"))
            if not full or not os.path.isfile(full):
                return self.js(404, {"error": "no such file"})
            return self.send_file(full)
        self.js(404, {"error": "unknown route"})

    def do_POST(self):
        p, q = self.route()
        if p == "/auth/login":
            d = self.body_json()
            if suwayomi_login(d.get("username", ""), d.get("password", "")):
                return self.js(200, {"token": make_token(d.get("username", ""))})
            return self.js(401, {"error": "bad login"})
        if not self.authed(q):
            return self.js(401, {"error": "login required"})
        d = self.body_json()
        try:
            if p == "/fs/mkdir":
                full, _ = resolve(d.get("path"), write=True)
                if not full:
                    return self.js(400, {"error": "bad path"})
                os.makedirs(full, exist_ok=True)
                return self.js(200, {"ok": True})
            if p == "/fs/move":
                src, _ = resolve(d.get("from"), write=True)
                dst, _ = resolve(d.get("to"), write=True)
                if not src or not dst or not os.path.exists(src):
                    return self.js(400, {"error": "bad path"})
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.move(src, dst)
                return self.js(200, {"ok": True})
            if p == "/fs/delete":
                full, _ = resolve(d.get("path"), write=True)
                if not full or not os.path.exists(full) or full in (os.path.realpath(r) for r in ROOTS.values()):
                    return self.js(400, {"error": "bad path"})
                shutil.rmtree(full) if os.path.isdir(full) else os.remove(full)
                return self.js(200, {"ok": True})
        except OSError as e:
            return self.js(500, {"error": str(e)})
        self.js(404, {"error": "unknown route"})

    def do_PUT(self):
        p, q = self.route()
        if not self.authed(q):
            return self.js(401, {"error": "login required"})
        if p != "/fs/upload":
            return self.js(404, {"error": "unknown route"})
        full, _ = resolve(q.get("path"), write=True)
        if not full:
            return self.js(400, {"error": "bad path"})
        n = int(self.headers.get("Content-Length") or 0)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        tmp = full + ".part"
        left = n
        with open(tmp, "wb") as f:
            while left > 0:
                chunk = self.rfile.read(min(1 << 20, left))
                if not chunk:
                    break
                f.write(chunk)
                left -= len(chunk)
        if left:
            os.remove(tmp)
            return self.js(400, {"error": "short upload"})
        os.replace(tmp, full)
        self.js(200, {"ok": True, "size": n})

    def send_file(self, full):
        size = os.path.getsize(full)
        start, end = 0, size - 1
        rng = self.headers.get("Range")
        code = 200
        if rng and rng.startswith("bytes="):
            a, _, b = rng[6:].partition("-")
            start = int(a) if a else max(0, size - int(b))
            end = int(b) if b and a else end
            code = 206
        self.send_response(code)
        self.cors()
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        self.send_header("Content-Disposition", 'attachment; filename="%s"' % os.path.basename(full).replace('"', ""))
        if code == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        with open(full, "rb") as f:
            f.seek(start)
            left = end - start + 1
            while left > 0:
                chunk = f.read(min(1 << 20, left))
                if not chunk:
                    break
                self.wfile.write(chunk)
                left -= len(chunk)


if __name__ == "__main__":
    for r in ROOTS.values():
        os.makedirs(r, exist_ok=True)
    secret()
    print(f"kumo files on 127.0.0.1:{PORT}", file=sys.stderr)
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
