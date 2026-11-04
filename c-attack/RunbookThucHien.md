# Runbook thực hiện KichBanTanCong

## 1. Chuẩn bị và truyền script

### Chuyển script vào CL01

**Chạy trên máy đang chứa repository:**

~~~bash
ssh labadmin@10.10.10.11 'mkdir -p ~/scripts'

scp c-attack/scripts/00-dvwa-login.sh \
    c-attack/scripts/01-recon-nmap.sh \
    c-attack/scripts/02-dvwa-login-bruteforce.sh \
    c-attack/scripts/03-dvwa-command-injection.sh \
    c-attack/scripts/03-reverse-shell-controlled.sh \
    c-attack/scripts/06-apache-log-read.sh \
    c-attack/scripts/08-smb-access.sh \
    labadmin@10.10.10.11:~/scripts/

ssh labadmin@10.10.10.11 \
  'chmod 750 ~/scripts/*.sh'
~~~

### Chuyển script vào WEB01

**Chạy trên máy đang chứa repository:**

~~~bash
ssh labadmin@10.10.20.10 'mkdir -p ~/scripts'

scp c-attack/scripts/04-mariadb-root-check.sh \
    c-attack/scripts/05-dvwa-credential-access.sh \
    c-attack/scripts/07-ssh-lateral.sh \
    labadmin@10.10.20.10:~/scripts/

ssh labadmin@10.10.20.10 \
  'chmod 750 ~/scripts/*.sh'
~~~

### Chuyển cleanup vào SPLUNK01

**Chạy trên máy đang chứa repository:**

~~~bash
ssh labadmin@10.10.40.20 'mkdir -p ~/scripts'

scp c-attack/scripts/09-final-cleanup.sh \
    labadmin@10.10.40.20:~/scripts/

ssh labadmin@10.10.40.20 \
  'chmod 750 ~/scripts/09-final-cleanup.sh'
~~~

## Topology và biến sử dụng

| Máy | IP sử dụng trong diễn tập | Vai trò |
|---|---|---|
| FW01 | 10.10.40.254 | nftables gateway |
| SPLUNK01 | 10.10.40.20 | Splunk Enterprise |
| SRV01 | 10.10.10.10 | MariaDB/Samba |
| CL01 | 10.10.10.11 | nguồn mô phỏng client/Kali |
| WEB01 | 10.10.20.10 | Apache/DVWA/MariaDB |

Các script nằm trong thư mục `scripts/` cạnh file này. Ví dụ:

**Chạy trên máy thực hiện diễn tập, thường là CL01:**

~~~bash
export LAB_CONFIRM=NT204-LAB
export WEB_IP=10.10.20.10
export CL01_IP=10.10.10.11
export SRV01_IP=10.10.10.10
~~~

Tạo cookie DVWA dùng chung cho các stage web.

**Chạy trên CL01:**

~~~bash
export LAB_CONFIRM=NT204-LAB
export DVWA_USER=admin
read -rsp 'DVWA password: ' DVWA_PASSWORD; echo
export DVWA_PASSWORD
export DVWA_COOKIE=/tmp/dvwa-auth-user.cookie
bash scripts/00-dvwa-login.sh
trap 'unlink "$DVWA_COOKIE" 2>/dev/null || true' EXIT
~~~

## 3. Kiểm tra trước khi chạy

Trên từng máy cần kiểm tra service liên quan:

~~~bash
systemctl is-active SplunkForwarder.service 2>/dev/null || true
systemctl is-active auditd 2>/dev/null || true
systemctl is-active apache2 2>/dev/null || true
systemctl is-active mariadb 2>/dev/null || true
systemctl is-active smbd 2>/dev/null || true
~~~

Trên SPLUNK01:

~~~bash
sudo systemctl is-active splunk
sudo /opt/splunk/bin/splunk btool inputs list --debug | grep -E 'udp://1514|audit.log|mariadb|samba|fw01.log'
~~~

Trên FW01:

~~~bash
sudo nft list set inet filter blocked_src
sudo nft list ruleset | grep -E 'FW-DNAT-WEB|blocked_src|FW-DROP'
~~~

## 4. Stage 1 — Recon bằng nmap

### 4.1. Thực hiện trên CL01

