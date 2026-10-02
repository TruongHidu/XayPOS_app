# Bàn giao quản lý nhân viên

Ngày kiểm tra: 2026-10-01. Contract đối chiếu: `../pos-saas-be/docs/tenant-api.md` và các DTO request backend (chỉ đọc).

## Hành vi hoàn thiện

- Chính sách staff dùng permission từ session và feature từ entitlement, đồng thời giới hạn actor OWNER/MANAGER và đối tượng theo contract. Menu, route `/app/staff`, màn hình, nút và controller khi lưu đều kiểm tra quyền. Phân quyền yêu cầu cả STAFF_MANAGEMENT và STAFF_PERMISSION.
- OWNER, SUPER_ADMIN, custom role và chính tài khoản đang đăng nhập được bảo vệ khỏi thao tác quản lý không hợp lệ. Dropdown tạo/sửa lấy role từ API và lọc theo chính sách.
- Danh sách dạng card, bộ lọc thu gọn, tìm kiếm debounce 350 ms, lọc role/trạng thái, phân trang và bốn trường sắp xếp backend hỗ trợ. Response cũ không ghi đè bộ lọc mới. Loading, empty, lỗi và retry riêng cho danh sách/vai trò.
- Chi tiết được tải từ API trước khi mở chi tiết, sửa hoặc đổi trạng thái. Controller kiểm tra lại đối tượng trước mutation sửa/trạng thái.
- Tạo có validation; sửa chỉ gửi trường thay đổi, giữ `phone=""` để xóa số điện thoại và chặn PATCH rỗng. Có cảnh báo xóa overrides khi đổi role, thu hồi refresh token khi đổi email/role. Disable yêu cầu lý do tối đa 500 ký tự.
- `maxStaff` nullable được truyền từ entitlement DTO tới entity/session và hiển thị trong màn hình. Không suy ra sức chứa từ số dòng một trang, không lấy giới hạn từ tên gói.
- Phân quyền xóa dữ liệu cũ ngay khi tải nhân viên mới, chống response A ghi vào B, khóa lưu nếu catalog/config lỗi hoặc chưa tải xong, kiểm tra staffId trước PUT. Gửi đầy đủ grants/denies; hai mảng rỗng xóa overrides. Quyền hiệu lực đã lưu lấy từ response thành công; PUT lỗi không giả lập thành công.
- State staff được tạo lại khi đổi tài khoản, tenant, quyền hoặc entitlement; request đang chạy của controller cũ bị bỏ qua. Refresh token thông thường giữ form và bộ lọc. Đổi tenant qua session event tải lại entitlement.
- Giữ Dio client/interceptor và refresh flow hiện có. Ánh xạ đầy đủ nhóm lỗi yêu cầu; STAFF_LIMIT_REACHED/EMAIL_EXISTS là conflict, USER_NOT_FOUND là notFound. Giữ fieldErrors và hiển thị cạnh trường; sửa đầu vào cho phép gửi lại sau lỗi server. Từ chối truy cập được thông báo và làm mới session/entitlement.

## File có thay đổi chức năng

| Nhóm | File |
| --- | --- |
| App, route, providers | `lib/app/app.dart`, `lib/app/providers.dart`, `lib/app/router/app_router.dart` |
| Chính sách, session | `lib/core/auth/access_policy.dart`, `lib/core/auth/app_session.dart`, `lib/core/ui/sidebar/sidebar_filter.dart` |
| Lỗi | `lib/core/errors/failure.dart`, `lib/core/network/api_error_mapper.dart` |
| Entitlement | `lib/features/subscription/data/dto/entitlement_dto.dart`, `lib/features/subscription/domain/entities/entitlement.dart` |
| Auth | `lib/features/auth/presentation/controllers/auth_controller.dart` |
| Staff controllers | `lib/features/staff/presentation/controllers/staff_list_controller.dart`, `lib/features/staff/presentation/controllers/staff_permission_controller.dart` |
| Staff screen | `lib/features/staff/presentation/screens/staff_management_screen.dart` |
| Staff dialogs | `lib/features/staff/presentation/widgets/create_staff_dialog.dart`, `lib/features/staff/presentation/widgets/edit_staff_dialog.dart`, `lib/features/staff/presentation/widgets/toggle_status_dialog.dart`, `lib/features/staff/presentation/widgets/staff_permission_dialog.dart` |

Các file được formatter chuẩn hóa, không đổi contract/hành vi: `lib/core/ui/shell/app_shell.dart`, `lib/core/ui/sidebar/app_sidebar.dart`, `lib/core/ui/sidebar/sidebar_category.dart`, `lib/features/staff/data/data_sources/staff_remote_data_source.dart`, `lib/features/staff/data/dto/staff_permission_config_dto.dart`, `lib/features/staff/data/dto/staff_role_dto.dart`, `lib/features/staff/data/repositories/staff_repository_impl.dart`, `lib/features/staff/domain/entities/staff_role.dart`.

## Kiểm thử

Thêm các file:

- `test/features/staff/staff_fakes.dart`
- `test/features/staff/staff_contract_test.dart`
- `test/features/staff/staff_controller_test.dart`
- `test/features/staff/staff_session_test.dart`
- `test/features/staff/staff_widget_test.dart`

Cập nhật kỳ vọng cũ trong `test/core/auth/access_policy_test.dart`, `test/features/auth/auth_controller_test.dart`, `test/widget_test.dart` theo unified shell `/app/home` vốn đã có trong app.

Kết quả cuối:

- `flutter analyze`: **No issues found**.
- `flutter test`: **54 tests passed**.
- Fake repository và Dio interceptor giả lập; không cần backend đang chạy.
- Bao phủ ma trận permission/feature/actor/target, maxStaff null, envelope lỗi, payload create/PATCH/status/PUT, debounce, response cũ, phân trang, A/B permission, lỗi tải/lưu, logout/đổi tenant, token rotation, sửa và gửi lại fieldErrors.
- Widget test danh sách, bộ lọc và các dialog ở kích thước **320 × 700** không overflow.

## Phạm vi xác minh còn lại

Chưa chạy kiểm thử tích hợp với backend thật hoặc thiết bị Android/iOS thật. Việc thay đổi quyền từ thiết bị khác được phản ánh qua session/entitlement được làm mới và xử lý phản hồi server; app không có kênh đẩy quyền tức thời. Backend tiếp tục quyết định quyền hiện hành, sức chứa và xung đột đồng thời.

Không sửa backend, thêm API, thư viện, module staff thứ hai hoặc chức năng ngoài phạm vi.
