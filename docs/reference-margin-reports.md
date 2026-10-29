# Báo cáo giá vốn và lãi tham chiếu

Module Flutter riêng tại `lib/features/reference_margin_reports`, đồng bộ theo
`reference-margin-report-api.md` và `report-fe-sync.md` của backend. Không thay đổi
REST, cơ sở dữ liệu hoặc nghiệp vụ thanh toán/hoàn tất đơn.

## Cấu trúc và luồng dữ liệu

- `domain`: entity, filter, repository contract và ba use case; không phụ thuộc
  Flutter, Riverpod hoặc Dio. Dùng lại value object tiền/ngày thuần Dart của reports.
- `data`: `ReferenceMarginRemoteDataSource` gọi ba GET; `ReferenceMarginDto` đọc
  JSON chính xác và kiểm tra contract; repository implementation ánh xạ lỗi.
- `presentation`: provider ghép dependency và quản lý scope/vòng đời;
  `ReferenceMarginReportsController` quản lý query, race, refresh và pagination;
  screen/widgets hiển thị state, không gọi Dio.

Luồng đọc: sidebar/route → capability guard → screen → controller → use case →
repository → authenticated Dio → DTO → Result → panel giao diện.
Module mới không mở rộng repository/controller báo cáo doanh thu thường.

## Điều hướng và quyền

- Sidebar: **BÁO CÁO → Giá vốn & lãi tham chiếu**.
- Route: `/app/reference-margin`.
- Sidebar ID: `reference-margin-reports`.
- Capability: `AccessPolicy.canViewReferenceMarginReports`.

Phải có tenant hợp lệ, subscription đang active, cả hai permission `ORDER_VIEW`,
`REPORT_DETAIL_VIEW` và cả hai feature `ORDER_MANAGEMENT`, `DETAIL_REPORT`.
Không yêu cầu quyền kho, công thức, menu, thanh toán hoặc doanh thu ngày.
Sidebar, deep link, màn hình và controller đều kiểm tra capability trước khi GET.

Không kiểm tra tên gói BASIC/PRO hoặc package ID. Backend hiện chưa có feature
riêng cho báo cáo lãi: hai gói cùng cấp các feature trên được sử dụng như nhau khi
người dùng đủ quyền. Muốn giới hạn riêng một gói khác cần contract entitlement từ
backend phân biệt được gói đó; frontend không tự tạo feature hoặc quyền mới.

CASHIER đủ capability có thể vào route báo cáo mới. Các chức năng vận hành cũ của
CASHIER vẫn giữ policy hiện có. Guard báo cáo ngày/chi tiết thường không bị thêm
điều kiện `ORDER_*`; báo cáo mới không dùng chung controller hoặc state với chúng.

## Ba API chỉ đọc

| API | Dữ liệu |
| --- | --- |
| `GET /api/v1/reports/reference-margin/summary` | Tổng quan hai phạm vi đơn |
| `GET /api/v1/reports/reference-margin/series` | Chuỗi ngày/tháng, có bucket rỗng |
| `GET /api/v1/reports/reference-margin/orders` | Đơn đối chiếu có phân trang |

Authenticated Dio tự gắn JWT. Request có `Accept: application/json` và không có
body, tenant ID, expectedVersion hay Idempotency-Key. Không gọi từ public QR/KDS.

Query chung gồm `fromDate`, `toDate` (ngày lịch, hai đầu được tính, tối đa 366 ngày),
currency, service type và root source channel. Series thêm `granularity=DAY|MONTH`;
orders thêm `costCoverage=ALL|COMPLETE|EXCLUDED`, page, size, sort và direction.

Series dùng metric phẳng cùng cấp `bucketStartDate` vì backend `JsonUnwrapped`.
Tháng đầu có thể bắt đầu trước fromDate ở ngày 1 của tháng; metric vẫn do server
giới hạn theo khoảng ngày yêu cầu. Orders dùng `data.content/page/size/totalElements/totalPages`.
Giữ thứ tự server trả về, kể cả các giá trị null được đặt cuối khi sort.

## Phạm vi và cách đọc số liệu

**Toàn bộ đơn hoàn tất** hiển thị số đơn và doanh số thuần của mọi đơn trong kỳ.
**Các đơn đủ giá vốn** chỉ gồm đơn có đầy đủ giá vốn của mọi dòng được xét.

Các field không có tiền tố `covered` thuộc toàn bộ đơn. Các field `covered*` thuộc
tập đủ giá vốn. Không lấy doanh số toàn bộ đơn làm mẫu số của lãi trong tập covered.

- `salesAmount = subtotalAmount - discountAmount + taxAmount + serviceChargeAmount`.
- `netSalesAmount = subtotalAmount - discountAmount`.
- `coveredReferenceMarginAmount = coveredNetSalesAmount - coveredReferenceCostAmount`.

