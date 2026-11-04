#!/usr/bin/env bash
set -euo pipefail

AUTH_FILE=/opt/splunk/etc/auth/fwblock/rest-auth
SEARCHES=(
  'SIEM - SSH Brute Force - High'
  'SIEM - DVWA Login Brute Force - High'
  'SIEM - SMB Brute Force - High'
  'SIEM - Recon Port Scan - Medium'
)

for search_name in "${SEARCHES[@]}"; do
    search="$(printf '| savedsearch "%s"' "$search_name")"
    response="$(curl -sk --max-time 30 -u "$(cat "$AUTH_FILE")" -X POST https://127.0.0.1:8089/services/search/jobs/export --data-urlencode "search=$search" --data-urlencode output_mode=json)"

    printf '%s\n' "$response" |
        jq -r 'select(.result.src_ip != null) | .result.src_ip' |
        sort -u |
        while read -r ip; do
            [ -n "$ip" ] || continue
            /opt/splunk/bin/scripts/fw_block_ip.sh "$ip" || true
        done
done
