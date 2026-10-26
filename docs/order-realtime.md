# Realtime QR, Order và KDS

Flutter dùng **một native WebSocket, STOMP 1.2** theo phiên đăng nhập. REST vẫn là
nguồn dữ liệu hiển thị và kết quả command. Backend chỉ được đọc để đối chiếu:
`pos-saas-be/docs/realtime-api.md`, `order-realtime-api.md`, `order-api.md`,
`public-qr-order-api.md`, `inventory-alert-realtime.md`.

## Cấu hình và kênh

Giữ `.env`, `RealtimeConfig`, settings đã có:

```dotenv
API_BASE_URL=http://<dia-chi-backend-thiet-bi-truy-cap-duoc>:8080
REALTIME_ENABLED=true
REALTIME_TRANSPORT=websocket
REALTIME_URL=
```

Lựa chọn công tắc đã lưu trên thiết bị ưu tiên hơn `REALTIME_ENABLED`. Stop/chạy lại
app để đóng gói thay đổi `.env`. URL suy từ REST: http → ws, https → wss; bỏ hậu tố
`/api/v1`, giữ context path rồi nối `/ws`. `REALTIME_URL` là override ws/wss đầy đủ.
Release yêu cầu wss. Không token trong URL; CONNECT dùng access token hiện tại,
không refresh token hoặc header tự khai tenant/user. Subscribe sau CONNECTED.

| ID / destination `/user/queue/…` | Permission | Feature |
| --- | --- | --- |
| `qr-order-requests` | ORDER_VIEW | ORDER_MANAGEMENT |
| `orders` | ORDER_VIEW | ORDER_MANAGEMENT |
| `kitchen-orders` | KITCHEN_VIEW | KITCHEN_DISPLAY |
| `inventory-alerts` | INVENTORY_VIEW | INVENTORY_MANAGEMENT, LOW_STOCK_ALERT |

`RealtimeAccessPolicy` tách quyền đọc socket khỏi policy điều hướng/mutation.
Kênh order/QR chấp nhận CASHIER có grants phù hợp, không cần QR_TABLE_ORDER,
QR_STATIC_ORDER hoặc approve. Kitchen-only chỉ cần quyền/feature bếp. Kho giữ
allowlist OWNER/MANAGER/WAITER/KITCHEN. System SUPER_ADMIN, phiên không có tenant,
subscription không active và role app chưa hỗ trợ không mở subscription tenant.
App vẫn giữ màn CASHIER web-only và các role gate UI cũ; lần này không mở rộng
quyền sửa đơn, duyệt QR hoặc điều hướng. Custom role hiện chưa được auth UI hỗ trợ.

## Cấu trúc

- `core/realtime`: transport/STOMP codec, heartbeat, physical connection, envelope,
  capability đọc và cache event hữu hạn.
- `app/realtime_providers.dart`: binding auth/settings/lifecycle; lắp danh sách kênh
  được phép vào **RealtimeConnectionService đang có**, không tạo socket theo màn.
- `order/data/dto/order_realtime_payload.dart`, `qr_order/data/dto/qr_realtime_payload.dart`:
  kiểm schema/type/resource, UUID, status, tập changes và context nullable.
- Coordinator Order, QR, Kitchen: parse, dedupe và gom hint; không HTTP/mutation/UI.
- `OrderEvents.invalidateRemote`, `QrEvents`, `KitchenEvents`: tín hiệu đọc, tách
  khỏi thành công của mutation local. Không unlock hoặc xóa unresolved.
- Controller/provider đang được dùng tải lại qua repository/use case và Dio có auth.

Bootstrap chỉ giữ coordinator/event bus, không dựng list/detail/KDS để duy trì socket.
Màn chưa mở sẽ đọc snapshot khi mở, không GET mọi order trong nền.

## Event → REST

| Event | Consumer đang hoạt động | REST |
| --- | --- | --- |
| QR_ORDER_REQUEST_CHANGED | Inbox/badge tại bàn; review trùng request/table/session | GET qr-order-requests; GET request review |
| ORDER_CHANGED | List giữ query/page; detail liên quan; workspace bàn; review liên quan | GET orders/order detail; GET tables và serving order snapshot |
| ORDER_CHANGED qua kitchen-orders | KDS đang hiển thị | GET kitchen/items theo các status/paging hiện có |
| INVENTORY_LOW_STOCK_ALERT_CHANGED | List/detail cảnh báo, badge tồn thấp | API inventory đang có |

Active-order của phiên tiếp tục được xác minh qua REST khi chọn bàn. Tổng tiền thẻ
bàn lấy từ serving-order REST snapshot, không cộng số tiền từ event. Cancel/complete
phát refresh bàn/phiên và thay toàn bộ snapshot phù hợp; không tự suy occupancy.

**Phạm vi QR UI:** inbox hiện chỉ đọc `entryType=TABLE` qua use case/API hiện có.
Event `RESTAURANT` vẫn được parse, invalidate và hiện thông báo rõ “mang đi”; chưa
có inbox tổng/màn riêng QR mang đi. Số badge hiện tại chỉ là pending QR tại bàn,
không tuyên bố là backlog mọi loại QR. Expiry vẫn tính bằng REST `expiresAt` và
timer hiện có, không chờ event EXPIRED.

