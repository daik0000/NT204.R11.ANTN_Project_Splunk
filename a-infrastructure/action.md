# Nhật ký triển khai lab (action.md)

Người ghi: Duyen.

Quy ước: chỉ cập nhật file này khi chủ file ra lệnh, mỗi lần xong một máy.

## Trạng thái các máy

| Máy | Trạng thái |
| --- | --- |
| FW01 | Xong phần cấu hình, đã thêm rule NTP và NTS (xem lỗi 5), còn mục "Việc còn lại" |
| SPLUNK01 | Xong cài hệ điều hành và mạng, giờ đã đồng bộ, còn snapshot (chưa cài Splunk, việc của B ở tuần 3) |
| SRV01 | Xong (hệ điều hành, mạng, SSH, Samba, MariaDB, auditd, snapshot) |
| CL01 | Xong (hệ điều hành, mạng, tài khoản, cron hoạt động nền đã chạy, snapshot) |
| WEB01 | Xong cài đặt và kiểm tra, còn xác nhận SSH sau khởi động lại, snapshot và bỏ host adapter VMnet3 |
| KALI | Xong kiểm tra mạng và công cụ (người làm báo ổn), còn snapshot |

---

## FW01 (Alpine Linux, firewall và router)

### Thông số

| Mục | Giá trị |
| --- | --- |
| Hệ điều hành | Alpine Linux, bản Virtual, x86_64 |
| RAM | 512 MB lúc cài, hạ xuống 256 MB sau khi xong (nếu treo thì 384 MB) |
| vCPU, ổ đĩa | 1 vCPU, 4 GB (không cấp phát trước) |
| Card mạng | 4 card, thứ tự gắn trong VMware quyết định tên eth |

| Tên card | Gắn vào | Vùng | IP |
| --- | --- | --- | --- |
| eth0 | VMnet8 (NAT) | WAN | DHCP của VMware (IP lúc ghi: `192.168.30.132`, có thể đổi) |
| eth1 | VMnet2 | LAN | 10.10.10.254/24 |
| eth2 | VMnet3 | DMZ | 10.10.20.254/24 |
| eth3 | VMnet4 | SIEM | 10.10.40.254/24 |

Bảng đối chiếu MAC (điền sau, dùng khi import OVA để kiểm tra card mạng):

| Network Adapter trong VMware | VMnet | MAC | Tên eth |
| --- | --- | --- | --- |
| 1 | VMnet8 | ........ | eth0 |
| 2 | VMnet2 | ........ | eth1 |
| 3 | VMnet3 | ........ | eth2 |
| 4 | VMnet4 | ........ | eth3 |

### Bước 0: Chuẩn bị

1. Tải Alpine Linux bản Virtual, x86_64 (file `alpine-virt-...-x86_64.iso`) từ alpinelinux.org/downloads.
2. Trong Virtual Network Editor (chạy bằng quyền admin), tạo mạng host-only và tắt "Use local DHCP service" ở cả ba:

| VMnet | Subnet | Host adapter |
| --- | --- | --- |
| VMnet2 | 10.10.10.0/24 | Bỏ chọn |
| VMnet3 | 10.10.20.0/24 | Bỏ chọn |
| VMnet4 | 10.10.40.0/24 | Giữ (để vào Splunk Web) |

VMnet8 (NAT) giữ mặc định.

### Bước 1: Tạo máy ảo

1. File, New Virtual Machine, Typical, chọn "I will install the operating system later".
2. Guest OS: Linux, Other Linux 6.x kernel 64-bit (hoặc 5.x).
3. Tên `FW01`, ổ đĩa 4 GB, không cấp phát trước.
4. Customize Hardware: Memory 512 MB, 1 CPU. Network Adapter đầu tiên là NAT. Thêm 3 Network Adapter, lần lượt Custom VMnet2, VMnet3, VMnet4 (thứ tự quan trọng). CD/DVD trỏ vào file ISO Alpine. Xóa Sound Card, Printer, USB Controller.

### Bước 2: Cài Alpine

Bật máy, đăng nhập `root` (không mật khẩu), chạy `setup-alpine`:

| Câu hỏi | Trả lời |
| --- | --- |
| Keyboard layout, variant | `us`, `us` |
| Hostname | `FW01` (xem lỗi 1) |
| eth0 | `dhcp` |
| eth1 | `10.10.10.254/24`, gateway `none` |
| eth2 | `10.10.20.254/24`, gateway `none` |
| eth3 | `10.10.40.254/24`, gateway `none` |
| Manual network configuration | `no` |
| DNS | `8.8.8.8` |
| Root password | đặt mật khẩu (lưu riêng, không đưa lên repo) |
| Timezone | `Asia/Ho_Chi_Minh` hoặc `Asia/Bangkok` |
| Proxy | `none` |
| NTP | `chrony` |
| Mirror | `f` |
| User | `no` |
| SSH server | `openssh`, cho phép root đăng nhập `yes` (tạm thời) |
| Disk | `sda`, chế độ `sys` |

Cài xong gõ `poweroff`. Trong VM Settings, CD/DVD bỏ chọn "Connect at power on". Bật máy lại, đăng nhập `root`.

### Bước 3: Kiểm tra card mạng

1. Cài bản `ip` đầy đủ (xem lỗi 2): `apk add iproute2`.
2. Chạy `ip -br a`. eth0 phải có IP dạng 192.168.x.x do VMware cấp, eth1 đến eth3 có `.254`.
3. Nếu thứ tự eth lệch, đối chiếu MAC bằng `ip link` với MAC trong Settings, Network Adapter, Advanced. Sửa `/etc/network/interfaces` rồi `rc-service networking restart`, và sửa bốn dòng `define` trong file rule ở bước 5 cho khớp.
4. Kiểm tra Internet: `ping -c 2 8.8.8.8`, rồi `apk update`.

### Bước 4: Bật chuyển tiếp gói tin và cài phần mềm

```
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-forward.conf
sysctl -p /etc/sysctl.d/99-forward.conf
apk add nftables tcpdump
rc-update add nftables
```

Tùy chọn: `apk add open-vm-tools` rồi `rc-update add open-vm-tools`.

### Bước 5: Bộ rule firewall

Ghi vào `/etc/nftables.nft`. Đây là bản đã sửa lỗi cú pháp (xem lỗi 3).

```
#!/usr/sbin/nft -f
flush ruleset

define WAN    = "eth0"
define LAN    = "eth1"
define DMZ    = "eth2"
define SIEM   = "eth3"
define SPLUNK = 10.10.40.20
define WEB01  = 10.10.20.10

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    iif lo accept
    icmp type echo-request accept
    iifname $WAN udp sport 67 udp dport 68 accept
    iifname $LAN tcp dport 22 accept
    iifname $WAN log prefix "FW-WAN-IN-DROP " counter drop
  }
  chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept

    iifname $WAN oifname $DMZ ip daddr $WEB01 tcp dport {80,443} ct status dnat accept

    iifname $LAN oifname $WAN tcp dport {53,80,443} accept
    iifname $LAN oifname $WAN udp dport 53 accept
    iifname $LAN oifname $DMZ ip daddr $WEB01 tcp dport {80,443} accept
    iifname $LAN oifname $SIEM ip daddr $SPLUNK tcp dport 9997 accept

    iifname $DMZ oifname $WAN tcp dport {53,80,443} accept
    iifname $DMZ oifname $WAN udp dport 53 accept
    iifname $DMZ oifname $SIEM ip daddr $SPLUNK tcp dport 9997 accept

    iifname $SIEM oifname $WAN tcp dport {53,80,443} accept
    iifname $SIEM oifname $WAN udp dport 53 accept

    # Thêm sau khi dựng SPLUNK01 (xem lỗi 5): NTP và NTS để đồng bộ giờ
    iifname { $LAN, $DMZ, $SIEM } oifname $WAN udp dport 123 accept
    iifname { $LAN, $DMZ, $SIEM } oifname $WAN tcp dport 4460 accept

    log prefix "FW-DROP " level info counter drop
  }
}

table ip nat {
  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname $WAN tcp dport {80,443} dnat to $WEB01
  }
  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    oifname $WAN masquerade
  }
}
```

