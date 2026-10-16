# Tài liệu Module Thống kê Doanh thu & Báo cáo (Revenue Reports)

Module Báo cáo Doanh thu trên ứng dụng Flutter POS SaaS được triển khai theo kiến trúc Clean Architecture, kết nối trực tiếp với 6 API báo cáo của backend `pos-saas-be` và tuân thủ chặt chẽ các quy định về phân quyền, timezone lịch nhà hàng, định dạng tiền tệ chính xác (BigInt/2-decimal fixed precision), cũng như nguyên tắc `Cache-Control: no-store`.

---

## 1. Điểm mở màn hình & Điều hướng

Ứng dụng cung cấp hai màn hình độc lập tương ứng với hai phạm vi báo cáo:

| Màn hình | Route | Sidebar Item | Quyền yêu cầu | Feature yêu cầu | Ghi chú |
|---|---|---|---|---|---|
| **Doanh thu ngày** | `/app/daily-revenue` | `daily-revenue` (Doanh thu ngày) | `REPORT_DAILY_VIEW` | `DAILY_REVENUE` | Xem tình hình thu tiền & doanh số của 1 ngày (mặc định hôm nay). |
| **Báo cáo doanh thu** | `/app/reports` | `reports` (Báo cáo) | `REPORT_DETAIL_VIEW` | `DETAIL_REPORT` | Xem báo cáo khoảng ngày (tối đa 366 ngày) với 3 tab: Tổng quan, Món bán chạy, Đơn đối chiếu. |

- **AppShell & Sidebar**: Được tích hợp tự động lọc theo `AccessPolicy.canDailyReport` và `AccessPolicy.canDetailReport`. Nếu tài khoản chỉ có quyền `REPORT_DETAIL_VIEW` + `DETAIL_REPORT` (hoặc chỉ có `REPORT_DAILY_VIEW` + `DAILY_REVENUE`), người dùng vẫn có thể đăng nhập vào `appHome` và sidebar hiển thị đúng mục được phép.
- **Không tự cấp quyền chéo**: Có quyền Doanh thu ngày không tự được xem Báo cáo chi tiết và ngược lại. Không yêu cầu các quyền `ORDER_VIEW`, `PAYMENT_VIEW` hay `MENU_VIEW` để xem báo cáo.

---

## 2. Danh sách 6 API Report & Contract

Tất cả các endpoint đều là `GET`, gửi kèm `Authorization: Bearer <accessToken>`, `Accept: application/json`, không có request body, không gửi `restaurantId` (backend trích xuất tenant từ JWT), phản hồi với header `Cache-Control: no-store`.

```json
{
  "meta": {
    "fromDate": "2026-10-01",
    "toDate": "2026-10-15",
    "timezone": "Asia/Ho_Chi_Minh",
    "currencyCode": "VND",
    "generatedAt": "2026-10-15T10:30:00Z",
    "serviceType": null,
    "sourceChannel": null,
    "granularity": "DAY",
    "dateBasis": "CREATED"
  },
  "data": { ... }
}
```

### A. `GET /api/v1/reports/daily`
- **Quyền**: `REPORT_DAILY_VIEW` + `DAILY_REVENUE`
- **Tham số**: `date` (optional, `yyyy-MM-dd`), `currencyCode`, `serviceType`, `sourceChannel`. Khi bỏ trống `date`, server tự lấy hôm nay theo timezone nhà hàng.
- **Data**: Object chứa 2 phần: `collections` (tiền thu) và `orders` (phân tích đơn).

### B. `GET /api/v1/reports/summary`
- **Quyền**: `REPORT_DETAIL_VIEW` + `DETAIL_REPORT`
- **Tham số**: `fromDate`, `toDate` (bắt buộc, `yyyy-MM-dd`), `currencyCode`, `serviceType`, `sourceChannel`.
- **Data**: Tương tự `/daily` nhưng tổng hợp cho cả khoảng ngày.

### C. `GET /api/v1/reports/revenue-series`
- **Quyền**: `REPORT_DETAIL_VIEW` + `DETAIL_REPORT`
- **Tham số**: `fromDate`, `toDate` (bắt buộc), `granularity` (`DAY` hoặc `MONTH`, mặc định `DAY`), `currencyCode`, `serviceType`, `sourceChannel`.
- **Data**: Danh sách các bucket `SeriesPoint` (`bucketStartDate`, `collectedAmount`, `completedOrderSalesAmount`, `successfulPaymentCount`, `completedOrderCount`).
- *Lưu ý về MONTH*: `bucketStartDate` là ngày đầu tháng, có thể trước `fromDate`. Tháng đầu/cuối chỉ chứa số tiền phát sinh trong các ngày được chọn.

