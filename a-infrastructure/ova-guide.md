# Xuất và import OVA

OVA là một file duy nhất đóng gói một máy ảo: ổ đĩa và cấu hình (RAM, CPU, số card mạng). Ai import file OVA vào VMware cũng có đúng máy đó, không phải cài lại hệ điều hành hay phần mềm.

Hai điều cần nhớ:

- **Mỗi OVA chỉ chứa một máy.** Lab có 5 máy tự dựng nên A xuất 5 file: FW01, SPLUNK01, SRV01, CL01, WEB01. Kali mỗi người tự tải bản VMware dựng sẵn.
- **OVA không chứa mạng ảo (VMnet) và không chứa snapshot.** Người nhận phải tạo VMnet2, 3, 4 giống A trước khi import, và tự chụp snapshot sau khi import.

Tên menu bên dưới theo VMware Workstation Pro trên Windows. Tên có thể hơi khác giữa các phiên bản.

---

## Phần 1: Người nhận dùng OVA để dựng lab
### Bước 0: Yêu cầu
- Máy host: RAM từ 12 GB, trống khoảng 100 GB ổ đĩa (SSD thì tốt hơn).
- Windows: chạy Virtual Network Editor bằng quyền admin.
- Đã tải đủ 5 file OVA và file Kali. Tắt bộ gõ tiếng Việt khi thao tác trong console máy ảo.

### Bước 1: Tạo mạng ảo VMnet2, 3, 4 **trước khi import**

Đây là bước hay bị bỏ sót nhất. OVA không mang mạng ảo theo, nên nếu chưa tạo, các card mạng của máy sẽ không có mạng để gắn.

1. Mở **Edit, Virtual Network Editor**, bấm **Change Settings** (cần quyền admin).
2. Kiểm tra trước xem VMnet2, 3, 4 đã tồn tại trên máy chưa (nếu đang dùng cho việc khác thì đổi sang việc khác hoặc cân nhắc lại).
3. Với mỗi mạng, bấm **Add Network**, chọn số VMnet, rồi chỉnh:

| VMnet | Kiểu | Subnet IP | Subnet mask | DHCP của VMware | Host virtual adapter |
| --- | --- | --- | --- | --- | --- |
| VMnet2 | Host-only | 10.10.10.0 | 255.255.255.0 | **Tắt** (bỏ tick "Use local DHCP service") | **Bỏ** |
| VMnet3 | Host-only | 10.10.20.0 | 255.255.255.0 | **Tắt** | **Bỏ** |
| VMnet4 | Host-only | 10.10.40.0 | 255.255.255.0 | **Tắt** | **Giữ** (để mở Splunk Web từ trình duyệt máy host) |

4. VMnet8 (NAT) **giữ nguyên mặc định**. Subnet của VMnet8 trên máy mỗi người sẽ khác nhau (ví dụ `192.168.x.0/24`), điều này bình thường vì FW01 nhận IP WAN bằng DHCP.
5. Bấm Apply, rồi OK.

### Bước 2: Import 5 file OVA

Làm lần lượt (khuyên theo thứ tự FW01, SPLUNK01, SRV01, CL01, WEB01):

1. Menu **File, Open**, chọn file `.ova`.
2. Đặt tên máy ảo (ví dụ `FW01`) và thư mục lưu, bấm **Import**.
3. Nếu báo lỗi kiểu "failed OVF specification conformance", bấm **Retry** (VMware nới lỏng kiểm tra).
4. Chưa bật máy vội.

### Bước 3: Kiểm tra card mạng của từng máy (rất quan trọng)

Sau khi import, **chưa chắc VMware giữ đúng VMnet cho từng card**, nên phải kiểm tra tay. Với mỗi máy: chuột phải máy ảo, **Settings**, chọn từng **Network Adapter** và chỉnh lại nếu cần:

| Máy | Network Adapter | Phải gắn vào |
| --- | --- | --- |
| FW01 | Adapter 1 | NAT (VMnet8) |
| FW01 | Adapter 2 | Custom: VMnet2 |
| FW01 | Adapter 3 | Custom: VMnet3 |
| FW01 | Adapter 4 | Custom: VMnet4 |
| SRV01 | Adapter 1 | Custom: VMnet2 |
| CL01 | Adapter 1 | Custom: VMnet2 |
| WEB01 | Adapter 1 | Custom: VMnet3 |
| SPLUNK01 | Adapter 1 | Custom: VMnet4 |

Thứ tự adapter của FW01 quan trọng vì nó quyết định tên `eth0` đến `eth3` bên trong máy (bộ rule firewall dựa trên tên này). Nếu VMware hỏi "I moved it" hay "I copied it" khi bật máy lần đầu, chọn **I copied it**.

Kali: máy tự tải về, Network Adapter phải là NAT (VMnet8).

### Bước 4: Bật máy theo thứ tự và kiểm tra

Bật **FW01 trước** (nó là gateway của mọi vùng), chờ khoảng 30 giây, rồi bật các máy còn lại. Đăng nhập bằng thông tin trong `thong-tin-mat.md` (Drive)

