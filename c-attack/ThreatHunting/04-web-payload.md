# Hướng dẫn d — log payload HTTP POST của DVWA

Hướng dẫn này được xây dựng từ
[log_payload_web.md](../../log_payload_web.md). Mục tiêu là ghi payload của
command injection trước khi thực thi command, đồng thời giữ request ID để
đối chiếu với auditd.

## 1. File cần sửa trên WEB01

| File | Vai trò |
|---|---|
| /var/log/dvwa/app_audit.log | File JSONL chứa application audit |
| /var/www/html/DVWA/dvwa/includes/app_audit.php | Helper ghi JSON và wrapper command |
| /var/www/html/DVWA/vulnerabilities/exec/index.php | Nạp helper trước source |
| /var/www/html/DVWA/vulnerabilities/exec/source/low.php | Source DVWA level Low |
| /var/www/html/DVWA/vulnerabilities/exec/source/medium.php | Source DVWA level Medium |
| /var/www/html/DVWA/vulnerabilities/exec/source/high.php | Source DVWA level High |
| /var/www/html/DVWA/vulnerabilities/exec/source/impossible.php | Source DVWA level Impossible |
| /opt/splunkforwarder/etc/system/local/inputs.conf | Monitor file gửi về Splunk |

## 2. Tạo log và cấp quyền

Apache/PHP chạy bằng www-data; Universal Forwarder chạy bằng splunkfwd trong
project:

~~~bash
sudo install -d -o root -g www-data -m 0750 /var/log/dvwa
sudo touch /var/log/dvwa/app_audit.log
sudo chown root:www-data /var/log/dvwa/app_audit.log
sudo chmod 0660 /var/log/dvwa/app_audit.log
sudo setfacl -m u:splunkfwd:rx /var/log/dvwa
sudo setfacl -m u:splunkfwd:r /var/log/dvwa/app_audit.log
~~~

## 3. Nạp helper và sửa source

Tạo helper tại:

~~~text
/var/www/html/DVWA/dvwa/includes/app_audit.php
~~~

Helper cần:

1. Tạo request_id, src_ip, HTTP method, URI, user và security level.
2. Ghi mỗi event thành một dòng JSON.
3. Ghi event phase=start trước shell_exec(), gồm payload và
   executed_command.
4. Ghi event phase=finish sau khi command kết thúc, gồm result và
   duration_ms.

Trong vulnerabilities/exec/index.php, nạp helper trước khi nạp file source:

~~~php
require_once DVWA_WEB_PAGE_TO_ROOT . 'dvwa/includes/app_audit.php';
~~~

Trong từng source level, lưu payload nguyên bản trước khi lọc/validate rồi
thay lời gọi shell_exec() bằng dvwaAppRunCommand(). Không ghi output command
vào audit log nếu output có thể chứa dữ liệu nhạy cảm.

Kiểm tra syntax:

~~~bash
sudo php -l /var/www/html/DVWA/dvwa/includes/app_audit.php
sudo php -l /var/www/html/DVWA/vulnerabilities/exec/index.php
for f in /var/www/html/DVWA/vulnerabilities/exec/source/*.php; do
  sudo php -l "$f"
done
~~~

## 4. Forward vào Splunk

Thêm vào /opt/splunkforwarder/etc/system/local/inputs.conf trên WEB01:

~~~ini
[monitor:///var/log/dvwa/app_audit.log]
disabled = false
index = web
sourcetype = dvwa:application
~~~

Kiểm tra bằng btool, reload Universal Forwarder rồi gửi payload vô hại
127.0.0.1;id trong lab. Phải thấy cả event phase=start và phase=finish.

## 5. Truy vấn

Sử dụng SPL 5 trong [SPL.md](../../SPL.md) để xem payload, request ID,
command và kết quả. Access log Apache chỉ cho biết request;
app_audit.log mới chứa payload POST nguyên bản.
