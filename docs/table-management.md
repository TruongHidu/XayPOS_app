# Quản lý khu vực, bàn và phiên phục vụ

## Phạm vi và contract

Module `lib/features/tables/` tích hợp 23 endpoint, gồm chuyển bàn và lịch sử
chuyển bàn. Contract được đối chiếu với
`pos-saas-be/docs/tenant-api.md`, `docs/openapi/tenant-api.yaml`, controllers,
request/response DTO, query, command services và lifecycle/validation policies
trong `com.possaas.modules.table`. Không phát hiện khác biệt ảnh hưởng các endpoint
đã tích hợp; không sửa backend.

Triển khai khu vực và bàn: tìm kiếm, lọc, sort, phân trang, chi tiết, tạo, sửa,
bật/tắt, xóa mềm; bàn thêm gán/bỏ khu vực và quản lý QR. Phiên phục vụ gồm mở,
xem phiên hiện tại, sửa số khách/ghi chú, chuyển bàn, hủy mở nhầm và xem lịch sử.

## Cấu trúc và phụ thuộc

```text
Widget → ChangeNotifier controller → Use case → Repository interface
                                              ↓
                                     Repository implementation
                                              ↓
                                    TablesRemoteDataSource → Dio
```

| Đường dẫn trong feature | Trách nhiệm |
| --- | --- |
| `domain/entities/table_entities.dart` | Khu vực, bàn, area/current-session summary, phiên, QR, enum, page bất biến |
| `domain/entities/table_inputs.dart` | Input tạo/sửa có kiểu, không có tenant hoặc field nội bộ |
| `domain/entities/table_query.dart` | Query, sort allowlist, giới hạn page/size và khoảng ngày |
| `domain/validation/table_validation.dart` | Quy tắc text, số nguyên, guestCount, capacity và version |
| `domain/repositories/` | TableAreaRepository, RestaurantTableRepository, TableSessionRepository |
| `domain/use_cases/` | Use case cụ thể cho 23 thao tác |
| `data/dto/` | Parse response chặt chẽ; serialize request theo allowlist |
| `data/data_sources/tables_remote_data_source.dart` | Method/path/body/query đúng contract |
| `data/repositories/` | Chuyển response/lỗi thành Result/Failure |
| `presentation/controllers/table_controller.dart` | Kiểm tra scope/quyền, khóa resource, vòng đời request |
| `presentation/controllers/table_list_controller.dart` | Search debounce, generation, pagination/fallback; không chứa quy tắc CRUD |
| `presentation/controllers/table_area_controller.dart` | Khu vực và selector khu vực phân trang độc lập |
| `presentation/controllers/restaurant_table_controller.dart` | Danh sách bàn, filter và mutation cấu hình |
| `presentation/controllers/table_session_controller.dart` | Phiên hiện tại/lịch sử và nghiệp vụ phục vụ theo tableId |
| `presentation/controllers/table_detail_controller.dart` | Detail bàn và QR controller độc lập |
| `presentation/controllers/table_events.dart` | Invalidation liên quan và khóa theo resource trong cùng scope |
| `presentation/providers/tables_providers.dart` | Inject Dio/repository/use case/controller và bounded access recovery |
| `presentation/screens/tables_management_screen.dart` | Hai tab Bàn / Khu vực, grid responsive và toolbar |
| `presentation/widgets/` | Form, picker, detail, lịch sử, QR, confirmation và kiểm tra kết quả tạo bị timeout |

Domain không import Flutter, Dio hoặc Riverpod. Widget không gọi Dio hoặc tạo JSON.
Controllers tables không kế thừa controller/entity của menu. Không thêm dependency
hoặc code generation. Formatter thời gian local đặt tại
`core/ui/formatters/local_date.dart`; helper menu cũng dùng formatter này.

Các điểm tích hợp: `app/providers.dart`, `app/app.dart`, `app/router/app_routes.dart`,
`app/router/app_router.dart`, `core/auth/access_policy.dart`,
`core/network/api_error_mapper.dart`, `core/ui/sidebar/sidebar_filter.dart`,
`core/ui/shell/app_shell.dart`. Giữ thay đổi kích thước AppBar đang có.

## Điều hướng và sử dụng

- `/app/tables` mở `AppShell(initialSection: 'tables')`; route guard dùng
  `AccessPolicy.canOpenRoute`. Sidebar “Sơ đồ bàn” sẵn có hiển thị màn thật.
- Tab Bàn: tìm code/name; chọn khu vực; lọc cấu hình AVAILABLE/INACTIVE và
  có khách/trống độc lập; chọn sort/direction, chuyển trang hoặc kéo tải lại.
