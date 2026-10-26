# Điều hướng Kho

Phần Kho được tách thành bảy màn hình. Mở menu chính, nhấn hàng **Kho** hoặc
mũi tên bên phải để hiện/ẩn các mục con. Nhóm tự mở khi đang ở một chức năng
Kho; vẫn có thể thu gọn thủ công và giữ trạng thái khi đóng/mở menu.

| Mục sidebar | Đường dẫn | Màn hình |
| --- | --- | --- |
| Tồn kho | `/app/inventory/balances` | `InventoryBalancesScreen` |
| Quản lý kho | `/app/inventory/warehouses` | `InventoryWarehousesScreen` |
| Chứng từ kho | `/app/inventory/stock-documents` | `InventoryDocumentsScreen` |
| Biến động kho | `/app/inventory/transactions` | `InventoryTransactionsScreen` |
| Tồn thấp hiện tại | `/app/inventory/low-stock` | `InventoryLowStockScreen` |
| Cảnh báo tồn kho | `/app/inventory/alerts` | `InventoryAlertsScreen` |
| Kiểm kê | `/app/inventory/audits` | `InventoryAuditsScreen` |

Mỗi màn hình chỉ gắn nội dung/provider của chức năng đó, có tiêu đề, thao tác và
tải lại tương ứng. Thanh chọn tab cũ đã được thay bằng các mục trên sidebar.
Chọn kho ở Tồn kho/Tồn thấp tiếp tục dùng selector hiện có.

## Cấu trúc

- `features/inventory/presentation/screens/`: bảy màn hình riêng; dùng chung
  `InventorySectionScreen` cho layout, scope, refresh và các widget nghiệp vụ.
- `app/router/app_routes.dart`, `app_router.dart`: route riêng và liên kết tương thích.
- `core/ui/sidebar/`: registry chức năng, nhóm thu gọn và lọc quyền/feature.
- `core/ui/shell/app_shell.dart`: chọn mục, tiêu đề và điều hướng qua GoRouter.
- Domain, repository, use case và contract API giữ cấu trúc hiện có.

`InventoryManagementScreen(initialTab)` là wrapper tương thích cho nơi gọi trực
tiếp cũ. `/app/inventory` chuyển sang Tồn kho; các liên kết `?tab=documents`,
`transactions`, `alerts`, `audits`, `warehouses`, `lowStock`/`low-stock` chuyển tới
màn tương ứng. Các query khác được giữ lại khi chuyển hướng. Lịch sử biến động
có bộ lọc tiếp tục dùng `InventoryTransactionRoute` và kiểm tra query hiện có.

## Quyền và luồng nhập liệu

Mọi mục cần `INVENTORY_VIEW` và `INVENTORY_MANAGEMENT`, cùng kiểm tra tenant,
vai trò và subscription hiện có. Tồn thấp/Cảnh báo cần thêm `LOW_STOCK_ALERT`;
Kiểm kê cần `STOCK_AUDIT`. Mục không đủ quyền bị ẩn; deep link cũng được guard.

Các thao tác tạo/chỉnh/xác nhận giữ quyền riêng. Màn tạo/chi tiết kiểm kê tiếp
tục dùng `confirmStockAuditExit`: chọn mục khác hoặc mở thông báo cảnh báo vẫn
phải xác nhận nếu có dữ liệu chưa lưu. Thu gọn nhóm Kho chỉ đổi cách hiển thị menu.

Liên kết quay lại từ chứng từ, kiểm kê và thông báo realtime dùng route mới.
Realtime cảnh báo tiếp tục hoạt động theo lifecycle và quyền hiện có.

## Số đỏ ở Tồn thấp hiện tại

Mục **Tồn thấp hiện tại** có huy hiệu đỏ khi tổng lớn hơn 0; trên 99 hiển thị
`99+`, trình đọc màn hình vẫn nhận được số đầy đủ. Tổng khớp danh sách mặc định
**Tất cả kho**: mỗi dòng nguyên liệu–kho là một vị trí tồn thấp. Một nguyên liệu
thấp ở hai kho tính hai dòng. Tìm kiếm, phân trang và bộ lọc của màn hình không
làm thay đổi huy hiệu này.

Controller riêng `InventoryLowStockCountController` gọi use case
`GetLowStockBalances` với `page=0,size=1`, lấy `totalElements`; không tải toàn bộ
danh sách hoặc đếm lịch sử OPEN/ACKNOWLEDGED/RESOLVED. Provider được scope theo
tài khoản/tenant/quyền và chỉ đọc khi có capability xem tồn thấp.

Tải khi khởi tạo, mở sidebar, trở lại foreground, tải lại màn Tồn thấp, và khi
có thay đổi warehouse/balance/orderStock/alertSync. Sự kiện realtime đi qua
coordinator hiện có; không thêm timer polling. Các sự kiện dồn được gom, một
yêu cầu đang chạy chỉ có tối đa một lượt tải bù để cập nhật kết quả mới nhất.

Số chưa xác minh/lỗi tải không được đổi thành 0; huy hiệu chỉ hiện số đã đọc
thành công. Background, dispose hoặc đổi scope chặn kết quả trễ. Lỗi quyền dùng
`revalidateAccess()` để giữ bản nhập khi grants không đổi.

Kiểm thử bổ sung gồm metadata phân trang, scope/lifecycle, gom sự kiện, lỗi mạng/
403, quyền, AppShell thực và sidebar 320 px với chữ 200%. Bộ kiểm thử liên quan
đạt 321/321; Dart analyze không có lỗi.
