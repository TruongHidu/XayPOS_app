# Xây POS

Gọi món tại bàn/mang đi: `/app/order-create`; danh sách: `/app/orders`.
Xem [tài liệu Order](docs/order-management.md) về permission, feature,
idempotency, version và giới hạn chưa có payment/KDS.
Grid Gọi món tải toàn bộ bàn AVAILABLE, ghép serving order theo currentSession để
hiển thị totalAmount/currency. Nhấn bàn có bill mở trực tiếp detail; FAB “+” gọi thêm.
Chọn bàn/chọn món không mở phiên. “Gửi đơn” dùng tableId+SUBMIT tạo phiên nếu cần
và xác nhận order trong một request. “Tạo nháp” chỉ giữ cho legacy session/TAKEAWAY.
“Gọi thêm món” vào order đã chọn (OPEN/CONFIRMED) có key/version bất biến để
resolve timeout an toàn; không tự tạo đơn mới hoặc đổi occupancy của bàn.

Ứng dụng Flutter POS SaaS với luồng đăng nhập, khôi phục phiên, refresh token
rotation, phân quyền theo permission và giới hạn tính năng theo package.

## Chạy ứng dụng

Backend URL được lấy từ compile-time environment, không hardcode trong widget:

```powershell
flutter run --dart-define=API_BASE_URL=https://api.example.com
```

Khi chạy backend local trên Android Emulator:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

`CASHIER_WEB_URL` có thể được truyền tương tự khi URL Cashier Web sẵn sàng.

Module quản lý bàn nằm tại `/app/tables`, yêu cầu feature `TABLE_MANAGEMENT`
và quyền `TABLE_VIEW`; các thao tác tạo/sửa/phục vụ kiểm tra quyền riêng.
Xem [tài liệu quản lý bàn](docs/table-management.md) để biết API, version,
QR và giới hạn phiên phục vụ. Chạy riêng test module: `flutter test test/features/tables`.

Trên Windows, dự án sử dụng plugin native nên cần bật **Developer Mode** để
Flutter tạo symlink: Settings → System → For developers → Developer Mode.

## Kiến trúc auth

- `core/network`: Dio client, error mapping và interceptor refresh single-flight.
- `core/storage`: lưu nguyên cặp access/refresh token trong secure storage.
- `core/auth`: `AppSession`, session events và `AccessPolicy`.
- `features/auth/domain`: entity, repository contract và use case.
- `features/auth/data`: DTO, remote/local data source và repository implementation.
- `features/auth/presentation`: controller, splash/login/bootstrap screen và widget.
- `features/subscription`: entitlement entity, repository và data source.
- `app/router`: route definitions, reactive guard và deep-link policy.

## Luồng phiên đăng nhập

1. Ứng dụng mở ở splash và đọc token từ secure storage.
2. Token sắp hết hạn được refresh trước khi bootstrap session.
3. Tenant role tải entitlement; lỗi mạng giữ token và cho phép thử lại.
4. Dio tự gắn bearer token và chỉ tạo một refresh cho nhiều response 401 đồng thời.
5. Logout luôn xóa phiên local, kể cả khi backend không phản hồi.

## Kiểm tra

```powershell
flutter analyze
flutter test
flutter build apk --debug --dart-define=API_BASE_URL=https://api.example.com
```