### D. `GET /api/v1/reports/payment-methods`
- **Quyền**: `REPORT_DETAIL_VIEW` + `DETAIL_REPORT`
- **Tham số**: `fromDate`, `toDate` (bắt buộc), `currencyCode`, `serviceType`, `sourceChannel`.
- **Data**: Danh sách phân bổ theo phương thức `CASH` và `TRANSFER` (`collectedAmount`, `successfulPaymentCount`, `percentage`).
- *Lưu ý*: `percentage` do server tính theo số tiền đã thu, không ép cộng dồn làm sai số gốc.

### E. `GET /api/v1/reports/top-items`
- **Quyền**: `REPORT_DETAIL_VIEW` + `DETAIL_REPORT`
- **Tham số**: `fromDate`, `toDate` (bắt buộc), `page` (>= 0), `size` (1–100, mặc định 20), `sortBy` (`quantity` hoặc `itemSalesAmount`), `direction` (`asc` hoặc `desc`, mặc định `desc`), các bộ lọc chung.
- **Data**: Spring `Page<TopItem>` (`itemId`, `itemName`, `unit`, `quantity`, `itemSalesAmount`, `completedOrderCount`).
- *Lưu ý*: `itemId` có thể null (món đã xóa). Dữ liệu là snapshot lịch sử, không gọi API menu để lấy thông tin món hiện tại.

### F. `GET /api/v1/reports/orders`
- **Quyền**: `REPORT_DETAIL_VIEW` + `DETAIL_REPORT` (không yêu cầu `ORDER_VIEW`).
- **Tham số**: `fromDate`, `toDate` (bắt buộc), `dateBasis` (`CREATED`, `COMPLETED`, `CANCELLED`, `PAID`, mặc định `CREATED`), `status`, `paymentStatus`, `sortBy` (`reportEventAt` hoặc `totalAmount`), `direction`, `page`, `size`, các bộ lọc chung.
- **Data**: Spring `Page<ReportOrder>` (`id`, `orderCode`, `serviceType`, `sourceChannel`, `status`, `paymentStatus`, `currencyCode`, `totalAmount`, `collectedAmountInRange`, `createdAt`, `completedAt`, `cancelledAt`, `reportEventAt`).
- *Lưu ý*: Với `dateBasis=PAID`, `reportEventAt` là thời điểm thanh toán thành công mới nhất trong khoảng. Nút "Xem chi tiết" chỉ hiển thị khi tài khoản có quyền `ORDER_VIEW` + `ORDER_MANAGEMENT`.

---

## 3. Ý nghĩa Số liệu (Tránh ngộ nhận & gộp nhầm)

1. **`collectedAmount` — "Tiền đã thu"**:
   - Tổng tiền thực tế từ các giao dịch thanh toán thành công (`payment.status == SUCCESS`) dựa theo thời điểm thu (`paidAt`) nằm trong khoảng thời gian báo cáo.
2. **`completedOrderSalesAmount` — "Doanh số đơn hoàn tất"**:
   - Tổng giá trị hóa đơn của các đơn hàng có trạng thái `COMPLETED` dựa theo thời điểm hoàn tất đơn (`completedAt`) nằm trong khoảng thời gian báo cáo.
   - *Lưu ý quan trọng*: Tiền đã thu và Doanh số đơn hoàn tất KHÔNG nhất thiết phải bằng nhau (ví dụ: đơn đặt trước đã thu tiền nhưng chưa hoàn tất, hoặc đơn hoàn tất thanh toán công nợ/kỳ khác).
3. **`successfulPaymentCount` — "Giao dịch thành công"**:
   - Số lượng transaction thanh toán thành công, không phải số lượng đơn hàng.
4. **`paidOrderCount` — "Đơn có phát sinh thu tiền"**:
   - Số đơn hàng có ít nhất một giao dịch thanh toán thành công trong kỳ (có thể thanh toán 1 phần hoặc toàn phần).
5. **`averageCompletedOrderValue` — "Giá trị TB / đơn hoàn tất"**:
   - Hiển thị trực tiếp giá trị server tính toán (`completedOrderSalesAmount / completedOrderCount`).
6. **`createdOrderCount`, `completedOrderCount`, `cancelledOrderCount`**:
   - Dựa trên 3 mốc thời gian độc lập (`createdAt`, `completedAt`, `cancelledAt`). Không tự chia làm tỷ lệ phần trăm giữa các tập đơn này.
7. **Cấu thành đơn hoàn tất**:
   - Phân rã: Tiền hàng (`completedSubtotalAmount`), Giảm giá (`completedDiscountAmount`), Thuế VAT (`completedTaxAmount`), Phí dịch vụ (`completedServiceChargeAmount`).