~~~bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y nmap
command -v nmap
sudo nmap -sS -Pn -p 1-100 "$WEB_IP" -oN /tmp/nmap-web01.txt
cat /tmp/nmap-web01.txt
~~~

Script tự động tương ứng: `scripts/01-recon-nmap.sh`.

Kết quả đã thực hiện:

- WEB01 mở TCP/22 và TCP/80.
- 98 cổng trong dải 1–100 bị firewall lọc.
- Alert `SIEM - Recon Port Scan - Medium` trả `src_ip=10.10.10.11`, `scan_hits=196` trong cửa sổ kiểm tra.

### 4.2. Kiểm tra Splunk

~~~spl
| savedsearch "SIEM - Recon Port Scan - Medium"
~~~

Hoặc kiểm tra firewall trực tiếp:

~~~spl
index=firewall ("FW-DROP" OR "FW-DNAT-WEB") earliest=-15m
| rex field=_raw "SRC=(?<src_ip>[0-9.]+)"
| stats count by src_ip host sourcetype source
~~~

### 4.3. Khắc phục và cleanup

Auto-response gọi `fw_auto_block_monitor.sh`, sau đó `fw_block_ip.sh` thêm nguồn vào `blocked_src` trong 1 giờ.

Kiểm tra:

~~~bash
sudo nft list set inet filter blocked_src
~~~

Sau diễn tập, xóa IP test:

~~~bash
sudo nft delete element inet filter blocked_src { 10.10.10.11 }
~~~

## 5. Stage 2 — DVWA login brute-force

### 5.1. Chuẩn bị trên CL01

Đăng nhập DVWA bằng credential lab qua biến môi trường; không ghi password vào command history. Nếu chưa tạo cookie ở phần chuẩn bị, chạy `scripts/00-dvwa-login.sh` trước:

~~~bash
export DVWA_USER=admin
read -rsp 'DVWA password: ' DVWA_PASSWORD; echo
export DVWA_PASSWORD
~~~

Chạy:

~~~bash
bash scripts/02-dvwa-login-bruteforce.sh
~~~

Script thực hiện 12 POST sai có `user_token` hợp lệ tới `/DVWA/login.php`.

### 5.2. Kiểm tra Splunk

~~~spl
| savedsearch "SIEM - DVWA Login Brute Force - High"
~~~

Đối chiếu Apache:

~~~spl
index=web ("POST /DVWA/login.php" OR "POST /dvwa/login.php") earliest=-15m
| rex field=_raw "^(?<src_ip>[0-9.]+)"
| stats count as attempts by src_ip host
~~~

Kết quả đã thực hiện: Apache ghi nhiều POST từ CL01; alert đạt ngưỡng `attempts >= 10`.

### 5.3. Khắc phục

- Block IP nguồn trong 1 giờ.
- Bật rate limit/account lockout ở ứng dụng.
- Kiểm tra tài khoản admin và rotate credential nếu có login thành công.
- Xóa cookie tạm trên CL01.

## 6. Stage 3 — Command injection và reverse shell có kiểm soát

### 6.1. Xác nhận command injection không phá hoại

Trên CL01, sau khi đã có `DVWA_COOKIE`, gửi payload `127.0.0.1;id`:

~~~bash
bash scripts/03-dvwa-command-injection.sh
~~~

Kết quả đã thực hiện: response xác nhận `uid=33(www-data)`.

Kiểm tra alert:

~~~spl
| savedsearch "SIEM - DVWA Command Injection - Critical"
~~~

### 6.2. Mở rule callback tạm thời trên FW01

Chỉ chạy trong lab và chỉ mở đúng nguồn/đích/port:

~~~bash
sudo nft insert rule inet filter forward \
  iifname eth2 oifname eth1 \
  ip saddr 10.10.20.10 ip daddr 10.10.10.11 \
  tcp dport 4444 accept
sudo nft -a list chain inet filter forward | grep 'tcp dport 4444 accept'
~~~

Ghi lại handle của rule để rollback.

### 6.3. Chạy callback tương tác có timeout

Trên CL01, script `scripts/03-reverse-shell-controlled.sh`:

~~~bash
export LAB_CONFIRM=NT204-LAB
bash scripts/03-reverse-shell-controlled.sh
~~~

