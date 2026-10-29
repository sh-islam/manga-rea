#!/bin/bash
# ONE-TIME, run by you: make the backend reachable on the internet with a valid certificate:
# https://shad-server.elf-tarpon.ts.net:8443/manga -> nginx 127.0.0.1:4570 -> 4567 (API) and /files -> 4569. Port 8443 is already a Funnel port
# (its root serves the video site); Tailscale strips the mount path, so the backends see / as usual.
# The backend itself demands a login (JWT), so nothing is usable without the password in server/.env.
ssh shad-server 'sudo tailscale funnel --bg --https=8443 --set-path /manga http://127.0.0.1:4570; tailscale serve status | grep -A6 8443'
