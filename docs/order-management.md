# ORDER trên app Flutter

## Phạm vi và kiến trúc

App tích hợp 10 endpoint trong pos-saas-be/docs/order-api.md và OpenAPI ORDER, gồm active-order theo phiên.
Giữ Widget → ChangeNotifier controller → use case → repository → remote → Dio.
Domain không import Flutter/Dio/Riverpod. Không thêm dependency.
Menu và tables là dependency đọc, không sao chép màn CRUD. ORDER hub không mở phiên qua HTTP; backend mở phiên khi POST tableId+SUBMIT thành công.

- domain/entities: summary/detail/dòng, enum, input, query, quantity chính xác.
- domain/policies: eligibility của action và validation.
- data/dto: response trực tiếp, serializer allowlist, không fallback version.
- data/repositories: Result/Failure và INVALID_ORDER_RESPONSE.
- presentation/controllers: hub, picker, draft, list, detail độc lập.
- submission: OrderSubmissionMode và OrderSubmission (order + replay metadata),
  input append bất biến, OrderAppendController riêng cho giỏ gọi thêm và frozen intent.
- presentation/providers: scoped Riverpod legacy và bounded access recovery.
- presentation/screens/widgets: grid, composer, detail và form.
- test/features/order: fake repositories/server, unit/controller/widget/golden.

Các điểm tích hợp: app providers/app/router, AccessPolicy, error mapper,
sidebar filter và AppShell. Giữ cashier/super-admin web-only, theme toàn app.

## Route và UI

- /app/order-create: hub gọi món. Tất cả / Sử dụng / Còn trống,
  chip khu vực thực tế, grid 2 cột điện thoại, card hồng/icon cam theo ảnh.
- /app/order-create?serviceType=TAKEAWAY: composer mang đi.
- /app/order-create?tableId=<uuid>: kiểm bàn/active-order, giỏ local và SUBMIT deferred seating.
- /app/order-create?tableSessionId=<uuid>: kiểm tra phiên OPEN và bàn thực tế
  rồi mở composer legacy, tab Lịch sử trong phiên khi có ORDER_VIEW.
- /app/order-create/bill/:orderId: màn chi tiết đơn phục vụ trong luồng Gọi món (sidebar giữ Gọi món).
- /app/order-create/bill/:orderId/add-items: màn chọn món gọi thêm vào order hiện tại qua FAB (+) (sidebar giữ Gọi món).
- /app/orders: tìm mã, trạng thái/loại đơn/sort/phân trang (sidebar chọn Đơn hàng).
- /app/orders?tableSessionId=<uuid>: các đơn trong phiên.
- /app/orders/<orderId>: chi tiết đơn lịch sử (sidebar chọn Đơn hàng).

Tên không hardcode. Sử dụng/Còn trống lọc occupied trên snapshot đã tải đủ các trang,
không đổi TableStatus AVAILABLE/INACTIVE. Khu vực active được tải đủ các trang.
Mang đi là action tile, không có table/session và không tính occupancy.
Không bịa tổng tiền/số món, không GET session/order cho từng card.
Một phiên có nhiều historical orders nhưng tối đa một serving order.

## Quyền và feature

Mọi ORDER cần restaurant hợp lệ, subscription ACTIVE và ORDER_MANAGEMENT.
Không suy từ tên package, không cấp OWNER bypass.

| Action | Permission / dependency |
| --- | --- |
| Danh sách/GET detail | ORDER_VIEW |
| Tạo nháp DRAFT | ORDER_CREATE; DINE_IN thêm TABLE_MANAGEMENT; TAKEAWAY thêm POS_QUICK_ORDER |
| Gửi đơn SUBMIT | ORDER_CREATE + ORDER_UPDATE; feature theo loại đơn như trên |
| Gọi thêm SUBMIT vào OPEN/CONFIRMED | ORDER_UPDATE; DINE_IN thêm TABLE_MANAGEMENT, TAKEAWAY thêm POS_QUICK_ORDER |
| Sửa thông tin/món đã lưu của OPEN, confirm legacy | ORDER_UPDATE |
| Hủy dòng chưa confirm | ORDER_UPDATE |
| Hủy dòng đã confirm | ORDER_CANCEL; boundary confirmedAt |
| Hủy đơn | ORDER_CANCEL |
| Chọn món private | MENU_VIEW + MENU_MANAGEMENT |
| Xem bàn/khu vực/phiên | TABLE_VIEW + TABLE_MANAGEMENT |
| Mở phiên | TABLE_OPEN + quyền đọc bàn |
| Create tableId mở mới | ORDER_CREATE + ORDER_UPDATE + TABLE_OPEN; TABLE_OPEN không cần nếu dùng OPEN session cũ |

