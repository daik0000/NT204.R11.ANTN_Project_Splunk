#!/usr/bin/env bash
set -euo pipefail
: "${LAB_CONFIRM:?Set LAB_CONFIRM=NT204-LAB}"
[[ "$LAB_CONFIRM" == NT204-LAB ]] || { echo 'Wrong lab confirmation' >&2; exit 1; }
: "${DVWA_USER:?Set DVWA_USER}"
: "${DVWA_PASSWORD:?Set DVWA_PASSWORD}"
WEB_IP="${WEB_IP:-10.10.20.10}"
COOKIE="$(mktemp)"
PAGE="$(mktemp)"
trap 'unlink "$COOKIE" "$PAGE" 2>/dev/null || true' EXIT
for i in $(seq 1 12); do
  curl --max-time 8 -fsS -c "$COOKIE" -b "$COOKIE" "http://${WEB_IP}/DVWA/login.php" -o "$PAGE"
  token="$(sed -n "s/.*name='user_token' value='\([^']*\)'.*/\1/p" "$PAGE" | head -1)"
  curl --max-time 8 -fsS -b "$COOKIE" -c "$COOKIE" \
    -d "username=${DVWA_USER}" -d "password=invalid-${i}" -d 'Login=Login' \
    --data-urlencode "user_token=${token}" \
    "http://${WEB_IP}/DVWA/login.php" -o /dev/null || true
done
echo "Sent 12 controlled invalid DVWA login attempts from $(hostname)."
