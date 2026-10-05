# Bàn giao quản lý thực đơn

## Phạm vi và kiến trúc

Module `lib/features/menu/` kết nối 14 API nhóm món/món ăn, dùng Dio authenticated client, Riverpod ChangeNotifier, GoRouter và shell hiện có. Không thay đổi backend; không thêm dependency. Đã đối chiếu DTO, controller và chính sách menu trong repository `pos-saas-be`.

| Thư mục/file | Trách nhiệm |
| --- | --- |
| `domain/entities/` | MenuGroup, MenuItem, group summary, MenuPage, MenuQuery, typed input và MenuPrice |
| `domain/validation/menu_validation.dart` | Validation text, giá, URL ảnh, thứ tự và PATCH |
| `domain/repositories/` | Hai interface repository nhóm và món |
| `domain/use_cases/` | Sáu use case nhóm và tám use case món |
| `data/dto/` | Parse response bắt buộc, nullable và serialize từng loại request |
| `data/data_sources/menu_remote_data_source.dart` | Method/path/query/body của 14 endpoint |
| `data/repositories/` | Repository implementation; chuyển lỗi sang Result/Failure |
| `presentation/controllers/` | State nhóm/món/selector riêng; chống response cũ, mutation trùng và invalidation liên quan |
| `presentation/providers/menu_providers.dart` | Inject repository/use case, scope phiên, sự kiện và phục hồi quyền |
| `presentation/screens/menu_management_screen.dart` | Hai tab, tìm kiếm, lọc, sort, phân trang và thao tác theo quyền |
| `presentation/widgets/` | Form, chi tiết, ảnh, badge, selector và dialog xác nhận |
| `test/features/menu/` | Contract, controller, session/policy và widget tests với dữ liệu giả |

Các điểm tích hợp đã sửa: `lib/app/providers.dart`, `lib/app/app.dart`, `lib/app/router/app_routes.dart`, `lib/app/router/app_router.dart`, `lib/core/auth/access_policy.dart`, `lib/core/network/api_error_mapper.dart`, `lib/core/ui/sidebar/sidebar_filter.dart`, `lib/core/ui/shell/app_shell.dart`. Test shell `test/widget_test.dart` dùng fake menu repository. Cấu hình API trong `environment.dart` đang có của người dùng được giữ nguyên.

## Route và quyền

Route `/app/menu` mở `AppShell(initialSection: 'menu')`. Sidebar “Thực đơn” hiện có mở màn thực đơn thật. Layout dùng toàn chiều rộng khả dụng: một cột trên điện thoại, nhiều cột trên tablet/desktop, form cuộn khi bàn phím mở.

Mọi quyền menu đều yêu cầu restaurantId hợp lệ, subscription ACTIVE và feature `MENU_MANAGEMENT`. OWNER không có quyền tương ứng sẽ không được bypass. OWNER, MANAGER, WAITER và KITCHEN dùng cùng chính sách permission; CASHIER/SUPER_ADMIN giữ luồng web riêng.

| Permission | Thao tác |
| --- | --- |
| `MENU_VIEW` | Route/sidebar, danh sách/chi tiết và tìm nhóm |
| `MENU_CREATE` | Thêm nhóm, thêm món |
| `MENU_UPDATE` | Sửa thông tin, bật/tắt, có hàng/hết hàng, chuyển/bỏ nhóm |
| `MENU_DELETE` | Xóa nhóm/món có xác nhận |

UI ẩn các nút ghi khi thiếu quyền. Controller kiểm tra lại scope và permission trước request, sau response; quyền backend vẫn là quyết định cuối cùng.

## API đã kết nối

Prefix: `/api/v1/menu`. Response entity/page trực tiếp, không có wrapper `data`.

| Method | Path | Nội dung |
| --- | --- | --- |
| GET | `/groups` | Tìm kiếm/phân trang nhóm |
| GET | `/groups/{id}` | Chi tiết nhóm |
| POST | `/groups` | name, displayOrder, active |
| PATCH | `/groups/{id}` | name/displayOrder thay đổi, expectedVersion |
| PATCH | `/groups/{id}/status` | active, expectedVersion |
| DELETE | `/groups/{id}?expectedVersion=n` | 204, không parse entity |
| GET | `/items` | Tìm kiếm/phân trang món |
| GET | `/items/{id}` | Chi tiết món |
| POST | `/items` | name, baseUnit, salePrice, costPrice, groupId, sku, description, imageUrl, active |
| PATCH | `/items/{id}` | Chỉ field thông tin thay đổi (bao gồm costPrice) và expectedVersion |
| PATCH | `/items/{id}/status` | active, expectedVersion |
| PATCH | `/items/{id}/availability` | availabilityStatus, expectedVersion |
| PUT | `/items/{id}/group` | groupId (luôn hiện diện, có thể null), expectedVersion |
| DELETE | `/items/{id}?expectedVersion=n` | 204, không parse entity |

