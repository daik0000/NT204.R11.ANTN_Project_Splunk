# So sánh Splunk Enterprise và Wazuh

## 1. Tìm hiểu Wazuh

### 1.1 Kiến trúc

![Kiến trúc triển khai Wazuh](https://documentation.wazuh.com/current/_images/deployment-architecture1.png)

*Sơ đồ kiến trúc triển khai Wazuh — Wazuh server và Wazuh indexer có thể cấu hình thành cụm (cluster) để cân bằng tải và đảm bảo tính sẵn sàng cao. Nguồn: [[1]](#ref1)*

Wazuh gồm 4 thành phần: agent (cài trên endpoint), Wazuh manager, Wazuh indexer, Wazuh dashboard. Kiến trúc này gồm một agent đa nền tảng và ba thành phần trung tâm: Wazuh manager, Wazuh indexer, và Wazuh dashboard; dashboard truy vấn dữ liệu đã được đánh chỉ mục từ indexer, cung cấp giao diện để cấu hình manager và trực quan hóa dữ liệu an ninh đã phân tích [[2]](#ref2)[[3]](#ref3). Manager nhận dữ liệu an ninh từ agent và thiết bị agentless, xử lý (qua "normalization engine") rồi chuyển tới indexer và các đích khác; indexer thực chất là một cụm OpenSearch dùng để lưu trữ và tìm kiếm [[4]](#ref4).

Có 3 kiểu triển khai: **all-in-one** (cả 3 thành phần trên một máy, hợp cho lab và môi trường nhỏ với số endpoint hạn chế), **single-node** (mỗi thành phần một máy riêng, cho môi trường vừa cần hiệu năng cao hơn), và **multi-node/cluster** (nhiều manager và nhiều indexer thành cụm, cho tổ chức lớn) [[3]](#ref3).

So với Splunk: Splunk gộp vai trò "nhận, lưu, tìm kiếm" vào một tiến trình `splunkd`, còn Wazuh tách rõ 3 vai trò (manager xử lý luật, indexer lưu trữ dựa trên OpenSearch, dashboard là lớp trình bày dựa trên OpenSearch Dashboards) — kiến trúc module hóa hơn nhưng cũng nhiều thành phần cần vận hành hơn.

### 1.2 Thu thập dữ liệu

Cách chính là **agent-based**: agent cài trên từng endpoint, gồm nhiều module (thu thập log, giám sát toàn vẹn file - FIM, rootcheck, đánh giá cấu hình an ninh - SCA, phát hiện lỗ hổng, phản hồi chủ động, và tùy chọn chạy osquery) [[5]](#ref5)[[2]](#ref2). Ngoài ra Wazuh cũng hỗ trợ **agentless** (ví dụ nhận syslog từ thiết bị không cài được agent, như firewall), nhưng đây là cách thu thập phụ, ít tính năng hơn so với agent đầy đủ.

So với Universal Forwarder của Splunk (chỉ đọc file và chuyển tiếp, không phân tích), agent Wazuh làm nhiều việc hơn ngay tại máy nguồn (FIM, kiểm tra cấu hình, dò lỗ hổng), rồi mới gửi lên manager.

### 1.3 Luật phát hiện (rules/decoders)

Wazuh không dùng ngôn ngữ truy vấn kiểu pipe như SPL để viết luật phát hiện, mà dùng **decoder** (tách field từ log thô bằng regex, khai báo bằng XML) và **rule** (điều kiện kích hoạt alert, cũng khai báo XML, có `level` từ 0 đến 16) [[6]](#ref6). Ví dụ một decoder/rule tùy biến:

```xml
<decoder name="example">
  <program_name>^example</program_name>
</decoder>
<decoder name="example">
  <parent>example</parent>
  <regex>User '(\w+)' logged from '(\d+.\d+.\d+.\d+)'</regex>
  <order>user, srcip</order>
</decoder>

<rule id="100010" level="5">
  <if_sid>5700</if_sid>
  <match>illegal user|invalid user</match>
  <description>sshd: Attempt to login using a non-existent user</description>
</rule>
```
*(Ví dụ tham khảo từ [[7]](#ref7))*

ID luật tùy biến nằm trong khoảng 100000–120000, đặt trong `local_rules.xml`/`local_decoder.xml` để không bị mất khi cập nhật ruleset mặc định [[6]](#ref6). Có công cụ `wazuh-logtest` để thử luật với một dòng log mẫu trước khi áp dụng thật [[8]](#ref8) — tương tự việc nhóm hay thử `rex` trước khi lưu field extraction trong Splunk, nhưng ở Wazuh việc thử diễn ra ở dòng lệnh, không có giao diện kéo-thả như Interactive Field Extractor.

Về correlation (gom nhiều sự kiện), Wazuh dùng thẻ `<frequency>`, `<timeframe>`, `<same_field>` ngay trong rule XML — ví dụ luật có sẵn tạo alert khi có 8 lần SSH đăng nhập sai liên tiếp từ cùng một IP, gắn kèm mã MITRE ATT&CK T1110 [[9]](#ref9). Đây là lối viết **khai báo tĩnh** (đặt ngưỡng ngay trong luật), khác với Splunk nơi ngưỡng nằm trong câu SPL của alert và có thể đổi tự do mỗi lần chạy.

### 1.4 Tìm kiếm và threat hunting

Wazuh hỗ trợ threat hunting qua mục **Discover** của dashboard (dựa trên OpenSearch Discover, giống Kibana Discover): an ninh viên tìm kiếm và đối chiếu phát hiện với dữ liệu lịch sử để khớp IOC, xác định endpoint bị ảnh hưởng và điều tra. Dữ liệu từ nhiều nguồn (sự kiện an ninh, inventory, lỗ hổng, telemetry khác) dùng chung một mô hình dữ liệu nhất quán, cho phép tìm kiếm và liên kết qua nhiều luồng dữ liệu ngay trong Discover [[10]](#ref10).

Ngôn ngữ lọc dữ liệu là **Wazuh Query Language (WQL)**, áp dụng cho vài mục cụ thể của dashboard (SCA, vulnerabilities, MITRE module, inventory, quản lý rule/decoder...) [[11]](#ref11). WQL đơn giản hơn SPL nhiều: nó là cú pháp lọc (field=value, kết hợp bằng `and`/`or`), không có chuỗi lệnh `|` nối tiếp để biến đổi dữ liệu như SPL (`stats`, `eval`, `transaction`...). Muốn phân tích sâu hơn lọc đơn giản, Wazuh dựa vào giao diện trực quan hóa của OpenSearch Dashboards hoặc truy vấn trực tiếp Query DSL của OpenSearch — đòi hỏi biết thêm công cụ khác ngoài Wazuh.

Điểm mạnh riêng: module **MITRE ATT&CK tích hợp sẵn** trên dashboard — ánh xạ TTP vào sự kiện phát hiện, miễn là rule có khai báo mã MITRE, tự động gắn tactic/technique vào alert, có tab Intelligence (tra cứu nhóm tấn công) và Framework (nhìn toàn cảnh TTP đã xuất hiện trong hạ tầng) [[12]](#ref12)[[13]](#ref13). Đây là tính năng có sẵn miễn phí, trong khi ở Splunk muốn có cái tương đương (Enterprise Security với notable events/risk-based) phải trả phí.

### 1.5 Chi phí

Phần lõi Wazuh **hoàn toàn miễn phí, mã nguồn mở** — không có phí license cho nền tảng, khác biệt lớn nhất với Splunk Enterprise. Một nguồn so sánh thương mại ghi nhận chi phí doanh nghiệp trung bình cho Splunk Enterprise Security khoảng 500 nghìn đến 2 triệu USD mỗi năm [[14]](#ref14). Có 2 lựa chọn trả phí không bắt buộc cho Wazuh: **Wazuh Cloud** (bản SaaS được quản lý sẵn, giá công bố theo quy mô — gói nhỏ khoảng 571 USD/tháng, gói vừa khoảng 923 USD/tháng, gói lớn khoảng 1.449 USD/tháng) [[15]](#ref15) và **hỗ trợ kỹ thuật trả phí** cho bản tự host (một người dùng ghi nhận mua hỗ trợ khoảng 1.000 USD/năm) [[16]](#ref16).

Điểm cần phân biệt rõ: "miễn phí" chỉ đúng với phí license. Chi phí thật của một triển khai Wazuh tự host vẫn gồm hạ tầng (máy chủ cho manager, cụm indexer OpenSearch vốn khá nặng tài nguyên, dashboard) và nhân lực vận hành/viết luật — một người dùng có kinh nghiệm thực tế ghi nhận "có thể miễn phí để sở hữu, nhưng tốn nhiều thời gian và công sức để đưa nó tới trạng thái dùng được" [[16]](#ref16).

### 1.6 Độ khó triển khai

Các đánh giá độc lập liệt kê điểm yếu của Wazuh gồm: cấu hình phức tạp, đường cong học tập dốc, tốn tài nguyên, tài liệu còn thiếu ở một số chỗ [[17]](#ref17). So với Splunk (một gói cài đặt, giao diện cấu hình trực quan nhiều, UF nhẹ và đơn giản), Wazuh đòi hỏi: dựng đủ 3 thành phần (hoặc chọn all-in-one), cài agent trên từng máy (hoặc cấu hình agentless cho thiết bị không cài được agent, như firewall trong lab của nhóm), và **tự viết decoder + rule XML bằng tay** cho mọi loại log không có sẵn trong ruleset mặc định [[6]](#ref6) — gần giống việc nhóm đã phải tự viết `props.conf`, `eventtypes.conf`, `tags.conf` cho log DVWA và firewall trong Splunk, chỉ khác là Wazuh làm việc đó qua rule/decoder XML thay vì field extraction và CIM.

## 2. Bảng so sánh Splunk Enterprise và Wazuh

| Tiêu chí | Splunk Enterprise | Wazuh |
| --- | --- | --- |
| **Kiến trúc** | Một vai trò `splunkd` gộp chung nhận, lưu, tìm kiếm (lab dùng standalone); Universal Forwarder là đại lý nhẹ chỉ đọc và chuyển log | 4 thành phần tách rời: agent, manager (xử lý luật), indexer (dựa trên cụm OpenSearch, lưu trữ/tìm kiếm), dashboard (dựa trên OpenSearch Dashboards); có thể gộp tất cả vào 1 máy (all-in-one) hoặc tách thành cụm |
| **Thu thập dữ liệu** | Universal Forwarder đọc file theo cấu hình `inputs.conf`, chỉ chuyển tiếp, không phân tích tại nguồn | Agent làm nhiều việc ngay tại endpoint: thu log, FIM, rootcheck, đánh giá cấu hình (SCA), dò lỗ hổng, phản hồi chủ động; có hỗ trợ agentless (syslog) cho thiết bị như firewall |
| **Ngôn ngữ truy vấn / phát hiện** | SPL: ngôn ngữ pipe mạnh (`stats`, `eval`, `transaction`, `rex`...), một ngôn ngữ cho cả tìm kiếm, phát hiện, dashboard, report | Phát hiện viết bằng rule/decoder XML khai báo tĩnh (`<frequency>`, `<if_sid>`, `<match>`); tìm kiếm tự do dùng WQL (chỉ lọc field, không có chuỗi biến đổi dữ liệu như SPL) kết hợp Discover của OpenSearch Dashboards |
| **Phát hiện và threat hunting** | Alert dựa trên saved search chạy theo lịch hoặc real-time; threat hunting là chạy SPL thủ công, tự liên kết log bằng `transaction`/`join`; muốn có notable events/MITRE tích hợp phải mua Enterprise Security | Rule tự kích hoạt gần thời gian thực ngay khi log tới manager (không cần đợi lịch); có sẵn module MITRE ATT&CK miễn phí, tự gắn tactic/technique vào alert nếu rule khai báo mã MITRE; hunting qua Discover để đối chiếu IOC và liên kết nhiều luồng dữ liệu (sự kiện, inventory, lỗ hổng) |
| **Chi phí** | Tính phí theo dung lượng dữ liệu nạp mỗi ngày (GB/day); chi phí doanh nghiệp trung bình được ghi nhận khoảng 500 nghìn đến 2 triệu USD/năm; bản Free giới hạn 500 MB/ngày | Phần lõi miễn phí, mã nguồn mở, không giới hạn dung lượng theo license; có tùy chọn trả phí: Wazuh Cloud (SaaS quản lý sẵn, từ khoảng 571 USD/tháng) hoặc hỗ trợ kỹ thuật cho bản tự host (khoảng 1.000 USD/năm theo một ghi nhận) |
| **Khả năng mở rộng** | Mở rộng bằng kiến trúc phân tán của Splunk (indexer cluster, search head cluster), SmartStore để đẩy dữ liệu ít dùng ra kho đối tượng từ xa; lab hiện tại chỉ chạy standalone nên chưa thấy hết | Mở rộng bằng cụm indexer OpenSearch và cụm manager (multi-node); vì indexer là OpenSearch nên thừa hưởng khả năng mở rộng ngang của OpenSearch, nhưng cụm OpenSearch vốn nổi tiếng tốn tài nguyên (RAM, heap) hơn so với mở rộng Splunk |
| **Độ khó triển khai** | Cài một gói, giao diện cấu hình trực quan cho phần lớn tác vụ (lookup, alert, dashboard); phần khó nằm ở việc hiểu field/CIM, không nằm ở việc dựng hạ tầng | Đánh giá độc lập ghi nhận: cấu hình phức tạp, đường cong học tập dốc, tốn tài nguyên hơn, một số chỗ tài liệu còn thiếu; phải tự viết decoder/rule XML cho mọi log không có sẵn trong ruleset mặc định (ví dụ log DVWA, log firewall tùy biến của nhóm) |


## Tài liệu tham khảo

<a id="ref1"></a>1. Wazuh — *Architecture*. https://documentation.wazuh.com/current/getting-started/architecture.html

<a id="ref2"></a>2. Wazuh — *Components*. https://documentation.wazuh.com/5.0-beta/getting-started/components/index.html

<a id="ref3"></a>3. Wazuh — *Architecture* (bản 5.0-rc, mô tả 3 kiểu triển khai). https://documentation.wazuh.com/5.0-rc/getting-started/architecture.html

<a id="ref4"></a>4. Wazuh manager — *Architecture*. https://documentation.wazuh.com/5.0-rc/getting-started/components/wazuh-manager.html

<a id="ref5"></a>5. Wazuh — *Use cases* (danh mục use case của ruleset). https://documentation.wazuh.com/current/user-manual/ruleset/ruleset-xml-syntax/index.html

<a id="ref6"></a>6. Wazuh — *Custom rules and decoders* (bản 4.6). https://documentation.wazuh.com/4.6/user-manual/ruleset/custom.html

<a id="ref7"></a>7. Wazuh — *Custom rules and decoders* (bản 4.0, ví dụ decoder/rule). https://documentation.wazuh.com/4.0/user-manual/ruleset/custom.html

<a id="ref8"></a>8. Wazuh — *Custom rules and decoders* (bản 4.2, minh họa `wazuh-logtest`). https://documentation.wazuh.com/4.2/user-manual/ruleset/custom.html

<a id="ref9"></a>9. Wazuh — *Enhancing detection with MITRE ATT&CK framework* (bản 4.4). https://documentation.wazuh.com/4.4/user-manual/ruleset/mitre.html

<a id="ref10"></a>10. Wazuh — *Threat hunting* (bản 5.0-rc). https://documentation.wazuh.com/5.0-rc/getting-started/use-cases/threat-hunting.html

<a id="ref11"></a>11. Wazuh — *Filtering security data with the Wazuh Query Language*. https://wazuh.com/blog/filtering-security-data-with-the-wazuh-query-language/

<a id="ref12"></a>12. Wazuh — *MITRE ATT&CK framework*. https://documentation.wazuh.com/current/user-manual/ruleset/mitre.html

<a id="ref13"></a>13. Wazuh — *Threat hunting* (bản 4.14). https://documentation.wazuh.com/4.14/getting-started/use-cases/threat-hunting.html

<a id="ref14"></a>14. PeerSpot — *Splunk vs Wazuh*. https://www.peerspot.com/products/comparisons/splunk_vs_wazuh

<a id="ref15"></a>15. TrustRadius — *Splunk Enterprise vs. Wazuh*. https://www.trustradius.com/compare-products/splunk-enterprise-vs-wazuh

<a id="ref16"></a>16. PeerSpot — *What is your experience regarding pricing and costs for Wazuh?*. https://www.ITCentralStation.com/questions/what-is-your-experience-regarding-pricing-and-costs-for-wazuh

<a id="ref17"></a>17. ToolRadar — *Wazuh*. https://toolradar.com/tools/wazuh