Route/sidebar/widget/controller kiểm tra; backend quyết định cuối.
Thiếu quyền bàn vẫn tạo TAKEAWAY nếu các quyền khác hợp lệ.
Thiếu MENU_VIEW không né qua API public. Create-only hiển thị response tạo
trong composer, không bắt buộc redirect/GET detail cần ORDER_VIEW.
SourceChannel app WAITER cho cả hai loại, không tạo quyền.
CASHIER vẫn dùng web. Không nhận QR ordering trên app này.

## Luồng nghiệp vụ

Màn Gọi món đọc đủ các trang bàn AVAILABLE, không dùng occupied=false hoặc
canOpen=true để lọc bàn active. Tabs Tất cả/Sử dụng/Còn trống và khu vực lọc snapshot
đã tải; bàn có phiên chưa có đơn vẫn occupied. Tên bàn/khu vực và total lấy server.

Số tiền card là totalAmount + currencyCode của serving order gắn currentSession.id.
Serving statuses: OPEN/CONFIRMED/PREPARING/READY/SERVED; CANCELLED/COMPLETED chỉ
lịch sử. Lấy đủ trang GET /orders?serviceType=DINE_IN theo từng status, tối đa ba
status streams đồng thời; không HTTP per-card, không quét lịch sử hoặc cộng các bill.
Dedup cùng orderId theo version; nhiều orderId/session đánh dấu cần đối chiếu,
không chọn latest/first. Failed/incomplete snapshot là unknown, không giả tiền 0.
Total 0 thực sự vẫn là bàn có đơn. Các GET không phải snapshot transaction/realtime.

Nhấn bàn: đọc detail mới, có phiên thì GET active-order. 200 mở trực tiếp detail;
204 mở composer từ tableId nếu đủ quyền. Lỗi không trở thành “không có đơn”. Bàn
trống chỉ mở giỏ local, không POST mở phiên. Nhấn Gửi đơn mới POST /orders với
tableId+SUBMIT; backend dùng phiên OPEN hoặc tạo phiên mới cùng order. Không có
/orders/from-table. Nếu phiên đã có serving order, create bị 409, giữ giỏ và kiểm tra
đơn của bàn; không auto-append/chuyển target. Cancel order không tự làm bàn trống.

Context identity phân biệt table/session/takeaway, gồm target kind + ID; display
metadata/open-seating hint không đổi identity. tableId serializer không gửi sessionId;
guestCount optional để backend dùng guestCount phiên hiện tại hoặc default 1 khi mở mới.
Không biến hint số khách hoặc sessionId từ GET thành dữ liệu frozen intent.
Legacy session composer vẫn dùng phiên OPEN thực tế, không tự thay thế phiên đã kết thúc.
Tab “Lịch sử trong phiên” là history, không phải chọn một trong nhiều bill đang phục vụ.

Mang đi: không gọi bàn/khu vực/phiên; tableSessionId=null, tên/số điện thoại
tùy chọn, guestCount mặc định 1.

Giỏ local chưa là order. Chọn món sellable; mỗi dòng có ID draft riêng,
không tự gộp món khác ghi chú. Quantity exact thousandths, giá MenuPrice
hundredths. Preview BigInt HALF_UP từng dòng, không double.
Preview không đoán currency khi menu response chưa cung cấp profile;
order đã lưu dùng currencyCode/tổng và snapshot backend.

Nút chính “Gửi đơn” gửi submissionMode=SUBMIT: tạo + xác nhận một HTTP request,
cần CREATE+UPDATE; không gọi /confirm lần hai. tableId không có nút Tạo nháp.
“Tạo nháp” gửi DRAFT rõ ràng cho legacy session/TAKEAWAY,
giữ luồng OPEN/confirm legacy cho người chỉ có CREATE; không silently downgrade.
Absent/null mode là DRAFT trên backend; serializer legacy vẫn bỏ field mode.

