# HƯỚNG DẪN LAB NT240 — SPLUNK ENTERPRISE VÀ UNIVERSAL FORWARDER

---

## 1. Sơ đồ địa chỉ IP của lab

| Máy | Mạng | Địa chỉ IP |
| --- | --- | --- |
| FW01 | WAN (VMnet8) | DHCP |
| FW01 | LAN (VMnet2) | `10.10.10.254` |
| FW01 | DMZ (VMnet3) | `10.10.20.254` |
| FW01 | SIEM (VMnet4) | `10.10.40.254` |
| SRV01 | LAN | `10.10.10.10` |
| CL01 | LAN | `10.10.10.11` |
| WEB01 | DMZ | `10.10.20.10` |
| SPLUNK01 | SIEM | `10.10.40.20` |
| KALI | WAN (VMnet8) | DHCP |

**[GIẢI THÍCH]** FW01 là gateway của LAN, DMZ và SIEM. KALI và cổng WAN của FW01 nhận IP động từ VMware NAT.

### 1.1. UFW trên máy host của người dựng lab

Này firewall trên máy tui thôi, ae không bị thì không cần chạy 

**[CHẠY LỆNH — HOST, giao diện `enp0s20f0u6`]**

```bash
sudo ufw route allow in on virbr-n204-wan out on enp0s20f0u6 from 192.168.100.0/24 to any port 53 proto udp
sudo ufw route allow in on virbr-n204-wan out on enp0s20f0u6 from 192.168.100.0/24 to any port 53 proto tcp
sudo ufw route allow in on virbr-n204-wan out on enp0s20f0u6 from 192.168.100.0/24 to any proto tcp
sudo ufw route allow in on virbr-n204-wan out on enp0s20f0u6 from 192.168.100.0/24 to any proto udp
sudo ufw reload
```

**[CHẠY LỆNH — HOST, giao diện `wlan0`]**

```bash
sudo ufw route allow in on virbr-n204-wan out on wlan0 from 192.168.100.0/24 to any port 53 proto udp
sudo ufw route allow in on virbr-n204-wan out on wlan0 from 192.168.100.0/24 to any port 53 proto tcp
sudo ufw route allow in on virbr-n204-wan out on wlan0 from 192.168.100.0/24 to any proto tcp
sudo ufw route allow in on virbr-n204-wan out on wlan0 from 192.168.100.0/24 to any proto udp
sudo ufw reload
```

---

## 2. Cài Splunk Enterprise trên SPLUNK01

**Phiên bản ghi nhận trong lab:** `10.6.1.1`.

### 2.1. Tải bộ cài

**[THAO TÁC TRÊN TRÌNH DUYỆT]**

1. Mở: https://www.splunk.com/en_us/download.html
2. Chọn **Splunk Enterprise**.
3. Tải gói `.deb`.

Có up trong link : https://drive.google.com/drive/u/2/folders/1X-hp3dDqI-HjlslgDP9TM61Rt9j9H1Y7
### 2.2. Chuyển bộ cài sang SPLUNK01

**[CHẠY LỆNH — MÁY ĐANG CHỨA FILE `.deb`]**

```bash
scp splunk-*.deb labadmin@10.10.40.20:~/
```

### 2.3. Cài đặt Splunk Enterprise

**[CHẠY LỆNH — SPLUNK01]**

```bash
sudo dpkg -i ./splunk-*.deb
```

**[GIẢI THÍCH]** Thư mục cài đặt mặc định: `/opt/splunk`.

### 2.4. Khởi động lần đầu

**[CHẠY LỆNH — SPLUNK01]**

```bash
sudo /opt/splunk/bin/splunk start --accept-license
```

**[TRÊN GIAO DIỆN WEB]** Truy cập: http://10.10.40.20:8000

**[GIẢI THÍCH]** Thư mục cấu hình hệ thống: `/opt/splunk/etc/system/local/`.

### 2.5. Đổi mật khẩu admin 

**[CHẠY LỆNH — SPLUNK01]**

```bash
SPLUNK_NEW_PASS=11223344
sudo /opt/splunk/bin/splunk cmd splunkd rest --noauth POST /services/admin/users/admin "password=${SPLUNK_NEW_PASS}"
unset SPLUNK_NEW_PASS
sudo /opt/splunk/bin/splunk restart
```

---

## 3. Xử lý cảnh báo Splunkbase do không có Internet