Script dùng listener timeout 15 giây, gửi `id`, gửi `exit`, sau đó tự dừng. Không thực hiện persistence và không stabilize shell.

Kết quả đã thực hiện:

- Listener nhận kết nối từ `10.10.20.10`.
- Shell chạy dưới `www-data`.
- Lệnh `id` trả `uid=33(www-data)`.
- Shell đã nhận `exit`.

Kiểm tra:

~~~spl
| savedsearch "SIEM - Web Reverse Shell Indicator - Critical"
~~~

~~~spl
index=linux_audit host=web01 ("web_process_exec" OR "web_network_connect") earliest=-15m
| stats count values(key) by host sourcetype
~~~

### 6.4. Cleanup bắt buộc

~~~bash
sudo nft delete rule inet filter forward handle <HANDLE_4444>
sudo nft list chain inet filter forward | grep 4444 || true
ss -lntup | grep 4444 || true
pgrep -af 'nc.*4444|bash -i' || true
~~~

Khắc phục khi phát hiện thật: cô lập WEB01, giữ evidence, kiểm tra process/outbound connection, sửa input validation và rotate credential.

## 7. Stage 4 — MariaDB root không password

### 7.1. Kiểm tra trên WEB01

~~~bash
sudo mariadb --batch --skip-column-names -e \
"SELECT User,Host,plugin,LENGTH(authentication_string) \
 FROM mysql.user WHERE User='root';"
sudo mariadb -e "SELECT User,Host FROM mysql.user LIMIT 5;"
~~~

Script tương ứng: `scripts/04-mariadb-root-check.sh`.

Kết quả đã thực hiện: `root@localhost` dùng `mysql_native_password`, độ dài authentication string bằng 0; chỉ đọc, không đổi dữ liệu.

### 7.2. Kiểm tra Splunk và khắc phục

~~~spl
| savedsearch "SIEM - MariaDB Root Login - Critical"
~~~

Khắc phục: đặt password mạnh hoặc dùng `unix_socket`, cấm root remote login, tạo account quản trị riêng và rotate credential.

## 8. Stage 5 — Credential access và offline hash check

### 8.1. Truy vấn chỉ đọc trên WEB01

~~~bash
bash scripts/05-dvwa-credential-access.sh
~~~

Script đọc bảng `dvwa.users` vào file tạm có quyền 600, tùy chọn đối chiếu MD5 với file candidate offline rồi xóa file. Không ghi hash hoặc password vào repository. Khi cần kiểm tra dictionary:

~~~bash
export CANDIDATES_FILE=/path/to/lab-candidates.txt
bash scripts/05-dvwa-credential-access.sh
~~~

Truy vấn Splunk:

~~~spl
| savedsearch "SIEM - MariaDB Credential Access - Critical"
~~~

~~~spl
| savedsearch "SIEM - Password Hash Access - Critical"
~~~

Kết quả đã thực hiện: alert MariaDB Credential Access và Password Hash Access phát hiện truy cập; file tạm đã xóa.

### 8.2. Khắc phục

Xem toàn bộ credential là đã lộ: rotate password, revoke privilege, kiểm tra credential reuse trên CL01/SRV01 và kiểm tra login bất thường.

## 9. Stage 6 — Đọc Apache access log

### 9.1. Thực hiện qua command injection

~~~bash
bash scripts/06-apache-log-read.sh
~~~

Payload chỉ đọc phần đầu log:

~~~text
127.0.0.1;head -n 20 /var/log/apache2/access.log
~~~

### 9.2. Kiểm tra và khắc phục

~~~spl
| savedsearch "SIEM - Apache Access Log Read - High"
~~~

~~~spl
index=linux_audit host=web01 apache_log_access earliest=-15m
| stats count values(uid) values(comm) by host key
~~~

Khắc phục: kiểm tra process dưới `www-data`, giới hạn quyền đọc log, tách quyền web khỏi quyền quản trị và điều tra command chain.

## 10. Stage 7 — SSH lateral movement

### 10.1. Thực hiện từ WEB01 tới CL01

Trên WEB01, nhập password khi SSH hỏi; không ghi password vào script:

~~~bash
bash scripts/07-ssh-lateral.sh
~~~

Script chỉ chạy marker `LATERAL_SSH_LAB` và `id`, không sửa file/quyền trên CL01.