Kiểm tra cú pháp trước, rồi mới nạp:

```
nft -c -f /etc/nftables.nft
nft -f /etc/nftables.nft
rc-service nftables start
rc-update add nftables
nft list ruleset
```

Sau khi nạp, SSH từ WAN bị chặn (chỉ LAN được SSH vào FW01). Console của VMware luôn dùng được nếu lỡ sai rule.

Bước bắt buộc sau khi nạp (xem lỗi 4): `rc-update -u`, rồi `reboot`, rồi kiểm tra lại `rc-service nftables status` và `nft list ruleset`.

### Bước 6: Gửi log về Splunk

Chưa xác minh được vì Splunk chưa cài. Theo hướng dẫn, sửa `/etc/conf.d/syslog`:

```
SYSLOGD_OPTS="-t -L -R 10.10.40.20:1514"
```

Rồi:

```
rc-update add klogd boot
rc-service klogd start
rc-service syslog restart
```

Cần kiểm tra lại ở tuần 3, khi B mở cổng nhận syslog 1514 trên Splunk: xem dòng `FW-DROP` có xuất hiện trong Splunk không.

### Bước 7: Kiểm tra sau khi xong

Kết quả người làm báo lại: `ip_forward` bằng 1, `nft list ruleset` hiện đủ bảng `inet filter` và `ip nat` sau khi khởi động lại, ping các máy thành công.

| Lệnh | Kết quả mong đợi |
| --- | --- |
| `sysctl net.ipv4.ip_forward` | `= 1` |
| `nft list ruleset` | Đủ hai bảng `inet filter` và `ip nat` |
| `ping -c 2 8.8.8.8` | Thông |
| `ping -c 2 10.10.10.254` (và `.20.254`, `.40.254`) | Thông |

Ghi chú: sau khởi động lại, counter `FW-WAN-IN-DROP` đã có vài gói (đã gặp 10 gói), là lưu lượng từ phía NAT của VMware bị chain `input` chặn, bình thường.

### Lỗi gặp phải và cách xử lý

| # | Lỗi | Nguyên nhân | Cách xử lý |
| --- | --- | --- | --- |
| 1 | Tên máy hiện `clear` thay vì `FW01` | Gõ nhầm ở câu hỏi hostname của `setup-alpine` | `echo FW01 > /etc/hostname`, `hostname -F /etc/hostname`, kiểm tra `/etc/hosts` không còn `clear`, gõ `exec sh -l` để dấu nhắc đổi |
| 2 | `ip -br a` báo lỗi, in ra bảng trợ giúp | `ip` của BusyBox trên Alpine không có tùy chọn `-br` | `apk add iproute2` (cần Internet). Nếu chưa có mạng, dùng `ip -4 -o a` và `ip link` |
| 3 | `nft -c -f` báo `Error: No symbol type information` ở dòng 17 | Viết `udp sport 67 dport 68`. Mỗi điều kiện cổng phải kèm giao thức | Đổi thành `udp sport 67 udp dport 68`. Có thể dùng `sed -i 's/udp sport 67 dport 68/udp sport 67 udp dport 68/' /etc/nftables.nft` |
| 4 | Sau `reboot`, `nft list ruleset` trống, `rc-service nftables status` báo `stopped`, dù `rc-update add` đã chạy | Chưa xác định chắc. `rc-status default` không liệt kê `nftables` dù liên kết có trong `/etc/runlevels/default/`, nên OpenRC không khởi động nó lúc boot. Nghi bộ nhớ đệm phụ thuộc của OpenRC cũ | Chạy `rc-update -u` (dựng lại bộ nhớ đệm), rồi `reboot`. Sau đó dịch vụ tự chạy và rule còn nguyên. Phương án dự phòng nếu lỗi lại: script `/etc/local.d/10-nft.start` chứa `nft -f /etc/nftables.nft`, `chmod +x`, `rc-update add local default` |
| 5 | Trên SPLUNK01, `System clock synchronized: no`, `chronyc sources` có `Reach` bằng 0 ở mọi nguồn | Chrony trên Ubuntu mặc định dùng nguồn NTS (`ntp-nts-*.canonical.com`). NTS cần TCP 4460 để trao đổi khóa rồi mới đồng bộ qua UDP 123, mà bộ rule FW01 lúc đầu không mở cả hai | Thêm vào chain `forward` của FW01, trước dòng `log ... drop`: `udp dport 123 accept` và `tcp dport 4460 accept` cho cả ba vùng LAN, DMZ, SIEM (xem bước 5). Nạp lại bằng `nft -c -f` rồi `nft -f /etc/nftables.nft`. Trên SPLUNK01: `sudo systemctl restart chrony`, đợi 30 giây, kiểm tra `chronyc sources` và `timedatectl` |
| 6 | Giờ trên FW01 lệch khoảng 4 tiếng 36 phút so với giờ thật (`date` hiện 16:50 khi giờ thật khoảng 21:27), log `FW-WAN-IN-DROP` ghi sai giờ | Chưa xác định chắc. `chronyc tracking` báo `System time: 16549 seconds slow of NTP time` nhưng vẫn `Leap status: Normal`, nghĩa là chrony nói chuyện được với máy chủ giờ nhưng không sửa lệch lớn (nghi cấu hình `makestep` chỉ cho nhảy giờ vài lần đầu). Nghi máy ảo bị suspend hoặc host đi ngủ làm đồng hồ máy ảo đứng yên | Người làm báo đã sửa xong. Cách: `chronyc makestep`, kiểm tra `date` và `chronyc tracking` (`System time` chỉ còn vài mili giây). Để tránh lặp lại, có thể đổi `makestep 1.0 3` thành `makestep 1.0 -1` trong `/etc/chrony/chrony.conf` rồi `rc-service chronyd restart` (chưa xác nhận đã làm). Giờ lệch làm log các máy nằm sai chỗ trong Splunk, nên sau mỗi lần host ngủ hoặc suspend máy ảo, chạy `date` trên từng máy để so với giờ thật, và `sudo chronyc makestep` trên máy Ubuntu nếu lệch |

Ghi chú thêm về quá trình làm:

- Dòng `grep -i nft /var/log/messages` lúc đầu chỉ hiện lỗi cũ (giờ 11:12, tên máy còn là `clear`), không phải lỗi lúc boot. Đừng dựa vào nó để kết luận.
- Đừng chạy `rc-service nftables save`. Với cấu hình mặc định nó chỉ lưu bộ đếm, không lưu rule, và không giải quyết lỗi 4.
- Khi dán nhiều lệnh một lúc vào console, kết quả bị lẫn lộn. Chạy từng lệnh một.
- `/etc/conf.d/nftables` toàn dòng comment là bình thường (giá trị mặc định), không cần sửa.
- Log `FW-WAN-IN-DROP` có các dòng `PROTO=ICMPv6 TYPE=134` (thông báo router IPv6) đều đặn, cách nhau khoảng 30 giây. Nhiều khả năng do cổng NAT của VMware phát ra (chưa kiểm chứng), vô hại vì FW01 không dùng IPv6. Nó là nhiễu khi hunt, có thể lọc trong Splunk ở tuần 4 hoặc thêm rule chặn im lặng ICMPv6 trên WAN trước dòng ghi log (chưa làm).
- Khi kiểm tra log, gõ đúng `FW-WAN-IN-DROP` (chữ D), gõ sai (`GROP`) thì `grep` không ra gì.

### Việc còn lại cho FW01

- [ ] Điền bảng MAC và IP của eth0 ở trên
- [ ] Hạ RAM xuống 256 MB và kiểm tra máy vẫn ổn (nếu chưa làm)
- [ ] Chụp snapshot `fw01-ok` (hoặc `fw01-rule-ok`)
- [x] Log `FW-WAN-IN-DROP` ghi vào `/var/log/messages` (đã thấy các dòng log mới từ IP của Kali theo thời gian thực)
- [ ] Xác minh log tới được Splunk (tuần 3, khi Splunk chạy và B mở cổng nhận syslog 1514)
- [x] Kali `curl` vào IP eth0 của FW01 ra trang DVWA (DNAT), Kali không ping được các máy `10.10.x.x`, WEB01 không vào được SRV01 cổng 22 (đều đã kiểm tra, đạt)
- [ ] LAN và DMZ gửi được tới SPLUNK01 cổng 9997 (chờ Splunk cài ở tuần 3)
- [ ] Xuất OVA khi cả lab đã xong (tắt hẳn máy rồi mới xuất, đặt tên `FW01-lab-v1.ova`)
- [ ] Cập nhật bộ rule trong tài liệu chung cho có hai dòng NTP và NTS (khi chủ file ra lệnh)

---

## SPLUNK01 (Ubuntu Server, máy chủ SIEM)

### Thông số

| Mục | Giá trị |
| --- | --- |
| Hệ điều hành | Ubuntu Server LTS, không có giao diện đồ họa (phiên bản: ........) |
| RAM | 3072 MB |
| vCPU, ổ đĩa | 2 vCPU, 40 GB (không cấp phát trước). Sau khi cài, hệ thống nhận đủ 40 GB, đã dùng 6,3 GB |
| Card mạng | 1 card, gắn VMnet4 (vùng SIEM) |
| Hostname | `splunk01` |
| Tài khoản | `labadmin` (mật khẩu lưu riêng, không đưa lên repo) |
| IP | `10.10.40.20/24`, gateway `10.10.40.254`, DNS `8.8.8.8` |
| Tên card trong máy | `ens32` (theo báo cáo của người làm; luôn lấy theo kết quả `ip -br a`) |

Quyết định thiết kế: giữ Ubuntu Server, không cài giao diện đồ họa. Splunk Web chạy ở cổng 8000 và được mở bằng trình duyệt trên máy host (VMnet4 có host adapter), nên không cần GUI trên máy ảo. GUI sẽ tốn thêm khoảng 1,5 đến 2 GB RAM và sinh thêm log nhiễu làm tốn license 500 MB mỗi ngày.

### Bước 0: Chuẩn bị

1. Tải Ubuntu Server LTS (file `ubuntu-...-live-server-amd64.iso`) từ ubuntu.com/download/server. Kiểm tra phiên bản hệ điều hành mà bộ cài Splunk Enterprise hỗ trợ trước khi chọn 22.04 hay 24.04.
2. Bật FW01 trước, vì FW01 là gateway của VMnet4 và SPLUNK01 cần nó để ra Internet.

### Bước 1: Tạo máy ảo

1. File, New Virtual Machine, Typical, chọn "I will install the operating system later".
2. Guest OS: Linux, Ubuntu 64-bit.
3. Tên `SPLUNK01`, ổ đĩa 40 GB, không cấp phát trước.
4. Customize Hardware: Memory 3072 MB, 2 CPU. Network Adapter đổi từ NAT sang Custom: VMnet4. CD/DVD trỏ vào file ISO Ubuntu. Xóa Sound Card, Printer, USB Controller.

### Bước 2: Cài Ubuntu Server

| Màn hình | Chọn |
| --- | --- |
| Installer update | Continue without updating |
| Language, Keyboard | English, English (US) |
| Type of install | Ubuntu Server (không phải minimized) |
| Network | Chọn card, Edit IPv4, Manual: Subnet `10.10.40.0/24`, Address `10.10.40.20`, Gateway `10.10.40.254`, Name servers `8.8.8.8` |
| Proxy, Mirror | Mặc định |
| Storage | Use an entire disk, bỏ tick "Set up this disk as an LVM group" (nếu để LVM, hệ thống thường chỉ dùng khoảng một nửa ổ) |
| Profile | Server name `splunk01`, username `labadmin`, đặt mật khẩu |
| Ubuntu Pro | Skip |
| SSH | Tick Install OpenSSH server, không import key |
| Featured snaps | Không chọn gì |

Cài xong bấm Reboot Now. Trong VM Settings, CD/DVD bỏ tick "Connected at power on".

### Bước 3: Kiểm tra mạng

```
ip -br a
ping -c 2 10.10.40.254
curl -I http://archive.ubuntu.com
```

Kết quả đúng: card có `10.10.40.20/24`, ping tới FW01 thông, `curl` trả về `HTTP/1.1 200 OK` hoặc tương tự.

`ping 8.8.8.8` thất bại là bình thường: bộ rule của FW01 chỉ cho vùng SIEM đi ra bằng TCP 53, 80, 443 và UDP 53 (và sau này thêm UDP 123, TCP 4460), ICMP bị chặn. Kiểm tra Internet bằng `curl` hoặc `apt update`.

Nếu phải sửa IP sau khi cài, sửa file netplan trong `/etc/netplan/` (tên file ở máy này là `00-installer-config.yaml`; máy khác có thể là `50-cloud-init.yaml`). Tên card trong file phải khớp tên card thật của máy (xem lỗi bên dưới):

```yaml
network:
  version: 2
  ethernets:
    ens32:
      addresses: [10.10.40.20/24]
      routes:
        - to: default
          via: 10.10.40.254
      nameservers:
        addresses: [8.8.8.8]
```

Áp dụng bằng `sudo netplan try` (tự quay lại cấu hình cũ sau 120 giây nếu không xác nhận) thay vì `netplan apply`. YAML dùng dấu cách, không dùng Tab.

### Bước 4: Cập nhật và cài gói cơ bản

```
sudo apt update && sudo apt -y upgrade
sudo apt install -y net-tools curl
systemctl status open-vm-tools --no-pager
sudo timedatectl set-timezone Asia/Ho_Chi_Minh
timedatectl
```

`open-vm-tools` thường đã có sẵn trên Ubuntu Server trong VMware. Nếu chưa có thì `sudo apt install -y open-vm-tools`.

### Bước 5: Đồng bộ giờ (cần sửa FW01, xem lỗi 5 ở phần FW01)

1. Trên FW01, thêm hai dòng NTP (UDP 123) và NTS (TCP 4460) vào chain `forward` của `/etc/nftables.nft`, rồi `nft -c -f /etc/nftables.nft` và `nft -f /etc/nftables.nft`.
2. Trên SPLUNK01:

```
sudo systemctl restart chrony
sleep 30
chronyc sources
chronyc tracking
timedatectl
```

Kết quả đúng: có ít nhất một dòng `^*` hoặc `^+` trong `chronyc sources`, `Leap status: Normal`, `System clock synchronized: yes`, giờ máy khớp giờ thực.

Ở máy này, trước khi sửa FW01, giờ máy lệch 7 tiếng so với giờ thực (hiện 20:25 trong khi giờ thực là 13:25). Sau khi đồng bộ, chrony nhảy giờ về đúng. Nguyên nhân lệch 7 tiếng chưa kiểm chứng (nghi VMware gán giờ địa phương của host thành giờ UTC cho máy ảo).

### Bước 6: Kiểm tra từ máy host

Kết quả người làm báo lại: SSH từ máy host vào `ssh labadmin@10.10.40.20` thành công, hệ thống nhận đủ ổ 40 GB và đã dùng 6,3 GB.

### Lỗi gặp phải và cách xử lý

| # | Lỗi | Nguyên nhân | Cách xử lý |
| --- | --- | --- | --- |
| 1 | Tên card là `ens32` trong khi hướng dẫn viết `ens33`, và có ý định đổi tên trong file netplan | Tên card do Ubuntu đặt theo vị trí khe PCI mà VMware gán cho card. Đổi tên trong netplan không đổi được card thật, netplan sẽ không tìm thấy card và máy mất mạng | Giữ nguyên `ens32`, ghi đúng tên card thật vào netplan. Không ép đổi tên bằng `set-name`, vì sẽ lệch khi import OVA (MAC mới) |
| 2 | `Failed to restart systemd-timesyncd.service: Unit ... not found` | Ubuntu này dùng `chrony` để đồng bộ giờ, không có `systemd-timesyncd` (`timedatectl timesync-status` cũng báo không khả dụng) | Dùng `chronyc` và `systemctl restart chrony` thay vì timesyncd |
| 3 | `System clock synchronized: no`, giờ lệch 7 tiếng, `chronyc sources` có `Reach` bằng 0 | Xem lỗi 5 ở phần FW01: NTS cần TCP 4460 và UDP 123, bộ rule FW01 lúc đầu chưa mở | Thêm hai rule vào FW01 rồi `restart chrony`. Kết quả: đồng bộ thành công |

Ghi chú thêm về quá trình làm:

- `NTP service: active` trong `timedatectl` chỉ cho biết dịch vụ đang chạy, chưa chắc đã đồng bộ được. Phải xem dòng `System clock synchronized`.
- `chronyc tracking` ngay sau khi restart có thể hiện `Frequency 0.000 ppm` và `Skew 1000000 ppm`, là giá trị khởi tạo của chrony. Không đáng lo, chạy lại sau khoảng 10 phút.

### Việc còn lại cho SPLUNK01

- [ ] Điền phiên bản Ubuntu Server đã cài ở bảng thông số
- [ ] `sudo poweroff` rồi chụp snapshot `splunk01-os-ready`
- [ ] Không cài Splunk lên máy này. Việc cài Splunk Enterprise là của người làm SIEM (B) ở tuần 3
- [ ] Xuất OVA khi cả lab đã xong (tắt hẳn máy rồi mới xuất, đặt tên `SPLUNK01-lab-v1.ova`)

---

## SRV01 (Ubuntu Server, máy chủ nội bộ chứa dữ liệu)

### Thông số

| Mục | Giá trị |
| --- | --- |
| Hệ điều hành | Ubuntu Server LTS, không có giao diện đồ họa (phiên bản: Ubuntu Server 26.04, file ISO `ubuntu-26.04-live-server-amd64`) |
| RAM | 2048 MB lúc cài, hạ xuống 1024 MB sau khi xong |
| vCPU, ổ đĩa | 1 vCPU, 12 GB (không cấp phát trước) |
| Card mạng | 1 card, gắn VMnet2 (vùng LAN) |
| Hostname | `srv01` |
| Tài khoản | `labadmin` (quản trị, có từ lúc cài), `ketoan1`, `nhansu1` (mật khẩu lưu riêng, không đưa lên repo) |
| IP | `10.10.10.10/24`, gateway `10.10.10.254`, DNS `8.8.8.8` |

Vai trò: mục tiêu cuối của chuỗi tấn công WEB01, CL01, SRV01. Dữ liệu trên máy đều là dữ liệu bịa.

### Bước 0: Chuẩn bị

1. Dùng lại file ISO Ubuntu Server đã tải cho SPLUNK01. Bật FW01 trước.
2. Bật tạm host adapter cho VMnet2 trong Virtual Network Editor (tick "Connect a host virtual adapter to this network", host nhận `10.10.10.1`) để SSH từ máy host vào được. Xong CL01 thì bỏ tick lại để vùng LAN cô lập như thiết kế.

### Bước 1: Tạo máy ảo

1. File, New Virtual Machine, Typical, chọn "I will install the operating system later".
2. Guest OS: Linux, Ubuntu 64-bit.
3. Tên `SRV01`, ổ đĩa 12 GB, không cấp phát trước.
4. Customize Hardware: Memory 2048 MB khi cài, 1 CPU. Network Adapter là Custom: VMnet2. CD/DVD trỏ vào ISO Ubuntu. Xóa Sound Card, Printer, USB Controller.

### Bước 2: Cài Ubuntu Server

| Màn hình | Chọn |
| --- | --- |
| Installer update | Continue without updating |
| Language, Keyboard | English, English (US) |
| Type of install | Ubuntu Server (không phải minimized) |
| Network | Edit IPv4, Manual: Subnet `10.10.10.0/24`, Address `10.10.10.10`, Gateway `10.10.10.254`, Name servers `8.8.8.8` |
| Proxy, Mirror | Mặc định |
| Storage | Use an entire disk, bỏ tick "Set up this disk as an LVM group" |
| Profile | Server name `srv01`, username `labadmin`, đặt mật khẩu |
| Ubuntu Pro | Skip |
| SSH | Tick Install OpenSSH server, không import key |
| Featured snaps | Không chọn gì |

Cài xong bấm Reboot Now, trong VM Settings bỏ tick "Connected at power on" ở CD/DVD.

### Bước 3: Kiểm tra mạng

```
ip -br a
ping -c 2 10.10.10.254
curl -I http://archive.ubuntu.com
```

Kết quả đúng: `10.10.10.10/24`, ping FW01 thông, `curl` trả về `HTTP/1.1 200 OK`. `ping 8.8.8.8` thất bại là bình thường (FW01 không chuyển tiếp ICMP). Sau đó làm qua SSH từ máy host: `ssh labadmin@10.10.10.10`.

### Bước 4: Cập nhật, múi giờ, kiểm tra giờ

```
sudo apt update && sudo apt -y upgrade
sudo apt install -y net-tools curl
sudo timedatectl set-timezone Asia/Ho_Chi_Minh
timedatectl
```

`System clock synchronized` phải là `yes` (rule NTP và NTS trên FW01 đã mở cho vùng LAN). `open-vm-tools` thường đã có sẵn; nếu chưa thì `sudo apt install -y open-vm-tools`.

### Bước 5: Cài dịch vụ cho vai trò máy chủ nội bộ

Tài khoản (mật khẩu tự đặt, lưu riêng):