| Kiểm tra | Chạy ở đâu | Kết quả mong đợi |
| --- | --- | --- |
| `ip -br a` | FW01 | `eth0` có IP `192.168.x.x`, `eth1` `10.10.10.254`, `eth2` `10.10.20.254`, `eth3` `10.10.40.254` |
| `ping -c 2 10.10.10.254` | CL01 | Thông (CL01 và FW01 cùng VMnet2) |
| `ping -c 2 10.10.20.254` | WEB01 | Thông (cùng VMnet3) |
| `ping -c 2 10.10.40.254` | SPLUNK01 | Thông (cùng VMnet4) |
| `curl -I http://archive.ubuntu.com` | Mỗi máy Ubuntu | `HTTP/1.1 200 OK` (ra Internet qua FW01) |
| Ping `10.10.40.20` và `ssh labadmin@10.10.40.20` | Máy host | Thông (nhờ host adapter của VMnet4) |
| `curl -I http://<IP eth0 của FW01>/DVWA/login.php` | KALI | `HTTP/1.1 200 OK` |
| `ping -c 2 10.10.10.10` | KALI | Mất gói (Kali không chạm được các vùng trong) |
| `date` | Mỗi máy | Đúng giờ thật (lệch thì xem mục lỗi thường gặp) |

`ping 8.8.8.8` từ các máy trong lab sẽ **không thông**, và đó là bình thường: firewall không cho ICMP đi ra. Dùng `curl` hoặc `apt update` để kiểm tra Internet.

### Bước 5: Snapshot và cách chạy hằng ngày

1. Khi mọi kiểm tra đạt, tắt hẳn các máy và chụp snapshot tên `sau-import-lab-v1` cho từng máy.
2. Để tiết kiệm RAM, chỉ bật Kali khi cần tấn công. Nếu máy host yếu, không import SRV01 hoặc CL01 (chuỗi tấn công sẽ ngắn hơn nhưng vẫn chạy được).
3. Có thể đổi RAM hoặc CPU từng máy trong **Settings** nếu cần. **Không tự đổi IP, tên máy hay số VMnet**, vì cấu hình dùng chung của cả nhóm (forwarder, rule firewall, rule phát hiện) dựa vào chúng. Muốn đổi thứ gì cho cả nhóm thì nhắn A.

### Bước 6: Làm việc với repo

1. `git clone` repo, làm trong thư mục của vai mình (`b-siem/` hoặc `c-attack/`).
2. Cấu hình của người khác kéo về bằng `git pull`, sau đó chép vào máy ảo của mình (mỗi thư mục có script chép cấu hình khi đã có).

---

## Lỗi thường gặp

| Lỗi | Nguyên nhân thường gặp | Cách xử lý |
| --- | --- | --- |
| Import báo lỗi "failed OVF specification conformance" | VMware kiểm tra OVF quá chặt | Bấm Retry khi hộp thoại hỏi |
| Máy ảo không có mạng, ping gateway không thông | Network Adapter sau import không gắn đúng VMnet, hoặc VMnet chưa được tạo | Tạo VMnet2, 3, 4 (bước 2), rồi kiểm tra từng adapter (bước 4) |
| FW01 không ra được Internet | Adapter 1 không phải NAT, hoặc thứ tự adapter bị đảo nên `eth0` không phải WAN | Xem `ip -br a` trên FW01 và đối chiếu với bảng bước 4. Nếu IP `192.168.x.x` không nằm trên `eth0` thì thứ tự adapter bị đảo |
| Kali không `curl` được FW01 | IP WAN của FW01 đã đổi, hoặc Kali không cùng VMnet8 | Chạy `ip -br a` trên FW01 để lấy lại IP eth0, kiểm tra Kali dùng NAT |
| Giờ trên các máy lệch nhau hoặc lệch giờ thật | Máy ảo bị suspend hoặc host ngủ làm đồng hồ ảo đứng yên | Chạy `chronyc makestep` (FW01) hoặc `sudo chronyc makestep` (máy Ubuntu) rồi `date` kiểm tra lại. Giờ lệch làm log các máy nằm sai chỗ trong Splunk |
| Không mở được Splunk Web từ máy host | VMnet4 thiếu host adapter, hoặc Splunk chưa cài | Kiểm tra VMnet4 có tick host virtual adapter. Splunk Web chỉ có sau khi B cài Splunk ở tuần 3 (địa chỉ `http://10.10.40.20:8000`) |
| `ssh.service` báo `inactive` sau khi khởi động lại (máy Ubuntu) | SSH chạy theo socket activation, dịch vụ chỉ khởi động khi có kết nối đầu tiên (chưa kiểm chứng trên lab này) | Kiểm tra `systemctl is-active ssh.socket`, thử SSH vào rồi kiểm tra lại. Nếu cả hai đều `inactive` thì `sudo systemctl enable --now ssh` |

---

## Phần 2: Khi A cập nhật bản nền

Khi A đổi nền (thêm máy, đổi IP, cài thêm gói, sửa lỗi ảnh hưởng mọi người), A:

1. Làm lại phần 1, đặt tên `lab-v2` (hoặc `v3`...).
2. Cập nhật bảng phiên bản OVA trong `README.md` và nhắn B và C.
3. B và C chỉ import lại những máy có thay đổi, **sau khi sao lưu phần việc dở** (vì import lại là máy mới, sẽ mất cấu hình tay đã làm trong máy cũ). Các thay đổi cấu hình của cá nhân nên nằm trong repo để chép lại.

Thay đổi nhỏ không cần xuất lại OVA, chỉ đưa vào repo.