**[HIỆN TƯỢNG]** Splunk có thể báo lỗi khi tìm nạp danh sách ứng dụng từ Splunkbase, do môi trường lab không truy cập Internet hoặc không phân giải được DNS. Ghi chú gốc xác định kết nối Splunkbase hiện chưa cần dùng trong lab.

![alt text](image.png)

### 3.1. Kiểm tra log lỗi

**[CHẠY LỆNH — SPLUNK01]**

```bash
sudo grep -aEi 'LocalAppsAdminHandler|apps_dump|Connect Timeout' /opt/splunk/var/log/splunk/splunkd.log | tail -30
```

**[KẾT QUẢ MẪU — KHÔNG CHẠY]**

```text
10-24-2026 00:34:02.263 +0700 WARN HttpClientRequest - Returning error HTTP/1.1 502 Error resolving: Temporary failure in name resolution while accessing server=https://cdn.splunkbase.splunk.com
10-24-2026 00:34:02.263 +0700 WARN LocalAppsAdminHandler - Could not fetch apps from apps dump; code=502; desc=Error resolving: Temporary failure in name resolution
10-24-2026 00:34:22.278 +0700 WARN HttpClientRequest - Returning error HTTP/1.1 502 Error resolving: Temporary failure in name resolution while accessing server=https://cdn.splunkbase.splunk.com
10-24-2026 00:34:22.278 +0700 WARN LocalAppsAdminHandler - Could not fetch archived apps dump; code=502
```

**[GIẢI THÍCH]** Dấu hiệu cần nhận diện: `Error resolving: Temporary failure in name resolution` khi truy cập `cdn.splunkbase.splunk.com`. Do là không truy cập được internet (Phần này không cần thiết do chỉ quản lý nội bộ thôi, mốt cần thêm các feature thì mở rule từ FW sau)

### 3.2. Điều chỉnh `server.conf`

**[CHẠY LỆNH — SPLUNK01]**

```bash
sudo nano /opt/splunk/etc/system/local/server.conf
```

**[GHI VÀO FILE `server.conf` — THÊM CUỐI FILE]**

```ini
[applicationsManagement]
allowInternetAccess = false
splunkbaseAppsDumpUrl=
archivedSplunkbaseAppsDumpUrl=
```

### 3.3. Kiểm tra cấu hình và khởi động lại

**[CHẠY LỆNH — SPLUNK01]**

```bash
sudo /opt/splunk/bin/splunk btool server list applicationsManagement --debug
```

**[KẾT QUẢ MẪU — CHỈ ĐỐI CHIẾU]** Những dòng quan trọng trong kết quả của ghi chú gốc:

```text
/opt/splunk/etc/system/local/server.conf   [applicationsManagement]
/opt/splunk/etc/system/local/server.conf   allowInternetAccess = false
/opt/splunk/etc/system/local/server.conf   archivedSplunkbaseAppsDumpUrl =
/opt/splunk/etc/system/local/server.conf   splunkbaseAppsDumpUrl =
```

-> Này để kiểm tra cấu hình không báo lỗi là được

**[CHẠY LỆNH — SPLUNK01]**

```bash
sudo /opt/splunk/bin/splunk restart
```

**[TRÊN GIAO DIỆN WEB]** Mở lại http://10.10.40.20:8000.

![alt text](image-2.png)

---

## 4. Tìm hiểu và tạo Index trong Splunk

### 4.1. Index dùng để làm gì?

**[GIẢI THÍCH]** Index là nơi Splunk lưu trữ dữ liệu. Việc chia nhiều index giúp:

- Phân quyền truy cập dữ liệu.
- Thiết lập thời gian lưu trữ khác nhau cho từng loại log.
- Tối ưu phạm vi tìm kiếm bằng cách chỉ truy vấn các index liên quan.

### 4.2. Vòng đời dữ liệu trong Index

`Hot → Warm → Cold → Frozen` (dữ liệu lưu trữ được khôi phục có thể ở trạng thái `Thawed`).

| Trạng thái | Giải thích | Tìm kiếm được? |
| --- | --- | --- |
| Hot | Bucket đang nhận dữ liệu mới | Có |
| Warm | Bucket đã ngừng ghi, vẫn lưu trữ để truy vấn | Có |
| Cold | Bucket cũ hơn, được chuyển sang vùng cold | Có |
| Frozen | Dữ liệu quá giới hạn thời gian/dung lượng, bị loại khỏi index; mặc định bị xóa nếu không archive | Không |
| Thawed | Dữ liệu từ archive được khôi phục để truy vấn | Có |