FAB dấu “+” (tooltip Gọi thêm món) trên detail mở giỏ append hiện có, đặt trong content
Stack dưới sidebar overlay, không Scaffold/AppBar lồng. SafeArea và scroll padding
không che dòng cuối/tổng tiền. Fresh FAB chỉ hiện khi canAppend + menu access và
không busy/loading/verification; unknown append vẫn có entry mở lại giỏ/retry.
“Gọi thêm món” gửi SUBMIT đến /orders/{selectedOrderId}/items, dùng key riêng và
baseline Order.version. Hỗ trợ tại bàn và mang đi, không cần ORDER_CREATE để
append. DINE_IN vẫn cần phiên OPEN/seating hợp lệ do backend kiểm tra.
Giỏ 1–100 dòng mới độc lập, quantity/note/preview riêng; không merge/reprice hoặc
reset trạng thái dòng cũ. OPEN+SUBMIT append và confirm atomically, backend recheck
mọi dòng live; món cũ không sellable cũng có thể làm cả thao tác bị từ chối.
CONFIRMED+SUBMIT giữ confirmedAt và lịch sử cũ. canAppend tách khỏi canEdit:
metadata và quantity/note của saved lines vẫn chỉ OPEN/PENDING.
Auto-confirm khiến hủy mọi dòng (kể cả mới thêm) cần ORDER_CANCEL theo confirmedAt.
Không giả lập gửi bếp. Dòng CANCELLED giữ gross snapshot, không cộng vào
tổng hiệu lực; root total lấy backend. Hủy order không làm bàn trống.

Dialog giữ baseline/version khi mở, background refresh không ghi đè giỏ.
Business refusal đã xác định giữ giỏ và yêu cầu người dùng tải hiện trạng,
đối chiếu rồi chủ động chọn dữ liệu mới; không tự đổi version rồi retry.
Nếu conflict version, phải có root version mới trước khi xác nhận đối chiếu.
Không fallback create khi append lỗi.

## API và concurrency

Dùng authenticated Dio/interceptor hiện có gắn Bearer và refresh single-flight.
Path /api/v1/orders, response trực tiếp, mutation child dùng orderItemId.

| Method | Path sau /api/v1/orders |
| --- | --- |
| GET | / và /{id} |
| POST | / với Idempotency-Key |
| PATCH | /{id} |
| POST | /{id}/items |
| PATCH | /{id}/items/{lineId} |
| POST | /{id}/confirm |
| POST | /{id}/items/{lineId}/cancel |
| POST | /{id}/cancel |

Ngoài base ORDER: GET /api/v1/table-sessions/{id}/active-order, 200 detail hoặc 204
không body. 403/404/409/parse failure là Error, không phải no-order. HTTP adapter
kiểm serviceType/session/status của response, không sử dụng root trả về sai session.

Workspace VIEW và CREATE được tách: chỉ VIEW vẫn vào hub/đọc bill nếu có TABLE_VIEW,
không cần MENU_VIEW/ORDER_CREATE. Sidebar có OR permission VIEW/CREATE; composer
tableId vẫn yêu cầu SUBMIT capability. Không QUERY/private money khi thiếu ORDER_VIEW.
TABLE_OPEN chỉ cần khi fresh create phải mở phiên mới, không cần append hoặc dùng
phiên OPEN cũ. CanOpen không phải quyền và không dùng để loại bàn occupied.
Source WAITER/CASHIER không cấp quyền; CASHIER/SUPER_ADMIN vẫn web-only.

Create và append SUBMIT key UUID v4 từ Random.secure, inject/fake được.
Chốt input bất biến + key trước submit, khóa double tap.
Timeout/500/parse lỗi: kết quả chưa xác định, khóa sửa giỏ/rời luồng;
kiểm tra lại đúng key/payload. 401 retry giữ nguyên request.
Replay 200 trả representation hiện tại; không ép OPEN/version=0.
SUBMIT mới CONFIRMED, lines PENDING và sentToKitchenAt=null. Replay có thể trả
root đã CANCELLED hoặc version cao hơn; luôn dùng toàn bộ representation server.
OrderSubmission giữ replayed=true/false, null nếu header bị thiếu (không bịa
metadata); header sai giá trị/body malformed trả INVALID_ORDER_RESPONSE.
IDEMPOTENCY_KEY_REUSED không tự đổi key. Từ chối business đã xác định:
người dùng sửa giỏ rồi tạo lại.

Append SUBMIT đóng băng targetId + scope + expectedVersion + mode + ordered lines
+ một key. Timeout/network/5xx/parse lỗi: kiểm tra lại đúng key/payload/version gốc,
kể cả GET đã thấy version/status mới, menu đổi hay phiên đã đóng. Retry chỉ kiểm
authority/scope/type feature; không chạy lại mutable canAppend/menu/seating guard.
GET không resolve unknown outcome; chưa resolve thì chặn append intent mới và
mutation khác trên cùng order. 401/403 sau timeout không chứng minh lần trước thất
bại. Key conflict giữ intent, không sinh key mới/retry mù; cần đối chiếu quản lý.