8. **`itemSalesAmount`**:
   - Doanh số bán ra của món trong các đơn hoàn tất; không phải lợi nhuận (chưa trừ chi phí vốn) và không phân bổ giảm giá/thuế cấp hóa đơn xuống từng dòng món.

---

## 4. Xử lý Ngày, Timezone & Tiền tệ

- **Lịch theo Timezone nhà hàng**: Ngày lọc `fromDate`, `toDate`, `date` là ngày lịch `yyyy-MM-dd`. Client không dùng `DateTime.toUtc()` hay `.toLocal()` làm lệch ngày lịch. Sau khi nhận response, ngày và timezone hiển thị ưu tiên theo `meta.timezone`.
- **Giới hạn 366 ngày**: Pre-request validation kiểm tra tính hợp lệ của ngày, đảm bảo `fromDate <= toDate` và `toDate - fromDate + 1 <= 366`. Nếu vi phạm, app hiển thị thông báo lỗi ngay trên UI thay vì gửi request sai lên server.
- **Tiền tệ chính xác (`ReportMoney`)**:
  - Lưu trữ dưới dạng đơn vị minor unit (cent/xu: 2 chữ số thập phân) sử dụng kiểu dữ liệu `BigInt`.
  - Không sử dụng `double` trong các phép tính toán tài chính để loại bỏ hoàn toàn sai số dấu phẩy động IEEE 754.
  - Hỗ trợ định dạng chuẩn tiền tệ Việt Nam (vi-VN) có dấu phân cách hàng nghìn và mã tiền tệ đi kèm (VD: `1.500.000 VND`).
  - Hỗ trợ hiển thị rút gọn an toàn cho trục biểu đồ (VD: `1.5M`, `250K`).
- **Số lượng món (`quantity`)**: Cho phép số thập phân (tối đa 3 chữ số thập phân, VD: `1.25 kg`), không ép thành kiểu `int`.

---

## 5. Kiến trúc & Quản lý State

- **Clean Architecture 3 lớp**:
  - `domain/`: Value Objects (`ReportDate`, `ReportMoney`, `ReportEnums`), Entities (`ReportMeta`, `ReportEnvelope`, `ReportOverview`, `RevenueSeriesPoint`, `PaymentMethodReportRow`, `TopItemReportRow`, `ReportOrderRow`, `ReportPage`, `ReportFilters`), Repositories interfaces, Use Cases. Không phụ thuộc vào Flutter UI hay Dio.
  - `data/`: DTOs (`ReportDto`), Data Source (`ReportRemoteDataSource` gọi Dio có auth), Repository Impl (`ReportRepositoryImpl` bọc Result/Failure và ApiErrorMapper).
  - `presentation/`:
    - Controllers: Tách riêng 4 ChangeNotifier Controllers chuyên biệt:
      - `DailyReportController`: Quản lý báo cáo ngày.
      - `ReportSummaryController`: Quản lý song song 3 panel (Tổng quan, Series biểu đồ, Phân bổ thanh toán). Hỗ trợ retry độc lập từng panel mà không hủy dữ liệu các panel khác.
      - `TopItemsReportController`: Quản lý danh sách món bán chạy, phân trang server và sort.
      - `ReportOrdersController`: Quản lý danh sách đơn đối chiếu, chọn `dateBasis`, bộ lọc trạng thái và phân trang server.
    - Providers: Quản lý vòng đời với Riverpod, theo dõi `reportScopeProvider` (tự động dọn dẹp state khi đổi người dùng, tenant, quyền).
- **Bộ lọc Draft / Applied**:
  - Người dùng thay đổi bộ lọc trên giao diện sẽ lưu vào trạng thái Draft. Chỉ khi nhấn nút "Áp dụng", controller mới chốt applied filter và kích hoạt gọi API. Tránh gọi request liên tục khi chọn từng mục filter.
- **Biểu đồ doanh thu tùy biến (`RevenueSeriesChart`)**:
  - Dựng bằng CustomPainter chuyên biệt, hỗ trợ hiển thị đồng thời hoặc ẩn/hiện từng chuỗi ("Tiền đã thu" / "Doanh số đơn hoàn tất").
  - Xử lý mượt mà và an toàn khi toàn bộ giá trị bằng 0 (không chia cho 0, không crash layout).
  - Tích hợp tooltip chạm/hover hiển thị đầy đủ số tiền, ngày và số giao dịch/đơn.
  - Tích hợp nút chuyển đổi xem dạng Bảng số liệu chi tiết.

---

## 6. Xử lý Lỗi & Thông báo Người dùng