Query chung: q đã trim (tối đa 100), active, page (0-based), size 1–100, sortBy, direction. Sort nhóm: createdAt/updatedAt/name/displayOrder; món: createdAt/updatedAt/name/salePrice. Món thêm groupId/availabilityStatus/sellable. Query null được bỏ qua. Không gửi tenant hoặc field nội bộ. Không có filter “chưa phân nhóm” ở danh sách do backend chưa hỗ trợ.

Search debounce 350 ms. Đổi query vô hiệu hóa request cũ ngay lập tức và reset page 0. Sau mutation tải lại query hiện tại; không append entity trái filter/sort. Xóa hết trang cuối tự chuyển về trang hợp lệ. Group selector có search và phân trang riêng; create/move chỉ lấy nhóm active, có lựa chọn chưa phân nhóm. Filter nhóm được xem cả nhóm inactive. Nhóm hiện tại được giữ, kể cả nằm ngoài trang selector hoặc đã inactive.

## Dữ liệu, lifecycle và version

- DTO yêu cầu đúng id, version, trạng thái, timestamp ISO và các trường bắt buộc; không dùng giá trị fallback che response lỗi. Group summary/SKU/mô tả/ảnh chấp nhận null.
- `MenuPrice` lưu integer minor units (1/100), tối đa `999999999999.99`. Validation, so sánh và phát hiện thay đổi không dùng phép toán double. Input dùng dấu chấm, tối đa hai chữ số thập phân, chấp nhận 0. Chỉ chuyển thành JSON number tại serializer.
- `costPrice` (giá vốn) dùng `MenuPrice` như giá bán. Khi tạo, null/để trống gửi số 0. PATCH không thay đổi giá vốn sẽ bỏ field; muốn đặt giá vốn về 0 phải gửi số 0, vì backend PATCH coi null là giữ nguyên. Form sửa giá vốn đã biết cho phép xóa nội dung để đặt về 0.
- Backend hiện đã nhận `costPrice` ở CreateItem/UpdateItem nhưng `MenuItemResponse` chưa trả field này. DTO đọc được giá vốn khi field có mặt, chuyển explicit null thành 0; nếu field bị bỏ qua, giữ trạng thái chưa biết thay vì đoán giá đã lưu bằng 0. Form sửa giữ nguyên giá vốn chưa biết khi không chạm ô nhập; nhập 0 để đặt về 0. Chi tiết chỉ hiển thị giá vốn khi response có cung cấp. Để đọc/hiển thị giá vốn đã lưu sau khi mở lại, backend cần thêm `costPrice` vào `MenuItemResponse` và mapper tương ứng.
- PATCH chỉ gửi field thay đổi; sku/description/imageUrl rỗng gửi `""`. Không gửi PATCH chỉ chứa version. Trạng thái và chuyển nhóm là thao tác riêng.
- Form/action giữ entity và version khi mở/xác nhận. Không tải version mới ngay trước submit, không tự tăng version. No-op dùng response server. Background refresh không ghi đè bản nháp.
- `CONCURRENT_MENU_UPDATE` giữ bản nháp và khóa gửi lại. Nút tải lại yêu cầu xác nhận thay bản nháp; thành công mới thay baseline. Not found hiển thị lỗi và tải lại danh sách; không báo mutation thành công.
- Không tự retry mutation khi conflict/timeout. Timeout thông báo kết quả chưa xác định và hướng dẫn kiểm tra dữ liệu trước khi gửi lại. Cơ chế refresh token single-flight và retry một lần khi 401 của AuthInterceptor được giữ nguyên.
- Hiển thị riêng active, availabilityStatus và sellable. Dùng sellable backend; không suy từ active. Món inactive không được đổi availability. Bật/tắt giữ tình trạng có hàng. Tắt nhóm làm món thuộc nhóm không thể bán; bật nhóm chỉ làm các món đủ điều kiện bán trở lại.
- Đổi tên/trạng thái/xóa nhóm refresh danh sách món, selector và chi tiết món đang mở. Xóa nhóm đang lọc sẽ bỏ filter đó. Form đang sửa giữ nguyên draft.
- Xóa món là soft delete, SKU vẫn được giữ, chưa có API restore. Nhóm còn món chưa xóa (kể cả inactive) không thể xóa; UI giải thích phải chuyển/bỏ nhóm hoặc xóa các món trước.
- Ảnh dùng URL HTTP(S) không credentials, placeholder khi tải/thất bại. Chưa có upload ảnh.

## Scope phiên và phục hồi quyền

`AccessPolicy.menuScope` gồm userId, restaurantId, role, permissions/features đã sắp xếp, subscriptionId/status. Không gồm accessToken/refreshToken. Provider dựng lại controller khi scope đổi; shell và dialog loại bỏ nội dung tenant cũ. Không lưu menu/bản nháp vào storage chung. Controller bỏ response cũ sau scope change/dispose, hủy debounce và chặn gửi trùng theo entity.

