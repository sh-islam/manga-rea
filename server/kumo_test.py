#!/usr/bin/env python3
"""End-to-end smoke test, run ON the server against a running backend (127.0.0.1:4567) and file service (:4569).
usage: kumo_test.py <user> <password>
"""
import json, os, sys, time, urllib.request

API = "http://127.0.0.1:4567"
FILES = "http://127.0.0.1:4569"
user, pw = sys.argv[1], sys.argv[2]
token = None


def http(url, data=None, method=None, headers=None, raw=False):
    h = {"content-type": "application/json"}
    h.update(headers or {})
    req = urllib.request.Request(url, data=data if raw or data is None else json.dumps(data).encode(), headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            body = r.read()
            return r.status, (body if raw else json.loads(body or b"{}"))
    except urllib.error.HTTPError as e:
        return e.code, e.read()[:300]


def gql(query, variables=None):
    code, d = http(API + "/api/graphql", {"query": query, "variables": variables or {}}, headers={"Authorization": f"Bearer {token}"} if token else None)
    if isinstance(d, dict) and d.get("errors"):
        print("  GQL errors:", json.dumps(d["errors"])[:300])
    return d.get("data") if isinstance(d, dict) else d


print("== login")
d = gql("mutation($u:String!,$p:String!){ login(input:{username:$u,password:$p}){ accessToken } }", {"u": user, "p": pw})
token = d["login"]["accessToken"]
print("  token ok")

print("== sources")
src = gql("{ sources { nodes { id name lang supportsLatest isNsfw } } }")["sources"]["nodes"]
print(" ", len(src), "sources:", [(s["name"], s["lang"]) for s in src][:6])
en = [s for s in src if s["lang"] == "en" and s["name"] == "MangaDex"]
if not en:
    print("  installing MangaDex")
    gql("mutation { fetchExtensions(input:{}) { extensions { pkgName } } }")
    gql('mutation { updateExtension(input:{id:"eu.kanade.tachiyomi.extension.all.mangadex", patch:{install:true}}) { extension { isInstalled } } }')
    src = gql("{ sources { nodes { id name lang } } }")["sources"]["nodes"]
    en = [s for s in src if s["lang"] == "en" and s["name"] == "MangaDex"]
sid = en[0]["id"]
print("  MangaDex en id", sid)

print("== search")
d = gql("mutation($s:LongString!,$q:String){ fetchSourceManga(input:{source:$s, type:SEARCH, query:$q, page:1}) { hasNextPage mangas { id title thumbnailUrl inLibrary } } }", {"s": sid, "q": "komi"})
m = d["fetchSourceManga"]["mangas"]
print(" ", len(m), "results; first:", m[0]["title"], m[0]["id"], (m[0]["thumbnailUrl"] or "")[:60])
d = gql("mutation($s:LongString!){ fetchSourceManga(input:{source:$s, type:POPULAR, page:1}) { hasNextPage mangas { id title } } }", {"s": sid})
print("  popular:", [x["title"] for x in d["fetchSourceManga"]["mangas"][:5]])

print("== manga + chapters (first result whose pages load)")
mid = cid = None
for cand in m[:4]:
    d = gql("mutation($id:Int!){ fetchMangaAndChapters(input:{id:$id, fetchManga:true, fetchChapters:true}) { manga { title author status genre } chapters { id name chapterNumber scanlator pageCount isDownloaded } } }", {"id": cand["id"]})
    if not d or not d.get("fetchMangaAndChapters"):
        continue
    ch = sorted(d["fetchMangaAndChapters"]["chapters"], key=lambda c: c["chapterNumber"])
    print(" ", d["fetchMangaAndChapters"]["manga"]["title"], "|", len(ch), "chapters; first:", ch[0]["name"] if ch else None)
    for c in ch[:3]:
        p = gql("mutation($id:Int!){ fetchChapterPages(input:{chapterId:$id}) { pages } }", {"id": c["id"]})
        if p and p.get("fetchChapterPages") and p["fetchChapterPages"]["pages"]:
            mid, cid, pages = cand["id"], c["id"], p["fetchChapterPages"]["pages"]
            break
    if cid:
        break
print("  using manga", mid, "chapter", cid, "pages", len(pages), "first:", pages[0])
code, body = http(API + pages[0], headers={"Authorization": f"Bearer {token}"}, raw=True)
print("  page0 bearer:", code, len(body) if isinstance(body, bytes) else body)

print("== image auth (thumbnail)")
for label, h, suffix in [("bearer", {"Authorization": f"Bearer {token}"}, ""), ("none", {}, ""), ("cookie", {"Cookie": f"suwayomi-server-token={token}"}, ""), ("query", {}, f"?token={token}")]:
    code, body = http(f"{API}/api/v1/manga/{mid}/thumbnail{suffix}", headers=h, raw=True)
    print(f"  {label}={code} bytes={len(body) if isinstance(body, bytes) else '?'}")

print("== download chapter to server")
gql("mutation($ids:[Int!]!){ enqueueChapterDownloads(input:{ids:$ids}) { downloadStatus { state } } }", {"ids": [cid]})
for i in range(90):
    q = gql("{ downloadStatus { state queue { state progress tries chapter { id } } } }")["downloadStatus"]
    if not q["queue"]:
        print(f"  queue empty after {i*2}s")
        break
    time.sleep(2)
else:
    print("  still queued:", q)
for root, dirs, files in os.walk(os.path.expanduser("~/kumo/manga")):
    depth = root.count(os.sep) - os.path.expanduser("~/kumo/manga").count(os.sep)
    if depth <= 3:
        print("  " + "  " * depth + os.path.basename(root) + "/", files[:3])
d = gql("query($id:Int!){ chapter(id:$id) { isDownloaded pageCount } }", {"id": cid})
print("  chapter isDownloaded:", d["chapter"])

print("== file service")
code, d = http(FILES + "/health")
print("  health", code, d)
code, d = http(FILES + "/auth/login", {"username": user, "password": pw})
ft = d.get("token") if isinstance(d, dict) else None
print("  login", code, "token" if ft else d)
fh = {"Authorization": f"Bearer {ft}"}
print("  roots", http(FILES + "/fs?path=", headers=fh)[1])
print("  mkdir", http(FILES + "/fs/mkdir", {"path": "local/Test Manga"}, headers=fh)[1])
blob = b"PK\x05\x06" + b"\0" * 18  # empty zip
print("  upload", http(FILES + "/fs/upload?path=local/Test%20Manga/ch1.cbz", blob, method="PUT", headers={**fh, "content-type": "application/octet-stream"}, raw=True)[1][:80])
print("  list", http(FILES + "/fs?path=local/Test%20Manga", headers=fh)[1])
print("  move", http(FILES + "/fs/move", {"from": "local/Test Manga/ch1.cbz", "to": "local/Test Manga/chapter 1.cbz"}, headers=fh)[1])
code, body = http(FILES + "/fs/file?path=local/Test%20Manga/chapter%201.cbz", headers={**fh, "Range": "bytes=0-3"}, raw=True)
print("  range get", code, body)
print("  bad path", http(FILES + "/fs/delete", {"path": "manga/x"}, headers=fh)[1])
print("  local source sees it?", [s["name"] for s in gql("{ sources { nodes { name } } }")["sources"]["nodes"] if "ocal" in s["name"]])
print("  delete", http(FILES + "/fs/delete", {"path": "local/Test Manga"}, headers=fh)[1])
print("DONE")
