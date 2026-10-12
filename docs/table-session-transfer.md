# Chuyển phiên phục vụ sang bàn khác

## Điểm mở và quyền

- Quản lý bàn: card/chi tiết phiên OPEN, kể cả phiên chưa có order.
- Chi tiết order DINE_IN: menu ba chấm; giữ nguyên route, orderId và sessionId.
- Chuyển cần `TABLE_TRANSFER`; đọc session/bàn đích cần `TABLE_VIEW`; cả hai cần
  feature `TABLE_MANAGEMENT`. Xem lịch sử chỉ cần TABLE_VIEW.
- Không hardcode OWNER/MANAGER và không yêu cầu TABLE_OPEN, TABLE_CLOSE,
  ORDER_UPDATE hoặc ORDER_CANCEL cho API chuyển bàn.

## Contract

```http
POST /api/v1/table-sessions/{sessionId}/transfer
Idempotency-Key: <stable key>
Content-Type: application/json

{
  "targetTableId": "<UUID>",
  "expectedVersion": 3,
  "reason": "Khách muốn chuyển sang khu vực yên tĩnh"
}
```

`expectedVersion` luôn là version của session. Reason được trim, chuỗi trống
thành null. Body không có tenant, actor, source table, order hay sessionCode.
HTTP 200 trả trực tiếp `TableSessionResponse`; data layer đọc
`Idempotency-Replayed: true|false`, thiếu header giữ `null`.

```http
GET /api/v1/table-sessions/{sessionId}/transfers?page=0&size=20
```

Lịch sử là page, giữ thứ tự backend. Mỗi dòng dùng snapshot bàn nguồn/đích,
actorUserId, nullable reason, version trước/sau và transferredAt.

## Idempotency và lỗi

Khi xác nhận, controller đóng băng scope, sessionId, targetTableId,
session.expectedVersion, reason và key. Hai lần nhấn chỉ tạo một POST. Timeout,
mất mạng, lỗi 5xx hoặc success body không parse được giữ nguyên intent; nút thử
lại replay đúng request. GET thấy bàn đã đổi không được dùng làm bằng chứng.

Conflict như bàn vừa có khách, stale version, cùng bàn hoặc session không còn
OPEN là từ chối xác định. App tải lại context để nhân viên xem, không tự retry
với version/key mới. `IDEMPOTENCY_KEY_REUSED` không tự sinh key thay thế.

Replay là resource replay: A→B có thể trả session hiện tại ở C hoặc terminal nếu
thiết bị khác đã thao tác tiếp. App hiển thị đúng C/trạng thái terminal và refresh
workspace; thông báo không khẳng định vừa chuyển đến B.

## Đồng bộ

Một sự kiện session chứa tableId thực tế, sessionId và tập bàn nguồn/đích/thực tế.
Danh sách bàn, detail/current-session, lịch sử phiên, lịch sử chuyển và workspace
order refresh có debounce/generation để response GET cũ không ghi đè kết quả POST.
Order và amount không được tạo lại hoặc tính lại; giỏ gọi thêm chưa gửi còn nguyên.

State uncertain được giữ trong RAM qua keepAlive và exit guard. Process kill làm
mất intent/key; lần mở sau chỉ tải dữ liệu hiện tại và không tự phát lại mutation.

## Kiểm thử thủ công

1. Mở order tại bàn A, gọi thêm vài món nhưng chưa gửi, chuyển A→B; kiểm tra giỏ,
   orderId/sessionId/tổng tiền giữ nguyên và tiêu đề thành B.
2. Mở session không có order từ quản lý bàn và chuyển sang bàn trống ở trang sau.
3. Thử trên điện thoại, tablet, desktop và khi bàn phím reason đang mở.
4. Cho hai máy chọn cùng bàn; máy thua phải báo conflict và tải lại, không gộp.
5. Ngắt mạng sau khi bấm xác nhận; mở lại dialog và retry đúng key/payload.
6. Sau A→B, dùng máy khác chuyển B→C rồi replay request đầu; UI phải hiển thị C.
7. Kiểm tra history khi session OPEN, CLOSED và CANCELLED; reason null không tạo
   dòng trống, thời gian hiển thị theo local và actor giữ nguyên ID.

## Xác minh tự động

Kết quả ngày 11/10/2026 trên bản source cuối:

- `flutter analyze`: không có lỗi hoặc cảnh báo.
- `flutter test`: 277/277 test passed.
- `flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.4:8080`:
  thành công; APK ở `build/app/outputs/flutter-apk/app-debug.apk`.

Các test chuyển bàn bao phủ request/header/body, lịch sử, quyền, double submit,
timeout và retry cùng key/payload/version, conflict xác định, 5xx chưa xác định,
resource replay, stale read, đổi scope, pagination không N+1, đồng bộ order và
responsive 320/800 px khi bàn phím đang mở. Chưa chạy E2E với backend thật hoặc
kiểm tra APK trên thiết bị vật lý.
