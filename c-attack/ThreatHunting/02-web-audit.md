# Hướng dẫn b — audit process và network của WEB01

Mục tiêu là ghi lại command được thực thi bởi www-data và các kết nối
network do service account này tạo ra.

## 1. Audit rule trên WEB01

Thêm vào /etc/audit/rules.d/web.rules:

~~~text
-a always,exit -F arch=b64 -S execve -F euid=33 -F key=web_process_exec
-a always,exit -F arch=b32 -S execve -F euid=33 -F key=web_process_exec
-a always,exit -F arch=b64 -S connect -F euid=33 -F key=web_network_connect
-a always,exit -F arch=b32 -S connect -F euid=33 -F key=web_network_connect
~~~

- web_process_exec: ghi command, executable và arguments của www-data.
- web_network_connect: ghi syscall connect() của www-data.

Nạp và kiểm tra rule:

~~~bash
sudo augenrules --load
sudo auditctl -l | grep -E 'web_process_exec|web_network_connect'
sudo systemctl is-active auditd
~~~

## 2. Gửi audit log vào Splunk

Universal Forwarder trên WEB01, file
/opt/splunkforwarder/etc/system/local/inputs.conf:

~~~ini
[monitor:///var/log/audit/audit.log]
disabled = false
index = linux_audit
sourcetype = auditd
~~~

Kiểm tra cấu hình:

~~~bash
sudo /opt/splunkforwarder/bin/splunk btool inputs list --debug \
  | grep -A5 '/var/log/audit/audit.log'
sudo /opt/splunkforwarder/bin/splunk restart
~~~

## 3. Truy vấn

Sử dụng SPL 1 trong [SPL.md](../../SPL.md) để ghép SYSCALL và EXECVE,
lấy đầy đủ arguments và trạng thái thành công/thất bại. Dùng SPL 4 để kiểm
tra network connection theo key web_network_connect.

Lưu ý: event SYSCALL hiện có process và syscall result nhưng chưa chắc có
IP/port đích đã giải mã. Muốn có địa chỉ đích cần thêm event SOCKADDR hoặc
log từ ứng dụng/WAF.
