# Tài khoản nhận chuyển khoản và VietQR khi thanh toán

Chủ nhà hàng cài **một lần** tài khoản ngân hàng nhận tiền. Từ đó, khi thu
ngân chọn **Chuyển khoản** trong hộp thoại thanh toán, app hiện mã VietQR có sẵn
số tiền và nội dung chuyển khoản để khách quét bằng app ngân hàng.

Mã QR **chỉ để hiển thị**: app không tạo payment, không hỏi ngân hàng, không
tự kiểm tra tiền về. Thu ngân vẫn xem tiền về rồi bấm "Đã nhận …" như trước
(xem [order-settlement.md](order-settlement.md)).

## Cài đặt tài khoản

**Cài đặt → Tài khoản nhận chuyển khoản** (`/app/settings`), dưới mục QR menu
mang đi.

- Xem: người có `RESTAURANT_PROFILE_VIEW` (hoặc quyền sửa) thấy mục này.
- Thêm / sửa / gỡ: `AccessPolicy.canManageTransferAccount` =
  `RESTAURANT_PROFILE_UPDATE`. Thiếu quyền thì không có nút sửa hay gỡ.
- Hộp thoại có ô chọn ngân hàng (tìm theo tên, tên đầy đủ hoặc BIN, không cần
  gõ dấu), số tài khoản và tên chủ tài khoản.
- Gỡ tài khoản luôn hỏi xác nhận. Sau khi gỡ, hộp thoại thanh toán chỉ báo chưa
  có mã QR; chuyển khoản thủ công vẫn dùng được.

### Kiểm tra dữ liệu (client, server kiểm lại)

| Trường | Quy tắc | Chuẩn hóa trước khi gửi |
| --- | --- | --- |
| `bankBin` | đúng 6 chữ số | trim |
| `accountNumber` | 1–19 chữ cái/chữ số | bỏ khoảng trắng, viết hoa |
| `accountName` | 1–50 ký tự `[A-Z0-9 ]` | bỏ dấu tiếng Việt, viết hoa, gộp khoảng trắng (`Nguyễn Văn Đức` → `NGUYEN VAN DUC`) |

Ô tên hiện "Sẽ lưu là: …" khi bản chuẩn hóa khác chữ đang gõ. Lỗi theo trường
từ server (`fieldErrors` của `INVALID_TRANSFER_ACCOUNT`) hiện ngay dưới ô tương
ứng.

Danh sách ngân hàng: `lib/core/values/vietnam_banks.dart` (`vietnamBanks`,
`bankByBin`, `bankLabel`). Danh sách không đầy đủ; BIN không có trong danh sách
hiện là `BIN 970xxx`.

## QR trong hộp thoại thanh toán

Khi phương thức là Chuyển khoản, `TransferQrPanel` hiện:

- ảnh QR (server dựng PNG, app không thêm thư viện QR), cạnh = min(240, bề
  rộng), nền trắng để quét được cả khi giao diện tối;
- ngân hàng, số tài khoản, chủ tài khoản, số tiền, nội dung chuyển khoản;
- chạm ảnh → toàn màn hình để quay về phía khách; chạm bất kỳ hoặc **Đóng** để
  quay lại.

Trạng thái: đang tải; chưa cài tài khoản (chỉ thông báo, không chặn thanh toán
thủ công); lỗi kèm **Thử lại**. Nếu số tiền trong mã khác số cần thu, panel cảnh
báo tải lại đơn.

Khi QR tải xong và ô **Mã tham chiếu** đang trống, app điền sẵn
`transferContent` (dạng `TT ` + 10 chữ/số cuối của mã đơn, server sinh) và đổi
gợi ý thành "Đã điền sẵn nội dung chuyển khoản. Có thể thay bằng mã giao dịch
ngân hàng." Mã thu ngân đã gõ không bị ghi đè. Backend vẫn bắt buộc mã tham
chiếu cho TRANSFER; luồng `controller.pay(TRANSFER, referenceNo)` không đổi.

QR ẩn khi thanh toán đang chờ kết quả hoặc cần đối chiếu (`ownsMutationBlock`
/ `needsReview`, giống phần tính tiền thừa) và khi đơn không còn UNPAID.

`orderTransferQrProvider` là `FutureProvider.autoDispose.family` theo
`(orderId, orderVersion)`: đơn đổi version thì đọc mã mới; đóng hộp thoại hoặc
đổi sang Tiền mặt thì bỏ. Không retry tự động, không polling.