Tích hợp trực tiếp vào `ApiErrorMapper` với thông báo tiếng Việt rõ ràng, thân thiện:
- `INVALID_REPORT_DATE_RANGE`: "Khoảng ngày báo cáo không hợp lệ."
- `REPORT_RANGE_TOO_LARGE`: "Khoảng ngày báo cáo vượt quá giới hạn cho phép (tối đa 366 ngày)."
- `INVALID_REPORT_CURRENCY`: "Mã tiền tệ báo cáo không hợp lệ."
- `INVALID_REPORT_SORT`: "Tiêu chí sắp xếp báo cáo không hợp lệ."
- `INVALID_REPORT_TIMEZONE`: "Cấu hình múi giờ của nhà hàng không hợp lệ. Vui lòng liên hệ quản lý."
- `UNAUTHORIZED`: Tự động kích hoạt cơ chế refresh token của Dio Interceptor.
- `FORBIDDEN` / `TENANT_ACCESS_DENIED` / `FEATURE_NOT_ENTITLED` / `SUBSCRIPTION_NOT_ACTIVE`: Hiển thị thông báo quyền tương ứng.

---

## 7. Kịch bản Kiểm thử Thủ công (Manual Test Scenarios)

1. **Kiểm tra phân quyền màn hình**:
   - Đăng nhập tài khoản chỉ có `REPORT_DAILY_VIEW` + `DAILY_REVENUE`: Mở app, sidebar chỉ hiện mục "Doanh thu ngày", màn hình `/app/daily-revenue` tải bình thường; không thể vào `/app/reports`.
   - Đăng nhập tài khoản chỉ có `REPORT_DETAIL_VIEW` + `DETAIL_REPORT`: Mở app, sidebar chỉ hiện mục "Báo cáo", màn hình `/app/reports` tải đủ 3 tab; không thể vào `/app/daily-revenue`.
2. **Kiểm tra bộ lọc ngày và preset**:
   - Chọn preset "Hôm nay", "Hôm qua", "7 ngày qua", "30 ngày qua", "Tháng này": Xem ngày `fromDate` và `toDate` được cập nhật chính xác.
   - Thử chọn khoảng ngày lớn hơn 366 ngày: Ứng dụng báo lỗi ngay lập tức, không gửi request.
3. **Kiểm tra tương tác biểu đồ**:
   - Chạm vào các điểm trên biểu đồ để xem tooltip chi tiết.
   - Nhấn vào legend để ẩn một trong hai chuỗi (app không cho phép ẩn cả hai).
   - Nhấn nút "Xem bảng" để đối chiếu dạng danh sách số liệu.
4. **Kiểm tra chuyển Tab**:
   - Mở màn hình Báo cáo: Ban đầu Tab 1 (Tổng quan) được tải.
   - Nhấn Tab 2 (Món bán chạy): Bắt đầu tải trang đầu tiên của món bán chạy. Thử chuyển trang và đổi tiêu chí sắp xếp (theo Doanh số / theo Số lượng).
   - Nhấn Tab 3 (Đơn đối chiếu): Tải danh sách đơn hàng đối chiếu. Thử đổi cơ sở ngày (`PAID`, `COMPLETED`, `CANCELLED`, `CREATED`).
5. **Kiểm tra tính phản hồi & Responsive**:
   - Thử nghiệm trên màn hình Desktop (1200px+): KPI hiển thị 4 cột, Biểu đồ và Phương thức thanh toán nằm cạnh nhau.
   - Thử nghiệm trên Tablet (600–1000px): KPI hiển thị 2 cột, các panel xếp dọc hợp lý.
   - Thử nghiệm trên Mobile (320–480px) với Text Scaling 200%: Không xảy ra hiện tượng tràn chữ (RenderFlex overflow), các nút bấm đạt diện tích chạm tối thiểu 48x48px.

---

## 8. Kết quả Xác minh Tự động Thực tế

- **Static Analysis**: `flutter analyze` chạy qua toàn bộ dự án: **0 issues found**.
- **Report Test Suites**: 4 bộ kiểm thử toàn diện với **38 tests PASSED**:
  - `test/features/reports/report_domain_and_data_test.dart`: Parse DTO 6 endpoint, `ReportDate`, `ReportMoney`, `ApiErrorMapper`.
  - `test/features/reports/report_permission_test.dart`: Quyền độc lập Daily/Detail, AccessPolicy, AppRouter, Sidebar filtering.
  - `test/features/reports/report_controller_test.dart`: Vòng đời Controller, parallel loading, partial failure/retry, pagination resets, scope resets.
  - `test/features/reports/report_widget_test.dart`: Render giao diện KPI, chuyển 3 tab, zero safety trên chart và thanh toán.
- **Hồi quy hệ thống**:
  - `test/features/order/`: **135 tests PASSED**.
  - `test/core/auth/`: **3 tests PASSED**.
