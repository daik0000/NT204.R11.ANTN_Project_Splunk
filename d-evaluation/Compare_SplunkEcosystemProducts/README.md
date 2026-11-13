# Tìm hiểu các sản phẩm trong hệ sinh thái Splunk

## I. Spunk Platform

### 1. Splunk Enterprise

Hệ thống SIEM(thu thập, tạo index, tìm kiếm, phân tích log) tự cài và vận hành trên hạ tầng bản thân

Các thành phần cơ bản:

- Universal Forwarder: cài trên máy nguồn, gửi dữ liệu về Heavy Forwarder/Indexer
- Heavy Forwarder: thực chất là một Splunk Enterprise instance được cấu hình ở chế độ forwarder, cài trên máy nguồn hoặc một server riêng, thực hiện xử lý log rồi forward đến Indexer
- Indexer: nhận, parse, index và lưu log
- Search Head: giao diện Splunk Web query đến Index để search, tạo dashboard và alert

Kiến trúc thông thường: UF -> HF(Optional) -> Indexer -> Search Head

### 2. Splunk Cloud Platform

Là Splunk Enterprise được cung cấp dưới dạng managed service(bản thân không cần quan tâm quản lý hạ tầng, hạ tầng được Splunk quản lý)

Splunk lo việc cấp phát hạ tầng, vá lỗi và bảo trì, còn người dùng chỉ tập trung vào dữ liệu, truy vấn, dashboard và cảnh báo

| Tiêu chí | Splunk Enterprise | Splunk Cloud Platform |
| --- | --- | --- |
| Triển khai | Tự cài đặt | Splunk cày đặt sẵn |
| Hạ tầng, nâng cấp, vá lỗi | Sử dụng hạ tầng của bản thân | Spunk chạy trên Cloud |
| Mức kiểm soát | Cao (tùy biến sâu, truy cập hệ điều hành) | Thấp hơn (có giới hạn về app và cấu hình) |
| Phù hợp | Cần kiểm soát hoàn toàn, dữ liệu phải ở on-prem | Muốn triển khai nhanh, ít gánh nặng vận hành |

> Tức chức năng core là giống nhau, chỉ khác ở vấn đề quản lý hạ tầng

## II. Splunk Security

### 1. Splunk Enterprise Security(ES)

Là một **module thêm** cài trên nền tảng Splunk, có thể là Splunk Enterprise hoặc Splunk Cloud Platform, để hỗ trợ thêm các chức năng về security như:

- Threat detection: các rule tìm kiếm threat chạy theo schedule, Splunk cũng hỗ trợ ESCU là một bộ rule tìm threat được định nghĩa sẵn
- Findings và Investigations: khi có threat match với rule đã cày đặt thì ES sẽ tạo finding tương ứng. Các finding liên quan sẽ được gom lại thành một investigation
- Risk-Based Alerting(RBA): thay vì tạo alert cho từng risk event riêng lẻ thì ES sẽ thực hiện như sau:
  - Mỗi risk event sinh ra sẽ có risk entity(thực thể tương ứng với risk đó) và risk score tương ứng
  - Gom các risk event lại với nhau theo risk entity, nếu tổng risk score vượt ngưỡng thì mới alert, cách này giúp giảm alert fatigue(admin nhận quá nhiều alert mà khó tổng hợp chúng)
- Kết hợp với Splunk SOAR để tự động hóa response đối với các threat detect được

(ES được cài trên Search Head, không cài trên Indexer hay Forwarder)

### 2. Splunk SOAR

Là một sản phẩm độc lập có máy chủ và giao diện riêng(khác với ES là một module cài lên Spunk Enterprise)

Chức năng: **SOAR - tự động hóa response khi có sự cố**

Các concepts:

- Events/Containers: sự cố
- Artifacts: các thông tin của một Events, ví dụ: IP, URL, email, ...
- App: bên thứ ba, ví dụ firewall, EDR, VirusTotal, Active Directory, ServiceNow…
- Actions: các hành động cụ thể mà App cung cấp, ví dụ block ip, disable user, ...
- Playbook: chuỗi các action kèm điều kiện, vòng lặp, phê duyệt của con người. Có thể dựng bằng trình thiết kế trực quan (kéo thả) hoặc viết bằng Python.

