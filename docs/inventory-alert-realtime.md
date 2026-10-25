# Cập nhật tự động cảnh báo tồn kho

Triển khai Flutter ngày 23/10/2026, cập nhật ngày 24/10/2026. Mặc định dùng
**WebSocket/STOMP** để thông báo theo sự kiện ngay khi backend đã lưu thành công
đợt cảnh báo chạm ngưỡng. App không chờ chu kỳ 20 giây. REST polling được giữ như
một lựa chọn riêng khi cấu hình rõ, không phải cơ chế realtime mặc định.
List/detail và thao tác **Đã xem** tiếp tục dùng ba API REST hiện có.

Luồng realtime yêu cầu backend phát sự kiện **sau khi transaction commit**:
`tồn vật lý <= ngưỡng (ngưỡng > 0)` → tạo đợt OPEN → commit → gửi sự kiện đúng tenant
→ app nhận sự kiện → hiện thông báo. Transaction rollback không được gửi thông báo
thành công giả. Thời gian hiển thị còn phụ thuộc độ trễ mạng; cửa sổ gom sự kiện
400 ms của app dùng để gộp một batch cảnh báo, không phải lịch kiểm tra định kỳ.

## Bật và tắt

Vào **Kho → Cảnh báo → Cập nhật tự động** để bật/tắt ngay trong app. Công tắc cũng
có ở đầu màn chi tiết cảnh báo. Không cần thêm dart-define để bật bằng công tắc.

Mặc định `REALTIME_ENABLED=false` chỉ xác định lựa chọn ban đầu khi thiết bị chưa
lưu tùy chọn. Lựa chọn trong app được ưu tiên khi mở lại, lưu ở key riêng
`preferences.realtime.enabled.v1`, độc lập với token và vẫn giữ sau logout.
Đây là tùy chọn trên thiết bị, không cấp quyền hoặc feature cho tài khoản.

Chờ đọc lựa chọn đã lưu trước khi chạy cập nhật: bản build mặc định ON không được
poll hoặc mở socket thoáng qua nếu người dùng đã lưu OFF. Bật/tắt áp dụng ngay; khi tắt hủy
retry và debounce đang chờ. Nếu ghi storage lỗi, lựa chọn vẫn áp dụng trong lần
mở hiện tại và UI báo chưa lưu cho lần mở sau. Lỗi đọc storage khởi động ở OFF.

REST vẫn tải khi vào màn hình, tải lại thủ công và khi ứng dụng quay lại foreground,
kể cả khi lựa chọn realtime đang OFF. Không đợi socket trước khi tải REST.

`REALTIME_TRANSPORT=websocket` là mặc định. Bật công tắc sẽ kết nối STOMP `/ws`;
khi kết nối thành công, trạng thái hiển thị **Đang tự động cập nhật cảnh báo.**
Từ đó đợt OPEN mới được backend đẩy tới app đang mở mà không cần tải lại hoặc
đợi chu kỳ polling. Đăng nhập/kết nối lại vẫn tải REST để đối chiếu hiện trạng,
không báo lại toàn bộ lịch sử. Cần kết nối thành công trước khi tạo đợt mới để thử.

