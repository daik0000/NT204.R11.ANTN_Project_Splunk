#!/usr/bin/env bash
set -euo pipefail
: "${LAB_CONFIRM:?Set LAB_CONFIRM=NT204-LAB}"
[[ "$LAB_CONFIRM" == NT204-LAB ]] || { echo 'Wrong lab confirmation' >&2; exit 1; }
DUMP="$(mktemp)"
trap 'unlink "$DUMP" 2>/dev/null || true' EXIT
chmod 600 "$DUMP"
sudo mariadb --batch --skip-column-names \
  -e "SELECT user,password FROM dvwa.users;" > "$DUMP"
test -s "$DUMP"
if [[ -n "${CANDIDATES_FILE:-}" ]]; then
  test -r "$CANDIDATES_FILE"
  while IFS=$'\t' read -r user hash; do
    while IFS= read -r candidate; do
      candidate_hash="$(printf '%s' "$candidate" | md5sum | awk '{print $1}')"
      if [[ "$candidate_hash" == "$hash" ]]; then
        printf 'Dictionary match for account %s\n' "$user"
      fi
    done < "$CANDIDATES_FILE"
  done < "$DUMP"
fi
echo 'Credential table was accessed for the controlled offline-check stage.'
echo 'Raw hashes are intentionally not printed.'