OrderAppendController/provider theo scope giữ intent trong bộ nhớ, keepAlive lúc
busy/uncertain; dialog teardown/rebuild không làm mất key. Exit guard và PopScope
chặn bỏ unknown intent. Token rotation cùng scope giữ giỏ; authority/tenant đổi
reset state và bỏ late response. Khi resolve thành công, release pin, dùng response
id/version/status/totals, invalidate list/session; không tự cộng version.

DRAFT append vẫn chỉ OPEN, không ledger/key retry. PATCH/cancel/confirm legacy
giữ policy version/verification riêng. Tải root để đối chiếu trước action mới,
không blind retry. Error mapper giữ code/fieldErrors.

Scope identity/tenant/permissions/features/subscription không chứa token:
rotation giữ giỏ; logout/quyền/tenant đổi hủy state, bỏ response trễ.
OrderEvents invalidate list/detail liên quan, không tự gán occupied=false.
Workspace nghe cả ORDER/TABLE events, coalesce refresh 120ms, có pull refresh và
refresh sau khi quay lại grid. Generation/scope guard bỏ response cũ và dừng khởi
tạo trang/status request mới khi scope đã đổi. Dữ liệu có thể stale giữa các GET;
chọn bàn và backend command vẫn revalidate cuối cùng.

Create từ tableId freeze nguyên tableId/key/mode/ordered payload. Retry không đổi
sang sessionId mới. Known table refusal khóa fresh send, giữ giỏ; “Kiểm tra đơn
của bàn” chỉ đọc/đối chiếu, không append tự động. Chỉ sau xác nhận trạng thái mới
không còn serving order mới cho fresh intent. Key conflict không sinh key/retry mù.

## Kiểm tra thủ công

1. Login tài khoản app có quyền/feature phù hợp.
2. Gọi món: kiểm tra khu vực/filter/card Mang đi.
3. Bàn trống chọn món chưa mở phiên; bàn có bill mở thẳng detail, kiểm tiền trên card.
4. Thêm món, quantity/note/thông tin khách, “Gửi đơn”: thấy CONFIRMED, không gửi bếp.
5. “Tạo nháp” chỉ legacy session/TAKEAWAY; giữ OPEN và confirm legacy.
6. FAB “+” trên OPEN/CONFIRMED gọi thêm nhiều dòng vào cùng id; kiểm snapshots cũ.
7. Hủy dòng/đơn theo quyền, kiểm tra snapshot đã hủy.
8. TAKEAWAY không cần quyền bàn.
9. Timeout tạo/gọi thêm: retry cùng key/payload, chỉ một mutation; GET không mở intent mới.
10. Hai client sửa: conflict không ghi đè/nhân đôi dòng.
11. Keyboard/320px/text scale/token refresh/logout.

## Verification — SUBMIT / gọi thêm, 09/10/2026

    dart format <chỉ các file Dart đã sửa>
    flutter analyze --no-pub
    flutter test --no-pub --reporter expanded
    flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:8080

Kết quả xác minh ngày 09/10/2026 trên bản source cuối:

- dart format: đã định dạng file nguồn/test thay đổi.
- flutter analyze: No issues found.
- flutter test --reporter expanded: 211/211 test passed,
  gồm 81 test Order và 130 test hồi quy; bổ sung 31 test cho SUBMIT/replay/UI/provider.
- Baseline trước lượt này: analyzer sạch, 180/180 test pass; không có lỗi baseline.
- Build APK debug thành công với API_BASE_URL=http://10.0.2.2:8080.
  Artifact: build/app/outputs/flutter-apk/app-debug.apk.
- git diff --check: không có lỗi whitespace.

Test fake không gọi backend/database thật, có golden phone.
Golden hiện có giữ nguyên; popup mới có test 320px/bàn phím/text scale,
đã sửa overflow bằng nội dung cuộn. Test bao gồm retry qua token rotation, GET
không resolve unknown outcome, dialog bị tháo khỏi cây và read-side provider
rebuild mà không mất frozen intent, chọn order ở page 2, route exit guard,
mode/permission/feature, read-only fields và response malformed.
Không thêm dependency, không đổi pubspec/lockfile, không sửa BE/Web/database.
APK debug dùng URL Android Emulator 10.0.2.2, không phải URL dùng trực tiếp trên
điện thoại vật lý. Chưa E2E với backend thật hoặc thiết bị vật lý.

Log kiểm chứng được giữ ngoài repo tại:

    C:\Users\Dell\OneDrive\Documents\New project\flutter-order-submit-work-20261009