### 3. Spunk Attack Analyzer (SAA)

Là một sản phẩm độc lập có máy chủ và giao diện riêng(khác với ES là một module cài lên Spunk Enterprise)

Chức năng: **phân tích mối threat tự động, tập trung vào credential phishing và malware.** Bạn đưa vào một thứ đáng ngờ (URL, tệp, email), SAA sẽ tự “mở ra xem” thay analyst và trả về kết luận kèm bằng chứng.

SAA sẽ nhận đầu vào là URL/tệp/email, sau đó chạy thử toàn bộ cuộc tấn công và trả về điểm đe dọa của đầu vào tương ứng đó

Các concepts:

- Resource: thứ được nộp để phân tích (URL, file, email)
- Job: một phân tích tương ứng với một resource, gồm nhiều taskes, tức toàn bộ cuộc tấn công
- Task: một bước nhỏ trong job(tức một giai đoạn trong toàn bộ cuộc tấn công), ví dụ `mở link`, `chạy sandbox`
- Engine: công cụ phân tích cụ thể thực hiện task

Các task sau khi chạy xong sẽ trả về điểm đe dọa tương ứng, điểm đe dọa của cả job là điểm đe dọa cao nhất trong các taskes

**Flow hoạt động của SAA như sau:**

- **Nhận đầu vào (Resource):** URL, tệp hoặc email. Resource là bất kỳ thứ gì được gửi đi phân tích.
- **Chạy nhiều engine phân tích:** SAA kết hợp phân tích tĩnh, động và theo ngữ cảnh trong một khung đa engine phối hợp, đồng thời có thể trích xuất các thành phần như mã QR mà kẻ tấn công thường sử dụng trong phishing.
- **Theo dõi chuỗi tấn công:** Link dẫn tới trang đăng nhập giả, tệp PDF chứa link khác, macro trong Office... SAA theo dõi từng bước và dựng sơ đồ trực quan. Nó tạo hình ảnh thời gian thực cho từng bước, cho thấy nội dung độc hại nằm ở đâu và cuộc tấn công diễn tiến ra sao.
- **Chuẩn hóa kết quả (Normalized Forensics):** Kết quả thô từ các engine được chuyển đổi sang một định dạng thống nhất để dễ diễn giải.
- **Chấm điểm (Scoring):** Điểm được phân loại theo màu sắc: xanh (0–49), vàng (50–74), đỏ (75–100). Task có điểm cao nhất quyết định điểm đe dọa của toàn bộ job.

## III. Splunk Observability

### 1. Splunk Observability Cloud

Là một sản phẩm độc lập có máy chủ và giao diện riêng(khác với ES là một module cài lên Spunk Enterprise)

Là nền tảng observability được cung cấp dưới dạng managed service(hạ tầng được quản lý bởi splunk)

Nền tảng observability: cung cấp khả năng giám sát và troubleshooting theo thời gian thực, ở mọi quy mô, trên toàn bộ hạ tầng, ứng dụng và giao diện người dùng -> Tức là monitor metric của các servers, ứng dụng, ... (giống prometheus + grafana)

Khác với Splunk AppDynamics(tập trung vào APM: theo dõi ứng dụng), Splunk Observability Cloud tập trung vào Full-Stack Observability

**Các thành phần chính:**

