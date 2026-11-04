#!/usr/bin/env bash
set -euo pipefail
: "${LAB_CONFIRM:?Set LAB_CONFIRM=NT204-LAB}"
[[ "$LAB_CONFIRM" == NT204-LAB ]] || { echo 'Wrong lab confirmation' >&2; exit 1; }
: "${SMB_USER:?Set SMB_USER}"
: "${SMB_PASSWORD:?Set SMB_PASSWORD}"
: "${SMB_BAD_PASSWORD:?Set SMB_BAD_PASSWORD}"
SRV01_IP="${SRV01_IP:-10.10.10.10}"
SHARE="${SMB_SHARE:-ketoan}"
OUT="/tmp/khachhang.csv"

for i in $(seq 1 5); do
  smbclient -L "//${SRV01_IP}" -U "${SMB_USER}%${SMB_BAD_PASSWORD}-${i}" >/dev/null 2>&1 || true
done
smbclient -L "//${SRV01_IP}" -U "${SMB_USER}%${SMB_PASSWORD}"
printf 'ls\nget khachhang.csv %s\nquit\n' "$OUT" \
  | smbclient "//${SRV01_IP}/${SHARE}" -U "${SMB_USER}%${SMB_PASSWORD}"
test -s "$OUT"
echo "Downloaded controlled test file to ${OUT}; deleting the local copy."
unlink "$OUT"
