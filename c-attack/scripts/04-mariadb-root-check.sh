#!/usr/bin/env bash
set -euo pipefail
: "${LAB_CONFIRM:?Set LAB_CONFIRM=NT204-LAB}"
[[ "$LAB_CONFIRM" == NT204-LAB ]] || { echo 'Wrong lab confirmation' >&2; exit 1; }
sudo mariadb --batch --skip-column-names -e \
  "SELECT User,Host,plugin,LENGTH(authentication_string) \
   FROM mysql.user WHERE User='root';"
sudo mariadb -e "SELECT User,Host FROM mysql.user LIMIT 5;"