- Menu từng card mở chi tiết, sửa, đổi khu vực, đổi trạng thái, xóa, QR,
  mở phiên hoặc lịch sử theo quyền/trạng thái.
- Chi tiết bàn tải phiên hiện tại một lần khi mở. Card danh sách dùng
  `occupied/currentSession/canOpen` trong response list, không gọi API từng card.
- “Lịch sử phục vụ” ở đầu màn xem cả phiên của bàn đã xóa mềm; lịch sử riêng
  của bàn có từ menu hoặc chi tiết. Lọc OPEN/CANCELLED/CLOSED, khoảng ngày mở,
  mới/cũ trước và phân trang. Khoảng ngày UI dùng giờ local rồi gửi UTC ISO instant.
- Tab Khu vực: tìm/lọc active, sort, phân trang, xem/sửa/tạo/bật/tắt/xóa.
- Form/dialog cuộn khi bàn phím mở. Grid tận dụng chiều rộng, không giới hạn thành
  cột nhỏ trên tablet/desktop. Loading/error/retry và empty khác no-results.

## Quyền và feature

Mọi thao tác cần nhà hàng hợp lệ, subscription ACTIVE và `TABLE_MANAGEMENT`.
Route và màn cần `TABLE_VIEW`; controller kiểm tra lại quyền tương ứng trước/sau
request. Không suy từ packageCode hoặc tự cấp OWNER/MANAGER bypass.

| Permission | Thao tác |
| --- | --- |
| TABLE_VIEW | Xem khu vực/bàn/phiên hiện tại/chi tiết/lịch sử, selector |
| TABLE_CREATE | Tạo khu vực/bàn |
| TABLE_UPDATE | Sửa cấu hình, status, area assignment, xóa mềm, xem QR, rotate QR |
| TABLE_OPEN | Mở phiên, sửa guestCount/note |
| TABLE_CLOSE | Hủy phiên mở nhầm |
| TABLE_TRANSFER | Chuyển phiên OPEN sang bàn trống; UI chọn bàn còn cần TABLE_VIEW |

Không có TABLE_DELETE/TABLE_CANCEL/TABLE_QR_MANAGE hoặc yêu cầu QR_MENU_VIEW.
OWNER, MANAGER, WAITER, KITCHEN dùng effective permissions; CASHIER và SUPER_ADMIN
giữ luồng web-only hiện tại. Không thêm maxTables.

## API

Dùng `apiClientsProvider.authenticated`, Bearer interceptor, refresh single-flight
và retry 401 một lần hiện có. Prefix `/api/v1`, tenant lấy từ JWT; không thêm
restaurantId hoặc X-Restaurant-Id. Response entity/page trực tiếp, không wrapper.

| Method | Path sau /api/v1 | Kết quả / quyền |
| --- | --- | --- |
| GET | /table-areas | Page khu vực / TABLE_VIEW |
| POST | /table-areas | Khu vực mới / TABLE_CREATE |
| GET | /table-areas/{id} | Chi tiết / TABLE_VIEW |
| PATCH | /table-areas/{id} | Sửa / TABLE_UPDATE |
| PATCH | /table-areas/{id}/status | Bật/tắt / TABLE_UPDATE |
| DELETE | /table-areas/{id}?expectedVersion=n | 204 / TABLE_UPDATE |
| GET | /tables | Page bàn / TABLE_VIEW |
| POST | /tables | Bàn mới / TABLE_CREATE |
| GET | /tables/{id} | Chi tiết / TABLE_VIEW |
| PATCH | /tables/{id} | Sửa cấu hình / TABLE_UPDATE |
| PATCH | /tables/{id}/status | Bật/tắt / TABLE_UPDATE |
| PATCH | /tables/{id}/area | Gán/bỏ khu vực / TABLE_UPDATE |
| DELETE | /tables/{id}?expectedVersion=n | 204 / TABLE_UPDATE |
| GET | /tables/{id}/qr | QR payload / TABLE_UPDATE |
| POST | /tables/{id}/qr/rotate | QR payload/version mới / TABLE_UPDATE |
| POST | /tables/{id}/sessions | Phiên OPEN / TABLE_OPEN |
| GET | /tables/{id}/current-session | Phiên hoặc 204 → Success(null) / TABLE_VIEW |
| GET | /table-sessions | Page lịch sử / TABLE_VIEW |
| GET | /table-sessions/{id} | Chi tiết phiên / TABLE_VIEW |
| PATCH | /table-sessions/{id} | Sửa guestCount/note / TABLE_OPEN |
| POST | /table-sessions/{id}/cancel | Phiên CANCELLED / TABLE_CLOSE |
| POST | /table-sessions/{id}/transfer | Phiên hiện tại + header replay / TABLE_TRANSFER |
| GET | /table-sessions/{id}/transfers?page=0&size=20 | Page lịch sử chuyển / TABLE_VIEW |