### 10.2. Kiểm tra và khắc phục

~~~spl
| savedsearch "SIEM - SSH Lateral Movement From Web - High"
~~~

~~~spl
index=linux_auth ("Accepted password" OR "LATERAL_SSH_LAB") earliest=-15m
| stats count values(src_ip) values(user) by host
~~~

Kết quả đã thực hiện: nguồn `10.10.20.10`, đích CL01; Splunk nhận event SSH/auth.

Khắc phục: cô lập WEB01, vô hiệu hóa credential reuse, rotate credential và rà soát các host đã nhận login.

## 11. Stage 8 — SMB authentication và sensitive file access

### 11.1. Thực hiện từ CL01 tới SRV01

~~~bash
export SMB_USER=ketoan1
read -rsp 'SMB password: ' SMB_PASSWORD; echo
export SMB_PASSWORD
bash scripts/08-smb-access.sh
~~~

Script thực hiện login sai, login đúng, liệt kê share, đọc `khachhang.csv` vào `/tmp`, rồi xóa bản sao; sau đó tạo 5 login sai để kiểm tra brute-force.

### 11.2. Kiểm tra Splunk

~~~spl
| savedsearch "SIEM - SMB Authentication Failure - High"
~~~

~~~spl
| savedsearch "SIEM - SMB Brute Force - High"
~~~

~~~spl
| savedsearch "SIEM - SMB Sensitive File Access - High"
~~~

Kết quả đã thực hiện:

- Có `NT_STATUS_WRONG_PASSWORD`.
- SMB brute-force đạt `failures >= 5`.
- Sensitive file access được audit và alert.

Khắc phục: block IP nguồn, đổi SMB credential, giới hạn share/ACL, bật lockout và kiểm tra file đã bị đọc.

## 12. Cleanup cuối phiên

Trên FW01:

~~~bash
sudo nft list set inet filter blocked_src
sudo nft -a list chain inet filter forward | grep 4444 || true
~~~

Nếu còn IP test:

~~~bash
sudo nft delete element inet filter blocked_src { 10.10.10.11 }
~~~

Có thể chạy cleanup chuẩn từ SPLUNK01 bằng script `scripts/09-final-cleanup.sh` sau khi khai báo `FW_SSH_KEY` và `FW_KNOWN_HOSTS`.

Trên CL01/WEB01:

~~~bash
ss -lntup | grep -E '4444|9999' || true
pgrep -af 'nc.*4444|bash -i|DVWA' || true
~~~

Trên SPLUNK01:

~~~bash
sudo systemctl is-active splunk
sudo /opt/splunk/bin/splunk btool savedsearches list --debug | grep -E 'SIEM -|disabled = false'
~~~

Trạng thái sau lần diễn tập đã ghi nhận: `blocked_src` rỗng, không còn rule/listener/process callback, Splunk active và 18 saved search enabled.

## 13. Playbook alert và phòng thủ chi tiết

Phần này là quy trình xử lý trực tiếp sau khi từng alert xuất hiện. Phạm vi chỉ gồm FW01, SPLUNK01, SRV01, CL01 và WEB01 trong lab. `SRC_IP` là IP lấy từ kết quả Splunk. Mật khẩu không ghi vào file.

### 15.1. Recon/nmap — Medium

Kiểm tra alert:

~~~spl
| savedsearch "SIEM - Recon Port Scan - Medium"
~~~

Kết quả cần thấy:

~~~text
src_ip=10.10.10.11 scan_hits=196 firewall=10.10.40.254
~~~

Đối chiếu raw firewall:

~~~spl
index=firewall earliest=-15m ("FW-DROP" OR "FW-DNAT-WEB")
| rex field=_raw "SRC=(?<src_ip>[0-9.]+)"
| table _time host src_ip _raw
| sort - _time
~~~

Raw log phải có dạng `FW-DROP ... SRC=10.10.10.11 ...`.

Block IP trên SPLUNK01:

~~~bash
case "$SRC_IP" in
  10.10.10.1|10.10.10.254|10.10.20.254|10.10.40.20|10.10.40.254) echo EXCLUDED; exit 1;;
esac
sudo -u splunk /opt/splunk/bin/scripts/fw_block_ip.sh "$SRC_IP"
~~~

