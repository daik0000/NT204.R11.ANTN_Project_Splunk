# Hướng dẫn e — bật Samba full audit và index SMB

Hướng dẫn này tóm tắt triển khai thực tế trong
[log_smb.md](../../log_smb.md). Mục tiêu là ghi user, client, share,
operation, result và object khi CL01 truy cập Samba trên SRV01.

## 1. Cài module và cấu hình Samba trên SRV01

~~~bash
sudo apt-get install -y samba-vfs-modules acl
sudo test -f /usr/lib/x86_64-linux-gnu/samba/vfs/full_audit.so
~~~

Trong /etc/samba/smb.conf, tại mỗi share cần audit, thêm:

~~~ini
vfs objects = full_audit
full_audit:prefix = %u|%I|%m|%S
full_audit:success = connect disconnect open close pread pwrite read write fdopendir readdir freaddir_attr mkdirat renameat unlinkat
full_audit:failure = all
full_audit:facility = LOCAL7
full_audit:priority = NOTICE
~~~

Tên operation phải phù hợp với phiên bản Samba đang chạy. Với Samba 4.23
trong lab, dùng readdir, mkdirat, renameat, unlinkat; các tên cũ như
opendir, mkdir, rmdir, rename, unlink làm module không khởi tạo.

Kiểm tra và reload:

~~~bash
sudo testparm -s
sudo systemctl reload smbd
sudo systemctl is-active smbd
~~~

## 2. Route syslog vào file audit

Tạo /etc/rsyslog.d/35-samba-full-audit.conf:

~~~conf
$FileOwner root
$FileGroup syslog
$FileCreateMode 0660
local7.notice    /var/log/samba/full_audit.log
& stop
~~~

Đảm bảo splunkfwd đọc được thư mục và file:

~~~bash
sudo setfacl -m u:splunkfwd:--x /var/log/samba
sudo setfacl -m u:splunkfwd:r /var/log/samba/full_audit.log
sudo systemctl restart rsyslog
sudo systemctl reload smbd
~~~

Thiết lập logrotate cho /var/log/samba/full_audit.log và giữ lại ACL sau
khi rotate. Chi tiết backup, ACL và lỗi operation list xem trong
[log_smb.md](../../log_smb.md).

## 3. Forward và tạo index

Universal Forwarder trên SRV01:

~~~ini
[monitor:///var/log/samba/full_audit.log]
disabled = false
index = smb
sourcetype = samba:full_audit
~~~

Tạo index smb trên SPLUNK01 rồi kiểm tra:

~~~spl
index=smb earliest=-30m
| stats count by host source sourcetype
~~~

## 4. Kiểm thử

Từ CL01 thực hiện một phiên SMB trong lab, ví dụ liệt kê share hoặc đọc
khachhang.csv. Raw record có dạng:

~~~text
timestamp host smbd_audit:user|client_ip|client_host|share|operation|result|object
~~~

## 5. Truy vấn

Sử dụng SPL 6 trong [SPL.md](../../SPL.md). Query parse các field:
audit_user, client_ip, client_host, share, operation, result và object; phiên
bản hiện tại chỉ giữ action_result=success.