Các file cuối: verified-analyze.log, verified-full-test.log, verified-apk-build.log.

## Verification — bàn/tiền, deferred seating và FAB, 10/10/2026

Baseline trước sửa: 211/211 test pass, analyzer sạch. Staging và source app thực tế
đều được chạy lại đầy đủ với cùng kết quả:

- flutter analyze --no-pub: No issues found.
- flutter test --no-pub --reporter expanded: 250/250 pass, không skip/exclude test.
- Bổ sung 39 test: 26 domain/data/controller và 13 widget cho bàn/tiền/deferred/FAB.
- Golden order_service_context.png cập nhật có chủ đích: bàn có tiền + bàn trống,
  bỏ pager trong workspace tải đủ trang; đã xem ảnh và kiểm tra overflow bằng widget tests.
- Build APK debug Android thành công với API_BASE_URL=http://10.0.2.2:8080.
- Artifact source thực tế: build/app/outputs/flutter-apk/app-debug.apk.
  URL trên chỉ dành cho Android Emulator; điện thoại vật lý cần URL LAN phù hợp.
- Giữ native TABLE CRUD/manual-open/auth/menu/staff regression. Không dependency mới,
  pubspec/lockfile/lint config và BE/Web không thay đổi.

Trong staging, pub get đã tạo package config/resolve dependency nhưng trả lỗi symlink
Windows desktop do Developer Mode chưa bật. Không đổi system settings. Analyzer,
toàn bộ test và build Android với --no-pub đã chạy thành công; không claim Windows
desktop build đã được kiểm chứng. Ảnh failures chỉ là diagnostics staging, không promote.

Widget test không gọi BE/database thật; chưa E2E trên backend live/thiết bị vật lý.
Read model ghép nhiều GET phân trang, không phải transaction snapshot/realtime.
Tải đủ trang theo page count của lần đọc đầu; concurrent insert/delete/status change
có thể làm snapshot stale. Chọn bàn/command revalidate, refresh lần sau cập nhật lại.
Giỏ và unresolved key vẫn chỉ trong memory, không phục hồi sau process kill.

Log ngoài repo: C:\Users\Dell\OneDrive\Documents\New project\flutter-table-orders-work-20261009
(baseline-test.log, analyze-final-first.log, full-test-first.log, apk-build-first.log,
actual-analyze.log, actual-full-test.log, actual-apk-build.log).
32 file source/test/docs được hash-verified sau promotion, 234 file baseline ngoài
phạm vi byte-identical. Generated Kotlin cache mới của build được chuyển ra staging
để giữ worktree sạch; không xóa code/dữ liệu, cache vẫn có thể lấy lại hoặc tái tạo.

### File của lượt bàn/tiền/FAB

32 file; tách khỏi dirty changes có sẵn trong worktree:

- lib/app/router/app_router.dart
- lib/core/auth/access_policy.dart
- lib/core/network/api_error_mapper.dart
- lib/core/ui/sidebar/app_sidebar_registry.dart
- lib/core/ui/sidebar/sidebar_filter.dart
- lib/core/ui/sidebar/sidebar_menu_item.dart
- lib/features/order/data/data_sources/order_remote_data_source.dart
- lib/features/order/data/dto/order_requests.dart
- lib/features/order/data/repositories/order_repository_impl.dart
- lib/features/order/domain/entities/order_inputs.dart
- lib/features/order/domain/entities/order_table_workspace.dart
- lib/features/order/domain/policies/order_table_policy.dart
- lib/features/order/domain/policies/order_validation.dart
- lib/features/order/domain/repositories/order_repository.dart
- lib/features/order/domain/use_cases/order_use_cases.dart
- lib/features/order/domain/use_cases/order_workspace_use_cases.dart
- lib/features/order/presentation/controllers/order_draft_controller.dart
- lib/features/order/presentation/controllers/order_service_context_controller.dart
- lib/features/order/presentation/providers/order_providers.dart
- lib/features/order/presentation/screens/order_create_screen.dart
- lib/features/order/presentation/screens/order_detail_screen.dart
- lib/features/order/presentation/screens/order_list_screen.dart
- lib/features/order/presentation/screens/order_service_context_screen.dart
- lib/features/order/presentation/widgets/order_append_dialog.dart
- test/features/order/order_controller_test.dart
- test/features/order/order_fakes.dart
- test/features/order/order_table_widget_test.dart
- test/features/order/order_table_workspace_test.dart
- test/features/order/order_widget_test.dart
- test/features/order/goldens/order_service_context.png
- docs/order-management.md
- README.md