Kiểm tra trên FW01 và SPLUNK01:

~~~bash
sudo nft list set inet filter blocked_src
sudo journalctl -t splunk-fw-block --since "5 minutes ago" --no-pager
~~~

Kết quả cần có `elements = { 10.10.10.11 expires 59m... }` và `blocked_ip=10.10.10.11 duration=1h`.

Nếu nguồn là CL01, dừng nmap trên CL01 và điều tra process. Sau diễn tập rollback:

~~~bash
sudo nft delete element inet filter blocked_src { 10.10.10.11 }
sudo nft list set inet filter blocked_src
~~~

### 15.2. DVWA login brute-force — High

Kiểm tra alert:

~~~spl
| savedsearch "SIEM - DVWA Login Brute Force - High"
~~~

Kết quả cần thấy:

~~~text
src_ip=10.10.10.11 attempts=12 targets=web01
~~~

Đối chiếu Apache:

~~~spl
index=web ("POST /DVWA/login.php" OR "POST /dvwa/login.php") earliest=-15m
| rex field=_raw "^(?<src_ip>[0-9.]+)"
| stats count as attempts values(status) as status by src_ip host
~~~

Raw log thường là:

~~~text
10.10.10.11 - - [date] "POST /DVWA/login.php HTTP/1.1" 302 ...
~~~

Xử lý trên SPLUNK01:

~~~bash
sudo -u splunk /opt/splunk/bin/scripts/fw_block_ip.sh 10.10.10.11
~~~

Xác nhận trên FW01:

~~~bash
sudo nft list set inet filter blocked_src
~~~

Kiểm tra login thành công sau brute-force:

~~~spl
index=web earliest=-15m ("POST /DVWA/login.php" OR "Location: index.php")
| rex field=_raw "^(?<src_ip>[0-9.]+)"
| table _time src_ip status _raw
| sort - _time
~~~

Nếu có login thành công, trên WEB01 backup và đổi password admin:

~~~bash
sudo mariadb -e "CREATE TABLE IF NOT EXISTS dvwa.users_backup_response AS SELECT * FROM dvwa.users;"
read -rsp 'New DVWA admin password: ' NEW_DVWA_PASSWORD; echo
NEW_HASH="$(printf '%s' "$NEW_DVWA_PASSWORD" | md5sum | awk '{print $1}')"
sudo mariadb -e "UPDATE dvwa.users SET password='${NEW_HASH}', failed_login=0 WHERE user='admin';"
unset NEW_DVWA_PASSWORD NEW_HASH
~~~

Kiểm tra query đổi credential:

~~~spl
index=mariadb host=web01 earliest=-10m ("UPDATE" OR "dvwa.users")
| table _time host source _raw
~~~

Xóa cookie tạm trên CL01:

~~~bash
unlink /tmp/dvwa-auth-user.cookie 2>/dev/null || true
~~~

Rate-limit/account-lockout là hardening trên WEB01, chưa phải auto-response hiện tại. Nếu được phép cài trong lab:

~~~bash
sudo apache2ctl -M | grep -E 'evasive|security2' || true
sudo apt-get install -y libapache2-mod-evasive
sudo a2enmod evasive
sudo systemctl restart apache2
sudo systemctl is-active apache2
~~~

Output cần là `active`. Kiểm tra bị giới hạn:

~~~spl
index=web host=web01 earliest=-10m (" 403 " OR " 429 ")
| stats count by status
~~~

### 15.3. Command injection/reverse shell — Critical

Kiểm tra alert:

~~~spl
| savedsearch "SIEM - DVWA Command Injection - Critical"
| savedsearch "SIEM - Web Reverse Shell Indicator - Critical"
~~~

Audit WEB01 cần có dạng:

~~~text
key=web_process_exec ... comm="bash" ... uid=33
key=web_network_connect ... uid=33
~~~

Kiểm tra process/kết nối và lưu evidence trên WEB01:

~~~bash
ps -ef --forest | grep -E 'www-data|bash|nc|python' | grep -v grep
sudo ss -ntp
sudo journalctl -u apache2 --since "15 minutes ago" --no-pager > /root/incident-apache.log
sudo ausearch -k web_process_exec -ts recent > /root/incident-web-process.audit || true
sudo ausearch -k web_network_connect -ts recent > /root/incident-web-network.audit || true
~~~

