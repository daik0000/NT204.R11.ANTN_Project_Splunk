#!/usr/bin/env bash
set -euo pipefail
: "${LAB_CONFIRM:?Set LAB_CONFIRM=NT204-LAB}"
[[ "$LAB_CONFIRM" == NT204-LAB ]] || { echo 'Wrong lab confirmation' >&2; exit 1; }
: "${DVWA_USER:?Set DVWA_USER}"
: "${DVWA_PASSWORD:?Set DVWA_PASSWORD}"
WEB_IP="${WEB_IP:-10.10.20.10}"
DVWA_COOKIE="${DVWA_COOKIE:-/tmp/dvwa-auth-user.cookie}"
PAGE="$(mktemp)"
trap 'unlink "$PAGE" 2>/dev/null || true' EXIT
umask 077
curl --max-time 8 -fsS -c "$DVWA_COOKIE" "http://${WEB_IP}/DVWA/login.php" -o "$PAGE"
token="$(sed -n "s/.*name='user_token' value='\([^']*\)'.*/\1/p" "$PAGE" | head -1)"
test -n "$token" || { echo 'DVWA user_token was not found' >&2; exit 1; }
curl --max-time 8 -fsS -b "$DVWA_COOKIE" -c "$DVWA_COOKIE" \
  -d "username=${DVWA_USER}" -d "password=${DVWA_PASSWORD}" -d 'Login=Login' \
  --data-urlencode "user_token=${token}" \
  "http://${WEB_IP}/DVWA/login.php" -o /dev/null
chmod 600 "$DVWA_COOKIE"
echo "DVWA cookie created at ${DVWA_COOKIE}; do not commit it."