### 4.3. Các tùy chọn khi tạo Index

**[TRÊN GIAO DIỆN WEB — TẠO 5 INDEX]** Dùng màn hình tạo Index trong Splunk. Áp dụng các lựa chọn sau, sau đó tạo lần lượt `linux_auth`, `linux_syslog`, `linux_audit`, `web` và `firewall`.

| Tùy chọn | Ý nghĩa theo ghi chú | Lựa chọn trong lab |
| --- | --- | --- |
| **Index data type** | `Events`: log có thời gian (SSH, web, lỗi, firewall); `Metrics`: CPU, RAM, latency, req/s | **Events** cho cả 5 index |
| **Home path** | Nơi lưu hot/warm bucket; ví dụ mặc định `$SPLUNK_DB/linux_auth/db` | Để trống |
| **Cold path** | Nơi lưu cold bucket; ví dụ `$SPLUNK_DB/linux_auth/colddb` | Để trống |
| **Thawed path** | Đường dẫn khôi phục dữ liệu từ archive | Để mặc định / không tự nhập (theo ghi chú “tương tự”) |
| **Data integrity check** | Khi bật, dùng SHA-256 để hỗ trợ kiểm tra tính toàn vẹn | **Disable** |
| **Max size of entire index** | Tổng dung lượng tối đa; quá giới hạn thì bucket cũ nhất chuyển Frozen (không tính Thawed); tham số `maxTotalDataSizeMB` trong `indexes.conf` | Theo bảng dung lượng bên dưới |
| **Max size of hot/warm/cold bucket** | `auto` cho bucket thông thường; `auto_high_volume` cho dữ liệu nhiều | Ghi chú chỉ giải thích hai lựa chọn, chưa chốt cụ thể |
| **Frozen path** | Có đường dẫn: archive; không có: dữ liệu Frozen bị xóa | Để trống |
| **App** | Phạm vi ứng dụng quản lý cấu hình index | Ghi chú nói chọn 1 app, chưa chốt lựa chọn |
| **TSIDX retention policy** | Enable reduction làm giảm kích thước TSIDX cũ, đổi lại tìm kiếm có thể chậm hơn | **Disable** |
| **Reduce tsidx files older than** | Mốc tuổi để giảm TSIDX khi dùng reduction | Ghi chú chỉ nêu ý nghĩa |

**[GIẢI THÍCH THÊM]**

- `Rawdata`: nội dung log thực tế được nén.
- `TSIDX`: dữ liệu chỉ mục phục vụ định vị và tìm kiếm sự kiện.
- Giá trị mặc định của **Max size of entire index** được ghi là 500 GB; chỉ số `linux_auth` trong bài này chọn 2 GB được rồi . Các index khác xem bảng sau.

### 4.4. Dung lượng cho từng Index

| Tên Index | Max size of entire index |
| --- | --- |
| `linux_auth` | 2 GB |
| `linux_syslog` | 3 GB |
| `linux_audit` | 3 GB |
| `web` | 5 GB |
| `firewall` | 3 GB |

### 4.5. Cái này không chạy. Giải thích các option trong app thôi

**[GIẢI THÍCH — KHÔNG PHẢI LỆNH]** Ghi chú gốc liệt kê các lựa chọn sau. Phần lựa chọn App chưa được chốt, nên bản này không tự chọn thay.

| App | Chức năng | Ví dụ |
| --- | --- | --- |
| Search & Reporting | Tìm kiếm, phân tích, báo cáo, cảnh báo, dashboard | Tìm SSH thất bại bằng `index=linux_auth` |
| Audit Trail | Theo dõi hoạt động người dùng/quản trị viên trong Splunk | Ai đăng nhập, sửa cấu hình hoặc dashboard |
| Data Management | Quản lý, xử lý và định tuyến dữ liệu | Xử lý/lọc/chuyển tiếp log |
| Instrumentation | Thu thập thông tin sử dụng và hiệu năng Splunk | Theo dõi telemetry |
| Monitoring Console | Giám sát sức khỏe Splunk Enterprise | CPU, RAM, ổ đĩa, indexing |
| Splunk Dashboard Studio | Tạo dashboard trực quan | Biểu đồ SSH thất bại |
| Splunk Observability Cloud | Giám sát hạ tầng, ứng dụng và dịch vụ | Hiệu năng ứng dụng, lỗi dịch vụ |
| Splunk Pipeline Builders | Xây dựng pipeline xử lý, biến đổi, định tuyến dữ liệu | Lọc log trước khi gửi |
| Splunk RapidDiag | Thu thập thông tin chẩn đoán | Log nội bộ, cấu hình phục vụ khắc phục lỗi |
| Upgrade Readiness App | Kiểm tra tương thích app trước khi nâng cấp (theo ghi chú: ngừng hoạt động từ 10.0) | Phát hiện nguy cơ không tương thích |