```
sudo adduser --disabled-password --gecos "" ketoan1
sudo adduser --disabled-password --gecos "" nhansu1
sudo passwd ketoan1
sudo passwd nhansu1
```

Samba (thư mục chia sẻ có file giả):

```
sudo apt install -y samba smbclient
sudo mkdir -p /srv/share/ketoan /srv/share/nhansu
sudo chown ketoan1:ketoan1 /srv/share/ketoan
sudo chown nhansu1:nhansu1 /srv/share/nhansu
sudo chmod 770 /srv/share/ketoan /srv/share/nhansu
```

Hai file giả: `/srv/share/ketoan/khachhang.csv` (3 khách hàng bịa, chủ `ketoan1`) và `/srv/share/nhansu/luong-thang-9.csv` (2 nhân viên bịa, chủ `nhansu1`). Hai thư mục chia sẻ thêm vào cuối `/etc/samba/smb.conf`:

```
[ketoan]
   path = /srv/share/ketoan
   valid users = ketoan1
   read only = no

[nhansu]
   path = /srv/share/nhansu
   valid users = nhansu1
   read only = no
```

Đặt mật khẩu Samba, kiểm tra và bật dịch vụ:

```
sudo smbpasswd -a ketoan1
sudo smbpasswd -a nhansu1
testparm -s
sudo systemctl enable --now smbd
sudo systemctl restart smbd
smbclient -L localhost -U ketoan1
```

Lệnh cuối phải liệt kê hai thư mục `ketoan` và `nhansu`. Không bật `ufw` (tránh lẫn với rule của FW01).

MariaDB:

```
sudo apt install -y mariadb-server
sudo systemctl enable --now mariadb
```

Tạo database `congty`, bảng `khachhang` (id, ho_ten, email, so_dien_thoai, cong_no) với 3 dòng dữ liệu bịa, và user `appuser`@`localhost` chỉ có quyền `SELECT` trên `congty` (mật khẩu lưu riêng). MariaDB mặc định chỉ lắng nghe ở `127.0.0.1`, để nguyên như vậy: kẻ tấn công muốn lấy dữ liệu phải có shell trên SRV01.

auditd (chỉ cài và bật, bộ rule và Universal Forwarder làm ở tuần 3):

```
sudo apt install -y auditd
sudo systemctl enable --now auditd
```

### Bước 6: Kiểm tra cuối

Kết quả người làm báo lại: setup SRV01 thành công. `smbd` ở trạng thái `active (running)` và `enabled`, `mariadb` ở trạng thái `active`. Log có hai phiên Samba của `ketoan1` lúc 20:00 và 20:06 (nhiều khả năng là hai lần chạy thử `smbclient`).

| Kiểm tra | Kết quả mong đợi |
| --- | --- |
| `ip -br a` | `10.10.10.10/24` |
| `timedatectl` | `System clock synchronized: yes` |
| `smbclient -L localhost -U ketoan1` | Thấy hai thư mục chia sẻ |
| `sudo mysql -e "SELECT * FROM congty.khachhang;"` | Hiện 3 dòng |
| `systemctl is-active ssh smbd mariadb auditd` | Cả bốn đều `active` |

### Lỗi gặp phải và cách xử lý

| # | Lỗi | Nguyên nhân | Cách xử lý |
| --- | --- | --- | --- |
| 1 | `systemctl is-active smdb mariadb` báo `inactive` ở dịch vụ đầu | Gõ nhầm tên dịch vụ: `smdb` thay vì `smbd`. Không có dịch vụ tên `smdb` nên báo `inactive` | Gõ đúng `smbd`. Dịch vụ Samba thật đang chạy bình thường. Dùng `systemctl is-active ssh smbd mariadb auditd` để kiểm tra cả bốn |

Ghi chú: `sudo journalctl -u smbd -b` trả về `No entries` dù `systemctl status smbd` vẫn hiện log. Chưa giải thích được, không ảnh hưởng đến hoạt động.

### Việc còn lại cho SRV01

- [x] Điền phiên bản Ubuntu Server đã cài (đã ghi ở bảng thông số)
- [x] Hạ RAM xuống 1024 MB (người làm báo đã làm)
- [x] Bỏ tick host adapter VMnet2 (người làm báo đã làm)
- [x] Tắt hẳn máy và chụp snapshot `srv01-ok` (người làm báo đã làm)
- [ ] Ghi tên, mật khẩu `ketoan1`, `nhansu1`, `appuser` và danh sách dữ liệu giả vào mục "điểm yếu cố ý" của `README.md` (mật khẩu ghi ở chỗ riêng, không đưa lên repo)
- [ ] Xuất OVA khi cả lab đã xong (tên `SRV01-lab-v1.ova`)

---

## CL01 (Ubuntu Server, máy của nhân viên)

### Thông số

| Mục | Giá trị |
| --- | --- |
| Hệ điều hành | Ubuntu Server LTS, không có giao diện đồ họa (phiên bản: Ubuntu Server 26.04, file ISO `ubuntu-26.04-live-server-amd64`) |
| RAM | 2048 MB lúc cài, hạ xuống 768 MB sau khi xong (nếu treo thì 1024 MB) |
| vCPU, ổ đĩa | 1 vCPU, 12 GB (không cấp phát trước) |
| Card mạng | 1 card, gắn VMnet2 (vùng LAN) |
| Hostname | `cl01` |
| Tài khoản | `labadmin`, `nhanvien1` (mật khẩu yếu cố ý), `nhanvien2` (mật khẩu bình thường). Mật khẩu lưu riêng, không đưa lên repo |
| IP | `10.10.10.11/24`, gateway `10.10.10.254`, DNS `8.8.8.8` |

Vai trò: điểm đặt chân của kẻ tấn công sau khi pivot từ WEB01, đồng thời tạo hoạt động bình thường (cron job) làm mốc so sánh cho các cuộc hunt ở tuần 7.

### Bước 0 đến 3: Tạo máy ảo, cài Ubuntu, kiểm tra mạng

Làm giống SRV01 (bước 0 đến 3), khác ở: tên máy ảo `CL01`, Server name `cl01`, Address `10.10.10.11`, Memory 2048 MB lúc cài. Kiểm tra: `ip -br a` ra `10.10.10.11/24`, ping `10.10.10.254` thông, `curl -I http://archive.ubuntu.com` trả về `HTTP/1.1 200 OK`. Sau đó SSH từ máy host: `ssh labadmin@10.10.10.11`.

### Bước 4: Cập nhật và cài gói

```
sudo apt update && sudo apt -y upgrade
sudo apt install -y net-tools curl smbclient auditd
sudo timedatectl set-timezone Asia/Ho_Chi_Minh
sudo systemctl enable --now auditd
python3 --version
timedatectl
```

`System clock synchronized` phải là `yes`. Chỉ cài và bật auditd, bộ rule và Universal Forwarder làm ở tuần 3.

### Bước 5: Tạo tài khoản người dùng

```
sudo adduser --disabled-password --gecos "" nhanvien1
sudo adduser --disabled-password --gecos "" nhanvien2
sudo passwd nhanvien1
sudo passwd nhanvien2
```

`nhanvien1` đặt mật khẩu yếu cố ý (loại có trong từ điển mật khẩu phổ biến), là mục tiêu brute force SSH ở bước pivot (tuần 6). `nhanvien2` đặt mật khẩu bình thường làm đối chứng.

### Bước 6: Tạo hoạt động nền (làm sau khi SRV01 xong)

