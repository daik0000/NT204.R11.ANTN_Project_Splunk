#!/usr/bin/env bash
set -euo pipefail
: "${LAB_CONFIRM:?Set LAB_CONFIRM=NT204-LAB}"
[[ "$LAB_CONFIRM" == NT204-LAB ]] || { echo 'Wrong lab confirmation' >&2; exit 1; }
FW_HOST="${FW_HOST:-10.10.40.254}"
TEST_IP="${TEST_IP:-10.10.10.11}"
FW_SSH_KEY="${FW_SSH_KEY:?Set FW_SSH_KEY to the lab-only Splunk service key}"
FW_KNOWN_HOSTS="${FW_KNOWN_HOSTS:?Set FW_KNOWN_HOSTS to the lab-only known_hosts file}"
ssh -i "$FW_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$FW_KNOWN_HOSTS" root@"$FW_HOST" \
  "for h in \$(nft -a list chain inet filter forward | awk '/tcp dport 4444 accept/ {print \$NF}'); do nft delete rule inet filter forward handle \"\$h\"; done; nft delete element inet filter blocked_src { ${TEST_IP} } 2>/dev/null || true; nft list set inet filter blocked_src; nft -a list chain inet filter forward | grep 4444 || true"
echo 'Cleanup command completed; verify no test listener/process remains on CL01 and WEB01.'
