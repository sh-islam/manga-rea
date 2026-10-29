#!/bin/bash
# ONE-TIME, run by you: make the backend reachable on the internet with a valid certificate:
# https://shad-server.elf-tarpon.ts.net:8443/kumo -> 127.0.0.1:4567 and /kumo/files -> 4569. Port 8443 is already a Funnel port
# (its root serves the video site); Tailscale strips the mount path, so the backends see / as usual.
# The backend itself demands a login (JWT), so nothing is usable without the password in server/.env.
ssh shad-server 'sudo tailscale serve --bg --https=8443 --set-path /kumo http://127.0.0.1:4567 && sudo tailscale serve --bg --https=8443 --set-path /kumo/files http://127.0.0.1:4569; tailscale serve status | grep -A6 8443'