Theo hướng dẫn. Người làm báo cả hai máy đã ổn, nhưng kết quả chi tiết từng bước dưới đây chưa được xác nhận.

1. Khóa SSH để `nhanvien1` đăng nhập SRV01 không cần mật khẩu:

```
sudo -u nhanvien1 mkdir -p -m 700 /home/nhanvien1/.ssh
sudo -u nhanvien1 ssh-keygen -t ed25519 -N "" -f /home/nhanvien1/.ssh/id_ed25519
sudo -u nhanvien1 ssh-copy-id -i /home/nhanvien1/.ssh/id_ed25519.pub ketoan1@10.10.10.10
```

Khóa không có mật khẩu bảo vệ, nên kẻ chiếm được `nhanvien1` đăng nhập thẳng vào SRV01 được. Đây là điểm yếu cố ý (tái sử dụng khóa), ghi vào danh sách điểm yếu.

2. File thông tin đăng nhập Samba `/home/nhanvien1/.smbcred` (chứa `username=ketoan1` và `password=...`), `chown nhanvien1:nhanvien1`, `chmod 600`.

3. Chạy thử từng lệnh trước khi đưa vào cron:

```
sudo -u nhanvien1 smbclient //10.10.10.10/ketoan -A /home/nhanvien1/.smbcred -c 'ls'
sudo -u nhanvien1 ssh -i /home/nhanvien1/.ssh/id_ed25519 -o BatchMode=yes ketoan1@10.10.10.10 uptime
sudo -u nhanvien1 curl -I https://www.ubuntu.com
```

4. Cron job cho `nhanvien1` (`sudo crontab -u nhanvien1 -e`):

```
SHELL=/bin/bash
*/5 * * * * sleep $((RANDOM \% 120)); smbclient //10.10.10.10/ketoan -A /home/nhanvien1/.smbcred -c 'ls' >/dev/null 2>&1
*/10 * * * * sleep $((RANDOM \% 240)); ssh -i /home/nhanvien1/.ssh/id_ed25519 -o BatchMode=yes ketoan1@10.10.10.10 uptime >/dev/null 2>&1
*/15 * * * * sleep $((RANDOM \% 300)); curl -s -o /dev/null https://www.ubuntu.com/
#*/5 * * * * sleep $((RANDOM \% 120)); curl -s -o /dev/null http://10.10.20.10/
```

Lưu ý: dấu `\%` là bắt buộc (trong crontab `%` thường bị coi là xuống dòng). `SHELL=/bin/bash` để dùng được `$RANDOM`. Độ trễ ngẫu nhiên để hoạt động nền không đều như đồng hồ, tránh trông giống beaconing làm hỏng cuộc hunt ở tuần 7. Dòng `curl` tới WEB01 đang bị comment, bỏ dấu `#` khi WEB01 dựng xong.

5. Kiểm tra sau vài phút: `sudo journalctl -u cron --since "15 minutes ago" --no-pager | tail` thấy dòng `CMD` của `nhanvien1`. Trên SRV01, `/var/log/auth.log` có dòng `Accepted publickey for ketoan1` từ `10.10.10.11`.

### Lỗi gặp phải và cách xử lý

| # | Lỗi | Nguyên nhân | Cách xử lý |
| --- | --- | --- | --- |
| 1 | Sau `apt upgrade`, hiện màn hình chọn ngôn ngữ và bấm nhầm sang ngôn ngữ khác tiếng Anh | Màn hình cấu hình hiện lên sau khi nâng cấp gói và chọn nhầm ngôn ngữ do đang bật chế độ gõ tiếng Việt (người làm xác nhận) | Người làm báo đã sửa xong, không còn lỗi. Cách kiểm tra: `locale` và `cat /etc/default/keyboard` (phải là `en_US.UTF-8` và `XKBLAYOUT=us`). Đặt lại: `sudo update-locale LANG=en_US.UTF-8` và `sudo dpkg-reconfigure keyboard-configuration`. Lab nên giữ tiếng Anh vì rule phát hiện theo chuỗi tiếng Anh, thông báo log bị dịch sẽ làm rule không khớp |
| 2 | `sudo -u nhanvien1 mkdir -p -m 700` báo thiếu đối số (`<dirs>...`) | Lệnh bị cụt, thiếu đường dẫn `/home/nhanvien1/.ssh` ở cuối (nhiều khả năng rớt khi sao chép) | Gõ đủ lệnh `sudo -u nhanvien1 mkdir -p -m 700 /home/nhanvien1/.ssh`, kiểm tra bằng `sudo ls -ld /home/nhanvien1/.ssh` (phải là `drwx------`). Chạy từng lệnh một, không dán nhiều dòng |
| 3 | `ssh-copy-id` không nhận chữ `yes` ở câu hỏi xác nhận khóa máy chủ, hỏi lại liên tục | Chế độ gõ tiếng Việt đang bật làm chữ `yes` gõ vào console bị sai (người làm xác nhận) | Người làm báo đã sửa xong sau khi tắt chế độ gõ tiếng Việt. Cách tránh: tắt bộ gõ tiếng Việt khi làm việc với máy ảo, chạy lại với `-o StrictHostKeyChecking=accept-new` để không phải gõ `yes`, và làm qua SSH từ máy host (`ssh labadmin@10.10.10.11`) thay vì console VMware, tắt bộ gõ tiếng Việt trước khi gõ |

### Việc còn lại cho CL01

- [x] Điền phiên bản Ubuntu Server đã cài (đã ghi ở bảng thông số)
- [x] Bước 6 (hoạt động nền): người làm báo cron đã chạy
- [x] Hạ RAM xuống 768 MB (người làm báo đã làm)
- [x] Bỏ tick host adapter VMnet2 (người làm báo đã làm)
- [x] Tắt hẳn máy và chụp snapshot `cl01-ok` (người làm báo đã làm)
- [ ] Khi dựng xong WEB01, bỏ dấu `#` ở dòng cron `curl` tới WEB01
- [ ] Ghi mật khẩu yếu của `nhanvien1` và điểm yếu khóa SSH không mật khẩu vào mục "điểm yếu cố ý" của `README.md`
- [ ] Xuất OVA khi cả lab đã xong (tên `CL01-lab-v1.ova`)

---

## WEB01 (Ubuntu Server, web server trong DMZ chạy DVWA)

### Thông số

| Mục | Giá trị |
| --- | --- |
| Hệ điều hành | Ubuntu Server 26.04 (file ISO `ubuntu-26.04-live-server-amd64`), không có giao diện đồ họa |
| RAM | 2048 MB lúc cài, hạ xuống 1536 MB sau khi xong (nếu treo thì 2048 MB) |
| vCPU, ổ đĩa | 1 vCPU, 15 GB (không cấp phát trước) |
| Card mạng | 1 card, gắn VMnet3 (vùng DMZ) |
| Hostname | `web01` |
| Tài khoản | `labadmin` (mật khẩu lưu riêng, không đưa lên repo) |
| IP | `10.10.20.10/24`, gateway `10.10.20.254`, DNS `8.8.8.8` |
| Phần mềm | Apache, PHP, MariaDB, DVWA (mức bảo mật Low đặt mặc định phía máy chủ, xem bước 7b), auditd |

Vai trò: máy duy nhất được mở ra ngoài (DNAT cổng 80 từ WAN của FW01), là điểm vào đầu tiên của kẻ tấn công. DVWA là ứng dụng cố ý có lỗ hổng, đại diện cho ứng dụng web chưa vá, dùng để có dữ liệu tấn công thật cho Splunk.

