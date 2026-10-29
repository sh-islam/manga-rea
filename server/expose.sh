#!/bin/bash
# ONE-TIME, run by you: make the backend reachable on the internet with a valid certificate:
# https://shad-server.elf-tarpon.ts.net:8443 -> 127.0.0.1:4567 (Tailscale Funnel; 8443 is an allowed Funnel port on this tailnet).
# The backend itself demands a login (JWT), so nothing is usable without the password in server/.env.
ssh shad-server 'sudo tailscale serve --bg --https=8443 --set-path / http://127.0.0.1:4567 && sudo tailscale serve --bg --https=8443 --set-path /files http://127.0.0.1:4569 && sudo tailscale funnel --bg --https=8443 on; tailscale serve status | grep -A3 8443'