## Giới hạn

- Chưa payment/refund/KDS/QR ordering/close bill/recipe/trừ kho/offline sync.
- Giỏ và key unresolved chỉ trong bộ nhớ luồng hiện tại, chưa khôi phục
  sau process kill. Restart cần kiểm tra danh sách đơn/liên hệ quản lý,
  không mặc định gửi lại ý định chưa xác minh.
- Giỏ gọi thêm hỗ trợ 1–100 dòng/request. Không append PREPARING/READY/SERVED
  trước khi backend có KDS/aggregate reconciliation tương ứng.
- IDEMPOTENCY_KEY_REUSED không có API tra ledger cho FE; giữ trạng thái cần
  đối chiếu với người quản lý, không tự bỏ request rồi sinh key khác.
- Chưa E2E với backend thật hoặc thiết bị vật lý.

## Đồng bộ chuyển bàn

Chi tiết đơn DINE_IN có action “Chuyển bàn” trong menu ba chấm khi order có
`tableSessionId`, session mới nhất còn OPEN và tài khoản có đồng thời TABLE_VIEW,
TABLE_TRANSFER, feature TABLE_MANAGEMENT. Đơn TAKEAWAY không tạo controller đọc
session và không hiển thị action. Quyền TABLE_TRANSFER không cấp ORDER_VIEW;
quản lý bàn vẫn chuyển được session chưa có order mà không đọc dữ liệu order.

`tableName` từ query route chỉ là hint ban đầu. Khi tải được session context theo
`sessionId`, tiêu đề chi tiết, phiếu tạm tính và query mở màn gọi thêm dùng tên bàn
từ session. Transfer không thay order.version, orderId, sessionId, danh sách món
hoặc số tiền. FAB “Gọi thêm món” tiếp tục truyền orderId cũ.

Trong lúc chuyển đang gửi hoặc chưa xác định, TableEvents khóa mutation của đúng
session/order: sửa, xác nhận, hủy và gửi giỏ gọi thêm đều bị chặn. Giỏ gọi thêm
chưa gửi không bị xóa. Create/append/order mutation đang gửi hoặc chưa xác định
phải được xử lý trước khi xác nhận transfer. Exit guard giữ người dùng ở luồng
để replay đúng ý định khi cần.

Sau thành công, event refresh danh sách bàn và workspace gọi món. Serving order
vẫn liên kết bằng sessionId, nên occupancy đi sang bàn thực tế trong response và
amount tiếp tục lấy từ ORDER response. Refresh đọc lỗi sau POST 200 không phát
thêm POST transfer.

## File của lượt SUBMIT / gọi thêm

30 file của lượt này (tách khỏi các thay đổi ORDER/auth/sidebar đã có trong worktree):

- lib/app/router/app_router.dart (onExit cho detail; không đổi auth route policy)
- lib/core/auth/access_policy.dart (type feature/submit/append helpers)
- lib/core/network/api_error_mapper.dart (message dùng được cho create và append)
- lib/features/order/data/data_sources/order_remote_data_source.dart
- lib/features/order/data/dto/order_requests.dart
- lib/features/order/data/repositories/order_repository_impl.dart
- lib/features/order/domain/entities/order_inputs.dart
- lib/features/order/domain/entities/order_submission.dart (mới)
- lib/features/order/domain/policies/order_access_policy.dart
- lib/features/order/domain/policies/order_submission_failure_policy.dart (mới)
- lib/features/order/domain/repositories/order_repository.dart
- lib/features/order/domain/use_cases/order_use_cases.dart
- lib/features/order/presentation/controllers/order_append_controller.dart (mới)
- lib/features/order/presentation/controllers/order_detail_controller.dart
- lib/features/order/presentation/controllers/order_draft_controller.dart
- lib/features/order/presentation/controllers/order_events.dart
- lib/features/order/presentation/providers/order_providers.dart
- lib/features/order/presentation/screens/order_create_screen.dart
- lib/features/order/presentation/screens/order_detail_screen.dart
- lib/features/order/presentation/screens/order_list_screen.dart
- lib/features/order/presentation/screens/order_service_context_screen.dart
- lib/features/order/presentation/widgets/order_append_dialog.dart (mới)
- lib/features/order/presentation/widgets/order_exit_guard.dart
- lib/features/order/presentation/widgets/order_mutation_forms.dart
- test/features/order/order_data_test.dart
- test/features/order/order_fakes.dart
- test/features/order/order_widget_test.dart
- test/features/order/order_submission_test.dart (mới)
- README.md
- docs/order-management.md