## API (sau /api/v1)

| Method | Path | Quyền | Kết quả |
| --- | --- | --- | --- |
| GET | /restaurants/me/transfer-account | xem nhà hàng | `{configured:false}` hoặc `{configured:true, bankBin, accountNumber, accountName, updatedAt}` |
| PUT | /restaurants/me/transfer-account | `RESTAURANT_PROFILE_UPDATE` | body `{bankBin, accountNumber, accountName}`, trả như GET |
| DELETE | /restaurants/me/transfer-account | `RESTAURANT_PROFILE_UPDATE` | `{configured:false}` |
| GET | /orders/{orderId}/transfer-qr | `PAYMENT_CREATE` | `{orderId, orderVersion, amount, currencyCode, bankBin, accountNumber, accountName, transferContent, qrPayload}` |
| GET | /orders/{orderId}/transfer-qr/image?format=png&size=720 | `PAYMENT_CREATE` | PNG |

`amount` nhận cả chuỗi thập phân lẫn số. App chỉ xin ảnh sau khi đọc được chi
tiết, nên khi chưa cài tài khoản không có request ảnh.

Mã lỗi mới (thông điệp tiếng Việt trong `ApiErrorMapper`):

| Mã | HTTP | Ý nghĩa trong app |
| --- | --- | --- |
| `TRANSFER_ACCOUNT_NOT_CONFIGURED` | 409 | Repository đổi thành "chưa cài" (`Success(null)`) |
| `ORDER_NOT_PAYABLE` | 409 | Đơn không còn thanh toán được (đã có từ trước) |
| `TRANSFER_QR_CURRENCY_UNSUPPORTED` | 422 | Chỉ hỗ trợ đơn VND |
| `INVALID_TRANSFER_ACCOUNT` | 400 | Dữ liệu tài khoản không hợp lệ, kèm `fieldErrors` |

## Mã nguồn

- Dùng chung: `lib/core/values/vietnam_banks.dart`,
  `lib/core/values/vietnamese_text.dart` (`removeVietnameseDiacritics`, cũng
  dùng cho `asciiSlug`).
- Cài đặt: entity `TransferAccount` / `TransferAccountDraft`
  (`domain/entities/transfer_account.dart`), `TransferAccountRepository`,
  `TransferAccountRemoteDataSource` + `TransferAccountRepositoryImpl`,
  `transferAccountRepositoryProvider` / `transferAccountProvider` trong
  `settings_providers.dart`, `_TransferAccountSection` trong
  `settings_screen.dart`, `widgets/transfer_account_dialog.dart`.
- Đơn hàng: `OrderTransferQr` / `OrderTransferQrCode`,
  `OrderTransferQrRepository`, use case `GetOrderTransferQr`
  (`order_use_cases.dart`), `OrderTransferQrDto`,
  `OrderTransferQrRemoteDataSource` + `OrderTransferQrRepositoryImpl`,
  `presentation/providers/order_transfer_qr_providers.dart`,
  `widgets/transfer_qr_panel.dart`, thay đổi trong `order_payment_dialog.dart`.

Repository riêng, không mở rộng `SettingsRepository` / `OrderRepository`.

## Kiểm thử

- `test/core/values/vietnam_banks_test.dart`: `bankByBin`, BIN duy nhất, bỏ dấu.
- `test/features/settings/transfer_account_test.dart`: kiểm tra/chuẩn hóa
  trường, GET/PUT/DELETE và body, lỗi server, thông điệp mã lỗi mới.
- `test/features/settings/settings_screen_test.dart`: thêm tài khoản gửi đúng
  body, gỡ có xác nhận, thiếu quyền thì chỉ xem.
- `test/features/order/order_transfer_qr_data_test.dart`: parse chi tiết, chưa
  cài → null, ảnh PNG, use case không xin ảnh khi chưa cài.
- `test/features/order/order_settlement_widget_test.dart`: QR hiện nội dung /
  số tiền / ngân hàng, điền sẵn mã và xác nhận gửi TRANSFER với mã đó, phóng
  to, giữ mã đã gõ khi thử lại, chưa cài vẫn thanh toán thủ công, version mới
  đọc lại QR, QR ẩn khi thanh toán đang chờ, vừa 320/800 px với chữ 200%.

Tất cả dùng fake repository / Dio adapter; chưa thử với backend thật.
