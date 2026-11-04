#!/usr/bin/env bash
set -euo pipefail

ip="${1:-}"
if ! printf '%s' "$ip" | grep -Eq '^[0-9]{1,3}([.][0-9]{1,3}){3}$'; then
    logger -t splunk-fw-block "invalid_ip=$ip"
    exit 2
fi

case "$ip" in
    10.10.10.1|10.10.10.254|10.10.20.254|10.10.40.20|10.10.40.254)
        logger -t splunk-fw-block "excluded_ip=$ip"
        exit 0
        ;;
esac

ssh -i /opt/splunk/etc/auth/fwblock/id_ed25519 -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/opt/splunk/etc/auth/fwblock/known_hosts root@10.10.40.254 "nft add element inet filter blocked_src { $ip timeout 1h }"

logger -t splunk-fw-block "blocked_ip=$ip duration=1h"
