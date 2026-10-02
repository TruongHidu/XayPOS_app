# Xây POS

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
