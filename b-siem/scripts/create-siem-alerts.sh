#!/usr/bin/env bash
set -euo pipefail

# Run on SPLUNK01 as root. The REST credential file must contain user:password.
BASE='https://127.0.0.1:8089/services/saved/searches'
AUTH_FILE=${AUTH_FILE:-/opt/splunk/etc/auth/fwblock/rest-auth}
AUTH="$(cat "$AUTH_FILE")"

save_search() {
    local name="$1"
    local search="$2"
    local severity="$3"
    local description="$4"
    local encoded
    local code

    encoded="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$name")"
    code="$(curl -sk -u "$AUTH" -o /dev/null -w '%{http_code}' "$BASE/$encoded")"

    local args=(
        --data-urlencode "search=$search"
        --data-urlencode 'cron_schedule=*/5 * * * *'
        --data-urlencode 'dispatch.earliest_time=-10m@m'
        --data-urlencode 'alert_type=number of events'
        --data-urlencode 'alert_comparator=greater than'
        --data-urlencode 'alert_threshold=0'
        --data-urlencode "alert.severity=$severity"
        --data-urlencode "description=$description"
        -d 'is_scheduled=1'
        -d 'disabled=0'
        -d 'alert.track=1'
    )

    if [ "$code" = '200' ]; then
        curl -sk -u "$AUTH" -X POST "$BASE/$encoded" "${args[@]}" >/dev/null
    else
        curl -sk -u "$AUTH" -X POST "$BASE" --data-urlencode "name=$name" "${args[@]}" >/dev/null
    fi
    printf 'saved: %s\n' "$name"
}

save_search 'SIEM - Recon Port Scan - Medium' 'index=firewall source="udp:1514" ("FW-DROP" OR "FW-DNAT-WEB") | rex field=_raw "SRC=(?<src_ip>[0-9]{1,3}([.][0-9]{1,3}){3})" | stats count as scan_hits values(host) as firewall by src_ip | where scan_hits >= 10 | table src_ip scan_hits firewall' 3 'Detect repeated firewall drops or DNAT probes. Block source IP for 1h when safe.'

save_search 'SIEM - DVWA Login Brute Force - High' 'index=web ("POST /DVWA/login.php" OR "POST /dvwa/login.php" OR "POST /DVWA/login.php?") | rex field=_raw "^(?<src_ip>[0-9]{1,3}([.][0-9]{1,3}){3})[[:space:]]" | stats count as attempts values(host) as targets by src_ip | where attempts >= 10 | table src_ip attempts targets' 5 'Detect repeated DVWA login attempts. Block source IP for 1h and review account lockout.'

save_search 'SIEM - DVWA Command Injection - Critical' 'index=web ("cmd=" OR "vulnerabilities/exec" OR ";id" OR ";pwd" OR "bash -c" OR "/dev/tcp/" OR "<script" OR "../" OR "union select") | rex field=_raw "^(?<src_ip>[0-9]{1,3}([.][0-9]{1,3}){3})[[:space:]]" | stats count as hits values(host) as targets by src_ip | where hits > 0 | table src_ip hits targets' 6 'Detect DVWA command injection and web exploit indicators. Isolate WEB01 and preserve evidence.'

save_search 'SIEM - Web Reverse Shell Indicator - Critical' '(index=web OR index=linux_audit) ("bash -c" OR "/dev/tcp/" OR "pty.spawn" OR "reverse shell" OR "web_process_exec" OR "web_network_connect") | stats count values(host) as targets values(sourcetype) as types by host | where count > 0 | table host count types targets' 6 'Detect reverse-shell indicators from the web service account. Isolate WEB01 and review audit trail.'

save_search 'SIEM - MariaDB Root Login - Critical' 'index=mariadb ("root@localhost" OR "User=root" OR "user=root" OR "Access denied") | stats count values(host) as targets by host | where count > 0 | table host count targets' 6 'Detect root or failed root MariaDB access. Disable remote root access and rotate credentials.'

save_search 'SIEM - MariaDB Credential Access - Critical' 'index=mariadb ("mysql.user" OR "FROM users" OR "authentication_string" OR "password") | stats count values(host) as targets by host | where count > 0 | table host count targets' 6 'Detect credential-table or password-field access. Rotate exposed credentials and revoke excess privileges.'

save_search 'SIEM - Password Hash Access - Critical' '(index=mariadb ("mysql.user" OR "authentication_string" OR "FROM users") OR index=linux_audit ("/etc/shadow" OR "smbcred_access" OR ".smbcred")) | stats count values(host) as targets values(sourcetype) as types by host | where count > 0 | table host count types targets' 6 'Detect credential/hash access. Rotate credentials, revoke excess privileges and preserve evidence.'

save_search 'SIEM - Apache Access Log Read - High' 'index=linux_audit host=web01 ("access.log" OR "apache_log_access" OR "/var/log/apache2") | stats count values(host) as targets by host | where count > 0 | table host count targets' 5 'Detect Apache access-log discovery. Review the web process and isolate WEB01 if unauthorized.'

save_search 'SIEM - SSH Lateral Movement From Web - High' 'index=linux_auth ("Accepted password" OR "Accepted publickey" OR "Failed password") | rex field=_raw "(?:from|rhost=)[[:space:]]+(?<src_ip>[0-9]{1,3}([.][0-9]{1,3}){3})" | where src_ip="10.10.20.10" | stats count values(host) as targets by src_ip | where count > 0 | table src_ip count targets' 5 'Detect SSH activity from WEB01 toward internal systems. Isolate WEB01 and review credential reuse.'

save_search 'SIEM - SMB Sensitive File Access - High' '(index=samba OR index=linux_audit) ("smbcred" OR ".smbcred" OR "khachhang.csv" OR "samba_config") | stats count values(host) as targets values(sourcetype) as types by host | where count > 0 | table host count types targets' 5 'Detect SMB credential or sensitive-file access. Revoke exposed SMB credentials and restrict shares.'

save_search 'SIEM - SMB Brute Force - High' 'index=samba ("NT_STATUS_WRONG_PASSWORD" OR "NT_STATUS_LOGON_FAILURE") | rex field=_raw "remote host [[]ipv4:(?<src_ip>[0-9]{1,3}([.][0-9]{1,3}){3})" | stats count as failures values(host) as targets by src_ip | where failures >= 5 | table src_ip failures targets' 5 'Detect repeated SMB authentication failures. Block source IP for 1h and review account lockout.'

printf '%s\n' 'SIEM alert creation/update completed.'
