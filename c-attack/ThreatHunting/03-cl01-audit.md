# Hướng dẫn c — audit command trên CL01

Mục tiêu là ghi lại command được thực thi bởi mọi user trên CL01 để điều tra
hoạt động sau khi có SSH lateral movement.

## 1. Audit rule

Thêm vào /etc/audit/rules.d/command-execution.rules trên CL01:

~~~text
-a always,exit -F arch=b64 -S execve -F key=command_execution
-a always,exit -F arch=b32 -S execve -F key=command_execution
~~~

Nạp và kiểm tra:

~~~bash
sudo augenrules --load
sudo auditctl -l | grep command_execution
sudo systemctl is-active auditd
~~~

## 2. Gửi log vào Splunk

Universal Forwarder trên CL01, file
/opt/splunkforwarder/etc/system/local/inputs.conf:

~~~ini
[monitor:///var/log/audit/audit.log]
disabled = false
index = linux_audit
sourcetype = auditd
~~~

Kiểm tra:

~~~bash
sudo /opt/splunkforwarder/bin/splunk btool inputs list --debug \
  | grep -A5 '/var/log/audit/audit.log'
sudo /opt/splunkforwarder/bin/splunk restart
~~~

## 3. Truy vấn

Sử dụng SPL 3 trong [SPL.md](../../SPL.md). Query ghép event SYSCALL và
EXECVE theo field audit native, lọc user nhanvien1, rồi ghép arguments thành
full_command.

Khi theo dõi .smbcred, cần có audit rule file-access riêng nếu muốn chứng
minh việc đọc file ở mức file system; linux_audit hiện có command execution
không tự động chứng minh mọi lần đọc file.