App tự nạp `.env` lúc khởi động trước khi tạo API client và kết nối realtime.
Đặt `API_BASE_URL`, `REALTIME_ENABLED`, `REALTIME_TRANSPORT`, `REALTIME_URL` trong
file này rồi chạy `flutter run` hoặc nhấn F5, không cần `--dart-define-from-file`.
Sau khi sửa `.env`, dừng app và chạy lại để đóng gói/nạp cấu hình mới.
Key được truyền rõ bằng `--dart-define` được ưu tiên hơn `.env`, kể cả boolean
`false` hoặc chuỗi trống. Ví dụ ghi đè cấu hình khi dùng Android emulator:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080 --dart-define=REALTIME_ENABLED=true
```

Thiết bị thật dùng địa chỉ backend mà thiết bị truy cập được, thay `10.0.2.2`
bằng IP LAN/domain thích hợp. Không dùng localhost chung cho mọi thiết bị.

Backend phải chạy phiên bản đã hỗ trợ STOMP `/ws`. Có thể đặt rõ
`--dart-define=REALTIME_TRANSPORT=websocket`; không tự chuyển từ lỗi socket sang
polling. Ví dụ override endpoint sau reverse proxy:

```powershell
flutter run --dart-define=API_BASE_URL=https://pos.example.com/restaurant --dart-define=REALTIME_ENABLED=true --dart-define=REALTIME_TRANSPORT=websocket --dart-define=REALTIME_URL=wss://pos.example.com/restaurant/ws
```

Các quy tắc URL dưới đây chỉ áp dụng chế độ WebSocket.
`Environment` đọc `.env` đã nạp và các override dart-define; `RealtimeConfig` kiểm
tra URL bằng `Uri`. File `.env` là asset đóng gói cùng app, chỉ chứa cấu hình client;
không đặt JWT signing secret, mật khẩu database hoặc token đăng nhập trong đó.
Không override thì http/https đổi thành ws/wss, giữ port và context path;
suffix `/api/v1` nếu có được bỏ trước khi nối `/ws`:

| REST base | WebSocket |
| --- | --- |
| `http://10.0.2.2:8080` | `ws://10.0.2.2:8080/ws` |
| `https://host/api/v1` | `wss://host/ws` |
| `https://host/restaurant/api/v1` | `wss://host/restaurant/ws` |

URL không nhận query, fragment hoặc userInfo. Release yêu cầu `wss`.
Không thay cấu hình cleartext/ATS, không giả mạo Origin. Backend phải cho phép
Origin/native client theo chính sách deployment hiện tại.

## Phân quyền và WebSocket mặc định

Cả polling và WebSocket đều dùng `AccessPolicy.canViewInventoryAlerts`:
INVENTORY_VIEW cùng INVENTORY_MANAGEMENT và LOW_STOCK_ALERT, cộng các giới hạn
tenant/subscription/role hiện có. Không tự cấp quyền theo role. Tài khoản đủ
capability đọc không cần quyền ACK; nút Đã xem vẫn cần INVENTORY_ALERT_ACKNOWLEDGE.
SUPER_ADMIN và session không có restaurant context không chạy cập nhật theo tenant.

Các chi tiết kết nối sau áp dụng chế độ mặc định `REALTIME_TRANSPORT=websocket`:

- Native WebSocket, đề nghị subprotocol `v12.stomp`, chỉ chấp nhận STOMP 1.2.
- Token hiện tại nằm trong header STOMP CONNECT `Authorization: Bearer ...`.
  Không gửi refresh token, token qua URL, cookie hay HTTP handshake header.
- Heartbeat STOMP `10000,10000`, thương lượng với server; chỉ gửi LF heartbeat.
- Sau CONNECTED, subscribe `id=inventory-alerts`,
  destination **`/user/queue/inventory-alerts`**, `ack:auto`.
- Không có API SEND/ACK/NACK trong transport của app. Không subscribe topic,
  raw queue, wildcard hoặc destination theo userId/restaurantId.

Transport không chứa policy kho. `RealtimeChannel` nhận handler/resync từ feature;
sau này có thể bổ sung channel khác trên cùng connection service. Lần này chưa
đăng ký realtime order.

## Polling REST tùy chọn

Chỉ dùng phần này khi đặt rõ `--dart-define=REALTIME_TRANSPORT=polling`.
Đây là kiểm tra định kỳ, không đáp ứng yêu cầu nhận ngay sự kiện chạm ngưỡng.
Trạng thái của chế độ này là **Đang kiểm tra cảnh báo mỗi 20 giây.**

`InventoryAlertPollingController` dùng `GetInventoryAlerts` qua repository/Dio
đã xác thực, không thêm endpoint. Mỗi lượt bắt đầu bằng GET danh sách **tất cả
trạng thái** (`status` bỏ trống), `size=100`, sắp `triggeredAt desc`; vì vậy đổi
ACK/RESOLVED không bị hiểu nhầm là một cảnh báo mới xuất hiện trong bộ lọc OPEN.
Chỉ ID mới được đối chiếu đủ tin cậy và vẫn OPEN mới phát notice; cập nhật version,
số dư hoặc trạng thái của ID đã biết không tạo thông báo mới.