Ví dụ 10 đơn có doanh số thuần 1.000.000 VND nhưng chỉ 8 đơn đủ giá: doanh số đủ giá
800.000 VND, giá vốn 300.000 VND, lãi tham chiếu 500.000 VND và tỷ lệ 62,50%.
Hai đơn còn lại vẫn đóng góp doanh số tổng, nhưng không được giả có giá vốn 0.

Tất cả metric và tỷ lệ lấy từ backend. Không tính trung bình tỷ lệ bucket, không
tính lại tổng từ trang đơn hiện tại. Lãi âm hợp lệ; mẫu số không dương có tỷ lệ null.

Nguồn giá là `CATALOG_REFERENCE_AT_ACCEPTANCE`: snapshot tại lúc nhận món. Không
gọi recipe cost-estimate hoặc lấy giá catalogue hiện tại để tính lại đơn lịch sử.
Thay giá hôm nay không bổ sung hoặc thay snapshot cũ qua màn báo cáo.

Đây là **lãi tham chiếu**, không phải lợi nhuận ròng hoặc actual COGS. Giao diện
giải thích phạm vi chưa gồm đầy đủ hao hụt, hoàn tiền và chi phí vận hành.

## Coverage, unknown và zero

| Trạng thái | Ý nghĩa |
| --- | --- |
| COMPLETE | Tất cả đơn trong tập có đủ giá vốn |
| PARTIAL | Có cả đơn đủ và đơn thiếu giá vốn |
| UNAVAILABLE | Có đơn nhưng không đơn nào đủ giá vốn |
| NO_DATA | Không có đơn trong kỳ |

Các issue `INCOMPLETE`, `UNAVAILABLE`, `LEGACY_UNAVAILABLE`, `NO_ELIGIBLE_ITEMS`
được giải thích bằng tiếng Việt. Một đơn có thể có nhiều issue, nên số đơn bị loại
lấy từ `excludedOrderCount`, không cộng các issue count.

Giá 0 đã cấu hình vẫn hợp lệ. Đơn bị loại giữ `referenceCostAmount`,
`referenceMarginAmount`, `referenceMarginPercent` null; UI hiển thị chưa xác định
hoặc không áp dụng. Không có đơn đủ giá thì covered sums bằng 0 cho tập rỗng,
nhưng tỷ lệ vẫn null và thông tin thiếu giá vẫn được hiển thị.

DTO mới không dùng hành vi `ReportMoney.parse(null) → 0` của module cũ. Response
được decode bằng `decodeExactJson` trước khi chuyển decimal sang BigInt cents;
numeric token không hợp lệ, field bắt buộc bị thiếu hoặc metadata lệch query trở
thành lỗi dữ liệu. Chỉ chuyển double trong bước vẽ chart.

## State và bảo vệ dữ liệu

- Provider autoDispose, state trong RAM; không lưu báo cáo xuống local database.
- Draft filter và applied filter riêng. Đổi query xóa dữ liệu cũ trước khi đổi nhãn.
- Query identity có endpoint, ngày, currency, dịch vụ, nguồn và các tham số riêng
  của endpoint. Scope có user/tenant/quyền/feature/subscription; không có token.
- Token rotation giữ scope; logout, đổi tenant hoặc authority thay đổi làm mất
  reader cũ và chặn response đến muộn.
- Summary, series và orders có loading/error/retry độc lập. Orders chỉ GET sau
  khi mở tab hoặc chọn xem các đơn thiếu giá vốn.
- Refresh cùng query có thể giữ kết quả cũ với nhãn rõ. Mỗi panel dùng metadata
  của chính response; không đổi nhãn tiền tệ cho số liệu của query khác.
- 403 trong cùng authority scope có hiệu lực với toàn capability, kể cả request
  thuộc query cũ: xóa mọi panel và đóng/scrub dialog chi tiết. Revalidate tự động
  có giới hạn; thử lại quyền do người dùng chủ động, không vòng GET vô hạn.
- Dialog chi tiết giữ captured scope, kiểm tra quyền và server-denied state,
  không để dữ liệu còn hiển thị sau khi màn hình nền mất quyền.

OrderEvents hiện có được dùng làm tín hiệu đối soát sau nghiệp vụ. Reader đang
mở và còn quyền gộp các tín hiệu gần nhau thành một lần refresh. Khi bị che hoặc
app ở nền không gọi GET; khi hiện lại sẽ đối soát. Reader chưa được tạo không có
subscription ngầm. Không thêm polling, socket hoặc event backend mới.

## Giao diện và thời gian

Màn hình riêng có hai tab: **Tổng quan** (KPI, coverage, biểu đồ/bảng chuỗi) và
**Đơn đối chiếu** (filter/sort/phân trang, card mobile, bảng desktop, dialog chi tiết).
Không gọi GET từng đơn để dựng danh sách hoặc dialog.

Ngày query giữ nguyên `yyyy-MM-dd`. Backend nhóm theo completedAt trong timezone
nhà hàng. UI hiển thị `meta.timezone`, currency, khoảng đang hiển thị và generatedAt.
Timestamp dùng IANA timezone của response, không lấy timezone của máy. Thêm
`timezone: 0.10.1` tương thích Dart SDK hiện tại; formatter dùng database all để
hỗ trợ alias và DST. Nếu tên zone không được nhận diện, timestamp được ghi rõ UTC.

