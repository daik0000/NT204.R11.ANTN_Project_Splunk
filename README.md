# NT204.R11.ANTN - SIEM và Threat Hunting với Splunk

Đồ án môn hệ thống IPDS: triển khai SIEM và threat hunting bằng Splunk Enterprise trên một mạng doanh nghiệp nhỏ mô phỏng. Mục tiêu là phát hiện và truy vết một chuỗi tấn công hoàn chỉnh (khai thác web, shell, persistence, pivot vào LAN, xóa log), mỗi rule gắn với một kỹ thuật MITRE ATT&CK.

## Thành viên
| **STT** | **Tên** | **MSSV** |
| :---: | --- | :---: |
| 1 | Đào Đình An | 24520041 |
| 2 | Nguyễn Thị Mỹ Duyên | 24520408 |
| 3 | Nguyễn Văn Quốc Gia | 24520415 |

## Cấu trúc repo

| Đường dẫn | Nội dung |
| --- | --- |
| `README.md` | Tài liệu này: tổng quan, sơ đồ mạng, cách bắt đầu, quy ước |
| `a-infrastructure/` | `nftables.conf`, bảng IP, `action.md` (nhật ký dựng từng máy), `ova-guide.md` (xuất và import OVA) |
| `b-siem/` | `inputs.conf`, `outputs.conf`, `props.conf`, `savedsearches.conf`, dashboard, câu SPL, tài liệu index và sourcetype |
| `c-attack/` | Kịch bản tấn công, bảng kiểm chứng, nhật ký hunt, ánh xạ MITRE, phần so sánh |

## Sơ đồ mạng

```
   KALI (VMnet8 NAT, kẻ tấn công)
        |
 [VMnet8 NAT] ---- Internet
        |
   +----+----+
   |  FW01   |  Alpine + nftables, DNAT 80/443 -> WEB01
   +--+-+-+--+
      | | |
 VMnet2 | VMnet4
  LAN   | SIEM
        VMnet3 = DMZ
```

| Vùng | VMnet | Subnet | Gateway (FW01) | Máy |
| --- | --- | --- | --- | --- |
| WAN | VMnet8 (NAT) | DHCP của VMware | eth0 của FW01 | KALI |
| LAN | VMnet2 (host-only) | 10.10.10.0/24 | 10.10.10.254 | SRV01 (.10), CL01 (.11) |
| DMZ | VMnet3 (host-only) | 10.10.20.0/24 | 10.10.20.254 | WEB01 (.10) |
| SIEM | VMnet4 (host-only) | 10.10.40.0/24 | 10.10.40.254 | SPLUNK01 (.20) |

Chỉ WEB01 được mở ra ngoài (WAN cổng 80 qua DNAT). Log về Splunk theo luồng: LAN và DMZ gửi TCP 9997 tới SPLUNK01, FW01 gửi syslog UDP 1514.

## Danh sách máy ảo

| Máy | Hệ điều hành | Vai trò | RAM | vCPU | Ổ đĩa |
| --- | --- | --- | --- | --- | --- |
| FW01 | Alpine Linux | Firewall, router, DNAT | 256 MB | 1 | 4 GB |
| SPLUNK01 | Ubuntu Server | SIEM | 3 GB | 2 | 40 GB |
| SRV01 | Ubuntu Server | Máy chủ nội bộ (SSH, Samba, MariaDB), mục tiêu cuối | 1 GB | 1 | 10 GB |
| CL01 | Ubuntu Server | Máy nhân viên, điểm trung gian khi pivot, cron tạo hoạt động nền | 768 MB | 1 | 10 GB |
| WEB01 | Ubuntu Server | Web server chạy DVWA trong DMZ | 1,5 GB | 1 | 12 GB |
| KALI | Kali Linux | Kẻ tấn công ngoài | 2 GB | 2 | 30 GB |

Tổng khoảng 8,5 GB RAM khi bật Kali (6,5 GB khi tắt Kali). Máy host nên có từ 12 GB RAM.

## Bắt đầu nhanh 

1. Cài VMware Workstation, dùng cùng phiên bản với A (ghi ở bảng bên dưới).
2. Tải 5 file OVA (FW01, SPLUNK01, SRV01, CL01, WEB01) từ link trong bảng phiên bản OVA. Kali tự tải bản VMware dựng sẵn.
3. Làm theo `a-infrastructure/ova-guide.md`: tạo trước VMnet2, 3, 4, import OVA, kiểm tra card mạng, chạy bảng kiểm tra kết nối.
4. Chụp snapshot sau khi import xong.

### Phiên bản OVA hiện tại

| Phiên bản | Ngày xuất | Ghi chú |
| --- | --- | --- |
| `lab-v1` | 18/10/2026 | Bản nền đầu tiên, Splunk chưa cài |

Mọi thay đổi nhỏ về cấu hình đi qua repo này, không đi qua OVA.

## Điểm yếu cố ý (để có dữ liệu tấn công cho Splunk)

| Máy | Điểm yếu | Dùng cho |
| --- | --- | --- |
| WEB01 | DVWA mức bảo mật Low, `allow_url_include` bật | Khai thác web (command injection, file upload, SQL injection) |
| CL01 | Tài khoản `nhanvien1` có mật khẩu yếu, khóa SSH không mật khẩu để vào SRV01 | Brute force SSH, di chuyển ngang |
| SRV01 | Dữ liệu bịa trong Samba và MariaDB | Mục tiêu lấy dữ liệu cuối chuỗi |
| FW01 | Rule DMZ vào LAN cổng 22 chỉ mở tạm ở tuần 6 | Mô phỏng sai cấu hình để diễn tập pivot |

Giờ trên các máy phải thống nhất để truy vết log. Sau mỗi lần host ngủ hoặc máy ảo bị suspend, chạy `date` trên từng máy; lệch thì chạy `chronyc makestep` (trên Alpine) hoặc `sudo chronyc makestep` (trên Ubuntu).

## Bảo mật cho repo

- **Không đẩy mật khẩu, khóa SSH, file license Splunk, file OVA lên repo.**
- Chỉ tấn công các máy trong lab. Kali ở cùng VMnet8 với đường ra Internet thật, không quét bất kỳ địa chỉ nào ngoài lab.

## Tài liệu liên quan

- `a-infrastructure/action.md`: nhật ký dựng từng máy, kèm lỗi gặp phải và cách xử lý.
- `a-infrastructure/ova-guide.md`: cách xuất và import OVA.