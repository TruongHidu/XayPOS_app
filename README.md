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

Copy file mẫu thành cấu hình cục bộ (chỉ cần khi chưa có `.env`):

```powershell
Copy-Item -LiteralPath .env.example -Destination .env
```

Sửa `.env` ở thư mục gốc, rồi chạy:

```powershell
flutter run
```

Trong VS Code, chọn **Xây POS (.env)** ở Run and Debug và nhấn F5. App tự nạp
`.env` lúc khởi động, trước khi tạo ProviderScope và các client API/realtime;
không cần truyền `--dart-define-from-file`. Backend URL và các tùy chọn được đọc
tập trung tại `lib/core/config/environment.dart`.

| Key | Ý nghĩa |
| --- | --- |
| `API_BASE_URL` | URL backend thiết bị truy cập được. Desktop/web dùng `http://localhost:8080`; Android Emulator dùng `http://10.0.2.2:8080`; thiết bị thật dùng IP LAN/domain của backend. |
| `CASHIER_WEB_URL` | URL Cashier Web dự phòng; hiện chưa có nơi sử dụng. Có thể để trống. |
| `REALTIME_ENABLED` | `true`/`false`: lựa chọn ban đầu khi thiết bị chưa lưu công tắc Cập nhật tự động. Lựa chọn trong app được ưu tiên. |
| `REALTIME_TRANSPORT` | Mặc định `websocket` để nhận sự kiện; `polling` chỉ dùng khi chủ động chọn kiểm tra định kỳ. |
| `REALTIME_URL` | Để trống để suy ra `/ws` từ `API_BASE_URL`; đặt rõ khi reverse proxy có đường WebSocket riêng. Bản release yêu cầu WSS. |

`.env` và `.env.*` được bỏ qua bởi Git; chỉ commit `.env.example`. Dùng định dạng
`KEY=value`, boolean viết `true`/`false`, comment đặt trên dòng riêng. `.env` được
khai báo là Flutter asset và nạp một lần lúc app khởi động; sau khi sửa hãy dừng
app và chạy lại để nhận cấu hình mới. `API_BASE_URL` trống dùng giá trị mặc định
`http://localhost:8080`.

Nếu gặp `FileNotFoundError` từ DotEnv sau khi thêm `.env`, bản ứng dụng đang chạy
có thể chưa chứa asset mới. Kiểm tra `.env` có trong thư mục gốc và được khai báo
ở `flutter: assets:` trong `pubspec.yaml`, sau đó **dừng hẳn phiên debug** và chạy:

```powershell
flutter pub get
flutter run
```

Với lỗi thiếu asset này, hãy build/cài lại từ một phiên chạy mới. Khi `.env` thiếu
hoặc rỗng, app hiện màn hình lỗi cấu hình có nút Thử lại. Các provider/API chỉ
được tạo khi cấu hình đã nạp thành công.

Có thể ghi đè một key bằng CLI, ví dụ Android Emulator:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Thứ tự ưu tiên: key được truyền rõ bằng `--dart-define` → `.env` → mặc định.
Override boolean `false` hoặc chuỗi trống vẫn được áp dụng theo key được truyền.
Khi build cho môi trường khác, chuẩn bị `.env` với cấu hình của môi trường đó hoặc
ghi đè từng key bằng `--dart-define`.

Đây là cấu hình phía client: `.env` được đóng gói trong app và có thể bị trích xuất.
JWT signing secret, mật khẩu database và khóa API bí mật phải nằm ở backend.
Access/refresh token đăng nhập tiếp tục được lưu qua secure storage, không ghi
vào `.env`.

Tham khảo [nạp asset bằng flutter_dotenv](https://pub.dev/packages/flutter_dotenv),
[compile-time override của Dart](https://dart.dev/libraries/core/environment-declarations)
và [launch configuration của Dart Code](https://dartcode.org/docs/launch-configuration/).

Module quản lý bàn nằm tại `/app/tables`, yêu cầu feature `TABLE_MANAGEMENT`
và quyền `TABLE_VIEW`; các thao tác tạo/sửa/phục vụ kiểm tra quyền riêng.
Xem [tài liệu quản lý bàn](docs/table-management.md) để biết API, version,
QR và giới hạn phiên phục vụ. Chạy riêng test module: `flutter test test/features/tables`.

Trên Windows, dự án sử dụng plugin native nên cần bật **Developer Mode** để
Flutter tạo symlink: Settings → System → For developers → Developer Mode.

## Kho

Nhóm **Kho** trên sidebar có mũi tên mở rộng/thu gọn, gồm Tồn kho, Quản lý kho,
Chứng từ kho, Biến động kho, Tồn thấp hiện tại, Cảnh báo tồn kho và Kiểm kê.
Mỗi chức năng có màn hình/đường dẫn riêng và chỉ hiển thị khi đủ quyền/feature.
Xem [điều hướng Kho](docs/inventory-navigation.md) để biết cấu trúc và route.

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
flutter build apk --debug
```
