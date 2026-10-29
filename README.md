# manga-rea — Manga (web) / Panels Rea (iOS)

A manga app in the spirit of **Tachimanga** (Tachiyomi for iOS: extension repos, browse/search any source,
library, updates, reader) crossed with **Panels** (cover-first library, folders, built-in web server to drop
files in from a browser). Three parts, one account, everything in sync through the server:

```
                 ┌──────────────── GitHub Pages (sh-islam) ─────────────────┐
                 │  web/   Manga web app: search sources, download to server, │
                 │         move/rename/delete, manage extension repos        │
                 └───────────────▲──────────────────────────────────────────┘
                                 │ GraphQL over HTTPS (JWT login)
┌──────── shad-server ───────────┴──────────────────────────────────────────┐
│ server/  Suwayomi-Server (JVM) = the extension runtime. Runs the real      │
│          Tachiyomi/Mihon extension APKs from keiyoushi (+ any repo you add)│
│          /home/shad/kumo/manga/<source>/<manga>/<chapter>.cbz             │
│          https://shad-server.elf-tarpon.ts.net:8443/manga  (Funnel)      │
└───────────────▲───────────────────────────────────────────────────────────┘
                │ same GraphQL + chapter/page files
┌───────────────┴───────────────────────────────────────────────────────────┐
│ App/   Panels Rea for iPhone/iPad (xtool, SwiftUI): Library · Updates · Browse  │
│        (search through the server's sources) · Downloads (to server, to   │
│        device, or server→device) · Panels-style reader · Web Server tab   │
│        (drop CBZ/ZIP from a PC browser straight onto the phone)           │
└───────────────────────────────────────────────────────────────────────────┘
```

## Why extensions run on the server

Tachiyomi extensions are Android APKs (Kotlin on the JVM). Tachimanga ships a JVM-like runtime inside its
iOS app to run them; that is months of work and not something a free-account sideload can carry. Suwayomi-
Server already runs those exact APKs headlessly and exposes everything (sources, search, filters, chapters,
pages, downloads, library, categories, updates, history, backups, extension repos) over GraphQL. So the phone
and the web app never execute extension code: "search directly from the extension" in the app means the app
asks the server's extension and shows the result, then downloads either to the server or straight to the
device. Same results, same repos, one place to log in.

## Layout

```
re/            evidence: dl/mihon (open-source reference APK), dl/suwayomi (backend jar), dl/keiyoushi
               (index.pb = extension repo format), mihon-notes.md (screen/feature inventory)
server/        server.conf, kumo.service, install.sh, deploy.sh (push + restart), expose.sh (Funnel, run once)
               .env (login + API URL, not in git), schema.graphql (introspected API)
web/           static web app (GitHub Pages)
App/           xtool iOS project
```

## Setting it up (one time, run by you)

1. `bash server/deploy.sh` (from Git Bash in this folder) — installs the backend (Suwayomi + file service) as services on shad-server,
   bound to localhost. Login is `shad` / the password in `server/.env`.
2. `bash server/expose.sh` — Tailscale Funnel: https://shad-server.elf-tarpon.ts.net:8443/manga → backend and
   `/kumo/files` → file service (port 8443's root stays your video site). Valid certificate, reachable from anywhere; nothing works without the login.
3. `bash publish.sh` — creates the public GitHub repo `manga-rea` and turns on Pages; the web app then lives at
   https://sh-islam.github.io/manga-rea/ and redeploys on every push that touches `web/`. The same app is also
   served by the server at https://shad-server.elf-tarpon.ts.net:8443/manga/app/ — use that one on devices
   that are on the tailnet (Chrome otherwise asks for "local network" permission because the name resolves
   to the 100.x address there; allowing it once also works).
4. `common\ship.cmd manga-rea` with the phone plugged in — installs the iOS app.

## Server notes

- The backend runs under `xvfb-run` because Suwayomi's bundled Chromium (KCEF) needs an X display. KCEF is on:
  many sources (anything behind Cloudflare or needing JavaScript, e.g. mkissa.to) only work with it. It costs
  ~250 MB disk in `data/bin/kcef` and a few hundred MB of RAM while a WebView is open.

## Status

- 2026-10-29: backend verified end to end on the server with a transient run (MangaDex extension installed
  from keiyoushi, search, chapters, pages, one chapter downloaded to
  `/home/shad/kumo/manga/mangas/MangaDex (EN)/<title>/<scanlator>_<chapter>.cbz`, file service upload/move/
  range-download, Local source picks uploads up; ~490 MB RSS). Web app walked through in headless Chrome
  (`node web/test/e2e.mjs`): login, library, browse, source search, manga, reader (webtoon + paged), updates,
  downloads, files, extensions, settings; no JS errors. iOS app compiles (`ios-build.sh`); not yet on the
  phone. Services, Funnel and the GitHub repo are waiting on the four steps above.

## What the iOS app does

Library (categories, filters, badges: unread / on server / on device) · Browse (search every source, per-source
popular/latest/search with the extension's filters) · Manga (add to library, categories, chapter list with
download to server / to this device, mark read, bookmarks, select mode) · Reader (webtoon, paged LTR/RTL,
pinch zoom, progress synced to the server, reads device copies offline) · Updates · Downloads (server queue +
device storage) · More: History, Files on the server (browse, new folder, upload, delete), Files on this device
(CBZ/ZIP library with its own reader), Web Server (Panels-style drop page at http://<phone-ip>:8787/),
Extensions & repos, Settings. Same account and data as the web app.