---

## 5. Chuẩn bị SPLUNK01 nhận log từ Universal Forwarder

### 5.1. Bật cổng nhận log trên giao diện Splunk

**[TRÊN GIAO DIỆN WEB — SPLUNK01]** Thực hiện phần **Setup** nhận dữ liệu Universal Forwarder theo các ảnh tham khảo trong ghi chú gốc, dùng cổng **TCP 9997**.

![alt text](image-3.png)

![alt text](image-4.png)

![alt text](image-5.png)

### 5.2. Kiểm tra cổng 9997

**[CHẠY LỆNH — SPLUNK01]**

```bash
sudo ss -lntp | grep :9997
```

**[KẾT QUẢ MONG ĐỢI]** Có tiến trình lắng nghe TCP trên cổng `9997`.

![alt text](image-6.png)

---

## 6. Kiểm tra đường truyền và cài Universal Forwarder trên CL01

### 6.1. Quy tắc firewall cho đường truyền

**[GIẢI THÍCH — ĐÂY LÀ CÁC RULE ĐÃ CÓ TRONG GHI CHÚ, KHÔNG PHẢI LỆNH TERMINAL]**

| Nguồn | Đích | IP đích | Cổng | Trạng thái |
| --- | --- | --- | --- | --- |
| `eth1` (LAN) | `eth3` (SIEM) | `10.10.40.20` | TCP 9997 | Đã cho phép |
| `eth2` (DMZ) | `eth3` (SIEM) | `10.10.40.20` | TCP 9997 | Đã cho phép |
| FW01 phát sinh log | `eth3` (SIEM) | `10.10.40.20` | UDP 1514 | Ghi chú: không có rule OUTPUT chặn |

**Rule 17 (nftables — đã có):**

```nft
 iifname "eth1" oifname "eth3" ip daddr 10.10.40.20 tcp dport 9997 accept
```

Cho phép LAN gửi log đến SPLUNK01 qua TCP 9997.

**Rule 21 (nftables — đã có):**

```nft
 iifname "eth2" oifname "eth3" ip daddr 10.10.40.20 tcp dport 9997 accept
```

Cho phép DMZ gửi log đến SPLUNK01 qua TCP 9997.


### 6.2. UFW trên máy host

Này tui cấu hình để giao tiếp giữa các mạng trên máy tui được do Firewall máy tui mặc định chặn 

```bash
sudo ufw route allow in on virbr-n204-lan out on virbr-n204-lan
sudo ufw route allow in on virbr-n204-dmz out on virbr-n204-dmz
sudo ufw route allow in on virbr-n204-siem out on virbr-n204-siem
sudo ufw route allow in on virbr-n204-wan out on virbr-n204-wan
sudo ufw reload
```

**[CHẠY LỆNH — CL01, KIỂM TRA TCP]**

```bash
nc -vz -w 3 10.10.40.20 9997
```

**[GIẢI THÍCH]**

- `-v`: verbose, hiển thị chi tiết.
- `-z`: chỉ kiểm tra khả năng kết nối, không gửi dữ liệu ứng dụng.
- `-w 3`: timeout 3 giây.

**[KẾT QUẢ MẪU — KHÔNG CHẠY]**

```text
Connection to 10.10.40.20 9997 port [tcp/*] succeeded!
```

### 6.3. Tải và cài Universal Forwarder trên CL01

**[THAO TÁC TRÊN TRÌNH DUYỆT]** Tải bản `.deb` tại https://www.splunk.com/en_us/download/universal-forwarder.html

Trong link drive : https://drive.google.com/drive/u/2/folders/1X-hp3dDqI-HjlslgDP9TM61Rt9j9H1Y7

**[CHẠY LỆNH — MÁY ĐANG CHỨA FILE `.deb`]**

```bash
scp splunkforwarder-10.6.1.1-b2ae2962645c-linux-amd64.deb labadmin@10.10.10.11:~/
```