## File của ORDER ban đầu (lịch sử)

- `lib/features/order/domain/entities/order_entities.dart`
- `lib/features/order/domain/entities/order_inputs.dart`
- `lib/features/order/domain/policies/order_validation.dart`
- `lib/features/order/domain/policies/order_access_policy.dart`
- `lib/features/order/domain/repositories/order_repository.dart`
- `lib/features/order/domain/use_cases/order_use_cases.dart`
- `lib/features/order/data/dto/order_requests.dart`
- `lib/features/order/data/dto/order_dto.dart`
- `lib/features/order/data/data_sources/order_remote_data_source.dart`
- `lib/features/order/data/repositories/order_repository_impl.dart`
- `lib/features/order/data/order_key_generator.dart`
- `lib/features/order/domain/entities/order_quantity.dart`
- `lib/features/order/presentation/controllers/order_events.dart`
- `lib/features/order/presentation/controllers/order_controller.dart`
- `lib/features/order/presentation/controllers/order_draft_controller.dart`
- `lib/features/order/presentation/controllers/order_detail_controller.dart`
- `lib/core/auth/access_policy.dart`
- `lib/features/order/presentation/controllers/order_list_controller.dart`
- `lib/features/order/presentation/controllers/order_menu_picker_controller.dart`
- `lib/features/order/presentation/controllers/order_service_context_controller.dart`
- `lib/features/order/presentation/providers/order_providers.dart`
- `lib/features/order/presentation/widgets/order_widgets.dart`
- `lib/features/order/presentation/widgets/order_menu_picker.dart`
- `lib/features/order/presentation/screens/order_list_screen.dart`
- `lib/features/order/presentation/screens/order_service_context_screen.dart`
- `lib/features/order/presentation/widgets/order_mutation_forms.dart`
- `lib/features/order/presentation/screens/order_detail_screen.dart`
- `lib/features/order/presentation/screens/order_create_screen.dart`
- `lib/app/providers.dart`
- `lib/app/router/app_routes.dart`
- `lib/app/router/app_router.dart`
- `lib/app/router/route_guard.dart`
- `lib/core/ui/sidebar/sidebar_filter.dart`
- `lib/core/ui/shell/app_shell.dart`
- `lib/app/app.dart`
- `lib/core/network/api_error_mapper.dart`
- `lib/features/order/presentation/widgets/order_exit_guard.dart`
- `test/features/order/order_fakes.dart`
- `test/features/order/order_data_test.dart`
- `test/features/order/order_controller_test.dart`
- `test/features/order/order_widget_test.dart`
- `README.md`
- `docs/order-management.md`
- `test/features/order/goldens/order_service_context.png`
- `test/features/order/order_goi_mon_flow_test.dart`

## Luồng Gọi Món & Thiết kế Màn Hình (10/10/2026)

### 1. Luồng Gọi món → Bill → Gọi thêm

1. **Từ Grid Bàn**:
   - Khi nhấn một bàn occupied có active order, app điều hướng trực tiếp tới `/app/order-create/bill/:orderId?tableName=...` (không qua `OrderListScreen` và **không đổi section trên sidebar sang "Đơn hàng"**).
   - Sidebar vẫn làm nổi bật mục **"Gọi món"** (`initialSection: 'order-create'`).
   - Nút Back trên màn bill gọi `context.pop()` trở về đúng grid bàn của Gọi món.

2. **Từ Bill → Màn Chọn Món Gọi Thêm**:
   - Màn chi tiết đơn hiển thị nút FAB (+) màu cam nổi góc phải phía trên footer.
   - Nhấn FAB (+) mở màn hình chọn món gọi thêm tại route `/app/order-create/bill/:orderId/add-items?tableName=...`.
   - Sidebar vẫn giữ **"Gọi món"**.
   - Nút Back từ màn chọn món gọi thêm quay trở về đúng màn bill của đơn hàng hiện tại (`/app/order-create/bill/:orderId`).

3. **Bàn chưa có đơn**:
   - Mở màn tạo món local (`/app/order-create?tableId=...`).
   - Thao tác chọn món, chỉnh số lượng, bấm Back không gọi API tạo phiên hay tạo order.
   - Chỉ khi nhấn "Gửi đơn", API `POST /api/v1/orders` với `tableId` và `submissionMode: SUBMIT` mới được gọi.

### 2. Phân biệt Route Workspace Gọi món và Lịch sử Đơn hàng