Lần đọc đầu giữ tối đa **100 ID ở trang đầu** và mốc cuối trang. Các lượt sau đọc
tuần tự tới mốc cũ, hết danh sách hoặc tối đa **10 trang**, rồi cập nhật mốc. Đây
là đối chiếu có giới hạn, không tải toàn bộ lịch sử: nếu không tìm lại được mốc,
chỉ báo những đợt xác định mới hơn được, bỏ qua các dòng cũ/cùng thời điểm còn mơ
hồ. Có thể bỏ lỡ đợt phát sinh giữa các lần kiểm tra, đợt đã ACK/RESOLVED trước
khi đọc hoặc burst vượt cửa sổ quét. Không hứa nhận đủ mọi đợt hay thông báo toàn
bộ cảnh báo lịch sử. Kết quả đọc từng lượt chỉ được chấp nhận sau khi mọi trang
đã yêu cầu thành công.

Lượt tiếp theo chạy khoảng **20 giây sau khi lượt hiện tại kết thúc**. Tín hiệu
thay đổi kho/ACK cục bộ gom trong **400 ms** để yêu cầu kiểm tra sớm. Không có hai
lượt polling chồng nhau; yêu cầu đến khi đang đọc được gom thành một lượt tiếp.
Lỗi mạng/đọc giữ mốc cũ, không phát thông báo hoặc signal thành công giả; retry
giãn dần tới tối đa **5 phút**. Lỗi auth/quyền/feature dừng retry và chuyển qua
luồng phục hồi quyền hiện có, không tự vượt quyền bằng retry.

Sau mỗi lượt thành công, phát `alertSync` để list/detail đang mở GET lại dữ liệu
hiện tại, giữ bộ lọc của từng controller. Polling dùng chung vẫn chạy trong app ở
foreground khi đang ở chức năng khác, nếu công tắc và quyền cho phép; không GET
detail cho từng dòng, không polling balances/order/KDS.

OFF, background, logout, đổi scope hoặc mất quyền dừng timer và loại response trễ.
Resume/OFF→ON tạo lại mốc im lặng; refresh token cùng scope không tự mất mốc. ACK
cục bộ được nhớ có giới hạn để response đọc trễ không báo lại hành động của chính
người dùng. Không có polling trong background hoặc thông báo hệ điều hành.

## Vòng đời và xác thực

`App` mount `realtimeBootstrapProvider` một lần và chuyển lifecycle qua
`realtimeForegroundProvider`. Widget cảnh báo chỉ quan sát state và REST controller.
Mỗi scope có một polling controller dùng chung. Chế độ WebSocket mới mở transport;
một `RealtimeConnectionService` sở hữu một transport, subscription và retry timer.
Rebuild/đổi tab không tạo thêm socket hoặc polling loop.

`realtimeBindingProvider` tạo một snapshot bất biến từ auth, coordinator/polling theo scope,
công tắc, foreground và config. Bootstrap chỉ nghe snapshot đã được giải quyết đầy
đủ; callback cấu hình connection dùng giá trị được truyền vào, không đọc lại từng
provider đang rebuild. Điều kiện hiện thông báo và scope của notice controller
cũng lấy từ snapshot này để tránh nhiều nhánh cập nhật chéo trong cùng lượt scheduler.

Coordinator/polling chỉ phát notice qua listener của feature. Bootstrap đăng ký listener
cho controller hiện tại và gỡ khi đổi scope/dispose, rồi kiểm tra điều kiện trước
khi cập nhật notice controller. Provider tạo coordinator không đọc ngược các
provider giao diện vốn phụ thuộc vào coordinator. Các provider binding/eligibility/
bootstrap được đặt tên để log Riverpod dễ xác định hơn.

Login/restore chỉ chạy cập nhật khi auth, tenant và entitlement đã sẵn sàng. Trong
chế độ WebSocket, refresh token đóng socket cũ rồi tạo CONNECT mới bằng token mới. Callback có epoch
và kiểm tra đúng transport, không để callback cũ phục hồi kết nối mới.