Query page bắt đầu 0, size mặc định 20, tối đa 100. Khu vực/bàn mặc định
displayOrder desc; phiên openedAt desc. Search debounce 350 ms; thay query reset
page 0 và vô hiệu request cũ ngay. Xóa hết trang cuối quay về trang còn hợp lệ.
Refresh sau mutation giữ filter/sort.

Selector khu vực có search và phân trang riêng. Khi tạo/gán chỉ chọn active;
filter có thể chọn inactive. Assignment inactive hiện tại vẫn hiển thị. Null
areaId trong query nghĩa tất cả khu vực, không phải “chỉ bàn chưa gán”.

## Version, null và nghiệp vụ

- Khu vực dùng area.version; cấu hình bàn/status/assignment/delete/QR/open phiên
  dùng table.version; update/cancel phiên dùng session.version.
- Không fallback version 0, không tự cộng version, không retry 409 với version
  mới. DTO thiếu/sai dữ liệu bắt buộc trở thành INVALID_TABLE_RESPONSE.
- Form được mở từ detail mới, giữ baseline riêng. Refresh nền không ghi đè draft.
  Conflict giữ draft, chặn gửi lại; tải bản mới cần xác nhận thay thế draft.
- PATCH chỉ gửi field thay đổi. Null/missing description/note giữ nguyên;
  chuỗi rỗng xóa nội dung. PATCH trống bị chặn ở controller.
- Assignment luôn gửi `areaId`, kể cả explicit null để bỏ gán; form sửa cấu hình
  không gửi areaId/status/qrToken. Đây là thao tác riêng, không giả lập transaction.
- Status cấu hình và occupancy độc lập: AVAILABLE có thể occupied=true.
  Bàn có khách không đổi code/capacity/area, không disable/delete; vẫn sửa
  name/displayOrder và rotate QR. Các ràng buộc liên quan toàn khu vực do backend
  quyết định, không suy từ một page bàn.
- GuestCount 1..32767, có thể vượt capacity. Mở mặc định 1; không sinh sessionCode.
  Chỉ OPEN có thao tác sửa/hủy. CANCELLED/CLOSED chỉ đọc; không có thao tác close.
- Cancel giữ sessionId ban đầu kể cả sau conflict/timeout hoặc retry chủ động;
  không lookup phiên hiện tại để đổi sang ID mới. Open/cancel không tự tăng
  version cấu hình bàn. Lịch sử vẫn xem sau khi bàn xóa mềm; code bàn vẫn reserved.
- Không retry mutation khi mất mạng/timeout. Draft được giữ và người dùng phải
  tải lại xác minh. Create chưa có ID dùng hộp kiểm tra kết quả tìm kiếm phân trang,
  giữ draft/filter, chỉ mở gửi lại khi người dùng xác nhận đã kiểm tra.
- Error mapper giữ code/fieldErrors và thông báo tiếng Việt cho các lỗi TABLE,
  không thay luồng auth hoặc mất mapping menu/staff. 404 làm refresh list liên quan.

## Scope và invalidation

`AccessPolicy.tableScope` gồm userId, restaurantId, role, permissions/features đã
sắp xếp, subscriptionId/status. Không gồm token: token rotation giữ draft/filter.
Provider thay controller khi boundary đổi, dialog scope guard đóng dialog cũ,
request generation bỏ response trễ; dispose hủy debounce và xóa state.

TableEvents refresh có chọn lọc: area đổi làm cập nhật selector, filter label,
table summaries và detail; table/QR đổi làm refresh list/detail; session đổi làm
refresh occupancy/detail và current/history đang dùng. Không tải current-session
cho từng card. Mutation lock dùng resource ID trong cùng scope, không khóa toàn màn.

## Chuyển bàn

“Chuyển bàn” có trong chi tiết phiên OPEN và card phiên của quản lý bàn. Giao
diện responsive hiển thị bàn hiện tại, mã phiên, số khách, tìm kiếm debounce,
bộ lọc khu vực, bàn trống phân trang, bàn đã chọn và lý do tùy chọn. Bàn đích
được lấy bằng `status=AVAILABLE&occupied=false`; client loại bàn nguồn và khu vực
inactive, nhưng không chặn theo capacity và không dùng `canOpen`. Không có request
`current-session` cho từng card.

