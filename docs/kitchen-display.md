# Màn hình bếp KDS

## Điểm mở và quyền

Mục **Màn hình bếp** trong sidebar mở `/app/kitchen`. Route legacy
`/app/dish-status` chuyển về cùng màn hình. Màn dùng chung AppShell, có hai chế độ
Theo món/Theo đơn, bộ lọc trạng thái và tìm kiếm trên dữ liệu đã tải.

| Thao tác | Permission | Feature |
| --- | --- | --- |
| Đọc queue | KITCHEN_VIEW | KITCHEN_DISPLAY |
| Bắt đầu nấu | KITCHEN_START_COOKING | KITCHEN_DISPLAY |
| Đã xong / Ready cả đơn | KITCHEN_MARK_READY | KITCHEN_DISPLAY |

Quyền hiệu lực quyết định thao tác. `KITCHEN_UPDATE` không thay thế hai quyền
mutation mới. KDS không yêu cầu ORDER_VIEW, MENU_VIEW, TABLE_VIEW hoặc
ORDER_MANAGEMENT. CASHIER/SUPER_ADMIN giữ chính sách web-only hiện có.

## Kiến trúc và contract

`lib/features/kitchen/` theo Widget → ChangeNotifier controller → Use case →
Repository interface → Repository implementation → Remote data source → Dio
authenticated. Domain dùng lại OrderQuantity, ServiceType, OrderItemStatus và
OrderDetail; data dùng OrderDto. Không thêm package/code generation.

- KitchenDisplayController: tải queue, merge version, filter/search, polling.
- KitchenOrderActionController: khóa từng order, intent/retry, batch và áp dụng
  OrderResponse; tích hợp OrderEvents/TableEvents ở providers.
- Widgets render card, tổng hợp và hộp xác nhận; không gọi HTTP hoặc tạo JSON.

Đã đối chiếu backend `docs/kitchen-completion-api.md`,
`docs/openapi/kitchen-lifecycle-api.yaml`, DTO/controllers, transition service và
serving status policy; backend không bị sửa.

| Method/path | Query/body |
| --- | --- |
| GET /api/v1/kitchen/items | status=PENDING/COOKING/READY, page, size=20 |
| POST /api/v1/orders/{orderId}/items/{orderItemId}/start-cooking | expectedOrderVersion |
| POST /api/v1/orders/{orderId}/items/{orderItemId}/mark-ready | expectedOrderVersion |

Query không hỗ trợ ALL, q, category hoặc date. Mutation không có Idempotency-Key;
body chỉ có expectedOrderVersion của order. Không dùng version session/table hoặc
fallback 0. Thành công là OrderResponse trực tiếp. DTO kiểm tra status/page,
nullable fields, quantity thập phân, version và identity mutation.

## Queue, giao diện và refresh

Tải đủ mọi page của ba stream trạng thái, tối đa ba request đồng thời. Dedup theo
orderId/orderItemId, ưu tiên version mới. Tổng hợp tên món/unit/note giữ nguyên
quantity thập phân và không cộng khác đơn vị. Tiến độ Theo đơn chỉ đếm dòng đang
ở queue; không coi đó là tổng món lịch sử (queue không có SERVED/CANCELLED).

Có trạng thái initial loading, đang tải tiếp, lỗi từng stream, empty, search không
có kết quả và dữ liệu cũ. Partial refresh giữ dữ liệu đã có nhưng báo chưa đầy đủ,
khóa batch. Mixed version của cùng order được đánh dấu cần đối chiếu.

Tìm kiếm local debounce 300 ms; filters không tạo request. Theo đơn hiển thị toàn
bộ dòng đã tải của các order khớp filter/search, để nhân viên không bỏ sót món ở
trạng thái khác. Không GET order/menu/staff/current-session theo từng card.

Bàn là bàn hiện tại từ queue, kể cả sau transfer. Giờ chờ lấy sentToKitchenAt,
fallback createdAt, hiển thị local; ngưỡng cảnh báo 20 phút chỉ là cấu hình UI.
Card có ghi chú đầy đủ và chiều cao theo nội dung. Grid dùng chiều rộng thực tế,
giảm số cột khi chữ lớn. Header/card/tổng hợp cùng vùng cuộn nên màn thấp/bàn phím
không làm các thanh cố định chiếm hết chiều cao.

Refresh thủ công và poll 12 giây khi màn KDS đang hiện/app foreground. Backoff
24/48/96 giây khi tải lỗi. RouteObserver và WidgetsBindingObserver dừng polling
khi có route khác che màn, background hoặc dispose; resume tải lại. Refresh
single-flight; nếu POST/event làm lượt GET đang chạy hết hiệu lực, chờ lượt cũ rồi
đọc lại. Đồng hồ phút chờ cập nhật local mỗi phút, không phát HTTP.

## Đã xong và Ready cả đơn

Món PENDING chỉ có **Bắt đầu nấu**; COOKING có **Đã xong** với xác nhận tên,
số lượng và ghi chú; READY hiển thị sẵn sàng phục vụ. Một mutation chuyển toàn bộ
dòng, không hỗ trợ xác nhận một phần quantity.

