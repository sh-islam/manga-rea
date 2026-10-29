#!/bin/bash
# From the PC (Git Bash): push config + service to shad-server and (re)start Kumo's backend.
cd "$(dirname "$0")"
source .env || { echo "server/.env missing (KUMO_PASS)"; exit 1; }
sed "s|__KUMO_PASS__|$KUMO_PASS|" server.conf > .server.conf.filled
scp -q .server.conf.filled shad-server:~/kumo/server.conf && rm -f .server.conf.filled
scp -q kumo.service kumo-files.service kumo_files.py kumo.nginx install.sh shad-server:~/kumo/ && ssh shad-server 'rm -rf ~/kumo/web' && scp -rq ../web shad-server:~/kumo/web && ssh shad-server 'rm -rf ~/kumo/web/test' && ssh shad-server 'bash ~/kumo/install.sh'