### Bước 0: Chuẩn bị

1. Dùng lại ISO Ubuntu Server. Bật FW01 trước.
2. Bật tạm host adapter cho VMnet3 (host nhận `10.10.20.1`) để SSH và mở trình duyệt từ máy host. Xong thì bỏ tick lại để DMZ cô lập như thiết kế.
3. Ghi lại IP eth0 của FW01 (`ip -br a` trên FW01) để thử đường DNAT.

### Bước 1: Tạo máy ảo

1. File, New Virtual Machine, Typical, chọn "I will install the operating system later".
2. Guest OS: Linux, Ubuntu 64-bit.
3. Tên `WEB01`, ổ đĩa 15 GB, không cấp phát trước.
4. Customize Hardware: Memory 2048 MB lúc cài, 1 CPU. Network Adapter là Custom: VMnet3. CD/DVD trỏ vào ISO Ubuntu. Xóa Sound Card, Printer, USB Controller.

### Bước 2: Cài Ubuntu Server

Giống SRV01 (bước 2), khác ở: Server name `web01`, Address `10.10.20.10`, Subnet `10.10.20.0/24`, Gateway `10.10.20.254`. Bỏ tick LVM, tick Install OpenSSH server, tắt chế độ gõ tiếng Việt khi gõ vào console. Cài xong bỏ tick "Connected at power on" ở CD/DVD.

### Bước 3: Kiểm tra mạng

```
ip -br a
ping -c 2 10.10.20.254
curl -I http://archive.ubuntu.com
```

Kết quả đúng: `10.10.20.10/24`, ping FW01 thông, `curl` trả về `HTTP/1.1 200 OK`. Sau đó SSH từ máy host: `ssh labadmin@10.10.20.10`.

### Bước 4: Cập nhật và kiểm tra giờ

```
sudo apt update && sudo apt -y upgrade
sudo apt install -y net-tools curl git
sudo timedatectl set-timezone Asia/Ho_Chi_Minh
timedatectl
```

`System clock synchronized` phải là `yes` (rule NTP và NTS trên FW01 đã mở cho DMZ).

### Bước 5: Cài Apache, PHP, MariaDB

```
sudo apt install -y apache2 mariadb-server php libapache2-mod-php php-mysql php-gd
sudo systemctl enable --now apache2 mariadb
PHPV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
echo $PHPV
ls /etc/php/
```

Biến `PHPV` chỉ sống trong phiên SSH hiện tại, chạy lại lệnh nếu đăng xuất giữa chừng.

### Bước 6: Cài DVWA

```
sudo git clone https://github.com/digininja/DVWA.git /var/www/html/DVWA
```

Tạo database và user cho DVWA (mật khẩu `p@ssw0rd` là mật khẩu mặc định công khai của DVWA, MariaDB chỉ lắng nghe `127.0.0.1`):

```
sudo mysql <<'EOF'
CREATE DATABASE dvwa;
CREATE USER 'dvwa'@'localhost' IDENTIFIED BY 'p@ssw0rd';
GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa'@'localhost';
FLUSH PRIVILEGES;
EOF
```

Tạo file cấu hình và kiểm tra:

```
sudo cp /var/www/html/DVWA/config/config.inc.php.dist /var/www/html/DVWA/config/config.inc.php
grep -E "db_(server|database|user|password)" /var/www/html/DVWA/config/config.inc.php
```

Bật các tùy chọn PHP cần cho lỗ hổng include file:

```
sudo sed -i 's/^allow_url_include.*/allow_url_include = On/' /etc/php/$PHPV/apache2/php.ini
sudo sed -i 's/^allow_url_fopen.*/allow_url_fopen = On/' /etc/php/$PHPV/apache2/php.ini
grep -E "^allow_url_(include|fopen)" /etc/php/$PHPV/apache2/php.ini
```

Phân quyền và khởi động lại Apache:

```
sudo chown -R www-data:www-data /var/www/html/DVWA
sudo chmod -R 775 /var/www/html/DVWA/hackable/uploads /var/www/html/DVWA/config
sudo systemctl restart apache2
systemctl is-active apache2
```

### Bước 7: Hoàn tất cài đặt DVWA bằng trình duyệt

Từ máy host mở `http://10.10.20.10/DVWA/setup.php` (được vì VMnet3 đang có host adapter):

1. Kiểm tra các mục quan trọng đã xanh (`allow_url_include`, `gd`, `mysqli`, ghi được `hackable/uploads`). Mục reCAPTCHA key Missing màu đỏ thì bỏ qua.
2. Bấm Create / Reset Database.
3. Đăng nhập `admin` / `password` (tài khoản mặc định của DVWA).
4. Vào DVWA Security, chọn mức Low, bấm Submit. Lựa chọn này chỉ áp dụng cho phiên trình duyệt đó (xem bước 7b).

### Bước 7b: Đặt mức bảo mật Low mặc định ở phía máy chủ

Phát hiện khi kiểm tra từ Kali: `curl -I http://<IP WAN của FW01>/DVWA/login.php` trả về `Set-Cookie: security=impossible`, tức phiên mới bắt đầu ở mức Impossible (khó nhất). Nghi mức bảo mật gắn với cookie từng phiên, nên chọn Low trên trình duyệt chỉ áp dụng cho phiên đó (chưa kiểm chứng). Cách sửa, trên WEB01:

```
grep -n "default_security_level" /var/www/html/DVWA/config/config.inc.php
sudo sed -i "s/^\(\$_DVWA\[ *'default_security_level' *\] *= *\).*/\1'low';/" /var/www/html/DVWA/config/config.inc.php
grep -n "default_security_level" /var/www/html/DVWA/config/config.inc.php
```

Dòng cuối phải hiện `= 'low';`. Kiểm tra từ Kali: `curl -s -I http://<IP WAN của FW01>/DVWA/login.php | grep -i "security="` phải ra `security=low`. Người làm báo đã sửa mức Low, kết quả kiểm tra cookie chưa được báo lại.

### Bước 8: Cài auditd

```
sudo apt install -y auditd
sudo systemctl enable --now auditd
systemctl is-active auditd
```

Chỉ cài và bật, bộ rule và Universal Forwarder làm ở tuần 3. Lúc đó cần cho tài khoản chạy forwarder đọc được log Apache trong `/var/log/apache2/`.

### Bước 9: Kiểm tra

Kết quả người làm báo lại: tất cả các bước đều thành công.

| Kiểm tra | Chạy ở đâu | Kết quả mong đợi |
| --- | --- | --- |
| `ip -br a` | WEB01 | `10.10.20.10/24` |
| `curl -I http://localhost/DVWA/login.php` | WEB01 | `HTTP/1.1 200 OK` |
| `systemctl is-active apache2 mariadb auditd ssh` | WEB01 | Xem lỗi 1 về `ssh` |
| Mở `http://<IP eth0 của FW01>/DVWA/` trên trình duyệt | Máy host | Thấy trang đăng nhập DVWA (kiểm tra DNAT qua FW01) |
| `curl -I http://10.10.20.10/DVWA/login.php` | CL01 | `HTTP/1.1 200 OK` |
| `timeout 5 bash -c 'echo > /dev/tcp/10.10.10.10/22' && echo OPEN \|\| echo BLOCKED` | WEB01 | `BLOCKED` (DMZ không chạm được LAN) |