`SessionRefreshCoordinator` được tách từ single-flight trong AuthInterceptor và
dùng chung cho REST, restore session và socket. REST 401 và TOKEN_EXPIRED đồng thời
chia sẻ một request refresh. 401 trễ của token cũ dùng phiên đã refresh; request
từ auth generation cũ không được retry bằng tài khoản mới.

Khi logout, snapshot auth mới dừng realtime qua scheduler và hủy retry/heartbeat/listener,
đồng thời bảo vệ storage trước refresh/login/logout trả về trễ. Request refresh
cũ không ghi token vào phiên mới; logout cũ không xóa token của lần login sau.

Background dừng polling, đóng socket và hủy timer debounce. Resume bắt đầu polling
với mốc im lặng hoặc kết nối lại WebSocket nếu đủ điều kiện. Resync REST vẫn phục
vụ controller đang tồn tại kể cả khi công tắc tắt; OFF không chạy vòng polling
định kỳ. Không có background service hay push.

Phần còn lại của mục xác thực này mô tả riêng transport WebSocket:

Reconnect dùng exponential backoff có jitter 75–100%, trần 30 giây và chỉ một timer.
Handshake/CONNECT có deadline 15 giây; heartbeat incoming có ngưỡng dung sai 2 lần
khoảng thương lượng. Khi đóng không chờ broker receipt vô hạn.

Lỗi handshake, STOMP ERROR, close, network và heartbeat có loại riêng. Chỉ giữ
stable code allowlist từ field `code` hoặc close reason khớp chính xác; không log
raw frame, JWT, body lỗi, SQL hoặc stacktrace để suy luận quyền.

- UNAUTHORIZED/TOKEN_EXPIRED gọi refresh dùng chung, giới hạn một lần trong chu kỳ
  lỗi liên tục; kết nối ổn định 30 giây đặt lại budget. Refresh lỗi mạng thì backoff.
- FORBIDDEN/FEATURE_NOT_ENTITLED/SUBSCRIPTION_NOT_ACTIVE chặn channel và revalidate
  quyền/entitlement qua auth hiện có. Cùng grants bị từ chối không retry vô hạn;
  không tự refresh JWT để vượt quyền. Channel khác vẫn có policy độc lập.
- ACCOUNT_INACTIVE/RESTAURANT_INACTIVE dừng kết nối và đi qua kiểm tra auth.
- REALTIME_PROTOCOL_VIOLATION hoặc close 1008 không có stable reason dừng retry
  tự động cho cấu hình đó; không đoán token hết hạn.
- REALTIME_CONNECTION_LIMIT và lỗi mạng/close khác dùng backoff.

Socket lỗi không tự logout, xóa dữ liệu hay hiện dialog/snackbar lặp. Auth flow
quyết định phiên hết hạn. UI có công tắc và trạng thái cập nhật tự động;
REST và nút tải lại luôn hoạt động theo quyền.

## Event → REST trong chế độ WebSocket

`RealtimeEnvelope` parse JSON an toàn. Handler inventory chỉ nhận schemaVersion=1,
type=INVENTORY_LOW_STOCK_ALERT_CHANGED, resourceType=LOW_STOCK_ALERT, có identity,
version không âm và payload warehouse/ingredient/status hợp lệ. Payload không
được chuyển thành InventoryAlert DTO. Unknown type/schema hoặc JSON hỏng bị bỏ qua.

Coordinator theo scope giữ tối đa 512 eventId và 512 alert-version, TTL 10 phút;
version so theo alert ID, không theo ingredientId, occurredAt hoặc replay cursor.
Đợt cảnh báo mới version 0 vẫn được nhận khi đợt cũ cùng nguyên liệu version lớn.
Burst vượt số ID chờ tối đa chuyển thành một signal resync toàn danh sách.