Xoay token cùng scope giữ controller, query và form. Lựa chọn nhóm dùng `menuGroupFilterProvider` theo scope để giữ đúng tên nhóm khi rời màn hình rồi quay lại. Logout/đổi tài khoản, tenant, quyền hoặc feature làm dialog đóng và state reset. Lỗi quyền/subscription/account/restaurant đi qua `AuthController.restore()` hiện có; `MenuAccessRecovery` giới hạn một lần tự phục hồi cho mỗi scope để tránh vòng lặp. Thông báo dùng `menuNoticeProvider` và messenger toàn app để còn hiển thị sau redirect. Không logout mọi lỗi 403, không tự gửi lại mutation.

## Chạy app và kiểm tra thủ công

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

`10.0.2.2` dùng khi backend chạy trên máy host của Android emulator. Với điện thoại thật, thay bằng IP LAN của máy backend cùng mạng (ví dụ cấu hình đang có `192.168.1.4:8080`); kiểm tra firewall và backend lắng nghe địa chỉ phù hợp.

1. Dùng tài khoản nhà hàng test có gói ACTIVE, `MENU_MANAGEMENT` và bốn quyền menu; mở Thực đơn từ sidebar hoặc `/app/menu`.
2. Tạo nhóm, thêm món với giá 0, 0.01, 35000.50; thử giá âm/quá hai số thập phân và URL sai. Thử giá vốn để trống khi tạo (0), nhập giá vốn thập phân, sửa giá vốn và đặt về 0; khi backend chưa trả giá vốn, sửa tên món phải giữ nguyên giá vốn đã lưu. Kiểm tra SKU/mô tả/ảnh có thể xóa bằng chuỗi rỗng.
3. Search nhanh, đổi filter/sort/page; kiểm tra nhóm ở trang selector thứ hai và nhóm hiện tại inactive. Bỏ phân nhóm rồi lọc nhóm khác.
4. Đánh dấu hết hàng, tắt và bật món: vẫn hết hàng. Tắt nhóm: món vẫn giữ active/availability nhưng sellable=false. Bật nhóm không tự đổi tình trạng có hàng của món.
5. Xóa nhóm còn món inactive phải báo không rỗng. Chuyển/bỏ nhóm các món rồi xóa nhóm. Xóa món phải có xác nhận giữ SKU; xóa món cuối trang kiểm tra phân trang.
6. Mở cùng món trên hai phiên test. Sửa ở phiên B rồi lưu draft A: A báo conflict và giữ draft. Chọn giữ draft/tải lại, kiểm tra không tự retry hay thay version âm thầm.
7. Dùng tài khoản chỉ MENU_VIEW: xem được danh sách/chi tiết, không có nút ghi. Thử WAITER được grant MENU_VIEW, OWNER thiếu quyền, thiếu feature/gói hết hạn và deep link menu.
8. Khi form mở, xoay token rồi kiểm tra draft; thu hồi quyền/đổi tenant/logout phải đóng form và bỏ dữ liệu cũ. Giả lập mạng chậm, timeout và response về sai thứ tự trên dữ liệu test.
9. Kiểm tra điện thoại 320 px và tablet, bàn phím mở, tên/mô tả dài, ảnh hỏng, list trống và Retry.

## Kết quả kiểm tra

Kiểm tra ngày 05/10/2026, Flutter 3.32.1 / Dart 3.8.1:

- `dart format`: đã chạy cho toàn bộ file Dart thêm/sửa của module và các điểm tích hợp.
- `flutter analyze`: **No issues found**.
- `flutter test`: **99/99 test đạt**, gồm 42 test menu và 57 test hồi quy auth/network/staff/shell, sau bổ sung costPrice.
- Các test menu kiểm tra đủ 14 endpoint, phiên bản và nullable, giá chính xác, phân quyền, debounce/response cũ, đổi tenant/token, khóa gửi trùng, conflict giữ draft, refresh chi tiết theo nhóm và layout 320×700 khi bàn phím mở.
- Test mới cho costPrice kiểm tra null/0/giá thập phân/giá không hợp lệ, PATCH chỉ giá vốn, không ghi đè giá vốn khi response thiếu field và xóa giá vốn đã biết thành 0.
- `flutter build apk --debug`: bản module menu trước khi bổ sung costPrice đã **build thành công**, Gradle 214,3 giây. APK hiện có: `build/app/outputs/flutter-apk/app-debug.apk` (117.238.985 byte). Chưa build lại APK sau bổ sung costPrice.

Không chạy tests bằng API production hoặc dữ liệu nhà hàng thật.

## Giới hạn

Chưa chạy thao tác end-to-end với backend thật hoặc thiết bị thật trong phiên triển khai. Tests sử dụng fake repository và Dio interceptor, không tạo/xóa dữ liệu nhà hàng thật. Không hỗ trợ offline sync, upload ảnh, khôi phục món đã xóa hoặc filter món chưa phân nhóm vì contract hiện tại không cung cấp các API này.
