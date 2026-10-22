# Inventory giai đoạn 6 — Các đợt cảnh báo tồn thấp

## Cách sử dụng

Mở **Kho → Cảnh báo**, hoặc `/app/inventory?tab=alerts`.
Mặc định danh sách đang lọc **Chưa xem**; chọn **Đã xem**, **Đã kết thúc**
hoặc **Tất cả** để xem các đợt khác. Có lọc kho, tên/SKU lịch sử, ngày phát,
sắp xếp và phân trang. Chọn **Chi tiết** để mở `/app/inventory/alerts/:id`.

**Tồn thấp hiện tại** vẫn dùng `/inventory/low-stock` và là các số dư đang
dưới ngưỡng. **Cảnh báo** dùng `/inventory/alerts` và là các đợt đã được lưu,
kể cả lịch sử đã kết thúc. Số kết quả của bộ lọc Chưa xem không phải tổng số
nguyên liệu hiện đang thiếu.

Chi tiết tách riêng:

- **Tại thời điểm phát cảnh báo**: tên, SKU, đơn vị, kho, tồn và ngưỡng snapshot.
- **Số dư hiện tại**: tồn vật lý, đang giữ, khả dụng, ngưỡng ở lần GET này.
  Nếu nguồn không còn đối chiếu được, hiển thị **Không còn dữ liệu so sánh**;
  không thay null bằng số 0, không ghi đè tên hoặc đơn vị lịch sử.
- **Lịch sử đợt cảnh báo**: thời điểm phát, người/thời điểm xác nhận đã xem,
  thời điểm kết thúc và lý do. Liên kết lịch sử giao dịch giữ đúng kho/nguyên liệu.

**Xác nhận đã xem** chỉ xuất hiện cho OPEN và có quyền ghi tương ứng.
ACKNOWLEDGED chỉ có nghĩa đã xem, không phải đã nhập kho hoặc hết thiếu.
RESOLVED có thể do nhập đủ, tắt ngưỡng, kho/nguyên liệu bị tắt/xóa/ngừng tracking,
hoặc đổi đơn vị; giao diện dịch rõ từng lý do.

Cảnh báo thấp dùng `minQuantity > 0 && quantity <= minQuantity` với **tồn vật lý**.
Khả dụng thấp do hàng đang giữ không tự đồng nghĩa tồn vật lý thấp.
Không có chức năng tạo, resolve hoặc xóa cảnh báo thủ công.

## Phân quyền, API và kiến trúc

Đọc cần `INVENTORY_VIEW`, `INVENTORY_MANAGEMENT` và `LOW_STOCK_ALERT`.
Xác nhận thêm `INVENTORY_ALERT_ACKNOWLEDGE`; quyền của OWNER cũng phải hiệu lực.
Giữ các giới hạn role/tài khoản/subscription chung của ứng dụng.
Guard controller, màn hình, route và date/warehouse picker cùng kiểm tra capability.

Luồng thực thi:

`InventoryAlertList / InventoryAlertDetailScreen`
→ `InventoryAlertListController / InventoryAlertDetailController`
→ `GetInventoryAlerts / GetInventoryAlert / AcknowledgeInventoryAlert`
→ `InventoryAlertRepository`
→ `InventoryAlertRepositoryImpl`
→ `InventoryAlertRemoteDataSource`
→ authenticated Dio hiện có.

Các file nằm trong `lib/features/inventory/`:

- `domain/entities/inventory_alert.dart`, `inventory_alert_query.dart`.
- `domain/repositories/inventory_alert_repository.dart`.
- `domain/use_cases/inventory_alert_use_cases.dart`.
- `data/dto/inventory_alert_dto.dart`, `inventory_alert_requests.dart`.
- `data/data_sources/inventory_alert_remote_data_source.dart`.
- `data/repositories/inventory_alert_repository_impl.dart`.
- `presentation/controllers/inventory_alert_*_controller.dart`.
- `presentation/providers/inventory_alert_providers.dart`.
- `presentation/widgets/inventory_alert_list.dart`, `inventory_alert_widgets.dart`.
- `presentation/screens/inventory_alert_detail_screen.dart`.

Chỉ dùng ba endpoint hợp đồng: GET list, GET detail, POST acknowledge.
GET không body; POST chỉ có `expectedVersion` lấy từ `alert.version`.
Không gửi restaurantId, actor, timestamp hoặc Idempotency-Key.
Response được đọc dạng plain và giải mã lossless bằng decoder số kho;
số lượng dùng `InventoryQuantity` chính xác tới 0.001, tối đa 99999999999.999.
Decoder kiểm tra lifecycle, identity, query và sự nhất quán số dư hiện tại.
Không GET detail cho từng hàng trong danh sách.

Khoảng ngày dùng `InventoryInstantRange`, cận cuối **exclusive**:
ngày kết thúc được đổi thành đầu ngày tiếp theo theo lịch địa phương, rồi sang UTC.
Không thay semantics bộ lọc thời gian chứng từ cũ. Tìm kiếm `%` và `_` giữ nguyên
như ký tự literal. Chỉ gửi query allowlist, kiểm tra độ dài, sort và paging.

## State và đồng bộ

Provider chỉ mount khi tab/màn hình được mở, có scope theo phiên kho hiện tại.
Đổi người dùng, tenant, quyền/feature hoặc logout loại kết quả trễ.
Token refresh cùng scope giữ trạng thái; request generation chặn kết quả bộ lọc cũ.
Date/warehouse picker tự đóng khi capability không còn.

ACK khóa theo `InventoryEvents.alertKey(id)` để chống nhấn lặp, kể cả hai controller.
Sử dụng actor/time/version server trả về; không optimistic version++.
Kết quả ACK chỉ phát `InventoryChangeKind.alert`, không phát balance hoặc ledger.
Controller danh sách/chi tiết đồng bộ khi nhận alert hoặc các signal kho phù hợp,
gộp các signal cùng lượt. Signal không biết warehouse vẫn được đọc lại an toàn.

409 stale hoặc kết quả ghi chưa rõ giữ dữ liệu và yêu cầu tải lại chi tiết trước
khi thao tác tiếp; không tự đổi expectedVersion rồi retry.
ACK replay hợp lệ là trạng thái server; RESOLVED không có nút ACK.
Có tải lại thủ công và pull-to-refresh màn chi tiết; quay lại danh sách sẽ đọc mới.
Không thêm polling toàn app, WebSocket hay notification delivery.

## Xác minh

Ba bộ kiểm thử chuyên biệt:

```powershell
flutter test test/features/inventory/inventory_alert_data_test.dart test/features/inventory/inventory_alert_controller_test.dart test/features/inventory/inventory_alert_widget_test.dart
```

Bao phủ method/path/header/body, replay, identity, null hiện tại, đủ resolution reason,
số lượng lớn chính xác, date exclusive, tìm literal, phân quyền độc lập, lock và conflict,
loại kết quả trễ, event phù hợp, không N+1, deep link ledger, thu hồi feature và picker.
Widget kiểm tra 320/600/800/1200/1440 với text scale 100%/200% và tên dài.

Kết quả cuối: **27/27 kiểm thử cảnh báo đạt**, toàn dự án **794/794 kiểm thử đạt**;
analyzer sạch. Đã kiểm tra bốn ảnh render danh sách/chi tiết trên 320/1200 px.

Không thay đổi backend hoặc kiểm thử mutation bằng dữ liệu nhà hàng thật.
Chưa xác nhận end-to-end với backend đang chạy và thiết bị thật.
