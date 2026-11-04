#!/usr/bin/env bash
set -euo pipefail
: "${LAB_CONFIRM:?Set LAB_CONFIRM=NT204-LAB}"
[[ "$LAB_CONFIRM" == NT204-LAB ]] || { echo 'Wrong lab confirmation' >&2; exit 1; }
: "${LATERAL_USER:?Set LATERAL_USER; SSH will prompt for password}"
CL01_IP="${CL01_IP:-10.10.10.11}"
ssh -o ConnectTimeout=8 -o PreferredAuthentications=password \
  "${LATERAL_USER}@${CL01_IP}" 'echo LATERAL_SSH_LAB; id'
