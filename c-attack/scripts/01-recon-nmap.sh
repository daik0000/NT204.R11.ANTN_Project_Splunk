#!/usr/bin/env bash
set -euo pipefail
: "${LAB_CONFIRM:?Set LAB_CONFIRM=NT204-LAB}"
[[ "$LAB_CONFIRM" == NT204-LAB ]] || { echo 'Wrong lab confirmation' >&2; exit 1; }
WEB_IP="${WEB_IP:-10.10.20.10}"
command -v nmap >/dev/null || { echo 'nmap is not installed' >&2; exit 1; }
sudo nmap -sS -Pn -p 1-100 "$WEB_IP" -oN /tmp/nmap-web01.txt
cat /tmp/nmap-web01.txt