Responsive ở 320/600/800/1200 px, text 200% và bàn phím. Chỉ bảng rộng cuộn ngang;
chart có tooltip và bảng thay thế. Màu sắc đi kèm nhãn trạng thái.

## Lỗi và retry

400 giữ bộ lọc để sửa. 401 dùng pipeline auth/refresh có sẵn. 403 là quyết định
cuối cùng của backend, không suy quyền từ tên gói. Lỗi mạng/5xx có retry thủ công.

`INVALID_REPORT_TIMEZONE` và `REPORT_COST_DATA_CONFLICT` là lỗi có thể đối soát rồi
thử lại; không hiển thị thành báo cáo zero hoặc NO_DATA. FE không sửa snapshot,
không tạo chứng từ hay stock adjustment để chữa lỗi báo cáo.

## Kiểm thử thủ công

1. Tài khoản đủ hai quyền/hai feature mở đúng sidebar và deep link độc lập.
2. Bỏ lần lượt mỗi quyền/feature hoặc hết hạn gói: sidebar ẩn, deep link chặn, không GET.
3. CASHIER đủ capability vào được báo cáo mới; không tự mở các màn vận hành cũ.
4. Áp dụng ngày/currency/dịch vụ/nguồn; nhãn và số tiền luôn thuộc đúng response.
5. Xem đủ bốn coverage, giá 0, lãi âm, null percentage và các issue chồng nhau.
6. Mở tab đơn: chỉ lúc đó GET orders; thử lọc thiếu giá, sort, trang và kích thước trang.
7. Mở dialog, đổi quyền/gói/logout hoặc gây 403 muộn: dữ liệu riêng phải biến mất.
8. Thanh toán/hoàn tất ở luồng khác; quay lại reader để kiểm tra refresh có kiểm soát.
9. Gây lỗi riêng series/orders, retry; phần khác không bị thay bằng zero.
10. Thử text 200%, bàn phím, tên/mã/tiền dài, DST và timezone khác máy.

## Kiểm tra tự động

Kết quả ngày 28/10/2026:

| Kiểm tra | Kết quả |
| --- | --- |
| Dart format các file Dart thêm/sửa của chức năng | Đã chạy |
| `flutter analyze --no-pub` | Không có lỗi/cảnh báo |
| Feature mới và reports/auth/sidebar/router liên quan | 167 test đạt |
| Trong đó feature mới | 77 test đạt: data 21, access 7, navigation 7, controller 29, widget/formatter 13 |
| Toàn bộ `flutter test --no-pub --reporter expanded` | 1.147 đạt, 6 lỗi có sẵn được đối chiếu bên dưới |

Test feature bao phủ số tiền chính xác, null/zero/lãi âm, metric phẳng, PageResponse,
metadata/query identity, quyền/entitlement, token rotation, response đến muộn,
403/409, refresh sau nghiệp vụ, dialog nhạy cảm và responsive/text 200%.
Các kiểm thử tích hợp dùng client/router thật cùng response API giả lập;
phần kiểm thử thủ công ở trên dùng tài khoản và dữ liệu nhà hàng thực tế.

### Bằng chứng lỗi có sẵn

Đã xuất riêng mã đầu phiên tại commit
`dbbf1e6ebac17be21784f348690953dd3728e34b` và chạy lại hai file test lỗi
trong `.dart_tool/reference_margin_baseline_dbbf1e6`, không đổi checkout hiện tại.
Dùng cùng SDK/dependency đã resolve và asset cấu hình từ `.env.example`.
Kết quả bản đầu phiên: **26 đạt, 6 lỗi**. Đối chiếu tên file + tên test cho thấy
tập 6 lỗi khớp chính xác với lần chạy toàn dự án hiện tại:

- `test/features/order/order_widget_test.dart`: `append popup is usable at 320px
  with keyboard and large text` — tràn ngang 18 px.
- `test/features/qr_order/qr_request_widget_test.dart`: ba test tìm nút/widget cũ
  (`QR additions are separate from bill, require review and explicit confirmation`,
  `QR approval unavailable without grants but rejection remains usable with reason`,
  `timeout prevents closing or reapproving until exact request readback`).
- Cùng file QR: hai test `QR card, inbox and review fit 320.0 px at text200 and
  with keyboard` và `QR card, inbox and review fit 800.0 px at text200 and with
  keyboard` — lỗi bố cục/tìm widget.

Log trong workspace: `.reference-margin-targeted-tests.log`,
`.reference-margin-analyze.log`, `.reference-margin-full-tests.log` và
`.reference-margin-baseline-tests.log`. Không bỏ qua test, giảm assertion hoặc
cập nhật golden để che lỗi. Chức năng báo cáo mới không sửa các màn QR/gọi thêm món.