Ready cả đơn chỉ bật khi tải đủ dữ liệu, không có PENDING, có COOKING và đủ quyền.
Hộp xác nhận liệt kê các dòng; controller chốt danh sách rồi gửi mark-ready tuần
tự, dùng version mỗi OrderResponse cho request kế tiếp. Bỏ qua dòng đã
READY/SERVED/CANCELLED. Lỗi hoặc PENDING mới làm batch dừng, giữ partial success.
Retry một dòng chưa xác định không tự chạy tiếp phần batch còn lại.

Không có endpoint Ready root. Backend tự tổng hợp READY/PREPARING/SERVED;
giao diện chỉ khẳng định **Đơn đã sẵn sàng** khi có OrderResponse READY.
Order đã PAID vẫn được bếp xử lý. Không complete, mark-served hoặc close session
trong task này; READY không giải phóng bàn.

## Version, retry và tích hợp

Khóa theo orderId bằng OrderEvents; đơn khác vẫn thao tác được. Trong providers,
TableEvents chặn transfer hoặc mutation cùng session đang gửi/chưa xác định.
Partial POST thành công cập nhật các dòng cùng order và phát OrderEvents cho
detail/list/workspace; không tạo order mới, không thay đổi giỏ chưa gửi.
Consumer phân biệt revision data-change với notify lock/unlock, tránh event loop.
Order detail/append chỉ đăng ký khóa phiên cho mutation do chính controller sở
hữu, tránh khóa vòng khi KDS đang retry và các consumer Order vẫn còn sống.

Timeout/mất mạng/5xx hoặc body 200 không parse được giữ intent bất biến gồm scope,
orderId/orderItemId/action/expectedOrderVersion. Nút **Kiểm tra lại đúng thao tác**
replay nguyên endpoint/body. GET queue mới hoặc dòng biến mất không chứng minh
lần POST đã thành công. Backend exact-target retry là no-op; vượt bước là conflict.

Conflict xác định/404 dừng và tải lại; nhân viên chọn **Đã xem dữ liệu mới** trước
khi tạo thao tác mới. Không tự đoán version rồi tiếp tục batch. Sau retry mất
quyền, intent chưa xác định vẫn không được coi là chắc chắn thất bại.
401 dùng auth interceptor; access recovery dùng cơ chế restore bounded hiện có.

POST 200 được giữ khi GET refresh lỗi; chỉ retry phần đọc. Token rotation cùng
scope giữ bộ lọc/intent; đổi tenant/user/quyền/feature loại response cũ. Busy hoặc
uncertain giữ provider sống qua đóng/mở view. Intent chỉ trong RAM; process kill
làm mất intent, mở lại chỉ tải queue mới, không tự phát mutation.

Âm thanh, in phiếu, thiết lập bếp và Theo nhóm là placeholder disabled có tooltip
Sắp có. Không giả số liệu, tên người phục vụ, category, hình món hoặc trạng thái
thiết bị. Chưa có realtime, offline queue hoặc in phiếu.

## Kiểm thử thủ công

1. Đăng nhập tài khoản chỉ có KITCHEN_VIEW/KITCHEN_DISPLAY: đọc được queue, không
   có quyền mutation; thêm từng quyền để kiểm tra nút tương ứng.
2. Gửi order tại bàn/mang đi: PENDING → Bắt đầu nấu → Đã xong; kiểm tra version,
   số lượng lẻ, ghi chú và tên bàn hiện tại.
3. Ready cả đơn nhiều dòng COOKING: kiểm tra root READY. Gọi thêm từ máy khác khi
   batch đang gửi: giữ món đã xác nhận, hiện món PENDING mới, dừng batch.
4. Hai thiết bị cập nhật cùng order: conflict phải tải lại/đối chiếu, không tự
   tạo order khác hoặc bỏ qua bước.
5. Mất mạng sau POST: đóng/mở lại KDS và retry đúng thao tác. Khi máy khác đã
   cập nhật tiếp, kiểm tra thông báo invalid transition và dữ liệu mới.
6. Chuyển bàn khi không có mutation bếp đang chờ: queue hiển thị bàn mới,
   orderId/sessionId và tiền giữ nguyên.
7. Thử 320/600/800/1024/1440 px, chữ 100/150/200%, bàn phím, xoay ngang.
8. Mở route khác/background: polling dừng; quay lại/resume tải mới.

## Kết quả xác minh 13/10/2026

- `dart format`: đã định dạng source/test thay đổi.
- `flutter analyze`: No issues found.
- `flutter test --reporter expanded`: 318/318 test passed, gồm 40 test KDS.
- `flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.4:8080`:
  thành công, native exit code 0. APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- `git diff --check`: không có lỗi whitespace.
- Đã render và kiểm tra ảnh UI bằng font Roboto/MaterialIcons thật ở 320 và
  1440 px; test responsive bao phủ 320/600/800/1024/1440 px, chữ 100/150/200%
  và bàn phím mở. Hộp xác nhận tự đóng khi scope thay đổi.

Test KDS tại `test/features/kitchen/` dùng fake repository và HTTP adapter,
bao phủ contract/quantity/quyền, pagination, retry/no-op, partial batch, append,
transfer, stale read, scope, polling và khóa tích hợp với Order. Đã điều chỉnh
hai selector hồi quy Order để chọn nhãn số món đúng thanh giỏ khi màn hình có
SafeArea ngoài; không thay đổi giao diện Order đang có của người dùng.

Chưa chạy E2E trên backend thật hoặc APK trên thiết bị vật lý.