Sự kiện được gom trong cửa sổ 400 ms, phát `InventoryChangeKind.alertSync` với tập
alert ID; list tải trang hiện tại và detail chỉ tải khi đúng ID. Resync dùng tập
rỗng để chỉ tất cả alert đang quan sát. Không append/prepend event vào phân trang.
Giữ filter/sort/tab; nếu trang hiện tại hết dữ liệu, dùng quy tắc lùi về trang hợp lệ
của controller hiện có.

Event đến trong GET được đánh dấu pending. GET hiện tại xong thì có đúng một
trailing refresh cho các invalidation đang chờ. Generation loại HTTP response của
query/scope cũ. Lỗi GET giữ dữ liệu, hiện lỗi và cho phép tải lại; resync sau resume/
reconnect bỏ qua dedupe event nên vẫn lấy được snapshot mới.

Sau CONNECTED: đăng ký lại channel rồi resync REST. Không giả định receipt, replay
hay snapshot REST và subscribe là transaction atomic. Không tự cộng/trừ badge,
balance, reserved hoặc tạo/resolve cảnh báo. Hiện app chưa có badge OPEN toàn cục,
không thêm endpoint count/bulk ACK.

ACK thành công phát local event kèm version REST. Coordinator ghi nhận version và
loại hint socket trùng đang chờ; không có toast lần hai. ACK xung đột tự GET detail,
không tự POST lại. Nếu GET vẫn trả OPEN với version cũ thì tiếp tục yêu cầu kiểm tra
trước thao tác. RESOLVED không ACK. ACKNOWLEDGED chỉ là đã xem, vẫn có thể thiếu hàng.

Current metrics nullable giữ nguyên semantics. REST cùng alert.version vẫn được
chấp nhận vì currentQuantity/reservedQuantity/availableQuantity/min có thể đổi
mà lifecycle version không đổi. Không dùng channel này làm live-stock feed.

## Thông báo nhỏ trong app

Khi đang bật **Cập nhật tự động**, app ở foreground, socket đã kết nối và tài khoản
còn quyền/feature đọc cảnh báo, sự kiện **OPEN của một alert ID mới** hiện thông báo
nhỏ trên màn hình hiện tại, kể cả khi đang ở chức năng khác. Không đợi một lượt
kiểm tra REST định kỳ. Dedupe eventId/version giữ giới hạn 512 ID và TTL 10 phút;
cập nhật version/status của cùng đợt không tạo thông báo mới. Đợt mới cùng nguyên
liệu nhưng khác alert ID vẫn có thể được báo. Nếu chọn polling riêng, lần lập mốc
đầu/resume/OFF→ON không báo các cảnh báo đang tồn tại.

Polling gom kết quả mới của một lượt thành một thông báo; WebSocket dùng cửa sổ
gom **400 ms** cùng REST invalidation. Nếu có đợt khác đến khi thông báo còn hiện, danh sách ID
được hợp nhất vào thông báo đó, không xếp hàng nhiều popup. Thông báo tự đóng sau
**5 giây** kể từ lần thêm ID mới; event trùng không kéo dài thời gian hiển thị.
Tối đa giữ 512 ID; khi vượt giới hạn dùng câu chung thay vì báo số lượng chính xác.

- Một đợt: **Có cảnh báo tồn thấp mới.**
- Nhiều đợt: **Có N cảnh báo tồn thấp mới.**
- Vượt giới hạn gom: **Có nhiều cảnh báo tồn thấp mới.**

Không lấy tên nguyên liệu/kho từ event để dựng nội dung, không GET thêm metadata
chỉ để hiện thông báo. Các GET list/detail đang mở vẫn thực hiện theo cơ chế
invalidation hiện có. Thông báo là gợi ý dữ liệu thay đổi, không thay thế REST hay
cam kết trạng thái OPEN còn nguyên tại thời điểm người dùng nhấn Xem.

Máy tính/tablet hiển thị ở **góc phải phía dưới**, rộng tối đa **420 px**; điện
thoại dùng phần chiều rộng khả dụng với lề 16 px và safe area. Vị trí tránh bàn
phím, nội dung có thể xuống dòng/cuộn khi chữ lớn. Không chặn thao tác phần còn
lại của màn hình. Có nút đóng, nút **Xem** tối thiểu cao 48 px và live region cho
trình đọc màn hình. Không phát âm thanh hoặc thông báo hệ điều hành.