**[CHẠY LỆNH — CL01]**

```bash
sudo dpkg -i ./splunkforwarder-*.deb
```

**[KẾT QUẢ MẪU — KHÔNG CHẠY]** Ghi chú ghi nhận quá trình cài hoàn thành và xuất hiện các dòng:

```text
Unpacking splunkforwarder (10.6.1.1) ...
Setting up splunkforwarder (10.6.1.1) ...
find: ‘/opt/splunkforwarder/lib/python3.7/site-packages’: No such file or directory
find: ‘/opt/splunkforwarder/lib/python3.9/site-packages’: No such file or directory
complete
```

**Thông tin tài khoản trong ghi chú gốc:** `admin` / `11223344` (dùng khi UF yêu cầu đăng nhập).

### 6.4. Cấu hình đích gửi log — `outputs.conf` trên CL01

**[CHẠY LỆNH — CL01]**

```bash
sudo nano /opt/splunkforwarder/etc/system/local/outputs.conf
```

**[GHI VÀO FILE `outputs.conf`]**

```ini
[tcpout]
defaultGroup = splunk_server

[tcpout:splunk_server]
server = 10.10.40.20:9997
```

**[GIẢI THÍCH]** `outputs.conf` quyết định **gửi log đến đâu**: SPLUNK01 tại `10.10.40.20:9997`.

### 6.5. Cấu hình nguồn log — `inputs.conf` trên CL01

**[CHẠY LỆNH — CL01]**

```bash
sudo nano /opt/splunkforwarder/etc/system/local/inputs.conf
```

**[GHI VÀO FILE `inputs.conf`]**

```ini
[monitor:///var/log/auth.log]
disabled = false
index = linux_auth
sourcetype = linux_secure

[monitor:///var/log/syslog]
disabled = false
index = linux_syslog
sourcetype = syslog
```

**[GIẢI THÍCH]** `inputs.conf` quyết định **đọc log gì**. Theo luồng gốc:

`CL01 → inputs.conf → Universal Forwarder → outputs.conf → SPLUNK01:9997 → index tương ứng`

`auth.log` đi vào `linux_auth`, `syslog` đi vào `linux_syslog`.

### 6.6. Khởi động lại và kiểm tra Forwarder

**[CHẠY LỆNH — CL01]**

```bash
sudo /opt/splunkforwarder/bin/splunk restart
```

**[CHẠY LỆNH — CL01]**

```bash
sudo /opt/splunkforwarder/bin/splunk list forward-server
```

**[KIỂM TRA]** Đối chiếu xem kết nối đến `10.10.40.20:9997` được ghi nhận. Khi có yêu cầu đăng nhập, ghi chú gốc dùng `admin` / `11223344`.

### 6.7. Kiểm tra log CL01 trong Splunk Web

**[TRÊN GIAO DIỆN WEB — SPLUNK01]** Vào Search & Reporting, nhập từng truy vấn bên dưới.

**[SPL — NHẬP VÀO Ô SEARCH, KHÔNG CHẠY TRONG BASH]**

```spl
index=linux_auth | stats count by host
```

**[GIẢI THÍCH]** Đếm số sự kiện trong `linux_auth` và nhóm theo host. nhìn thấy `CL01` là đạt.

![alt text](image-7.png)

**[SPL — NHẬP VÀO Ô SEARCH]**

```spl
index=linux_auth "sshd"
| table _time host _raw
| sort - _time
```

**[GIẢI THÍCH]** Lọc các sự kiện liên quan đến `sshd`, hiển thị thời gian, host và nội dung log; sắp xếp thời gian giảm dần.

![alt text](image-8.png)

---

## 7. Cài Universal Forwarder trên SRV01

### 7.1. Chuyển và cài gói `.deb`

**[CHẠY LỆNH — MÁY ĐANG CHỨA FILE `.deb`]**

```bash
scp splunkforwarder-10.6.1.1-b2ae2962645c-linux-amd64.deb labadmin@10.10.10.10:~/
```

**[CHẠY LỆNH — SRV01]**

```bash
sudo dpkg -i ./splunkforwarder-*.deb
```

### 7.2. Cấu hình đích nhận log trên SRV01

**[CHẠY LỆNH — SRV01]**

```bash
sudo nano /opt/splunkforwarder/etc/system/local/outputs.conf
```

**[GHI VÀO FILE `outputs.conf`]**

