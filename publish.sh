#!/bin/bash
# ONE-TIME, run by you (Git Bash, from this folder): put the repo on GitHub and turn on Pages.
# Afterwards every push that touches web/ redeploys https://sh-islam.github.io/kumo/ automatically.
set -e
cd "$(dirname "$0")"
gh repo create kumo --public --description "Kumo: manga reader (Tachiyomi sources via your own server + Panels-style files)" --source=. --remote=origin --push
gh api -X POST repos/sh-islam/kumo/pages -f build_type=workflow >/dev/null || true
echo "Pages is building; check: gh run watch --repo sh-islam/kumo   then open https://sh-islam.github.io/kumo/"