Nhấn **Xem** đóng thông báo rồi điều hướng qua GoRouter hiện có:

- Một alert ID: mở chi tiết cảnh báo đó.
- Nhiều ID hoặc bị giới hạn gom: mở **Kho → Cảnh báo**.

Điều hướng vẫn đi qua kiểm tra quyền và `onExit`; nếu đang nhập kiểm kê chưa lưu,
app vẫn yêu cầu xác nhận trước khi rời màn hình. Nếu người dùng chọn ở lại, màn hình nhập
liệu giữ nguyên, thông báo đã được đóng. Không dùng navigator riêng để vượt guard.

ACKNOWLEDGED, RESOLVED và ACK cục bộ không tự tạo thông báo. Lập mốc polling hoặc
resync/reconnect/resume của WebSocket không báo lại lịch sử. Trong chế độ WebSocket,
nếu OPEN đang chờ gom được ACK/RESOLVED hoặc ACK cục bộ trước khi hết 400 ms, ID đó
bị loại khỏi thông báo chờ. Khi vượt giới hạn giữ ID, nếu toàn bộ ID còn giữ đã
được xử lý, bỏ thông báo thay vì báo dựa riêng vào các ID tràn không còn theo dõi.

Tắt công tắc, vào nền, logout, đổi tài khoản/tenant hoặc mất quyền/feature sẽ xóa
thông báo đang hiện; callback của scope cũ không được hiện lại. Trong chế độ
WebSocket, mất kết nối cũng xóa thông báo; OPEN chờ bị xóa khi tắt/vào nền/dispose
hoặc resync. Polling resume lập mốc mới; WebSocket reconnect/resume tải lại REST
để đồng bộ hiện trạng, không phát lại thông báo cũ. Đây là thông báo tạm trong
app, không phải hộp thư lịch sử hoặc kênh bảo đảm nhận đủ mọi sự kiện.

## File triển khai

| Nhóm | File chính |
| --- | --- |
| Config | `core/config/environment.dart`, `core/realtime/realtime_config.dart` |
| Tùy chọn thiết bị | `core/realtime/realtime_preference_storage.dart`, `realtime_settings_controller.dart` |
| Transport | `core/realtime/realtime_transport.dart`, `stomp_codec.dart`, `stomp_websocket_transport.dart` |
| Connection/envelope | `core/realtime/realtime_connection_service.dart`, `realtime_envelope.dart` |
| DI/lifecycle | `app/realtime_providers.dart`, `app/providers.dart`, `app/app.dart` |
| Auth dùng chung | `core/network/session_refresh_coordinator.dart`, `auth_interceptor.dart`, `api_client.dart`, `core/auth/session_events.dart`, auth controller/repository |
| Inventory | `inventory_alert_realtime_coordinator.dart`, `inventory_events.dart`, alert list/detail controller, `inventory_alert_sync_status.dart`, list/detail widget |
| Polling REST tùy chọn | `inventory_alert_polling_controller.dart`, `inventory_alert_polling_providers.dart` |
| Thông báo trong app | `inventory_alert_notice.dart`, `inventory_alert_notice_controller.dart`, `inventory_alert_notice_providers.dart`, `inventory_alert_notice_overlay.dart` |

