# Kiểm kê kho — giai đoạn 7

Triển khai Flutter ngày 22/10/2026, theo `stock-audit-api.md` và
`stock-audit-fe-sync.md` trong backend. Không thay đổi backend hoặc dependency.

## Cách dùng

Vào **Kho → Kiểm kê**. Danh sách hỗ trợ kho, trạng thái, từ khóa mã/ghi chú,
khoảng ngày tạo, sắp xếp và phân trang server. Nút tạo yêu cầu quyền quản lý.

1. **Tạo phiên nháp**: chọn kho active và ghi chú. Chưa chốt sheet hay thay tồn.
2. **Bắt đầu kiểm kê**: xác nhận trước khi chốt danh sách nguyên liệu, tồn vật lý,
   đơn vị và giá tham chiếu tại thời điểm này. Kho không bị đóng băng giao dịch.
3. Nhập số đếm thực tế và ghi chú. Ô trống là chưa đếm, `0` là đã đếm bằng không.
   Số đếm đã gồm hàng đang reserved; không cộng hoặc trừ reserved lần nữa.
4. **Lưu số đếm**: gửi các dòng thay đổi theo batch tối đa 100, tuần tự bằng version
   header mới trả về. Bản nhập theo auditItemId được giữ qua trang và bộ lọc.
5. Khi mọi dòng của toàn phiên đã đếm và không còn bản nhập chưa lưu, người có
   quyền chốt có thể xác nhận **Chốt kiểm kê**.
6. Có chênh lệch: backend tạo đúng một ADJUSTMENT CONFIRMED, mở bằng liên kết
   **Xem chứng từ điều chỉnh**. Không chênh lệch: CONFIRMED và không có chứng từ,
   đây là kết quả thành công hợp lệ.

`DRAFT → COUNTING → CONFIRMED`; `DRAFT/COUNTING → CANCELLED`.
Phiên kết thúc chỉ đọc. Start/confirm/cancel replay theo desired state của backend;
không tạo snapshot, chứng từ hoặc lịch sử trùng.

## Snapshot và dữ liệu đang nhập

Start chốt toàn bộ INGREDIENT tracked chưa xóa của tenant trong kho, kể cả inactive
và nguyên liệu chưa có balance. Dòng chưa có balance có tồn hệ thống 0. Không chọn
subset, thêm/xóa dòng hoặc đưa nguyên liệu mới sau start vào sheet.

Header và items là hai API đọc riêng; danh sách chỉ trả summary, không chứa actor
đầy đủ như detail. Mỗi trang items giữ tên/SKU/unit/tồn/giá tại start. Không GET
catalog/balance riêng từng dòng, không ghi đè snapshot bằng nguồn hiện tại.

Chênh lệch có dấu, cho phép 0; null là chưa đếm. `StockQuantityChange` của ledger
không dùng cho trường này vì ledger cấm biến động 0. `StockAuditDifference` lưu
BigInt scale 3; quantity dùng InventoryQuantity tối đa 99999999999.999. Giá tham
chiếu dùng StockMoney, 0 hợp lệ; đây không phải actual COGS hay lợi nhuận.
Đọc HTTP bằng decoder giữ chính xác lexeme số. Tổng/tiền chứng từ từ backend là
chuẩn, không áp dụng validation tích tiền của phiếu thủ công cho chứng từ kiểm kê.

Draft nằm ở controller theo scope/audit/item, không phụ thuộc TextField của trang.
Lưu chỉ gửi dòng dirty và hợp lệ. Không dùng ingredientId thay auditItemId.
Không gửi null để reset số đếm đã lưu: PATCH yêu cầu countedQuantity là số.
Note dòng omit/null giữ cũ, blank xóa. Note header null/blank xóa; cancel note
omit/null giữ ghi chú phiên cũ. Giới hạn note header 2000, note dòng 1000 ký tự.
Khi đối chiếu PATCH sau timeout, chỉ so khớp số đếm và ghi chú thực sự đã gửi.
Ghi chú không sửa bị omit khỏi request; ghi chú mới từ thiết bị khác không làm
việc xác minh số đếm thất bại. Ghi chú có sửa hoặc chủ động xóa vẫn phải khớp.

Batch thành công dùng version thực tế server, không tự `version++`; no-op có thể
giữ version. Khi một batch giữa chuỗi lỗi, phần đã lưu được giữ, phần chưa lưu
vẫn ở draft và thông báo số dòng đã lưu/chưa xác nhận. Không giả lập rollback
cả chuỗi batch hoặc gửi song song các command chung audit.version.

Rời màn bằng Back/menu/link có lựa chọn giữ bản nhập, lưu rồi rời hoặc bỏ bản nhập
có xác nhận khi phù hợp trạng thái. Intent chưa rõ kết quả tiếp tục được giữ;
không âm thầm bỏ yêu cầu. Token refresh cùng scope giữ draft. Đổi user/tenant,
quyền/feature/subscription hoặc logout hủy scope cũ và loại response trễ.
Phiên DRAFT chỉ sửa ghi chú cũng có lựa chọn **Lưu và rời**, không tự start phiên
hoặc gửi số đếm.

## Quyền và route

Mọi API cần INVENTORY_VIEW và hai feature INVENTORY_MANAGEMENT + STOCK_AUDIT.

| Thao tác | Quyền bổ sung |
| --- | --- |
| Đọc list/header/items | Không |
| Tạo, start, sửa note, lưu số đếm, cancel | STOCK_AUDIT_MANAGE |
| Confirm | STOCK_AUDIT_CONFIRM |

MANAGE và CONFIRM độc lập. Confirm không cần INVENTORY_ADJUST; kiểm kê không cần
LOW_STOCK_ALERT. Giữ giới hạn role, tenant và subscription của ứng dụng; không
tự cấp quyền theo tên role hoặc thay đổi subscription snapshot.

