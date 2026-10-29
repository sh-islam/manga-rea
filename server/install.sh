#!/bin/bash
# Runs ON the server (sent there by deploy.sh). Idempotent. Backend listens on 127.0.0.1:4567 only.
set -e
cd /home/shad/kumo
mkdir -p data manga local backups
cp -f server.conf data/server.conf
sudo cp -f kumo.service /etc/systemd/system/kumo.service
sudo cp -f kumo-files.service /etc/systemd/system/kumo-files.service
sudo systemctl daemon-reload
sudo systemctl enable kumo.service kumo-files.service >/dev/null
sudo systemctl restart kumo.service kumo-files.service
for i in $(seq 1 90); do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:4567/api/graphql -H 'content-type: application/json' -d '{"query":"{__typename}"}' || true)
  if [ "$code" = "200" ] || [ "$code" = "401" ]; then echo "server up after ${i}s (http $code)"; break; fi
  sleep 1
done
systemctl is-active kumo.service kumo-files.service
curl -s http://127.0.0.1:4569/health; echo
echo "--- log tail"; journalctl -u kumo.service --no-pager -n 12 | cut -c1-180