Các file inventory nằm trong `lib/features/inventory/presentation/`. Domain,
REST DTO/repository/use case, route và nghiệp vụ kho giữ contract hiện tại.
`web_socket_channel` 3.0.3 và `fake_async` 1.3.3 được khai báo trực tiếp từ các phiên
bản đã có trong lockfile; không nâng dependency khác. Adapter STOMP triển khai
subset đọc theo [đặc tả STOMP 1.2](https://stomp.github.io/stomp-specification-1.2.html),
gồm UTF-8/content-length, frame chia nhỏ/gộp, escaping, CRLF và heartbeat.

## Kiểm thử và giới hạn

Unit/controller/widget test dùng fake transport, fake_async và Completer, gồm:
policy/flag/auth lifecycle, một socket, header/subprotocol/heartbeat, phiên cũ,
single-flight REST+socket, stop/retry/backoff, mã lỗi terminal, dedupe/TTL/version,
burst/trailing GET, thất bại GET/resync, ACK đồng thời event, null/same-version
metrics và UI giữ filter. Widget test mount App thật để kiểm tra lifecycle observer.

Thông báo trong app bổ sung kiểm thử gom OPEN/chống lặp, ACK/RESOLVED trước khi
flush, không báo do resync, giới hạn bộ nhớ, timer 5 giây, gộp thông báo đang hiện,
dọn theo scope/eligibility và điều hướng qua guard nhập liệu. Widget test còn kiểm
tra chuột trên nút đóng, màn hình 320/800 px với chữ phóng to và bàn phím đang mở.

Kết quả xác minh theo từng mốc triển khai (các số dưới đây là lịch sử):

- Formatter theo convention dự án; không tắt lint.
- `flutter analyze`: **No issues found**.
- Trước khi bổ sung công tắc: `flutter test --reporter expanded` đạt **851/851**
  kiểm thử toàn dự án, gồm 51 kiểm thử mới về realtime và race xác thực liên quan.
- Sau khi bổ sung công tắc/lưu tùy chọn: **68/68** test realtime/settings/controller/
  widget và **10/10** test App/điều hướng đạt; `dart analyze` không có lỗi.
  Có thêm 10 test cho tùy chọn, hydration, lỗi lưu, bật/tắt và REST fallback.
- Sau khi bổ sung thông báo trong app: `dart analyze` không có lỗi và
  `flutter test --reporter expanded` đạt **894/894** kiểm thử toàn dự án.
  Phần thông báo có thêm **33** kiểm thử (16 coordinator/model, 5 controller,
  12 widget) về gom sự kiện, lifecycle, điều hướng và bố cục.
- Sau khi sửa luồng provider realtime/thông báo: `dart analyze` không có lỗi và
  toàn bộ **912/912** kiểm thử đạt. Bổ sung 13 kiểm thử: 2 listener coordinator,
  7 trường hợp rebuild/thứ tự khởi tạo notice và 4 trường hợp chi tiết đơn dùng
  App/router thật khi đổi token/quyền/tenant/logout. Kiểm thử fake thời gian chờ
  lượt scheduler của Riverpod bằng `clock.elapse(Duration.zero)`.
- Tại mốc thử polling làm mặc định trước khi quay lại push: **88/88** kiểm thử chọn lọc đạt. Phân tích
  mã không có lỗi và bộ kiểm thử toàn dự án tại mốc tích hợp đạt **942/942**.
  Sau khi bổ sung bảo vệ form khi phục hồi quyền và khởi động lại polling sau
  một lần bị từ chối quyền, **29/29** kiểm thử controller/chi tiết đơn đạt;
  `dart analyze` tiếp tục không có lỗi. Hai kiểm thử bổ sung chưa chạy lại trong
  toàn bộ bộ kiểm thử; đã chạy trong nhóm kiểm thử liên quan nêu trên.
- Khi khôi phục WebSocket mặc định ngày 24/10/2026: `dart analyze` không có lỗi;
  toàn bộ **945/945** kiểm thử Flutter đạt, gồm kiểm tra không có REST polling
  định kỳ khi dùng cấu hình mặc định và popup xuất hiện từ OPEN push sau 400 ms.
  Backend đạt **35** unit/wiring test và **4** native WebSocket integration test,
  gồm commit/rollback, tenant, JSON, từ chối truy cập, Origin web và dọn subscription.
- Thay đổi lockfile chỉ chuyển web_socket_channel/fake_async từ transitive thành
  direct dependency; giữ nguyên các phiên bản.

Đã sửa lỗi build web trong `lib/features/tables/domain/validation/table_validation.dart`:
cả 5 kiểm tra `expectedVersion` dùng chung giới hạn số nguyên an toàn
9007199254740991 (`2^53 - 1`), giữ độ chính xác khi gửi JSON trên native và web.
Sau thay đổi này, `dart analyze` không có lỗi; **49/49** kiểm thử module bàn đạt,
gồm 5 kiểm thử biên mới. Lệnh
`flutter build web --no-pub --dart-define=REALTIME_ENABLED=true` thành công,
artifact tại `build/web`. Build thành công chưa thay thế kiểm thử kết nối BE thực tế.

Nếu một phiên debug đã gặp lỗi `Tried to rebuild ... multiple times in the same
frame` hoặc provider ở error state, dừng app và chạy lại sau khi nhận bản sửa.
Hot reload có thể giữ trạng thái provider/scheduler lỗi của phiên cũ.

Backend trong repository `pos-saas-be` đã bổ sung native STOMP `/ws`, CONNECT Bearer,
heartbeat, user queue, kiểm tra tenant/quyền/features và phát event sau commit.
Contract và hướng dẫn thử tại `pos-saas-be/docs/inventory-alert-realtime.md`.
Cần khởi động lại backend và app; nếu cấu hình chạy còn
`REALTIME_TRANSPORT=polling`, bỏ cấu hình đó hoặc đổi thành `websocket`.
Kiểm thử native WebSocket dùng server thực ở cổng ngẫu nhiên và context không
datasource đã nhận đúng JSON, xác minh cô lập tenant, rollback không gửi và từ chối
anonymous/SEND/raw queue. Chưa thử hai thiết bị thật trong môi trường triển khai.

Thử thật ở môi trường test với backend đã hỗ trợ WebSocket:

1. Hai thiết bị A/B cùng tenant, đủ quyền đọc, bật **Cập nhật tự động** trong app.
   Đợi kết nối thành công, thấy **Đang tự động cập nhật cảnh báo.**
   Ở môi trường test, tạo đợt cảnh báo tồn thấp mới bằng nghiệp vụ kho hợp lệ;
   sau khi transaction commit, B phải nhận sự kiện và hiện thông báo cho đợt mới
   còn OPEN dù đang ở màn hình khác, không chờ 20 giây. Cảnh báo đã có trước lúc
   kết nối không tự tạo popup chỉ vì tải lại danh sách.
   Thử một/nhiều cảnh báo,
   tự ẩn sau 5 giây, đóng thủ công, Xem đúng chi tiết/danh sách, màn hình nhỏ và
   lúc mở bàn phím. Khi đang sửa kiểm kê, Xem vẫn phải đi qua xác nhận rời màn hình.
2. A nhấn Đã xem. B phải GET lại và hiển thị ACKNOWLEDGED; không phát POST từ B
   hoặc hiện thêm thông báo mới do ACK. Trong polling, đợt đã ACK trước lượt đọc
   không hiện popup mới; với WebSocket, OPEN đã ACK trước khi hết cửa sổ gom
   400 ms không được hiện thành thông báo chờ.
3. Dùng luồng nhập hàng hợp lệ ở môi trường test để backend RESOLVED; B cập nhật
   qua GET và vẫn đọc được lịch sử. Không nhập hàng bằng socket.
4. Thiết bị C tenant khác không nhận event/data. Thử staff chỉ có VIEW, không ACK.
5. Ngắt mạng B, đổi trạng thái ở A, nối lại B: polling retry theo backoff và GET
   hiện trạng khi thành công; nếu resume thì lập mốc mới im lặng. Với WebSocket,
   B subscribe rồi REST resync. Không kỳ vọng mọi cảnh báo trong thời gian offline
   đều tạo popup khi quay lại.
6. Đưa B vào nền rồi resume; logout/login tài khoản khác; thu hồi quyền/feature.
   Kiểm tra thông báo cũ được đóng, không phát lại sau reconnect/resume, không
   còn event cũ, subscription trùng hoặc retry terminal liên tục. Tắt công tắc
   trong app cũng phải đóng ngay thông báo đang hiện.

Đây là cập nhật foreground best-effort, không bảo đảm bắt mọi đợt, không replay,
không push/notification inbox/âm thanh và không có realtime order trong lần này.