Ghi chú: DNAT cũng chuyển cổng 443 vào WEB01, nhưng Apache chưa bật HTTPS nên cổng 443 chỉ báo lỗi kết nối, không ảnh hưởng gì.

### Lỗi gặp phải và cách xử lý

| # | Lỗi | Nguyên nhân | Cách xử lý |
| --- | --- | --- | --- |
| 1 | Sau khi hạ RAM xuống 1536 MB và khởi động lại, `systemctl is-active ssh` báo `inactive` | Chưa xác nhận. Nghi SSH chạy theo socket activation: `ssh.socket` luôn lắng nghe cổng 22, còn `ssh.service` chỉ khởi động khi có kết nối đầu tiên, nên `ssh` báo `inactive` dù SSH vẫn dùng được. Người làm kết luận không có lỗi, nhưng kết quả kiểm tra `ssh.socket` chưa được báo lại | Kiểm tra: `systemctl is-active ssh.socket`, `systemctl is-enabled ssh ssh.socket`, `sudo ss -tlnp \| grep ':22'`. Nếu `ssh.socket` active và cổng 22 đang lắng nghe thì bình thường. Nếu không thì `sudo systemctl enable --now ssh` và xem `sudo journalctl -u ssh -b --no-pager \| tail -n 30`. Trên Ubuntu tên dịch vụ là `ssh` (không phải `sshd`) |
| 2 | Từ Kali, `curl -I` trang đăng nhập DVWA thấy `Set-Cookie: security=impossible`, các lỗ hổng gần như không khai thác được | Chọn mức Low ở bước 7 chỉ áp dụng cho phiên trình duyệt của host, còn mức mặc định của máy chủ vẫn là Impossible (giả thuyết, chưa kiểm chứng) | Đổi `default_security_level` thành `'low'` trong `/var/www/html/DVWA/config/config.inc.php` (bước 7b). Người làm báo đã sửa |

### Việc còn lại cho WEB01

- [ ] Xác nhận `ssh.socket` active và SSH vào được sau khi khởi động lại (xem lỗi 1)
- [x] Hạ RAM xuống 1536 MB (người làm báo đã làm)
- [x] Đặt mức Low mặc định phía máy chủ (người làm báo đã sửa)
- [ ] Xác nhận từ Kali `curl` ra `security=low`
- [ ] Bỏ tick host adapter VMnet3
- [ ] Tắt hẳn máy và chụp snapshot `web01-ok`
- [ ] Trên CL01, bỏ dấu `#` ở dòng cron `curl` tới `http://10.10.20.10/` (`sudo crontab -u nhanvien1 -e`)
- [ ] Ghi vào mục "điểm yếu cố ý" của `README.md`: DVWA mức Low, `admin/password`, MariaDB `dvwa/p@ssw0rd` (chỉ nghe trên localhost), `allow_url_include = On`
- [ ] Xuất OVA khi cả lab đã xong (tên `WEB01-lab-v1.ova`)

---

## KALI (kẻ tấn công, nằm ngoài firewall)

Máy này dùng bản Kali dựng sẵn cho VMware mà người làm đã có, nên không có phần cài đặt hệ điều hành. Mỗi người trong nhóm tự tải bản Kali của mình, không xuất OVA.

### Thông số

| Mục | Giá trị |
| --- | --- |
| Hệ điều hành | Kali Linux (bản VMware dựng sẵn) |
| RAM, vCPU, ổ đĩa | Theo thiết kế: 2 GB, 2 vCPU, 30 GB (cấu hình thực tế chưa được báo lại) |
| Card mạng | 1 card, gắn VMnet8 (NAT), cùng mạng với cổng WAN của FW01 |
| IP | DHCP của VMware, cùng dải với eth0 của FW01 (`192.168.30.x`). Theo log FW01, IP của Kali lúc ghi là `192.168.30.134` (suy ra từ log, có thể đổi) |

Vai trò: kẻ tấn công ở ngoài, chỉ thấy IP WAN của FW01 (`192.168.30.132` lúc ghi). Muốn vào bên trong phải đi qua DNAT cổng 80 vào WEB01 rồi pivot.

### Các bước đã làm

1. Kiểm tra Network Adapter của Kali là NAT (VMnet8) và IP cùng dải với eth0 của FW01.
2. Kiểm tra công cụ: người làm báo các công cụ cần dùng (`nmap`, `hydra`, `sqlmap`, `nikto`, `msfconsole`) đã có sẵn, không cần cài thêm.
3. Kiểm tra góc nhìn của kẻ tấn công ngoài (chạy từ Kali):

```
curl -I http://<IP WAN của FW01>/DVWA/login.php
nmap -Pn -p 22,80,443,10000 <IP WAN của FW01>
ping -c 2 10.10.20.10
ping -c 2 10.10.10.10
ping -c 2 10.10.40.20
```

Kết quả người làm báo lại:

| Kiểm tra | Kết quả | Đánh giá |
| --- | --- | --- |
| `curl` tới IP WAN của FW01 | `HTTP/1.1 200 OK`, trang DVWA | Đạt, DNAT hoạt động |
| `nmap` cổng 80 | `open` | Đạt |
| `nmap` cổng 443 | `closed` | Đạt (DNAT chuyển vào WEB01, Apache chưa bật HTTPS nên từ chối) |
| `nmap` cổng 22 và 10000 | `filtered` | Đạt (FW01 chặn im lặng mọi gói vào chính nó từ WAN trừ DHCP, và chỉ LAN được SSH vào FW01) |
| `ping` tới `10.10.20.10`, `10.10.10.10`, `10.10.40.20` | Mất 100% gói | Đạt, Kali không chạm được các vùng bên trong |

Log của FW01 ghi lại các lần quét: có các dòng `FW-WAN-IN-DROP` với `SRC` là IP của Kali và `PROTO=TCP DPT=22` (cờ SYN), cùng các dòng từ máy host thử SSH vào IP WAN của FW01. Người làm xác nhận thấy log mới từ Kali theo thời gian thực sau khi sửa giờ FW01.

### Lưu ý

- Kali ở cùng VMnet8 với đường ra Internet thật, nên chỉ quét và tấn công IP WAN của FW01 và các máy trong lab, không quét địa chỉ nào ngoài lab.
- IP WAN của FW01 do DHCP của VMware cấp nên có thể đổi, và mỗi người import OVA sẽ có IP khác nhau. Ghi lại IP của máy mình trước mỗi lần tấn công.
- Phát hiện khi kiểm tra: mức bảo mật mặc định của DVWA đang là Impossible (xem bước 7b và lỗi 2 ở phần WEB01).
- Giờ trên các máy phải thống nhất khi truy vết. Kali (VMnet8, ra Internet trực tiếp) đồng bộ giờ bình thường, nhưng nên kiểm tra `timedatectl` và đặt múi giờ `Asia/Ho_Chi_Minh` cho khớp các máy khác.

### Việc còn lại cho KALI

- [ ] Xác nhận đã đổi mật khẩu mặc định của Kali
- [ ] Xác nhận giờ và múi giờ (`timedatectl`, múi giờ `Asia/Ho_Chi_Minh`)
- [ ] Tắt hẳn máy và chụp snapshot `kali-ok`
- [ ] Ghi IP WAN của FW01 và IP của Kali vào chỗ riêng của nhóm trước khi làm kịch bản tấn công (tuần 6)