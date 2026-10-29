# manga-rea — Kumo

A manga app in the spirit of **Tachimanga** (Tachiyomi for iOS: extension repos, browse/search any source,
library, updates, reader) crossed with **Panels** (cover-first library, folders, built-in web server to drop
files in from a browser). Three parts, one account, everything in sync through the server:

```
                 ┌──────────────── GitHub Pages (sh-islam) ─────────────────┐
                 │  web/   Kumo web app: search sources, download to server, │
                 │         move/rename/delete, manage extension repos        │
                 └───────────────▲──────────────────────────────────────────┘
                                 │ GraphQL over HTTPS (JWT login)
┌──────── shad-server ───────────┴──────────────────────────────────────────┐
│ server/  Suwayomi-Server (JVM) = the extension runtime. Runs the real      │
│          Tachiyomi/Mihon extension APKs from keiyoushi (+ any repo you add)│
│          /home/shad/kumo/manga/<source>/<manga>/<chapter>.cbz             │
│          https://shad-server.elf-tarpon.ts.net:8443  (Tailscale Funnel)   │
└───────────────▲───────────────────────────────────────────────────────────┘
                │ same GraphQL + chapter/page files
┌───────────────┴───────────────────────────────────────────────────────────┐
│ App/   Kumo for iPhone/iPad (xtool, SwiftUI): Library · Updates · Browse  │
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

## Status

- 2026-10-29: references downloaded; backend config written; server has Java 21, 4567 free.
  Next: `bash server/deploy.sh` (installs the service) and `bash server/expose.sh` (public HTTPS), then the
  web app, then the iOS app.