Dừng đúng process đáng ngờ:

~~~bash
sudo kill -TERM <PID>
sleep 2
sudo kill -KILL <PID> 2>/dev/null || true
~~~

Cô lập WEB01 bằng console/hypervisor hoặc rule FW01 đã được duyệt. Nếu có source IP, block trên SPLUNK01:

~~~bash
sudo -u splunk /opt/splunk/bin/scripts/fw_block_ip.sh "$SRC_IP"
~~~

Xác nhận sạch:

~~~bash
pgrep -af 'bash -i|nc.*4444|python.*pty' || true
sudo ss -ntp | grep -E '4444|443' || true
sudo nft -a list chain inet filter forward | grep 4444 || true
~~~

Gỡ rule callback lab theo handle:

~~~bash
sudo nft delete rule inet filter forward handle <HANDLE_4444>
~~~

### 15.4. MariaDB root login không an toàn — Critical

Kiểm tra alert và trạng thái root trên WEB01:

~~~spl
| savedsearch "SIEM - MariaDB Root Login - Critical"
~~~

~~~bash
sudo mariadb --batch --skip-column-names -e \
"SELECT User,Host,plugin,LENGTH(authentication_string) FROM mysql.user WHERE User='root';"
~~~

Output nguy hiểm là `root localhost mysql_native_password 0`. Đối chiếu:

~~~spl
index=mariadb host=web01 earliest=-15m ("root" OR "mysql.user")
| table _time host source _raw
~~~

Khắc phục trên WEB01:

~~~bash
sudo mariadb -e "SELECT User,Host,plugin FROM mysql.user;" > /root/mariadb-users-before-response.txt
sudo mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket; FLUSH PRIVILEGES;"
sudo mariadb -e "SELECT User,Host FROM mysql.user WHERE User='root';"
~~~

Nếu vẫn có root login mới, giữ evidence và điều tra client; không xóa event lịch sử.

### 15.5. Credential/hash access — Critical

Kiểm tra alert:

~~~spl
| savedsearch "SIEM - MariaDB Credential Access - Critical"
| savedsearch "SIEM - Password Hash Access - Critical"
~~~

Query nhạy cảm thường chứa `dvwa.users`, `mysql.user`, `password` hoặc `authentication_string`:

~~~spl
index=mariadb host=web01 earliest=-15m ("dvwa.users" OR "mysql.user" OR "authentication_string")
| table _time user host source _raw
~~~

Khắc phục trên WEB01:

~~~bash
sudo mariadb -e "SELECT User,Host,Grant_priv,Super_priv,Create_user_priv FROM mysql.user;" > /root/mariadb-privileges-before-response.txt
sudo mariadb -e "SHOW GRANTS FOR 'dvwa'@'localhost';"
~~~

Sau khi xác định account: đổi secret ứng dụng, revoke quyền dư thừa và kiểm tra credential reuse trên CL01/SRV01. Không chạy `DROP USER` khi chưa xác định account.

Kiểm tra sau xử lý:

~~~spl
index=mariadb host=web01 earliest=-10m ("GRANT" OR "ALTER USER" OR "REVOKE")
| table _time user host _raw
~~~

### 15.6. Đọc Apache access.log — High

Kiểm tra alert và audit trên WEB01:

~~~spl
| savedsearch "SIEM - Apache Access Log Read - High"
~~~

~~~spl
index=linux_audit host=web01 ("apache_log_access" OR "/var/log/apache2/access.log") earliest=-15m
| table _time host uid auid comm exe key _raw
~~~

Khắc phục:

~~~bash
sudo namei -l /var/log/apache2/access.log
sudo ps -o user,pid,ppid,cmd -C apache2
sudo ausearch -k apache_log_access -ts recent
sudo systemctl is-active apache2
~~~

Nếu `www-data` không cần đọc log, chuyển việc đọc log cho collector/group riêng; không cấp quyền quản trị cho `www-data`. Output cuối cần là `active`.

### 15.7. SSH lateral movement từ WEB01 — High

Kiểm tra alert:

~~~spl
| savedsearch "SIEM - SSH Lateral Movement From Web - High"
~~~

Output cần có:

~~~text
src_ip=10.10.20.10 count=1 targets=cl01
~~~