## Dedupe, race và mutation

Order/Kitchen dùng **cache riêng từng consumer/channel**, nên cùng eventId fan-out
vẫn làm mới cả hai. Thông báo món mới chỉ phát từ kitchen consumer; order consumer
không phát lại. QR có cache riêng. Cache tối đa 512 ID, TTL 10 phút, xóa khi scope
auth đổi/dispose. Không dùng highestVersion toàn nhà hàng hoặc delta cursor.
Event đến lệch version vẫn là hint hợp lệ để đọc snapshot, không được áp state trực tiếp.

Gom burst mặc định 400 ms, một timer/coordinator, giữ tập ID order/session/request.
Quá 512 context ID chuyển sang invalidate toàn scope. Payload được copy bất biến
cả nested list/map, envelope tối đa 256 KiB, list payload tối đa 2048 phần tử.
JSON sai, type/schema chưa hỗ trợ bị bỏ qua. Không log frame/raw body/token.

Các refresh do event được gom trong controller: khi GET đang chạy, ghi nhận một
lần đọc tiếp; response của generation cũ không ghi đè lần mới. Detail còn kiểm ID
và version REST. Workspace vẫn cho phép refresh thủ công mới thay thế lần đọc cũ
và loại response cũ bằng generation. Snapshot gần nhất còn hiển thị khi refresh.
KDS không GET order detail; snapshot queue là nguồn để tổng hợp món/theo đơn.

Remote hint không giải phóng pending/unresolved, không retry POST/PATCH, không xem
socket là bằng chứng thanh toán/command thành công. Detail defer refresh khi đang
ghi hoặc cần verification. KDS defer đọc khi local order command còn pending.
Sau command, response REST và cơ chế verification/idempotency cũ quyết định trạng thái.
Giỏ/form nhập dở không bị dựng lại hoặc xóa. Khi append target đã kết thúc, policy
REST detail chặn gửi; lựa chọn chưa gửi còn giữ để người dùng kiểm tra/bỏ giỏ.

Review QR invalidation đánh dấu needsReload và chặn hash cũ. Không đổi generation
của approve/reject đang chạy. Nếu kết quả chưa xác định, giữ khóa và cần verification;
nếu đọc lại thành công, review object mới buộc xác nhận lại. Không tự duyệt/từ chối
bằng hash/version thay thế. QR expiry/cooldown cũ được giữ.

## Lifecycle, lỗi và polling

Giữ SessionRefreshCoordinator chung với REST, refresh token single-flight. Token
đổi → đóng socket cũ tuần tự trước khi mở mới và đăng ký kênh còn quyền. Sau
CONNECTED/reconnect, mỗi channel invalidate snapshot; không dựng thông báo từ REST
lịch sử. Logout/đổi scope hủy callback/cache/debounce; background đóng socket,
dừng coordinator; resume dùng auth hiện tại, revalidate access cho các kênh mới,
resync đọc. Không tác vụ nền mới, không vòng kiểm tra quyền liên tục.

Lỗi FORBIDDEN/FEATURE_NOT_ENTITLED/SUBSCRIPTION_NOT_ACTIVE fence subscription ID
nếu có; thiếu/không biết ID thì block toàn bộ kênh của kết nối đó. Revalidate qua
AuthController, grants y nguyên không retry kênh bị từ chối vô hạn. Kênh còn hợp lệ
có thể reconnect. ACCOUNT_INACTIVE/RESTAURANT_INACTIVE/protocol/subscription-limit
dừng kết nối; auth flow quyết định session. Close 1008 không tự suy là token hết hạn.
Mạng/heartbeat/connection-limit/shutdown retry với một timer, exponential backoff,
jitter, tối đa delay 30 giây. ERROR có thể đến sau SUBSCRIBE: connected không phải
bằng chứng quyền từng kênh còn hiệu lực; REST 401/403 vẫn được xử lý.

QR/KDS chỉ polling khi route hiển thị và foreground: 12 giây theo cấu hình cũ khi
socket chưa kết nối/tắt, 60 giây đối soát khi channel connected, có backoff lỗi.
Kho giữ WebSocket/polling opt-in và notice cũ; `REALTIME_TRANSPORT=polling` không
mở socket khác. Không thêm polling nền cho list hoặc detail order. Pull-to-refresh
giữ nguyên. QR polling arrivals tắt khi socket hoạt động để tránh báo trùng.

Thông báo QR mới/món mới xuất hiện góc trên, tự ẩn 5 giây, không tự điều hướng.
Chỉ QR CREATED hoặc `newKitchenItemIds` khác rỗng tạo notice; READY/SERVED/hủy/
complete không tạo notice món mới. Kho vẫn có popup riêng góc dưới. Không thêm
âm thanh, notification inbox hoặc package mới.

## Chạy thử hai thiết bị

1. Chạy backend có contract realtime mới, cùng tenant; bật realtime trong app.
   Dùng API_BASE_URL mà cả hai thiết bị truy cập được. Xác minh quyền/feature từng tài khoản.