```ini
[tcpout]
defaultGroup = siem

[tcpout:siem]
server = 10.10.40.20:9997
```

### 7.3. Cấu hình nguồn log trên SRV01

**[CHẠY LỆNH — SRV01]**

```bash
sudo nano /opt/splunkforwarder/etc/system/local/inputs.conf
```

**[GHI VÀO FILE `inputs.conf`]**

```ini
[monitor:///var/log/auth.log]
disabled = false
index = linux_auth
sourcetype = linux_secure

[monitor:///var/log/syslog]
disabled = false
index = linux_syslog
sourcetype = syslog
```

**[KIỂM TRA]** Xác nhận file log tồn tại và tài khoản chạy UF có quyền đọc (tương tự CL01).

### 7.4. Khởi động lại UF

**[CHẠY LỆNH — SRV01]**

```bash
sudo /opt/splunkforwarder/bin/splunk restart
```

**[GHI CHÚ]** Sau khi chạy, tài liệu gốc ghi nhận UF yêu cầu nhập `admin` và mật khẩu `11223344`.

![alt text](image-9.png)

---

## 8. Cài Universal Forwarder trên WEB01

**[MỤC TIÊU]** Thu thập 3 nguồn: SSH, Apache Access, Apache Error.

### 8.1. Kiểm tra Apache và các file log

**[CHẠY LỆNH — WEB01]**

```bash
sudo systemctl status apache2
sudo ls -lh /var/log/apache2/
```

### 8.2. Chuyển và cài UF

**[CHẠY LỆNH — MÁY ĐANG CHỨA FILE `.deb`]**

```bash
scp splunkforwarder-10.6.1.1-b2ae2962645c-linux-amd64.deb labadmin@10.10.20.10:~/
```

**[CHẠY LỆNH — WEB01]**

```bash
sudo dpkg -i ./splunkforwarder-*.deb
```

### 8.3. Cấu hình điểm gửi trên WEB01

**[CHẠY LỆNH — WEB01]**

```bash
sudo nano /opt/splunkforwarder/etc/system/local/outputs.conf
```

**[GHI VÀO FILE `outputs.conf`]**
```ini 
[tcpout]
defaultGroup = siem

[tcpout:siem]
server = 10.10.40.20:9997
```
### 8.4. Cấu hình 3 nguồn log trên WEB01

**[CHẠY LỆNH — WEB01]**

```bash
sudo nano /opt/splunkforwarder/etc/system/local/inputs.conf
```

**[GHI VÀO FILE `inputs.conf`]**

```ini
[monitor:///var/log/auth.log]
disabled = false
index = linux_auth
sourcetype = linux_secure

[monitor:///var/log/apache2/access.log]
disabled = false
index = web
sourcetype = access_combined

[monitor:///var/log/apache2/error.log]
disabled = false
index = web
sourcetype = apache_error
```

### 8.5. Khởi động UF và tạo truy cập thử

**[CHẠY LỆNH — WEB01]**

```bash
sudo /opt/splunkforwarder/bin/splunk restart
```

**[CHẠY LỆNH — WEB01]**

```bash
curl http://127.0.0.1/
```

**[GIẢI THÍCH]** Truy cập thử vào Apache localhost để tạo request, từ đó kiểm tra log web có được thu thập không.

### 8.6. Truy vấn trong Splunk Web

**[SPL — NHẬP VÀO Ô SEARCH TRÊN SPLUNK01]**

```spl
index=web
| table _time host source _raw
| sort - _time
```

![alt text](image-10.png)

---

## 9. Thu thập log FW01 bằng rsyslog trên SPLUNK01

**[LUỒNG DỮ LIỆU]** `FW01 → UDP 1514 → rsyslog tại SPLUNK01 → /var/log/fw01.log → Splunk → index firewall`.

### 9.1. Tạo cấu hình rsyslog

**[CHẠY LỆNH — SPLUNK01]**

```bash
sudo nano /etc/rsyslog.d/30-fw01.conf
```

**[GHI VÀO FILE `30-fw01.conf`]**

```conf
module(load="imudp")
input(type="imudp" port="1514")

if ($fromhost-ip == '10.10.40.254') then {
    action(type="omfile"
           file="/var/log/fw01.log"
           fileGroup="adm"
           fileCreateMode="0640")
    stop
}
```

**[GIẢI THÍCH]** Rsyslog nhận UDP 1514, lọc gói syslog đến từ địa chỉ `10.10.40.254` (FW01 phía mạng SIEM) và ghi vào `/var/log/fw01.log`.