- **Workspace Gọi món**:
  - `/app/order-create`: Grid bàn / chọn phương thức phục vụ.
  - `/app/order-create/bill/:orderId`: Xem chi tiết đơn đang phục vụ của bàn.
  - `/app/order-create/bill/:orderId/add-items`: Chọn món gọi thêm vào order hiện tại.
  - Sử dụng `AppShell(initialSection: 'order-create')`.
- **Lịch sử Đơn hàng**:
  - `/app/orders`: Danh sách và bộ lọc lịch sử đơn.
  - `/app/orders/:orderId`: Chi tiết đơn trong ngữ cảnh lịch sử.
  - Sử dụng `AppShell(initialSection: 'orders')`.

### 3. API và Phân Quyền

- **Xem Bill trong Gọi món** (`/app/order-create/bill/:orderId`):
  - Quyền yêu cầu: `ORDER_VIEW` và feature `ORDER_MANAGEMENT`.
  - Không bắt buộc `ORDER_CREATE` hay `MENU_VIEW` đối với nhân viên chỉ có quyền xem bill.
- **Chọn Món Gọi Thêm** (`/app/order-create/bill/:orderId/add-items`):
  - Quyền yêu cầu: `ORDER_UPDATE`, `MENU_VIEW`, cùng feature theo `serviceType` (`TABLE_MANAGEMENT` cho DINE_IN, `POS_QUICK_ORDER` cho TAKEAWAY).
  - Không yêu cầu `ORDER_CREATE` hay `TABLE_OPEN`.

### 4. Dòng Local Giỏ Hàng so với Dòng Đã Lưu

- **Dòng trong Giỏ Hàng (Chưa gửi)**:
  - Cho phép dùng nút `+` / `-` trực tiếp trên card món để tăng/giảm số lượng local.
  - Giảm về 0 sẽ tự động xóa dòng local tương ứng khỏi giỏ, không gửi quantity=0 lên backend.
  - Hỗ trợ stepper số lượng chính xác qua `OrderQuantity` (không dùng float/double).
  - Hai dòng cùng `itemId` nhưng khác ghi chú được quản lý độc lập.
- **Dòng Đã Lưu trên Bill**:
  - Khi order ở trạng thái `CONFIRMED`: các dòng cũ là read-only snapshot, không có stepper `±` local. Muốn gọi thêm bắt buộc dùng nút FAB (+) và gửi qua append SUBMIT.
  - Khi order ở trạng thái `OPEN` và dòng `PENDING`: cho phép chỉnh sửa qua form xác nhận với quyền `ORDER_UPDATE`, gửi `PATCH /api/v1/orders/:orderId/items/:orderItemId`. Không auto-PATCH trên từng cú bấm stepper.
  - Món `CANCELLED`: hiển thị style gạch ngang riêng biệt, không cộng vào tổng hiệu lực.

### 5. Giới Hạn Nghiệp Vụ Backend & Thao Tác Chưa Hỗ Trợ

- **Thanh toán & Gửi bếp & Thông báo**:
  - Backend hiện tại chưa có API thanh toán, gửi bếp, đóng bill hay thông báo.
  - Không triển khai mutation giả. Màn hình chi tiết đơn hiển thị thông báo rõ: *"Chưa hỗ trợ gửi bếp, thanh toán hoặc đóng bill."*
- **Tạm tính**:
  - Chỉ hiển thị bản xem trước các dòng và tổng tiền snapshot hiện có của backend trong popup xem nhanh, không gọi endpoint tạo hóa đơn mới hay thay đổi trạng thái đơn.
- **Ảnh Thumbnail**:
  - Snapshot backend `OrderResponse` chưa lưu URL ảnh món. App tận dụng cache danh mục ảnh trong bộ nhớ khi đã tải catalog, hoặc fallback sang icon/placeholder hài hòa, không gọi HTTP riêng cho từng dòng.

### 6. Retry và Xử Lý Kết Quả Chưa Xác Định (Unknown Outcome)

- Khi gửi tạo đơn hoặc gọi thêm gặp lỗi mạng, timeout hoặc HTTP 5xx: intent được đóng băng với cùng `Idempotency-Key`, `expectedVersion`, và danh sách items.
- Người dùng có thể bấm "Kiểm tra lại" để retry bằng cùng key mà không làm mất giỏ hàng.
- Lỗi `409 CONCURRENT_ORDER_UPDATE`: giữ nguyên giỏ, yêu cầu người dùng xác nhận làm mới để đối chiếu.
- Lỗi `409 TABLE_SESSION_HAS_SERVING_ORDER`: giữ giỏ, không tự động chuyển thành auto-append.
