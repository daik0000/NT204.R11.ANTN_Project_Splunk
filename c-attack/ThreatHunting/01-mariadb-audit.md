# Hướng dẫn a — bật MariaDB Audit Log

Mục tiêu là ghi lại kết nối, câu SQL và thao tác trên table của MariaDB trên
WEB01, sau đó gửi log vào index database_web.

## 1. Kiểm tra audit plugin

Thực hiện trên WEB01:

~~~sql
SHOW VARIABLES LIKE 'plugin_dir';
~~~

Thoát MariaDB rồi kiểm tra plugin:

~~~bash
sudo find /usr/lib /usr/lib64 -name 'server_audit.so' 2>/dev/null
~~~

Nếu chưa có server_audit.so, cài package MariaDB tương thích trước khi tiếp
tục.

## 2. Cài và nạp plugin

~~~bash
sudo mariadb
~~~

~~~sql
INSTALL SONAME 'server_audit';
SHOW PLUGINS;
~~~

Kết quả cần có SERVER_AUDIT ở trạng thái ACTIVE.

## 3. Bật các loại audit cần thiết

~~~sql
SET GLOBAL server_audit_logging = ON;
SET GLOBAL server_audit_events = 'CONNECT,QUERY,TABLE';
SET GLOBAL server_audit_output_type = 'FILE';
SET GLOBAL server_audit_file_path = '/var/log/mysql/audit.log';
~~~

Các event được dùng:

| Event | Ý nghĩa |
|---|---|
| CONNECT | Kết nối/ngắt kết nối và đăng nhập thất bại |
| QUERY | Câu SQL được thực hiện |
| TABLE | Truy cập table |

## 4. Lưu cấu hình sau khi restart

Sửa /etc/mysql/mariadb.conf.d/50-server.cnf:

~~~ini
[mariadb]
plugin_load_add = server_audit
server_audit_logging = ON
server_audit_events = CONNECT,QUERY,TABLE
server_audit_output_type = FILE
server_audit_file_path = /var/log/mysql/audit.log
~~~

Chuẩn bị quyền cho log:

~~~bash
sudo mkdir -p /var/log/mysql
sudo chown mysql:mysql /var/log/mysql
sudo chmod 750 /var/log/mysql
sudo systemctl restart mariadb
sudo systemctl is-active mariadb
~~~

## 5. Kiểm tra log và cấu hình Splunk

~~~bash
sudo mariadb -e 'SELECT * FROM dvwa.users LIMIT 1;'
sudo tail -f /var/log/mysql/audit.log
~~~

Universal Forwarder trên WEB01:

~~~ini
[monitor:///var/log/mysql/audit.log]
disabled = false
index = database_web
sourcetype = mariadb:audit
~~~

Kiểm tra trên Splunk:

~~~spl
index=database_web sourcetype="mariadb:audit" host=web01 earliest=-60m
| table _time user operation source sourcetype _raw
| sort 0 - _time
~~~

Truy vấn MariaDB và cách parse chi tiết được ghi trong
[SPL.md](../../SPL.md). Cấu hình index và input xem tại
[AGENTS.md](../../AGENTS.md).
