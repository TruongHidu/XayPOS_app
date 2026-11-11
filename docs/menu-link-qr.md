# QR menu mang đi (link menu chung)

Link menu chung `/menu/{menuToken}` cho khách không ngồi bàn (mang đi). Quản lý
ở **Cài đặt → QR menu mang đi** (`/app/settings`), ngay dưới mục Nhà hàng.

## Quyền

Mục chỉ hiện khi tài khoản có `RESTAURANT_PROFILE_UPDATE` (mặc định OWNER và
MANAGER). Không cần subscription hay `QR_MENU_VIEW`, giống backend. Thu ngân và
nhân viên không thấy mục này.

## API (sau /api/v1)

| Method | Path | Kết quả |
| --- | --- | --- |
| GET | /restaurants/me/menu-link | `{menuToken, menuPath, menuUrl}`; 404 `PUBLIC_MENU_LINK_NOT_INITIALIZED` khi chưa tạo |
| POST | /restaurants/me/menu-link | Tạo link |
| POST | /restaurants/me/menu-link/rotate | Đổi token, link cũ ngừng hoạt động |
| GET | /restaurants/me/menu-link/qr/image?format=png&size=1024 | PNG mã QR trần (`qr-menu.png`) |
| GET | /restaurants/me/menu-link/qr/card | PNG thẻ in A6 1240×1748 (`the-qr-menu.png`) |

## Luồng UI

- Chưa có link (`PUBLIC_MENU_LINK_NOT_INITIALIZED` → repository trả
  `Success(null)`): hiện mô tả và nút **Tạo link menu**.
- Đã có link: xem trước thẻ in / mã QR, link khách quét (sao chép, mở), nút
  lưu / chia sẻ, và nút **Đổi link** ở tiêu đề mục (có xác nhận, nhắc in lại
  thẻ).
- `menuLinkFileProvider` key theo `menuToken`, nên tạo hoặc đổi link xong ảnh tự
  tải lại. Ảnh không được cache ngoài vòng đời màn hình.

## Mã nguồn

- Dữ liệu: `lib/features/settings/data/settings_remote_data_source.dart`,
  `settings_repository_impl.dart`, entity `PublicMenuLink`.
- Provider: `menuLinkProvider`, `menuLinkFileProvider` trong
  `settings_providers.dart`.
- UI: `_MenuLinkSection` trong `settings_screen.dart`, dùng chung widget
  `QrPreview` (`lib/core/ui/widgets/qr_preview.dart`) với dialog QR bàn.

## Lưu ý

- Muốn đọc tên file từ `Content-Disposition` trên web khác domain thì backend
  phải thêm header này vào CORS `exposedHeaders`. Hiện app dùng tên fallback
  nên không bắt buộc.
- Chỉ hỗ trợ PNG. Muốn tải SVG cho in khổ lớn thì gọi `format=svg` (chưa có UI).