Đối chiếu trên CL01:

~~~spl
index=linux_auth host=cl01 earliest=-15m ("Accepted password" OR "LATERAL_SSH_LAB")
| rex field=_raw "from[[:space:]]+(?<src_ip>[0-9.]+)"
| table _time user src_ip host _raw
~~~

Raw log cần có dạng `Accepted password for nhanvien1 from 10.10.20.10 ... ssh2`.

Khắc phục trên CL01:

~~~bash
sudo passwd -l nhanvien1
sudo loginctl terminate-user nhanvien1 2>/dev/null || true
who
ps -fu nhanvien1
~~~

Đổi credential đó trên mọi máy dùng lại. Nếu cần block nguồn:

~~~bash
sudo -u splunk /opt/splunk/bin/scripts/fw_block_ip.sh 10.10.20.10
~~~

Xác nhận không còn login mới:

~~~spl
index=linux_auth ("Accepted password" OR "Accepted publickey") earliest=-10m
| search src_ip=10.10.20.10
| stats count by host user
~~~

### 15.8. SMB brute-force/sensitive file — High

Kiểm tra alert:

~~~spl
| savedsearch "SIEM - SMB Authentication Failure - High"
| savedsearch "SIEM - SMB Brute Force - High"
| savedsearch "SIEM - SMB Sensitive File Access - High"
~~~

Output cần có:

~~~text
src_ip=10.10.10.11 failures=8 targets=srv01
~~~

Raw Samba thường có `NT_STATUS_WRONG_PASSWORD ... remote host [ipv4:10.10.10.11]`; audit nhạy cảm có `smbcred_access`, `samba_config` hoặc `user_files`.

Khắc phục trên SRV01:

~~~bash
sudo -u splunk /opt/splunk/bin/scripts/fw_block_ip.sh 10.10.10.11
sudo testparm -s
sudo smbstatus
sudo ls -ld /srv /srv/samba /home/ketoan1 /home/nhansu1 2>/dev/null || true
~~~

Sau khi xác định account bị lộ:

~~~bash
sudo smbpasswd -d <USER>
sudo smbpasswd <USER>
~~~

Kiểm tra event mới:

~~~spl
index=samba host=srv01 earliest=-10m
| stats count by _raw
~~~

Xóa file test trên CL01:

~~~bash
unlink /tmp/khachhang.csv 2>/dev/null || true
~~~

### 15.9. Kiểm tra sau xử lý và cleanup chung

Trên FW01:

~~~bash
sudo nft list set inet filter blocked_src
sudo nft -a list chain inet filter forward | grep 4444 || true
~~~

Trên CL01/WEB01:

~~~bash
ss -lntup | grep -E '4444|9999' || true
pgrep -af 'nc.*4444|bash -i|python.*pty' || true
~~~

Trên SPLUNK01:

~~~bash
sudo systemctl is-active splunk
sudo journalctl -t splunk-fw-block --since "15 minutes ago" --no-pager
~~~

Trạng thái sạch: `blocked_src` không còn IP test, không còn rule TCP/4444, không còn listener/process test; event cũ vẫn giữ nguyên làm evidence.

## 14. Rollback và escalation

- Nếu SSH quản trị bị mất: dùng console VM, nạp `/root/fw01-ruleset-before.nft` trên FW01.
- Nếu Splunk input sai: khôi phục `/root/splunk-inputs-before-fwlog.conf` và `/root/search-inputs-before-fwlog.conf` rồi restart Splunk.
- Nếu audit rule gây quá nhiều event: khôi phục `/root/audit.rules-before-siem`, chạy `augenrules --load` và kiểm tra auditd.
- Nếu MariaDB general log làm tăng dung lượng: `SET GLOBAL general_log = OFF`, sau đó rollback file cấu hình.
- Sự kiện Critical thật phải cô lập host, bảo toàn evidence và báo người phụ trách lab trước khi rotate/xóa dữ liệu.

## 15. Liên kết tài liệu

- Kịch bản gốc: `KichBan.md`.
- Báo cáo kết quả: `KetQuaThucHien.md`.
- Alert/auto-response: `../../b-siem/scripts/`.
- Runbook triển khai hạ tầng: `../../CL01-UF-FIX-QUICK.md`.