Controller chuyển bàn định danh bằng `sessionId`. Một ý định bất biến giữ bàn
đích, `session.version`, reason đã trim và `Idempotency-Key`. Timeout, mất mạng,
5xx hoặc response 200 không parse được chuyển sang trạng thái chưa xác định;
người dùng chỉ có thể replay đúng payload/key/version. Conflict xác định không
tự retry; controller tải lại phiên và danh sách để người dùng xem rồi tạo ý định
mới. Token rotation cùng scope giữ intent; đổi user/tenant/quyền loại response trễ.

Response POST là `TableSession` hiện tại. Với resource replay, request A→B có thể
trả phiên đang ở C hoặc đã CLOSED/CANCELLED sau một thay đổi khác; UI luôn dùng
bàn và trạng thái từ response, không ép về B. Thành công phát một `TableChange`
có `sessionId` và tập bàn nguồn/đích/bàn thực tế để refresh occupancy, current
session, lịch sử và workspace gọi món mà vẫn giữ nguyên sessionId/orderId.

Lịch sử chuyển bàn đọc được cả với phiên terminal, giữ thứ tự server và snapshot
tên/mã bàn nguồn → đích. UI hiển thị giờ local, lý do và actorUserId, không gọi
staff API theo từng dòng.

Intent chưa xác định chỉ được giữ trong RAM qua rebuild/đóng mở dialog nhờ
`keepAlive` và exit guard. Nếu app bị tắt hẳn, app tải hiện trạng mới khi mở lại
và không tự replay mutation cũ.

Access recovery dùng AuthController.restore hiện có, một lần mỗi scope và
single-flight; không logout mọi lỗi 403 hoặc tự lặp restore/refetch vô hạn.
Thông báo đi qua messenger toàn app để còn hiển thị sau redirect.

## QR

QR dialog chỉ tải payload khi mở, giới hạn TABLE_UPDATE. Hiển thị qrToken,
qrPath tương đối và version, rotate có xác nhận thay token cũ, dùng version
snapshot và nhận token/version mới từ backend. Không lưu token vào log, analytics,
storage hoặc cache dùng chung tenant; state theo tableId + session scope.

Hiện chọn hiển thị payload/path quản trị, chưa render ảnh QR hoặc tạo URL tuyệt đối.
Không thêm package QR, không dùng API_BASE_URL/CASHIER_WEB_URL làm public origin.
UI ghi rõ website menu công khai chưa cấu hình. Khi triển khai public menu cần
resolver backend và cấu hình origin riêng, sau đó mới dựng URL/ảnh QR tương ứng.

## Kiểm tra và chạy

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.4:8080
flutter analyze
flutter test
flutter test test/features/tables
flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.4:8080
```

Địa chỉ trên lấy từ cấu hình LAN hiện có; Android emulator có thể dùng
`http://10.0.2.2:8080`. Không sửa Environment. Test dùng fake backend/repositories,
không tạo dữ liệu trong nhà hàng thật. Chưa chạy kiểm thử end-to-end trên backend
thật hoặc kiểm tra APK trên thiết bị vật lý.

Các test tại `test/features/tables/` kiểm tra contract đủ 23 endpoint,
parse/204/null/version/error mapping, quyền và web-only roles, scope/rotation,
debounce/stale response/dispose, double-submit/conflict/timeout/404, pagination,
selector ngoài page đầu, refresh phụ thuộc, QR confirmation/version, terminal
session, chuyển bàn/idempotency/resource replay/lịch sử, draft và form 320 px/bàn
phím, màn 320/800/1440 px.

Kết quả xác minh ngày 11/10/2026:

- `dart format`: đã định dạng các file tạo/sửa.
- `flutter analyze`: No issues found.
- `flutter test`: 277/277 test passed, gồm test chuyển bàn và toàn bộ hồi quy
  auth/network/menu/staff/order/tables/shell hiện có.
- `flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.4:8080`:
  thành công trên bản code cuối. APK tại `build/app/outputs/flutter-apk/app-debug.apk`.
- Test QR bổ sung xác nhận GET cũ không ghi đè token/version mới sau rotate.

## Mở rộng Order/Payment

Không có Payment, reservation, gộp/tách bàn, realtime hay offline sync.
Khi thêm Order/Payment, dùng sessionId để liên kết nghiệp vụ, bổ sung use case/API
close sau thanh toán và policy kiểm tra session đang được sử dụng ở backend.
Cancel vẫn chỉ phục vụ hủy mở nhầm; không đổi nhãn hoặc dùng cancel để thanh toán.
TableEvents là điểm nhận invalidation sau Order/Payment; version và backend là
nguồn quyết định cuối cùng, không tự chuyển status cấu hình thành occupied.