2. A: app nhân viên tại workspace bàn; B: guest QR gửi request. Badge/inbox A cập nhật;
   món chưa vào KDS. Không phát sinh order/approve tự động.
3. Duyệt QR ở B/thiết bị staff khác. Request rời pending; bàn/order/KDS A cập nhật REST.
4. Gọi thêm ở B. Vẫn cùng order, tiền bàn A đổi, KDS có lượt món mới. Chuyển món
   COOKING/READY/SERVED: A cập nhật, không báo món mới.
5. Mở review QR ở A rồi sửa order/duyệt request ở B. A phải đọc lại review và xác nhận
   lại trước approve, không dùng hash cũ. Thử khi A đang xác nhận/POST để kiểm khóa.
6. Thanh toán/served/complete đúng nghiệp vụ. Complete tại bàn làm mới phiên/bàn,
   đơn rời danh sách đang phục vụ; không tự thanh toán từ event.
7. Ngắt mạng rồi nối lại, background/resume: một socket, snapshot resync, không báo
   lại lịch sử. Tắt công tắc vẫn refresh thủ công/polling của màn hoạt động được.
8. Logout/login tenant khác: không frame/response/notice từ phiên trước.
9. Thu hồi feature kho rồi revalidate/resume: kênh kho mất, order/kitchen còn quyền
   hoạt động. Thử CASHIER chỉ nhận order/QR và KITCHEN chỉ nhận queue API bếp.
10. Tạo đợt tồn thấp mới: inventory notice/list/badge vẫn hoạt động như trước.

## Giới hạn

Staff-only, best-effort, backend single-instance, không replay/outbox/push khi app
đóng. Payment độc lập, chuyển bàn, menu availability và guest chưa có channel riêng:
giữ refresh qua REST local/lifecycle/thủ công hiện tại. Không hứa các thay đổi này
luôn có ORDER_CHANGED. Polling đối soát chỉ ở màn QR/KDS/kho theo cơ chế đã mô tả.

## Kiểm tra tự động

Test mới: `test/core/realtime/staff_realtime_test.dart`,
`test/features/order/order_realtime_integration_test.dart` và widget notice.
Giữ test STOMP/URL/heartbeat/settings, refresh REST+socket, auth/scope, order/QR/KDS
và inventory cũ. Chạy format file thay đổi, flutter analyze và toàn bộ flutter test.
Không update golden hoặc giảm assertion để che hồi quy.

Kết quả kiểm tra ngày 26/10/2026:

- Format: 34 file Dart thêm/sửa; `flutter analyze --no-pub`: **No issues found**.
- Toàn bộ `flutter test --no-pub --reporter expanded`: **1004 đạt, 1 lỗi có sẵn**.
  Cả 28 test mới đều đạt; test STOMP/settings/auth refresh/inventory/QR/KDS vẫn được chạy.
- Lỗi duy nhất: `test/features/order/order_widget_test.dart`, test
  `append popup is usable at 320px with keyboard and large text`, overflow ngang 18 px.
  Đã tái hiện chính lỗi này bằng test nguyên bản trên HEAD
  `261412e62771ad2b40daeef8c6cd8a01255c8167`, trong bản archive riêng tại
  `C:\Users\Dell\AppData\Local\Temp\pos-saas-realtime-baseline-b70ca15258c544779f09693c8b98404f`.
  Không đồng bộ mã từ bản archive vào workspace, không sửa assertion/golden.
- Log: `.order-channels-full-tests.log`, `.order-channels-final-analyze.log`,
  `.order-channels-baseline-layout.log`. Git diff whitespace check đạt.
- Chưa chạy kịch bản hai thiết bị thực; các bước phía trên dành cho kiểm thử tích hợp.

Các nhóm file thêm/sửa:

| Nhóm | File chính |
| --- | --- |
| Shared realtime | `core/realtime/realtime_access_policy.dart`, `realtime_event_window.dart`, `realtime_envelope.dart`, `realtime_transport.dart`, `realtime_connection_service.dart`, `stomp_websocket_transport.dart` |
| Composition/notice | `app/realtime_providers.dart`, `app/realtime_notice.dart`, `app/app.dart`, `core/ui/widgets/staff_realtime_notice_overlay.dart` |
| Order | `order_realtime_payload.dart`, `order_realtime_coordinator.dart`, `order_invalidation.dart`, `order_events.dart`, list/detail/service-context/append controllers và `order_providers.dart` |
| QR | `qr_realtime_payload.dart`, `qr_realtime_coordinator.dart`, `qr_events.dart`, inbox/review controllers và `qr_request_providers.dart` |
| KDS/table | `kitchen_realtime_coordinator.dart`, `kitchen_events.dart`, `kitchen_display_controller.dart`, `kitchen_providers.dart`, `table_events.dart` |
| Tests | `staff_realtime_test.dart`, `staff_realtime_notice_test.dart`, `order_realtime_integration_test.dart`, `helpers/order_realtime_fakes.dart` |

Chỉ thay đổi repository Flutter; backend giữ nguyên. Không thêm package, không commit/reset Git.