### 9.2. Kiểm tra cú pháp và khởi động lại rsyslog

**[CHẠY LỆNH — SPLUNK01]**

```bash
sudo rsyslogd -N1
```

**[KIỂM TRA]** Không báo lỗi cú pháp là đạt theo ghi chú gốc.

**[CHẠY LỆNH — SPLUNK01]**

```bash
sudo systemctl restart rsyslog
```

### 9.3. Cấu hình Splunk theo dõi file FW01

**[TRÊN GIAO DIỆN WEB — SPLUNK01]**

1. Vào **Settings → Add Data**.
2. Chọn **Monitor → Files & Directories**.
3. Nhập đường dẫn: `/var/log/fw01.log`.
4. Chọn `sourcetype`: `syslog`.
5. Chọn `index`: `firewall`.
6. Hoàn tất.

![alt text](image-11.png)

![alt text](image-12.png)

![alt text](image-14.png)

**[GIẢI THÍCH — CÁC LỰA CHỌN TRÊN WEB]**

| Mục | Ý nghĩa |
| --- | --- |
| **Index Once** | Chỉ nạp dữ liệu từ file một lần |
| **Continuously Monitor** | Tiếp tục theo dõi và nạp các log mới |
| **App: Search & Reporting** | Lưu cấu hình theo phạm vi ứng dụng Search & Reporting |
| **Host → Constant value** | Gán một giá trị host cố định cho các sự kiện của input |
| **Host → Regular expression on path** | Tách host từ đường dẫn bằng regex |
| **Host → Segment in path** | Dùng một thành phần trong đường dẫn làm host |
| **Index** | Nơi Splunk lưu sự kiện để tìm kiếm, phân tích |

**Ví dụ trích host bằng Regex (chỉ để giải thích, không phải cấu hình bắt buộc):**

```text
/var/log/firewalls/FW01/firewall.log
/var/log/firewalls/FW02/firewall.log
```

**[REGEX THAM KHẢO — KHÔNG CHẠY TRONG TERMINAL]**

```regex
/var/log/firewalls/([^/]+)/
```

Kết quả trích tương ứng là `FW01` và `FW02`.

**Ví dụ Segment in path:** Với `/var/log/firewalls/FW01/firewall.log`, các thành phần là `var → log → firewalls → FW01 → firewall.log`; chọn phần tương ứng `FW01` để dùng làm host.

### 9.4. Quyền đọc file cho tài khoản Splunk

**[CHẠY LỆNH — SPLUNK01]**

```bash
sudo usermod -aG adm splunk
```

**[GIẢI THÍCH]** Thêm người dùng dịch vụ `splunk` vào nhóm `adm` để đáp ứng quyền đọc file log theo ghi chú gốc. Tài liệu nguồn chưa nêu bước kích hoạt lại phiên nhóm; không bổ sung thay đổi ở đây.

### 9.5. Kiểm tra trong Splunk Web

**[SPL — NHẬP VÀO Ô SEARCH TRÊN SPLUNK01]**

```spl
index=firewall
| table _time host _raw
| sort - _time
```

**[KẾT QUẢ MONG ĐỢI]** Có các sự kiện firewall trong `index=firewall`.

![alt text](image-15.png)

---

## 10. Bảng tra nhanh: thực hiện ở máy nào?

| Máy / vị trí | Việc cần thực hiện | Mục |
| --- | --- | --- |
| Host dựng lab | Các lệnh UFW cho mạng ảo, nếu cấu hình host giống ghi chú | 1.1, 6.2 |
| SPLUNK01 | Cài Enterprise, đăng nhập Web, cấu hình `server.conf`, tạo index, bật TCP 9997 | 2–5 |
| CL01 | Kiểm tra TCP, cài UF, tạo `outputs.conf`, `inputs.conf`, restart UF | 6 |
| SRV01 | Cài UF, tạo `outputs.conf`, `inputs.conf`, restart UF | 7 |
| WEB01 | Kiểm tra Apache, cài UF, cấu hình log SSH/Apache, thử `curl` | 8 |
| SPLUNK01 | Nhận syslog FW01 bằng rsyslog, thêm file vào index `firewall` | 9 |
| Splunk Web | Chạy các truy vấn SPL để xác nhận log | 6.7, 8.6, 9.5 |


**Hoàn thành.**