- **Infrastructure Monitoring**: Giám sát server, container, Kubernetes, cloud services bằng metrics theo thời gian thực. -> tức theo dõi servers, hạ tầng
- **APM (Application Performance Monitoring)**: Theo dõi distributed traces giữa các microservice để tìm nút thắt và nguyên nhân gốc. -> tức theo dõi ứng dụng
- **RUM (Real User Monitoring)**: Đo trải nghiệm thực tế của người dùng trên web và mobile.
- **Synthetic Monitoring**: Giả lập giao dịch người dùng để phát hiện sự cố trước khi người dùng gặp phải.
- **Log Observer Connect**: Cho phép truy vấn log từ Splunk Enterprise hoặc Splunk Cloud Platform ngay trong Observability Cloud, giúp xem dữ liệu tập trung tại một nơi.
- **Splunk On-Call**: Quản lý lịch trực và xử lý incident.
- **Ứng dụng mobile**: App iOS/Android để xem metrics quan trọng, nhận cảnh báo thời gian thực và xem dashboard thân thiện với điện thoại.

### 2. Splunk Agent Observability

Là một tính năng trong Splunk Observability Cloud để **theo dõi các ứng dụng AI/LLM và AI agent**

Chức năng:

- Theo dõi hành vi agent
- Đánh giá chất lượng đầu ra của AI agent
- Phân tích token và chi phí
- Xem nội dung hội thoại

### 3. Splunk AppDynamics

Là một sản phẩm độc lập có máy chủ và giao diện riêng(khác với ES là một module cài lên Spunk Enterprise)

Cũng là một nền tảng observability như Splunk Observability Cloud nhưng sản phẩm này tập trung chuyên sâu về APM(theo dõi ứng dụng), theo dõi Business Transactions và liên kết hiệu năng ứng dụng với hoạt động kinh doanh.

Hỗ trợ cả hai mô hình triển khai SaaS và Self-hosted

### 4. Splunk IT Service Intelligence(ITSI)

Là một sản phẩm độc lập có máy chủ và giao diện riêng(khác với ES là một module cài lên Spunk Enterprise)

Splunk ITSI là một giải pháp IT Service Monitoring và AIOps được xây dựng trên nền tảng Splunk Enterprise.

Mục đích chính của ITSI là giám sát tình trạng hoạt động của các dịch vụ IT (IT services), phát hiện bất thường, tương quan các sự kiện và hỗ trợ đội ngũ vận hành xác định nguyên nhân gây ra sự cố.

Điểm quan trọng là:

- Splunk Enterprise tập trung vào việc thu thập, lưu trữ, tìm kiếm và phân tích machine-generated data.
- Splunk ITSI sử dụng dữ liệu đó để xây dựng bức tranh tổng thể về tình trạng của các dịch vụ IT, phát hiện vấn đề và hỗ trợ xử lý sự cố.

### 5. Splunk On-Call

Là một sản phẩm độc lập có máy chủ và giao diện riêng(khác với ES là một module cài lên Spunk Enterprise)

Là nền tảng quản lý sự cố(Incident) và điều phối nhân sự trực xử lý sự cố

Ví dụ:

- Server production bị down lúc 2 giờ sáng.
- Monitoring system phát hiện server không phản hồi và tạo alert.
- Splunk On-Call tiếp nhận alert.
- Hệ thống xác định kỹ sư đang trực (on-call engineer).
- Gửi thông báo qua Push Notification, SMS hoặc cuộc gọi.
- Nếu kỹ sư không phản hồi, hệ thống tự động chuyển cảnh báo đến người tiếp theo.

Các chức năng:

- On-call Schedulling: quản lý lịch trực của các thành viên trong tổ chức
- Alert Routing: định tuyến cảnh báo đến đúng người hoặc đội ngũ phụ trách, ví dụ:
  - Alert liên quan đến Database → Database Team.
  - Alert liên quan đến Network → Network Team.
- Escalation Policies: tự chuyển tiếp cảnh báo nếu người nhận ban đầu không phản hồi.
- Incident Management: quản lý toàn bộ vòng đời của một incident
  - Acknowledge: Xác nhận đã nhận và chịu trách nhiệm xử lý incident
  - Snooze: Tạm hoãn thông báo trong một khoảng thời gian
  - Reroute: Chuyển incident sang người hoặc team khác
  - Resolve: Đánh dấu incident đã được xử lý
  - Add Responders: Thêm người tham gia xử lý sự cố