- `/app/inventory?tab=audits`: danh sách.
- `/app/inventory/audits/new`: tạo nháp, khai báo trước route tham số.
- `/app/inventory/audits/:auditId`: chi tiết/sheet.

Route và dialog đều kiểm tra capability chuyên biệt, dùng AppShell với
initialSection inventory. Menu Kho tiếp tục điều hướng bằng router.
Date filter dùng `[createdFrom, createdTo)`; ngày cuối được đổi thành đầu ngày
kế tiếp theo lịch địa phương rồi sang UTC. Không thay đổi cận inclusive của
StockDateRange ở các API cũ.

## Xung đột và kết quả chưa rõ

- Create dùng key và payload bất biến. Timeout/5xx không tự đổi key; retry đúng
  intent cũ. Key create audit và lock create chứng từ độc lập.
- Các command khác không thêm Idempotency-Key. Timeout confirm phải đọc/đối chiếu
  hoặc replay đúng phiên; không tạo manual ADJUSTMENT thay thế.
- CONCURRENT_STOCK_AUDIT_UPDATE: tải header/trang liên quan, giữ bản nhập và yêu
  cầu đối chiếu trước lưu tiếp; không tự thay version rồi ghi đè.
- STOCK_AUDIT_SNAPSHOT_STALE: giữ COUNTING và số đếm để tham khảo. Hủy phiên,
  tạo/start mới và đếm lại. Không tự rebase snapshot hay copy số đếm cũ.
- Mọi biến động vật lý sau start có thể stale, kể cả nhập rồi xuất về cùng số
  tồn ban đầu. Reserve/release, thay threshold/giá đơn thuần không làm stale.
  Event order chung chỉ báo có thể có thay đổi; backend quyết định staleness.
- INSUFFICIENT_AVAILABLE_STOCK khi số đếm nhỏ hơn reserved: giữ input, không tự
  giảm reservation, hủy order hoặc tăng số đếm để vượt kiểm tra.
- Một kho chỉ có một COUNTING nhưng có thể có nhiều DRAFT; frontend không suy
  luận kho chắc chắn rảnh từ một trang danh sách chưa đầy đủ.

## Chứng từ và đồng bộ kho

StockDocumentSummary/Detail và DTO đọc thêm `stockAuditId` nullable. Có association
này thì chỉ đọc ở mọi điểm vào và controller, kể cả khi người dùng có quyền sửa.
Không gửi stockAuditId/origin hoặc key namespace SYS_STOCK_AUDIT: từ frontend.
Người chỉ có quyền xem kho vẫn đọc được chứng từ; link về audit cần feature audit.

Ledger do kiểm kê sinh ra vẫn STOCK_DOCUMENT và ADJUSTMENT_INCREASE/DECREASE,
không có nguồn ledger mới. RECIPE_USE và unitCost=null hiện có được giữ nguyên.

Create/start/note/count/cancel phát event audit, không giả định đã thay tồn.
Confirm có adjustment phát document + balance event theo kho/documentId, làm mới
list chứng từ, balance, ledger và cảnh báo đang quan sát. Confirm khớp hoàn toàn
không phát tín hiệu thay tồn hoặc documentId giả. Threshold đang nhập được giữ
và yêu cầu baseline mới khi tồn thực sự thay đổi.

## Kiến trúc và file chính

```text
StockAuditList/CreateScreen/DetailScreen/CountSheet
  → controller theo scope và auditId
  → stock_audit_use_cases
  → StockAuditRepository
  → StockAuditRepositoryImpl
  → StockAuditRemoteDataSource → authenticated Dio
```

- Domain: stock_audit.dart, stock_audit_inputs/queries, inventory_instant_range,
  stock_audit_validation, repository contract và 9 use case.
- Data: stock_audit_dto/requests, remote data source và implementation.
- Presentation: stock_audit_* controller, stock_audit_providers, list/create/detail,
  count sheet, widgets và exit guard.
- Tích hợp: AccessPolicy, ApiErrorMapper, AppRoutes/router, InventoryManagementScreen,
  InventoryEvents, balance listener, stock document model/DTO/controller/screen.
- Tests: stock_audit_data/controller/widget_test, inventory_extensions_integration/
  navigation_test và regression inventory/stock_document hiện có.
- Web precision: tool/verify_stock_audit_precision.dart.

## Xác minh

- Formatter: các file Dart thay đổi đã được định dạng.
- `dart analyze`: **No issues found**.
- Lượt chạy toàn dự án trước phần rà soát bổ sung: **794/794 bài đạt**.
- Sau khi bổ sung 6 test cho đối chiếu timeout và lưu ghi chú trước khi rời:
  **47/47 test controller/widget kiểm kê đạt**, `dart analyze` không có lỗi.
  Bộ kiểm kê hiện có 12 test contract/data, 24 controller và 23 widget; còn có
  các test tích hợp quyền, route, event, chứng từ chỉ đọc và regression hiện có.
- Đã render và kiểm tra tám ảnh list/create/detail/bản nhập trên 320/1200 px;
  test responsive còn bao phủ 320/600/800/1200/1440, chữ 100%/200%, bàn phím và tên dài.
- `verify_stock_audit_precision.dart` đã biên dịch dart2js và chạy Node thành công,
  gồm quantity/delta cực đại, delta zero và cent giá tham chiếu lớn.

Chưa xác nhận end-to-end với backend đang chạy hoặc thiết bị thật. Không chạy
mutation lên dữ liệu nhà hàng thật. Không hỗ trợ freeze kho, tự rebase, partial
confirm, quy đổi đơn vị, reversal, xóa lịch sử hoặc realtime/push.
